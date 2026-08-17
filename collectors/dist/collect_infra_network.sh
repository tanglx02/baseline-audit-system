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

# ---- NET-AUTH-001 (网络安全/网络设备) ----
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
ITEM_MDESC='登录设备确认所有账号均使用强口令，无 admin/admin、空口令或厂商默认凭据。需 console/SSH 核查。'
ITEM_STATIC='"item_id":"NET-AUTH-001","category":"网络安全","subsystem":"网络设备","name":"修改默认口令/无空口令","severity":"high","expected":"","remediation":"修改所有默认账号口令为不规律强口令；删除/禁用无用账号。","reference":"等保2.0 8.1.4 / CIS Network"'
_run_item

# ---- NET-TELNET-002 (网络安全/网络设备) ----
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
ITEM_MDESC='设备管理仅允许 SSHv2，确认未开放 telnet server。需登录设备核查 running-config。'
ITEM_STATIC='"item_id":"NET-TELNET-002","category":"网络安全","subsystem":"网络设备","name":"禁用 Telnet 明文管理","severity":"high","expected":"","remediation":"no telnet-server; 启用 line vty 仅 transport input ssh。","reference":"等保2.0 8.1.4"'
_run_item

# ---- NET-SSH-003 (网络安全/网络设备) ----
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
ITEM_MDESC='ip ssh version 2；管理 ACL 限制仅运维网段可 SSH。需核查配置。'
ITEM_STATIC='"item_id":"NET-SSH-003","category":"网络安全","subsystem":"网络设备","name":"仅启用 SSHv2 并限制源","severity":"high","expected":"","remediation":"ip ssh version 2; 配置 ACL 限制管理源地址。","reference":"等保2.0 8.1.4"'
_run_item

# ---- NET-SNMP-004 (网络安全/网络设备) ----
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
ITEM_MDESC='确认未使用 public/private 社区字，SNMP 仅启用 v3 带认证与加密。需核查配置。'
ITEM_STATIC='"item_id":"NET-SNMP-004","category":"网络安全","subsystem":"网络设备","name":"禁用 SNMP v1/v2c(仅 v3)","severity":"high","expected":"","remediation":"no snmp-server community public; snmp-server group v3 配合 auth/priv。","reference":"等保2.0 8.1.4"'
_run_item

# ---- NET-ACL-005 (网络安全/网络设备) ----
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
ITEM_MDESC='边界与互联系应有 ACL 控制互访，默认拒绝非法流量。需核查策略。'
ITEM_STATIC='"item_id":"NET-ACL-005","category":"网络安全","subsystem":"网络设备","name":"配置访问控制列表(ACL)","severity":"high","expected":"","remediation":"部署入向/出向 ACL，按最小授权放行必要流量。","reference":"等保2.0 8.1.3"'
_run_item

# ---- NET-LOG-006 (网络安全/网络设备) ----
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
ITEM_MDESC='设备应配置 syslog 指向日志服务器，记录登录与策略变更。需核查 logging host 配置。'
ITEM_STATIC='"item_id":"NET-LOG-006","category":"网络安全","subsystem":"网络设备","name":"启用日志并集中收集","severity":"medium","expected":"","remediation":"logging host <syslog-server>; logging trap informational。","reference":"等保2.0 8.1.4"'
_run_item

# ---- NET-NTP-007 (网络安全/网络设备) ----
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
ITEM_MDESC='设备应指向受信 NTP 服务器并保持时间一致。需核查 ntp server 配置。'
ITEM_STATIC='"item_id":"NET-NTP-007","category":"网络安全","subsystem":"网络设备","name":"配置 NTP 时间同步","severity":"low","expected":"","remediation":"配置 ntp server 指向内网/受信时间源。","reference":"等保2.0 8.1.4"'
_run_item

# ---- NET-PORT-008 (网络安全/网络设备) ----
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
ITEM_MDESC='未用端口应 shutdown 并置于未用 VLAN；access 端口关闭 DTP/协商。需核查接口配置。'
ITEM_STATIC='"item_id":"NET-PORT-008","category":"网络安全","subsystem":"网络设备","name":"关闭未使用物理/逻辑端口","severity":"medium","expected":"","remediation":"interface range 未用端口 shutdown; switchport mode access。","reference":"CIS Network"'
_run_item

# ---- NET-BANNER-009 (网络安全/网络设备) ----
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
ITEM_MDESC='登录前应展示法律/授权告警横幅(banner login)。需核查配置。'
ITEM_STATIC='"item_id":"NET-BANNER-009","category":"网络安全","subsystem":"网络设备","name":"配置登录告警横幅","severity":"low","expected":"","remediation":"配置 banner login 与 banner motd 法律声明。","reference":"等保2.0 8.1.4"'
_run_item

# ---- NET-AUDIT-010 (网络安全/网络设备) ----
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
ITEM_MDESC='失败登录应触发锁定/延时，关键操作应审计。需核查 aaa/.login block 配置。'
ITEM_STATIC='"item_id":"NET-AUDIT-010","category":"网络安全","subsystem":"网络设备","name":"启用操作审计与账户锁定","severity":"medium","expected":"","remediation":"启用 aaa authentication 与 login block-for 防暴破。","reference":"等保2.0 8.1.4"'
_run_item

# ---- NET-FW-011 (网络安全/防火墙) ----
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
ITEM_MDESC='防火墙安全策略默认动作应为 deny/deny-all，按需放行业务。需核查默认策略与规则排序。'
ITEM_STATIC='"item_id":"NET-FW-011","category":"网络安全","subsystem":"防火墙","name":"防火墙默认拒绝策略","severity":"high","expected":"","remediation":"将默认策略设为拒绝，按白名单放行。","reference":"等保2.0 8.1.3"'
_run_item

# ---- NET-FW-012 (网络安全/防火墙) ----
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
ITEM_MDESC='防火墙应记录会话/威胁日志并启用 IPS(如支持)，日志外发至 SIEM。需人工核查。'
ITEM_STATIC='"item_id":"NET-FW-012","category":"网络安全","subsystem":"防火墙","name":"启用会话日志与入侵防护","severity":"medium","expected":"","remediation":"开启会话与威胁日志，启用 IPS 规则集并外发至 SIEM。","reference":"等保2.0 8.1.4"'
_run_item
# ---------------------------------------------------------------------------
# 主机元数据 + 汇总 + 输出
# ---------------------------------------------------------------------------
HOSTNAME=$(hostname 2>/dev/null || echo unknown)
OSVER=$( (cat /etc/os-release 2>/dev/null | awk -F= '/^PRETTY_NAME=/{v=$2; gsub(/"/,"",v); print v; exit}') )
KERNEL=$(uname -r 2>/dev/null || echo "")
COLLECTED=$(date -Iseconds 2>/dev/null || date "+%Y-%m-%dT%H:%M:%S")
CATALOG_ID="infra_network"
CATALOG_VER="1.0.0"
VERSIONS='{"db2":"1.0.0","db_mariadb":"1.0.0","db_mongodb":"1.0.0","db_mysql_linux":"1.0.0","db_mysql_win":"1.0.0","db_oracle_linux":"1.0.0","db_oracle_win":"1.0.0","db_postgresql":"1.0.0","db_redis":"1.0.0","db_sqlserver_win":"1.0.0","host_linux":"1.0.0","host_windows":"1.0.0","infra_docker":"1.0.0","infra_k8s":"1.0.0","infra_network":"1.0.0"}'

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
