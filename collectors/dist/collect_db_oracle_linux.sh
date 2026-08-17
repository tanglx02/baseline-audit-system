#!/usr/bin/env bash
# ===========================================================================
# 基线核查收集脚本（Linux）— 由 baseline/*.yaml 自动生成，零 Python 依赖
# 适用：任意带 bash + coreutils 的 Linux 服务器（无需安装 Python）
# 用法：
#   bash collect_xxx.sh            # 当前目录生成 results_<host>_<ts>.json 并打印 JSON
#   bash collect_xxx.sh -o /tmp    # 指定输出目录
# 说明：仅执行只读检测；建议以 root 执行以获取 /etc/shadow、PAM 等完整权限。
#       命令超时/无权限/文件缺失 -> status=unknown，不修改任何系统。
# ===========================================================================
COLLECTOR_VERSION="2.0.0-bash"

# 读 stdin，输出 JSON 转义后的字符串（不含两侧引号）；支持多行
_json_escape() {
  awk 'BEGIN{f=1} { if(!f) printf "\\n"; f=0; gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\r/,""); printf "%s", $0 }'
}

# 命令是否存在（跨发行版通用）
_have() { command -v "$1" >/dev/null 2>&1; }

# 运行命令（带超时保护，超时则返回空）。优先用 GNU timeout；
# 极简环境无 timeout 时，用「后台运行 + wait + sleep 超时 kill」降级保护，避免卡死。
_run_cmd() {
  local cmd="$1" to="$2" out
  if command -v timeout >/dev/null 2>&1; then
    # --kill-after: 若命令忽略 SIGTERM，5s 后强制 SIGKILL，杜绝卡死
    out=$(timeout --kill-after=5s "$to" sh -c "$cmd" 2>/dev/null | head -c 8000)
  else
    out=$(
      sh -c "$cmd" 2>/dev/null & pid=$!
      ( sleep "$to"; kill -9 "$pid" 2>/dev/null ) &
      wait "$pid" 2>/dev/null
    )
  fi
  printf '%s' "$out" | head -c 8000
}

# 配置文件值提取：参数 pc(候选路径，换行分隔) fmt section key to
_cfg_get() {
  local pc="$1" fmt="$2" section="$3" key="$4" to="$5"
  local fpath="" cand expanded
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    cand=$(eval echo "$cand")
    expanded=$(ls -d $cand 2>/dev/null | head -1)
    if [ -n "$expanded" ] && [ -f "$expanded" ]; then fpath="$expanded"; break; fi
  done <<< "$pc"
  if [ -z "$fpath" ]; then printf '__NOFILE__'; return; fi
  local content
  content=$(cat "$fpath" 2>/dev/null)
  if [ -z "$content" ]; then printf '__NOPERM__'; return; fi
  _cfg_parse "$content" "$fmt" "$section" "$key"
}

# 按格式解析配置文本
_cfg_parse() {
  local content="$1" fmt="$2" section="$3" key="$4"
  case "$fmt" in
    key_value|conf|ini)
      printf '%s\n' "$content" | awk -v s="[$section]" -v k="$key" '
        function clean(v){ sub(/^[ \t=:]+/,"",v); sub(/[ \t;#]+$/,"",v); gsub(/^"|"$/,"",v); return v }
        { line=$0; if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) next
          if (s != "[]") { if (line ~ "^[ \t]*\\[" s "\\][ \t]*$") { f=1; next } if (line ~ /^[ \t]*\[/) { f=0 } }
          if (f != 0 || s == "[]") {
            if (line ~ "^[ \t]*" k "[ \t]*[=:]") { print clean(line); exit }
          }
        }'
      ;;
    yaml)
      _cfg_parse_yaml "$content" "$key" "$section"
      ;;
    json)
      _cfg_parse_json "$content" "$key" "$section"
      ;;
  esac
}

_cfg_parse_yaml() {
  local content="$1" key="$2" section="$3"
  local dotted="$key"
  [ -n "$section" ] && dotted="$section.$key"
  printf '%s\n' "$content" | awk -v want="$dotted" '
  function d(s){ match(s,/^ */); return RLENGTH }
  { line=$0
    if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) next
    n=d(line)
    while (ld>0 && lvl[ld]>=n) { delete path[ld]; ld-- }
    ci=index(line,":")
    if (ci>0) {
      k=substr(line,1,ci-1); v=substr(line,ci+1)
      sub(/^[ \t]+/,"",k); sub(/[ \t]+$/,"",k)
      sub(/^[ \t]+/,"",v); sub(/[ \t]+$/,"",v)
      if (substr(v,1,1)=="\"" && substr(v,length(v),1)=="\"") v=substr(v,2,length(v)-2)
      if (v=="") { ld++; lvl[ld]=n; path[ld]=k }
      else {
        p=""; for(i=1;i<=ld;i++){ p=(p=="")?path[i]:(p"."path[i]) }
        p=(p=="")?k:(p"."k)
        if (p==want) { print v; exit }
      }
    }
  }'
}

_cfg_parse_json() {
  local content="$1" key="$2" section="$3"
  printf '%s\n' "$content" | grep -oE "\"$key\"[ \t]*:[ \t]*(\"[^\"]*\"|true|false|-?[0-9]+(\\.[0-9]+)?)" | head -1 \
    | sed -E 's/.*:[ \t]*//; s/^"//; s/"$//'
}

# 进程检查（优先 pgrep；退化到 ps -e 兼容无 pgrep 的极简/容器环境）
_proc_check() {
  local name="$1"
  if _have pgrep && pgrep -x "$name" >/dev/null 2>&1; then
    local user; user=$(ps -eo user=,comm= 2>/dev/null | awk -v n="$name" '$2==n{print $1; exit}')
    printf 'running:%s' "${user:-unknown}"
  elif ps -e -o comm= 2>/dev/null | grep -qx "$name"; then
    printf 'running:unknown'
  else
    printf 'not_running'
  fi
}

# 端口检查（优先 ss/netstat；再退化到直接解析 /proc/net/tcp，覆盖无 iproute2/coreutils 的极简发行版）
_port_check() {
  local port="$1" out=""
  if _have ss || _have netstat; then
    out=$( ( (_have ss && ss -tln 2>/dev/null) || (_have netstat && netstat -tln 2>/dev/null) ) \
            | awk -v p="$port" '{print $4}' | grep -E "[:.]${port}$" | sort -u | head -20 )
  fi
  if [ -z "$out" ] && [ -r /proc/net/tcp ]; then
    # 0A = TCP_LISTEN；把端口转 16 进制比对，任意内核/发行版通用
    local hex; hex=$(printf '%04X' "$port" 2>/dev/null)
    [ -n "$hex" ] && out=$(awk -v h="$hex" 'NR>1 && $4=="0A" { split($2,a,":"); if (toupper(a[2])==h) print "proc:"a[1] }' /proc/net/tcp 2>/dev/null | sort -u | head -20)
  fi
  if [ -n "$out" ]; then printf '%s' "$out"; else printf 'not_listening'; fi
}

# 判定：_judge <jtype> <actual> <jval>  -> 返回 0(pass)/1(fail)
_judge() {
  local jt="$1" actual="$2" jval="$3"
  case "$jt" in
    equals) [ "$actual" = "$jval" ] ;;
    not_equals) [ "$actual" != "$jval" ] ;;
    contains) case "$actual" in *"$jval"*) return 0;; esac; return 1 ;;
    regex_present) printf '%s' "$actual" | grep -Piq -- "$jval" 2>/dev/null || printf '%s' "$actual" | grep -Eiq -- "$jval" ;;
    regex_absent) { printf '%s' "$actual" | grep -Piq -- "$jval" 2>/dev/null || printf '%s' "$actual" | grep -Eiq -- "$jval"; } && return 1 || return 0 ;;
    numeric_leq) _num_cmp "$actual" "$jval" le ;;
    numeric_geq) _num_cmp "$actual" "$jval" ge ;;
    file_perm_leq) _perm_cmp "$actual" "$jval" le ;;
    *) return 1 ;;
  esac
}

_num_cmp() {
  local a="$1" b="$2" op="$3" na
  na=$(printf '%s' "$a" | grep -oE '-?[0-9]+(\.[0-9]+)?' | head -1)
  [ -z "$na" ] && return 1
  awk -v x="$na" -v y="$b" -v o="$op" 'BEGIN{ if(o=="le") exit !(x<=y); if(o=="ge") exit !(x>=y); exit 1 }'
}

_perm_cmp() {
  local a="$1" b="$2" pa
  pa=$(_parse_perm "$a")
  [ -z "$pa" ] && return 1
  awk -v x="$pa" -v y="$b" -v o="$op" 'BEGIN{ if(o=="le") exit !(x<=y); exit 1 }'
}

_parse_perm() {
  local s="$1"
  printf '%s' "$s" | awk '
  { s=$0
    if (substr(s,1,1)=="d" || substr(s,1,1)=="-" || substr(s,1,1)=="l") {
      u=substr(s,2,3); g=substr(s,5,3); o=substr(s,8,3); f=0;gu=0;go=0
      for(i=1;i<=3;i++){ c=substr(u,i,1); if(c=="r")f+=4; if(c=="w")f+=2; if(c=="x")f+=1 }
      for(i=1;i<=3;i++){ c=substr(g,i,1); if(c=="r")gu+=4; if(c=="w")gu+=2; if(c=="x")gu+=1 }
      for(i=1;i<=3;i++){ c=substr(o,i,1); if(c=="r")go+=4; if(c=="w")go+=2; if(c=="x")go+=1 }
      print f*64+gu*8+go; exit
    }
    n=s; gsub(/[^0-7]/,"",n)
    if (n!="") { v=0; for(i=1;i<=length(n);i++) v=v*8+substr(n,i,1); print v; exit }
  }'
}

# 结果累加
RESULTS=""
PASSED=0; FAILED=0; MANUAL=0; UNKNOWN=0

_add_finding() {
  local obj="$1" status="$2"
  if [ -z "$RESULTS" ]; then RESULTS="$obj"; else RESULTS="$RESULTS,$obj"; fi
  case "$status" in
    pass) PASSED=$((PASSED+1));; fail) FAILED=$((FAILED+1));;
    manual) MANUAL=$((MANUAL+1));; unknown) UNKNOWN=$((UNKNOWN+1));;
  esac
}

# 单条核查执行（读取下方每个 ITEM_* 变量；静态字段已预生成在 $ITEM_STATIC）
_run_item() {
  local status="unknown" actual="" msg="" ajson mjson resolved=1
  if [ "$ITEM_CHECK" = "manual" ]; then
    status="manual"; msg="$ITEM_MDESC"; ajson="null"; resolved=0
  else
    case "$ITEM_MTYPE" in
      shell|powershell)
        actual=$(_run_cmd "$ITEM_CMD" "$ITEM_TIMEOUT")
        ;;
      config_file)
        actual=$(_cfg_get "$ITEM_PC" "$ITEM_FORMAT" "$ITEM_SECTION" "$ITEM_KEY" "$ITEM_TIMEOUT")
        if [ "$actual" = "__NOFILE__" ]; then status="unknown"; msg="配置文件不存在"; ajson="null"; actual=""; resolved=0
        elif [ "$actual" = "__NOPERM__" ]; then status="unknown"; msg="无权限读取配置文件"; ajson="null"; actual=""; resolved=0; fi
        ;;
      process)
        actual=$(_proc_check "$ITEM_PROC")
        ;;
      port)
        actual=$(_port_check "$ITEM_PORT")
        ;;
      *) status="unknown"; msg="未知 method.type: $ITEM_MTYPE"; ajson="null"; resolved=0;;
    esac
  fi
  if [ "$resolved" = "1" ]; then
    if [ -z "$actual" ]; then
      if [ "$ITEM_TE" = "pass" ]; then status="pass"; else status="fail"; fi
      msg="实际值为空，按 treat_empty_as=$ITEM_TE 判定"; ajson="null"; actual=""
    elif _judge "$ITEM_JTYPE" "$actual" "$ITEM_JVAL"; then
      status="pass"
    else
      status="fail"; msg="不满足合规判定条件"
    fi
    ajson="\"$(printf '%s' "$actual" | _json_escape)\""
  fi
  mjson="\"$(printf '%s' "$msg" | _json_escape)\""
  local obj="{$ITEM_STATIC,\"status\":\"$status\",\"actual\":$ajson,\"message\":$mjson}"
  _add_finding "$obj" "$status"
}

# ---- ORA-AUD-001 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='select value from v$parameter where name='\''audit_trail'\''; audit_trail 不为 NONE 则合规。需以 sysdba 执行 SQL 核查。'
ITEM_STATIC='"item_id":"ORA-AUD-001","category":"数据库安全","subsystem":"Oracle","name":"数据库审计策略(audit_trail)","severity":"high","expected":"","remediation":"alter system set audit_trail='\''OS'\'' scope=spfile; 重启数据库。","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-PWD-002 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='select limit from dba_profiles where resource_name='\''PASSWORD_LIFE_TIME'\''; 值<=90 合规。需 SQL 核查。'
ITEM_STATIC='"item_id":"ORA-PWD-002","category":"数据库安全","subsystem":"Oracle","name":"口令生存期(PASSWORD_LIFE_TIME<=90)","severity":"high","expected":"","remediation":"alter profile DEFAULT limit PASSWORD_LIFE_TIME 90;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-PRIV-003 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='select a.username from dba_users a left join dba_role_privs b on a.username=b.grantee where granted_role='\''DBA'\'' and a.username not in ('\''SYS'\'','\''SYSMAN'\'','\''SYSTEM'\''); 无其它 DBA 用户则合规。'
ITEM_STATIC='"item_id":"ORA-PRIV-003","category":"数据库安全","subsystem":"Oracle","name":"管理对象权限(除默认用户外无DBA角色)","severity":"high","expected":"","remediation":"revoke dba from <username>;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-DICT-004 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='O7_DICTIONARY_ACCESSIBILITY 应为 false。需 SQL/参数核查。'
ITEM_STATIC='"item_id":"ORA-DICT-004","category":"数据库安全","subsystem":"Oracle","name":"启用数据字典保护(O7_DICTIONARY_ACCESSIBILITY=false)","severity":"high","expected":"","remediation":"alter system set O7_DICTIONARY_ACCESSIBILITY=FALSE scope=spfile; 重启。","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-PWD-005 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='FAILED_LOGIN_ATTEMPTS 值<5(建议5)则合规。需 SQL 核查。'
ITEM_STATIC='"item_id":"ORA-PWD-005","category":"数据库安全","subsystem":"Oracle","name":"最大认证失败次数(FAILED_LOGIN_ATTEMPTS<5)","severity":"high","expected":"","remediation":"alter profile DEFAULT limit FAILED_LOGIN_ATTEMPTS 5;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-REM-006 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='REMOTE_LOGIN_PASSWORDFILE 值为 NONE 则合规。需 SQL 核查。'
ITEM_STATIC='"item_id":"ORA-REM-006","category":"数据库安全","subsystem":"Oracle","name":"限制SYSDBA远程登录(REMOTE_LOGIN_PASSWORDFILE=NONE)","severity":"high","expected":"","remediation":"alter system set REMOTE_LOGIN_PASSWORDFILE=NONE scope=spfile; 重启。","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-PWD-007 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='PASSWORD_REUSE_MAX 值>=5 则合规。需 SQL 核查。'
ITEM_STATIC='"item_id":"ORA-PWD-007","category":"数据库安全","subsystem":"Oracle","name":"记住历史密码次数(PASSWORD_REUSE_MAX>=5)","severity":"medium","expected":"","remediation":"alter profile DEFAULT limit PASSWORD_REUSE_MAX 5;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-PWD-008 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='已配置口令验证函数(PASSWORD_VERIFY_FUNCTION)则合规。需 SQL 核查。'
ITEM_STATIC='"item_id":"ORA-PWD-008","category":"数据库安全","subsystem":"Oracle","name":"口令强度函数(verify_function)","severity":"high","expected":"","remediation":"执行 utlpwdmg.sql 并 alter profile DEFAULT limit PASSWORD_VERIFY_FUNCTION verify_function;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-NET-009 (数据库安全/Oracle) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='20'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='grep -rIE '\''tcp\.validnode_checking|tcp\.invited_nodes'\'' --include=sqlnet.ora /u01/app/oracle /opt/oracle /oracle 2>/dev/null | head -5'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?i)(?=.*validnode_checking\s*=\s*yes)(?=.*invited_nodes)'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"ORA-NET-009","category":"数据库安全","subsystem":"Oracle","name":"限制可访问数据库地址(tcp.validnode_checking & invited_nodes)","severity":"high","expected":"匹配 (?i)(?=.*validnode_checking\\s*=\\s*yes)(?=.*invited_nodes)","remediation":"在 $ORACLE_HOME/network/admin/sqlnet.ora 设置 tcp.validnode_checking=yes 与 tcp.invited_nodes=(信任IP)。","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-LST-010 (数据库安全/Oracle) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='20'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='grep -rIE '\''PASSWORDS_LISTENER'\'' --include=listener.ora /u01/app/oracle /opt/oracle /oracle 2>/dev/null | head -3'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?i)PASSWORDS_LISTENER'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"ORA-LST-010","category":"数据库安全","subsystem":"Oracle","name":"监听器设置密码(PASSWORDS_LISTENER)","severity":"medium","expected":"匹配 (?i)PASSWORDS_LISTENER","remediation":"在 listener.ora 设置 PASSWORDS_LISTENER 并为监听器配置密码。","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-PRIV-011 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='select table_name from dba_tab_privs where grantee='\''PUBLIC'\'' and privilege='\''EXECUTE'\'' and table_name in ('\''UTL_FILE'\'','\''UTL_TCP'\'','\''UTL_HTTP'\'','\''UTL_SMTP'\'','\''DBMS_LOB'\'','\''DBMS_SYS_SQL'\'','\''DBMS_JOB'\''); 无结果则合规。'
ITEM_STATIC='"item_id":"ORA-PRIV-011","category":"数据库安全","subsystem":"Oracle","name":"账户最小授权(回收PUBLIC危险包执行权)","severity":"high","expected":"","remediation":"revoke execute on <包> from public;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-PWD-012 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='10g: 检查 dba_users 中 password 哈希是否仍为默认哈希；无默认密码账号则合规。需 SQL 核查。'
ITEM_STATIC='"item_id":"ORA-PWD-012","category":"数据库安全","subsystem":"Oracle","name":"修改默认账户密码(10g)","severity":"high","expected":"","remediation":"alter user <username> identified by <强密码>;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-PWD-013 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='11g: select count(*) from DBA_USERS_WITH_DEFPWD a,dba_users b where a.username=b.username and b.account_status='\''open'\''; 结果为0则合规(XS$NULL 除外)。'
ITEM_STATIC='"item_id":"ORA-PWD-013","category":"数据库安全","subsystem":"Oracle","name":"修改默认账户密码(11g)","severity":"high","expected":"","remediation":"alter user <username> identified by <强密码>;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-PWD-014 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='PASSWORD_GRACE_TIME 值<=7 则合规。需 SQL 核查。'
ITEM_STATIC='"item_id":"ORA-PWD-014","category":"数据库安全","subsystem":"Oracle","name":"口令到期宽限天数(PASSWORD_GRACE_TIME<=7)","severity":"medium","expected":"","remediation":"alter profile DEFAULT limit PASSWORD_GRACE_TIME 7;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-AUTH-015 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='REMOTE_OS_AUTHENT 值为 FALSE 则合规。需 SQL 核查。'
ITEM_STATIC='"item_id":"ORA-AUTH-015","category":"数据库安全","subsystem":"Oracle","name":"登录认证方式(REMOTE_OS_AUTHENT=false)","severity":"high","expected":"","remediation":"alter system set REMOTE_OS_AUTHENT=FALSE scope=spfile; 重启。","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-OS-016 (数据库安全/Oracle) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='id oracle 2>/dev/null | grep -oE '\''groups=[0-9]+\(.+\)'\'' || echo NOUSER'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?i)\(dba.*oinstall\)|\(oinstall.*dba\)'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"ORA-OS-016","category":"数据库安全","subsystem":"Oracle","name":"禁止oracle作为主机管理员帐号(仅属dba/oinstall)","severity":"medium","expected":"匹配 (?i)\\(dba.*oinstall\\)|\\(oinstall.*dba\\)","remediation":"将 oracle 用户仅加入 dba 与 oinstall 组，移出 wheel 等管理员组。","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-PWD-017 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='PASSWORD_LOCK_TIME 值=1(天)则合规。需 SQL 核查。'
ITEM_STATIC='"item_id":"ORA-PWD-017","category":"数据库安全","subsystem":"Oracle","name":"认证失败账户锁定时间(PASSWORD_LOCK_TIME=1)","severity":"medium","expected":"","remediation":"alter profile DEFAULT limit PASSWORD_LOCK_TIME 1;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-AUD-018 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='select * from DBA_AUDIT_TRAIL; 存在审计记录则合规。需 SQL 核查。'
ITEM_STATIC='"item_id":"ORA-AUD-018","category":"数据库安全","subsystem":"Oracle","name":"日志记录及保存(DBA_AUDIT_TRAIL有记录)","severity":"high","expected":"","remediation":"audit session; audit table; 开启相应审计。","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-LST-019 (数据库安全/Oracle) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='20'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='grep -rIE '\''LOGGING_LISTENER|LOG_FILE_LISTENER|LOG_DIRECTORY_LISTENER'\'' --include=listener.ora /u01/app/oracle /opt/oracle /oracle 2>/dev/null | head -5'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?i)(?=.*LOGGING_LISTENER)(?=.*LOG_FILE_LISTENER)(?=.*LOG_DIRECTORY_LISTENER)'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"ORA-LST-019","category":"数据库安全","subsystem":"Oracle","name":"开启监听器日志(LOGGING_LISTENER等)","severity":"medium","expected":"匹配 (?i)(?=.*LOGGING_LISTENER)(?=.*LOG_FILE_LISTENER)(?=.*LOG_DIRECTORY_LISTENER)","remediation":"在 listener.ora 设置 LOGGING_LISTENER=ON、LOG_FILE_LISTENER、LOG_DIRECTORY_LISTENER。","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-LST-020 (数据库安全/Oracle) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='20'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='grep -rIE '\''INBOUND_CONNECT_TIMEOUT'\'' --include=listener.ora --include=sqlnet.ora /u01/app/oracle /opt/oracle /oracle 2>/dev/null | head -5'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?i)INBOUND_CONNECT_TIMEOUT\s*=\s*10'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"ORA-LST-020","category":"数据库安全","subsystem":"Oracle","name":"监听器连接超时(INBOUND_CONNECT_TIMEOUT=10)","severity":"medium","expected":"匹配 (?i)INBOUND_CONNECT_TIMEOUT\\s*=\\s*10","remediation":"listener.ora 与 sqlnet.ora 均设置 INBOUND_CONNECT_TIMEOUT=10。","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-LST-021 (数据库安全/Oracle) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='20'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='grep -rIE '\''ADMIN_RESTRICTIONS_'\'' --include=listener.ora /u01/app/oracle /opt/oracle /oracle 2>/dev/null | head -3'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?i)ADMIN_RESTRICTIONS_\w+\s*=\s*ON'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"ORA-LST-021","category":"数据库安全","subsystem":"Oracle","name":"监听器管理限制(ADMIN_RESTRICTIONS=ON)","severity":"medium","expected":"匹配 (?i)ADMIN_RESTRICTIONS_\\w+\\s*=\\s*ON","remediation":"在 listener.ora 设置 ADMIN_RESTRICTIONS_<listener_name>=ON。","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-ACC-022 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='select username from dba_users where account_status='\''OPEN'\''; 不存在与运行维护无关账号则合规。需人工核查。'
ITEM_STATIC='"item_id":"ORA-ACC-022","category":"数据库安全","subsystem":"Oracle","name":"删除或锁定无关帐号","severity":"high","expected":"","remediation":"alter user <username> account lock; 或 drop user <username> cascade;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-ACC-023 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='核查 SCOTT/HR/OE/PM/SH 等示例账号是否已锁定或到期。需 SQL 核查。'
ITEM_STATIC='"item_id":"ORA-ACC-023","category":"数据库安全","subsystem":"Oracle","name":"锁定/到期默认示例账号","severity":"medium","expected":"","remediation":"锁定或删除示例账号。","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-PRIV-024 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='select limit from dba_profiles where profile='\''DEFAULT'\'' and resource_name='\''SESSIONS_PER_USER'\''; 不为 UNLIMITED 则合规。'
ITEM_STATIC='"item_id":"ORA-PRIV-024","category":"数据库安全","subsystem":"Oracle","name":"限制用户并行会话数(SESSIONS_PER_USER)","severity":"low","expected":"","remediation":"alter profile DEFAULT limit SESSIONS_PER_USER 10;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-PRIV-025 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='select limit from dba_profiles where profile='\''DEFAULT'\'' and resource_name='\''CPU_PER_USER'\''; 已设置限制值则合规。'
ITEM_STATIC='"item_id":"ORA-PRIV-025","category":"数据库安全","subsystem":"Oracle","name":"限制会话CPU时间(CPU_PER_USER)","severity":"low","expected":"","remediation":"alter profile DEFAULT limit CPU_PER_USER 10000;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-PRIV-026 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='select limit from dba_profiles where profile='\''DEFAULT'\'' and resource_name='\''IDLE_TIME'\''; 不为 UNLIMITED 则合规。'
ITEM_STATIC='"item_id":"ORA-PRIV-026","category":"数据库安全","subsystem":"Oracle","name":"限制空闲会话时间(IDLE_TIME)","severity":"low","expected":"","remediation":"alter profile DEFAULT limit IDLE_TIME 30;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-CONN-027 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='select value from v$parameter where name='\''processes'\''; 值<=1000 则合规。'
ITEM_STATIC='"item_id":"ORA-CONN-027","category":"数据库安全","subsystem":"Oracle","name":"限制数据库最大连接数(processes<=1000)","severity":"medium","expected":"","remediation":"alter system set processes=500 scope=spfile;","reference":"等保2.0 8.1.4"'
_run_item

# ---- ORA-AUD-028 (数据库安全/Oracle) ----
ITEM_CHECK='manual'
ITEM_MTYPE='manual'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE=''
ITEM_TE=''
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC='show parameter audit_trail; show parameter audit_sys_operations; 并按业务配置 dba_stmt/priv/obj_audit_opts。需人工核查审计策略完整性。'
ITEM_STATIC='"item_id":"ORA-AUD-028","category":"数据库安全","subsystem":"Oracle","name":"审计记录规范(audit_sys_operations等)","severity":"high","expected":"","remediation":"设置 audit_trail=DB、audit_sys_operations=TRUE，并配置语句/权限/对象级审计。","reference":"等保2.0 8.1.4"'
_run_item
# ---------------------------------------------------------------------------
# 主机元数据 + 汇总 + 输出
# ---------------------------------------------------------------------------
HOSTNAME=$(hostname 2>/dev/null || echo unknown)
OSVER=$( (cat /etc/os-release 2>/dev/null | awk -F= '/^PRETTY_NAME=/{v=$2; gsub(/"/,"",v); print v; exit}') )
KERNEL=$(uname -r 2>/dev/null || echo "")
COLLECTED=$(date -Iseconds 2>/dev/null || date "+%Y-%m-%dT%H:%M:%S")
CATALOG_ID="db_oracle_linux"
CATALOG_VER="1.0.0"
VERSIONS='{"db2":"1.0.0","db_mariadb":"1.0.0","db_mongodb":"1.0.0","db_mysql_linux":"1.0.0","db_mysql_win":"1.0.0","db_oracle_linux":"1.0.0"}'

TOTAL=$((PASSED+FAILED+MANUAL+UNKNOWN))
DENOM=$((PASSED+FAILED))
if [ "$DENOM" -gt 0 ]; then
  COMPL=$(awk -v p="$PASSED" -v d="$DENOM" 'BEGIN{ printf "%.4f", p/d }')
else
  COMPL="null"
fi

DOC=$(printf '{\n  "schema_version": 1,\n  "generator": "baseline-collector-bash",\n  "host": {"hostname": "%s", "os": "Linux", "os_version": "%s", "kernel": "%s", "platform": "linux", "collector_version": "%s", "collected_at": "%s"},\n  "catalog": {"id": "%s", "version": "%s", "all_versions": %s},\n  "summary": {"total": %s, "passed": %s, "failed": %s, "manual": %s, "unknown": %s, "compliance_rate": %s},\n  "results": [%s]\n}' \
  "$(printf '%s' "$HOSTNAME" | _json_escape)" \
  "$(printf '%s' "$OSVER" | _json_escape)" \
  "$(printf '%s' "$KERNEL" | _json_escape)" \
  "$COLLECTOR_VERSION" "$COLLECTED" \
  "$CATALOG_ID" "$CATALOG_VER" "$VERSIONS" \
  "$TOTAL" "$PASSED" "$FAILED" "$MANUAL" "$UNKNOWN" "$COMPL" \
  "$RESULTS")

OUT_DIR="."
while [ $# -gt 0 ]; do
  case "$1" in
    -o) shift; if [ $# -gt 0 ]; then OUT_DIR="$1"; fi;;
  esac
  shift
done
mkdir -p "$OUT_DIR"
TS=$(date +%Y%m%d_%H%M%S)
OUT="$OUT_DIR/results_${HOSTNAME}_${TS}.json"
printf '%s\n' "$DOC" > "$OUT"
echo "基线结果已写入: $OUT" >&2
cat "$OUT"
