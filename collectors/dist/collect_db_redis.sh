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

# ---- REDIS-BIND-001 (数据库安全/Redis) ----
ITEM_CHECK='auto'
ITEM_MTYPE='config_file'
ITEM_TIMEOUT='10'
ITEM_FORMAT='key_value'
ITEM_JTYPE='regex_absent'
ITEM_TE='fail'
ITEM_CMD=''
ITEM_PC='/etc/redis/redis.conf
/etc/redis.conf
$REDIS_HOME/redis.conf
/usr/local/etc/redis.conf'
ITEM_SECTION=''
ITEM_KEY='bind'
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='0.0.0.0'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"REDIS-BIND-001","category":"数据库安全","subsystem":"Redis","name":"监听地址绑定(禁止0.0.0.0)","severity":"high","expected":"不包含 0.0.0.0","remediation":"redis.conf 设置 bind 127.0.0.1（或内网地址），禁止 0.0.0.0 公网暴露。","reference":"CIS Redis Benchmark"'
_run_item

# ---- REDIS-AUTH-002 (数据库安全/Redis) ----
ITEM_CHECK='auto'
ITEM_MTYPE='config_file'
ITEM_TIMEOUT='10'
ITEM_FORMAT='key_value'
ITEM_JTYPE='not_equals'
ITEM_TE='fail'
ITEM_CMD=''
ITEM_PC='/etc/redis/redis.conf
/etc/redis.conf
$REDIS_HOME/redis.conf
/usr/local/etc/redis.conf'
ITEM_SECTION=''
ITEM_KEY='requirepass'
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL=''
ITEM_MDESC=''
ITEM_STATIC='"item_id":"REDIS-AUTH-002","category":"数据库安全","subsystem":"Redis","name":"设置访问口令(requirepass)","severity":"high","expected":"不等于 ","remediation":"redis.conf 设置 requirepass <强密码>，重启 Redis。","reference":"CIS Redis Benchmark"'
_run_item

# ---- REDIS-PROT-003 (数据库安全/Redis) ----
ITEM_CHECK='auto'
ITEM_MTYPE='config_file'
ITEM_TIMEOUT='10'
ITEM_FORMAT='key_value'
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD=''
ITEM_PC='/etc/redis/redis.conf
/etc/redis.conf
$REDIS_HOME/redis.conf
/usr/local/etc/redis.conf'
ITEM_SECTION=''
ITEM_KEY='protected-mode'
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='yes'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"REDIS-PROT-003","category":"数据库安全","subsystem":"Redis","name":"启用 protected-mode","severity":"high","expected":"等于 yes","remediation":"redis.conf 设置 protected-mode yes。","reference":"CIS Redis Benchmark"'
_run_item

# ---- REDIS-USER-004 (数据库安全/Redis) ----
ITEM_CHECK='auto'
ITEM_MTYPE='process'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD=''
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC='redis-server'
ITEM_PORT=''
ITEM_JVAL='(?i)running:(?!root)'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"REDIS-USER-004","category":"数据库安全","subsystem":"Redis","name":"禁止以 root 运行 Redis","severity":"high","expected":"匹配 (?i)running:(?!root)","remediation":"创建专用 redis 用户并以 redis 用户启动 redis-server。","reference":"CIS Redis Benchmark"'
_run_item

# ---- REDIS-CMD-005 (数据库安全/Redis) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='grep -riE '\''^\s*rename-command'\'' /etc/redis/redis.conf /etc/redis.conf 2>/dev/null | grep -iE '\''FLUSHALL|FLUSHDB|CONFIG|KEYS'\'' | head -5'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='(?i)rename-command'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"REDIS-CMD-005","category":"数据库安全","subsystem":"Redis","name":"重命名/禁用危险命令","severity":"medium","expected":"匹配 (?i)rename-command","remediation":"redis.conf 中用 rename-command 禁用/重命名 FLUSHALL、FLUSHDB、CONFIG、KEYS 等危险命令。","reference":"CIS Redis Benchmark"'
_run_item

# ---- REDIS-MEM-006 (数据库安全/Redis) ----
ITEM_CHECK='auto'
ITEM_MTYPE='config_file'
ITEM_TIMEOUT='10'
ITEM_FORMAT='key_value'
ITEM_JTYPE='numeric_geq'
ITEM_TE='fail'
ITEM_CMD=''
ITEM_PC='/etc/redis/redis.conf
/etc/redis.conf
$REDIS_HOME/redis.conf
/usr/local/etc/redis.conf'
ITEM_SECTION=''
ITEM_KEY='maxmemory'
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='1'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"REDIS-MEM-006","category":"数据库安全","subsystem":"Redis","name":"设置最大内存限制(maxmemory)","severity":"low","expected":"≥ 1","remediation":"redis.conf 设置 maxmemory 限制，避免耗尽系统内存。","reference":"CIS Redis Benchmark"'
_run_item

# ---- REDIS-PERM-007 (数据库安全/Redis) ----
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
ITEM_MDESC='redis.conf 权限应 <= 600（仅属主可读写，其他用户无权限）。需人工核查 chmod。'
ITEM_STATIC='"item_id":"REDIS-PERM-007","category":"数据库安全","subsystem":"Redis","name":"配置文件权限(仅属主可读写)","severity":"medium","expected":"","remediation":"chmod 600 /etc/redis/redis.conf","reference":"CIS Redis Benchmark"'
_run_item

# ---- REDIS-LOG-008 (数据库安全/Redis) ----
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
ITEM_MDESC='redis.conf 应设置 logfile 启用日志，且不要以默认端口 6379 暴露在公网。需人工核查。'
ITEM_STATIC='"item_id":"REDIS-LOG-008","category":"数据库安全","subsystem":"Redis","name":"启用日志与禁止裸奔端口","severity":"medium","expected":"","remediation":"设置 logfile 路径并启用日志；通过防火墙/绑定内网限制访问。","reference":"CIS Redis Benchmark"'
_run_item
# ---------------------------------------------------------------------------
# 主机元数据 + 汇总 + 输出
# ---------------------------------------------------------------------------
HOSTNAME=$(hostname 2>/dev/null || echo unknown)
OSVER=$( (cat /etc/os-release 2>/dev/null | awk -F= '/^PRETTY_NAME=/{v=$2; gsub(/"/,"",v); print v; exit}') )
KERNEL=$(uname -r 2>/dev/null || echo "")
COLLECTED=$(date -Iseconds 2>/dev/null || date "+%Y-%m-%dT%H:%M:%S")
CATALOG_ID="db_redis"
CATALOG_VER="1.0.0"
VERSIONS='{"db2":"1.0.0","db_mariadb":"1.0.0","db_mongodb":"1.0.0","db_mysql_linux":"1.0.0","db_mysql_win":"1.0.0","db_oracle_linux":"1.0.0","db_oracle_win":"1.0.0","db_postgresql":"1.0.0","db_redis":"1.0.0"}'

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
