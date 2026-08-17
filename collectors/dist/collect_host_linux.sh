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

# ---- LIN-PAM-001 (主机安全/口令策略) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='grep -rihE "pam_tally2?\.so" /etc/pam.d/ 2>/dev/null | grep -oE "deny=[0-9]+|unlock_time=[0-9]+" | tr '\''\n'\'' '\'' '\'''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?=.*deny=[0-5])(?=.*unlock_time=)'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-PAM-001","category":"主机安全","subsystem":"口令策略","name":"检查口令锁定策略","severity":"high","expected":"匹配 (?=.*deny=[0-5])(?=.*unlock_time=)","remediation":"在 /etc/pam.d/system-auth 增加 auth required pam_tally2.so deny=5 onerr=fail no_magic_root unlock_time=180 与 account required pam_tally2.so","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-AUTH-002 (主机安全/会话超时) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='grep -i "TMOUT" /etc/profile 2>/dev/null | tail -1'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?i)TMOUT\s*=\s*600'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-AUTH-002","category":"主机安全","subsystem":"会话超时","name":"登陆超时时间设置(TMOUT)","severity":"medium","expected":"匹配 (?i)TMOUT\\s*=\\s*600","remediation":"在 /etc/profile 增加 TMOUT=600 与 export TMOUT","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-SSH-003 (主机安全/SSH) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='grep -vE "^[[:space:]]*#" /etc/ssh/sshd_config 2>/dev/null | grep -iE "PermitRootLogin|Protocol" | tr '\''\n'\'' '\'' '\'''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?=.*PermitRootLogin\s+no)(?=.*Protocol\s+2|.*Protocol\s+[0-9])'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-SSH-003","category":"主机安全","subsystem":"SSH","name":"限制 root 用户 SSH 远程登录且使用协议2","severity":"high","expected":"匹配 (?=.*PermitRootLogin\\s+no)(?=.*Protocol\\s+2|.*Protocol\\s+[0-9])","remediation":"设置 PermitRootLogin no 与 Protocol 2 并重启 sshd","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-SSH-004 (主机安全/远程维护) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='t=$(systemctl is-enabled telnet.socket 2>/dev/null; systemctl is-enabled telnet 2>/dev/null; chkconfig --list 2>/dev/null | grep -i telnet); s=$(systemctl is-enabled sshd 2>/dev/null || systemctl is-enabled ssh 2>/dev/null || echo na); if echo "$t" | grep -qiE "enabled|on"; then echo "telnet=enabled ssh=$s"; else echo "telnet=disabled ssh=$s"; fi'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?=.*telnet=disabled)(?=.*ssh=(enabled|na))'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-SSH-004","category":"主机安全","subsystem":"远程维护","name":"使用 SSH 协议进行远程维护（禁用 Telnet）","severity":"high","expected":"匹配 (?=.*telnet=disabled)(?=.*ssh=(enabled|na))","remediation":"关闭 Telnet 服务，启用并仅使用 SSH 进行远程维护","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-FILE-005 (主机安全/文件权限) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='grep -i "umask" /etc/profile 2>/dev/null | tail -1'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?i)umask\s+0?22'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-FILE-005","category":"主机安全","subsystem":"文件权限","name":"文件与目录缺省权限控制(umask)","severity":"medium","expected":"匹配 (?i)umask\\s+0?22","remediation":"在 /etc/profile 末尾增加 umask 022 并执行 source /etc/profile","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-ACCT-006 (主机安全/账号文件) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD='p=$(stat -c '\''%a'\'' /etc/passwd 2>/dev/null); s=$(stat -c '\''%a'\'' /etc/shadow 2>/dev/null); g=$(stat -c '\''%a'\'' /etc/group 2>/dev/null); c=$(stat -c '\''%a'\'' /etc/crontab 2>/dev/null); r=$(stat -c '\''%a'\'' /etc/rsyslog.conf 2>/dev/null); [ -z "$r" ] && r=$(stat -c '\''%a'\'' /etc/syslog.conf 2>/dev/null); if [ "$p" -le 644 ] && [ "$s" -le 400 ] && [ "$g" -le 644 ] && [ "$c" -le 644 ] && { [ -z "$r" ] || [ "$r" -le 644 ]; }; then echo OK; else echo FAIL; fi'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='OK'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-ACCT-006","category":"主机安全","subsystem":"账号文件","name":"账号文件权限设置","severity":"high","expected":"等于 OK","remediation":"chmod 644 /etc/passwd /etc/group /etc/crontab; chmod 400 /etc/shadow; 日志配置文件 chmod 644","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-PWD-007 (主机安全/口令策略) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD='m=$(grep -i '\''^PASS_MAX_DAYS'\'' /etc/login.defs 2>/dev/null | awk '\''{print $2}'\''); n=$(grep -i '\''^PASS_MIN_DAYS'\'' /etc/login.defs 2>/dev/null | awk '\''{print $2}'\''); w=$(grep -i '\''^PASS_WARN_AGE'\'' /etc/login.defs 2>/dev/null | awk '\''{print $2}'\''); l=$(grep -i '\''^PASS_MIN_LEN'\'' /etc/login.defs 2>/dev/null | awk '\''{print $2}'\''); if [ -n "$m" ] && [ "$m" -le 180 ] && [ -n "$n" ] && [ "$n" -ge 1 ] && [ -n "$w" ] && [ "$w" -ge 28 ] && [ -n "$l" ] && [ "$l" -ge 8 ]; then echo OK; else echo FAIL; fi'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='OK'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-PWD-007","category":"主机安全","subsystem":"口令策略","name":"口令生存期(login.defs)","severity":"high","expected":"等于 OK","remediation":"在 /etc/login.defs 设置 PASS_MAX_DAYS 180 / PASS_MIN_DAYS 1 / PASS_WARN_AGE 28 / PASS_MIN_LEN 8","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-ACCT-008 (主机安全/账号管理) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD='awk -F: '\''{print $3}'\'' /etc/passwd 2>/dev/null | sort | uniq -d | wc -l'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='0'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-ACCT-008","category":"主机安全","subsystem":"账号管理","name":"禁止 UID 相同的用户存在多个","severity":"medium","expected":"等于 0","remediation":"删除重复 UID 的账号（切勿删除 root），userdel <username>","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-PWD-009 (主机安全/口令策略) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='grep -rihE "pam_cracklib|pam_pwquality" /etc/pam.d/ 2>/dev/null | grep -oE "minlen=[0-9]+|[dluo]credit=[0-9-]+" | tr '\''\n'\'' '\'' '\'''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?=.*minlen=(8|9|[0-9]{2,}))(?=.*credit)'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-PWD-009","category":"主机安全","subsystem":"口令策略","name":"口令复杂度(pam_cracklib/pwquality)","severity":"high","expected":"匹配 (?=.*minlen=(8|9|[0-9]{2,}))(?=.*credit)","remediation":"在 /etc/pam.d/system-auth 的 password requisite 行增加 pam_cracklib.so minlen=8 dcredit=-4 ucredit=-2 lcredit=-1 ocredit=-1","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-ENV-010 (主机安全/环境变量) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD='echo "$PATH" | tr '\'':'\'' '\''\n'\'' | grep -xE '\''^\.$|^\.\.$'\'' | wc -l'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='0'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-ENV-010","category":"主机安全","subsystem":"环境变量","name":"root 用户环境变量安全性(PATH 不含.或..)","severity":"medium","expected":"等于 0","remediation":"修改 /etc/profile 或 /root/.bash_profile，删除 PATH 中的 . 与 .. 路径","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-LOG-011 (主机安全/日志) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='grep -hE "@" /etc/rsyslog.conf /etc/syslog.conf 2>/dev/null | grep -vE '\''^#'\'' | head -3 | tr '\''\n'\'' '\'' '\'''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='@'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-LOG-011","category":"主机安全","subsystem":"日志","name":"启用远程日志功能并配置记录内容","severity":"medium","expected":"匹配 @","remediation":"在 /etc/rsyslog.conf 增加 *.* @<loghost> 并重启 rsyslog","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-ACCT-012 (主机安全/账号管理) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD='users="daemon bin sys adm uucp nuucp lpd imnadm ipsec ldap nobody lp snapp invscount"; bad=0; for u in $users; do p=$(getent shadow "$u" 2>/dev/null | awk -F: '\''{print $2}'\''); s=$(getent passwd "$u" 2>/dev/null | awk -F: '\''{print $7}'\''); if [ -n "$p" ] && [ "$p" != "*" ] && [ "$p" != "!" ] && [ "${p:0:2}" != "!!" ] && [ "$s" != "/bin/false" ] && [ "$s" != "/usr/sbin/nologin" ]; then bad=1; fi; done; [ "$bad" -eq 0 ] && echo OK || echo FAIL'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='OK'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-ACCT-012","category":"主机安全","subsystem":"账号管理","name":"删除或锁定无关帐号","severity":"medium","expected":"等于 OK","remediation":"对无关系统账号执行 usermod -s /bin/false <user> 或 userdel / passwd -l 锁定","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-NET-013 (主机安全/访问控制) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD='a=$(grep -vE '\''^#|^$'\'' /etc/hosts.allow 2>/dev/null | head -1); d=$(grep -vE '\''^#|^$'\'' /etc/hosts.deny 2>/dev/null | grep -iE "all" | head -1); if [ -n "$a" ] && [ -n "$d" ]; then echo OK; else echo FAIL; fi'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='OK'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-NET-013","category":"主机安全","subsystem":"访问控制","name":"主机访问控制 IP 限制(hosts.allow/deny)","severity":"medium","expected":"等于 OK","remediation":"在 /etc/hosts.allow 设置允许访问的 IP；在 /etc/hosts.deny 设置 ALL:ALL 拒绝全部","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-ACCT-014 (主机安全/账号管理) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD='awk -F: '\''($2==""){c++} END{print c+0}'\'' /etc/shadow 2>/dev/null'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='0'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-ACCT-014","category":"主机安全","subsystem":"账号管理","name":"禁止存在空密码的帐户","severity":"high","expected":"等于 0","remediation":"为所有空密码账号设置满足复杂度的口令：passwd <username>","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-LOG-015 (主机安全/日志) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='grep -hE "authpriv" /etc/rsyslog.conf /etc/syslog.conf /etc/syslog-ng/syslog-ng.conf 2>/dev/null | grep -vE '\''^#'\'' | head -2 | tr '\''\n'\'' '\'' '\'''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='authpriv'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-LOG-015","category":"主机安全","subsystem":"日志","name":"记录帐户登录日志(authpriv)","severity":"medium","expected":"匹配 authpriv","remediation":"在 /etc/rsyslog.conf 增加 authpriv.* /var/log/authlog 并重启 rsyslog","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-FTP-016 (主机安全/FTP) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD='u=$(grep -iE "root" /etc/vsftpd/ftpusers /etc/ftpusers /etc/vsftpd.user_list 2>/dev/null | head -1); if [ -n "$u" ]; then echo OK; else echo FAIL; fi'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='OK'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-FTP-016","category":"主机安全","subsystem":"FTP","name":"禁止 root 用户登录 FTP","severity":"medium","expected":"等于 OK","remediation":"在 vsftpd 的 ftpusers/user_list 中加入 root 等特权账号禁止其 FTP 登录；未安装 FTP 则视为合规","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-ENV-017 (主机安全/历史命令) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD='hf=$(grep -i '\''^HISTFILESIZE'\'' /etc/profile 2>/dev/null | awk -F= '\''{print $2}'\'' | tr -d '\'' '\'' | tail -1); hs=$(grep -i '\''^HISTSIZE'\'' /etc/profile 2>/dev/null | awk -F= '\''{print $2}'\'' | tr -d '\'' '\'' | tail -1); if [ -n "$hf" ] && [ "$hf" -le 5 ] && [ -n "$hs" ] && [ "$hs" -le 5 ]; then echo OK; else echo FAIL; fi'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='OK'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-ENV-017","category":"主机安全","subsystem":"历史命令","name":"历史命令设置(HISTFILESIZE/HISTSIZE)","severity":"low","expected":"等于 OK","remediation":"在 /etc/profile 设置 HISTFILESIZE=5 与 HISTSIZE=5","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-AUTH-018 (主机安全/登录控制) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD='grep -cE '\''^pts'\'' /etc/securetty 2>/dev/null || echo 0'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='0'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-AUTH-018","category":"主机安全","subsystem":"登录控制","name":"限制 root 用户登录系统(securetty 不含 pts)","severity":"medium","expected":"等于 0","remediation":"在 /etc/securetty 仅保留控制台 tty，删除 pts 等远程终端条目","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-SVC-019 (主机安全/服务) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD='bad=0; for s in telnet.socket ftp.service sendmail.service klogin kshell ntalk tftp imap pop3; do e=$(systemctl is-enabled "$s" 2>/dev/null); if [ "$e" = "enabled" ]; then bad=1; fi; done; [ "$bad" -eq 0 ] && echo OK || echo FAIL'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='OK'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-SVC-019","category":"主机安全","subsystem":"服务","name":"禁用不必要的系统服务","severity":"medium","expected":"等于 OK","remediation":"关闭并禁用 telnet/ftp/sendmail/klogin/kshell/ntalk/tftp/imap/pop3 等非必要服务","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-SYS-020 (主机安全/系统加固) ----
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
ITEM_MDESC='审查 rpm -qa / dpkg -l 输出，卸载业务不需要的组件与服务，保持最小安装。'
ITEM_STATIC='"item_id":"LIN-SYS-020","category":"主机安全","subsystem":"系统加固","name":"操作系统遵循最小安装原则","severity":"low","expected":"","remediation":"卸载非必要软件包，如 rpm -e <pkg>","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-SYS-021 (主机安全/强制访问控制) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='getenforce 2>/dev/null || echo "na"'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?i)enforcing|permissive'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-SYS-021","category":"主机安全","subsystem":"强制访问控制","name":"开启 SELinux(可选)","severity":"low","expected":"匹配 (?i)enforcing|permissive","remediation":"修改 /etc/selinux/config 设置 SELINUX=enforcing 并重启","reference":"等保2.0 8.1.4"'
_run_item

# ---- LIN-SYS-022 (主机安全/防病毒) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='ps -ef 2>/dev/null | grep -iE "qaxsafed|clamd|savd|symantec" | grep -v grep | head -1'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='[a-zA-Z]'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"LIN-SYS-022","category":"主机安全","subsystem":"防病毒","name":"防病毒管理-Linux(可选)","severity":"low","expected":"匹配 [a-zA-Z]","remediation":"安装并运行必要的防病毒软件（如 ClamAV），及时更新病毒库","reference":"等保2.0 8.1.4"'
_run_item
# ---------------------------------------------------------------------------
# 主机元数据 + 汇总 + 输出
# ---------------------------------------------------------------------------
HOSTNAME=$(hostname 2>/dev/null || echo unknown)
OSVER=$( (cat /etc/os-release 2>/dev/null | awk -F= '/^PRETTY_NAME=/{v=$2; gsub(/"/,"",v); print v; exit}') )
KERNEL=$(uname -r 2>/dev/null || echo "")
COLLECTED=$(date -Iseconds 2>/dev/null || date "+%Y-%m-%dT%H:%M:%S")
CATALOG_ID="host_linux"
CATALOG_VER="1.0.0"
VERSIONS='{"db2":"1.0.0","db_mariadb":"1.0.0","db_mongodb":"1.0.0","db_mysql_linux":"1.0.0","db_mysql_win":"1.0.0","db_oracle_linux":"1.0.0","db_oracle_win":"1.0.0","db_postgresql":"1.0.0","db_redis":"1.0.0","db_sqlserver_win":"1.0.0","host_linux":"1.0.0"}'

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
