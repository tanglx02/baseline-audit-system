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

# ---- DOCKER-SOCK-001 (容器安全/Docker) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_absent'
ITEM_TE='fail'
ITEM_CMD='ls -l /var/run/docker.sock 2>/dev/null | awk '\''{print $1, $3, $4}'\'' || echo "none"'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='srw-rw-rw-'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"DOCKER-SOCK-001","category":"容器安全","subsystem":"Docker","name":"限制 Docker 守护进程 socket 访问","severity":"high","expected":"不包含 srw-rw-rw-","remediation":"将 /var/run/docker.sock 权限收紧为 root:docker 660，或仅通过 TLS 远程 socket 访问。","reference":"CIS Docker Benchmark 1.2"'
_run_item

# ---- DOCKER-DAEMON-002 (容器安全/Docker) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_absent'
ITEM_TE='pass'
ITEM_CMD='ps -ef 2>/dev/null | grep -i "[d]ockerd" | grep -oE "\-H\s+tcp://[^ ]+" | head -1 || echo "none"'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='tcp://'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"DOCKER-DAEMON-002","category":"容器安全","subsystem":"Docker","name":"守护进程仅监听安全 socket","severity":"high","expected":"不包含 tcp://","remediation":"不要将 dockerd 暴露为 -H tcp://0.0.0.0:2375，必须使用 TLS 认证 socket。","reference":"CIS Docker Benchmark 2.1"'
_run_item

# ---- DOCKER-USERNS-003 (容器安全/Docker) ----
ITEM_CHECK='auto'
ITEM_MTYPE='config_file'
ITEM_TIMEOUT='10'
ITEM_FORMAT='json'
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD=''
ITEM_PC='/etc/docker/daemon.json
$DOCKER_HOME/daemon.json'
ITEM_SECTION=''
ITEM_KEY='userns-remap'
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='default|[^\s]'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"DOCKER-USERNS-003","category":"容器安全","subsystem":"Docker","name":"启用用户命名空间重映射(userns-remap)","severity":"medium","expected":"匹配 default|[^\\s]","remediation":"在 /etc/docker/daemon.json 设置 \"userns-remap\": \"default\" 并重启 dockerd。","reference":"CIS Docker Benchmark 2.8"'
_run_item

# ---- DOCKER-NEWP-004 (容器安全/Docker) ----
ITEM_CHECK='auto'
ITEM_MTYPE='config_file'
ITEM_TIMEOUT='10'
ITEM_FORMAT='json'
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD=''
ITEM_PC='/etc/docker/daemon.json
$DOCKER_HOME/daemon.json'
ITEM_SECTION=''
ITEM_KEY='no-new-privileges'
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='true'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"DOCKER-NEWP-004","category":"容器安全","subsystem":"Docker","name":"默认禁止容器获取新特权(no-new-privileges)","severity":"high","expected":"等于 true","remediation":"在 /etc/docker/daemon.json 设置 \"no-new-privileges\": true。","reference":"CIS Docker Benchmark 2.10"'
_run_item

# ---- DOCKER-LOG-005 (容器安全/Docker) ----
ITEM_CHECK='auto'
ITEM_MTYPE='config_file'
ITEM_TIMEOUT='10'
ITEM_FORMAT='json'
ITEM_JTYPE='not_equals'
ITEM_TE='fail'
ITEM_CMD=''
ITEM_PC='/etc/docker/daemon.json
$DOCKER_HOME/daemon.json'
ITEM_SECTION=''
ITEM_KEY='log-driver'
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='none'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"DOCKER-LOG-005","category":"容器安全","subsystem":"Docker","name":"配置日志驱动与轮转","severity":"medium","expected":"不等于 none","remediation":"在 daemon.json 设置 log-driver(如 json-file) 并配置 log-opts max-size/max-file 轮转。","reference":"CIS Docker Benchmark 2.12"'
_run_item

# ---- DOCKER-AUTH-006 (容器安全/Docker) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='equals'
ITEM_TE='fail'
ITEM_CMD='echo "${DOCKER_CONTENT_TRUST:-0}"'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='1'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"DOCKER-AUTH-006","category":"容器安全","subsystem":"Docker","name":"启用镜像内容信任(DCT)","severity":"medium","expected":"等于 1","remediation":"导出 DOCKER_CONTENT_TRUST=1，启用镜像签名校验。","reference":"CIS Docker Benchmark 2.15"'
_run_item

# ---- DOCKER-ROOT-007 (容器安全/Docker) ----
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
ITEM_MDESC='docker ps --format '\''{{.Names}}'\'' 后逐个 docker inspect 检查 HostConfig.Privileged 应为 false，且未挂载敏感宿主路径。'
ITEM_STATIC='"item_id":"DOCKER-ROOT-007","category":"容器安全","subsystem":"Docker","name":"容器不以 --privileged 运行","severity":"high","expected":"","remediation":"停止并重建以 --privileged 启动的容器；改用最小必要 cap-add。","reference":"CIS Docker Benchmark 5.4"'
_run_item

# ---- DOCKER-IMG-008 (容器安全/Docker) ----
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
ITEM_MDESC='镜像应来自可信仓库并经漏洞扫描(CVE)；禁止 latest 标签用于生产。需人工核查 CI 流水线。'
ITEM_STATIC='"item_id":"DOCKER-IMG-008","category":"容器安全","subsystem":"Docker","name":"使用可信基础镜像并定期扫描","severity":"medium","expected":"","remediation":"接入镜像扫描(Trivy/Clair)，固定镜像摘要，阻断高危漏洞镜像。","reference":"CIS Docker Benchmark 4.x"'
_run_item

# ---- DOCKER-RESOURCE-009 (容器安全/Docker) ----
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
ITEM_MDESC='生产容器应设 --memory/--cpus 上限，防止资源耗尽 DoS。需人工核查运行参数。'
ITEM_STATIC='"item_id":"DOCKER-RESOURCE-009","category":"容器安全","subsystem":"Docker","name":"限制容器资源(CPU/内存)","severity":"low","expected":"","remediation":"为容器设置 --memory 与 --cpus 限制。","reference":"CIS Docker Benchmark 5.10/5.11"'
_run_item

# ---- DOCKER-HEALTH-010 (容器安全/Docker) ----
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
ITEM_MDESC='关键容器镜像应定义 HEALTHCHECK，便于编排层剔除异常实例。需人工核查 Dockerfile。'
ITEM_STATIC='"item_id":"DOCKER-HEALTH-010","category":"容器安全","subsystem":"Docker","name":"配置容器健康检查","severity":"low","expected":"","remediation":"在 Dockerfile 增加 HEALTHCHECK 指令。","reference":"CIS Docker Benchmark 4.6"'
_run_item

# ---- DOCKER-FILE-011 (容器安全/Docker) ----
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
ITEM_MDESC='/etc/docker、daemon.json 及 TLS 证书文件权限应仅限 root 可读写。需人工核查 chmod 600/644。'
ITEM_STATIC='"item_id":"DOCKER-FILE-011","category":"容器安全","subsystem":"Docker","name":"守护进程与证书文件权限","severity":"medium","expected":"","remediation":"chmod 644 /etc/docker/daemon.json; chmod 600 /etc/docker/ca.pem /etc/docker/cert.pem /etc/docker/key.pem","reference":"CIS Docker Benchmark 2.x"'
_run_item

# ---- DOCKER-SECCOMP-012 (容器安全/Docker) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='docker info 2>/dev/null | grep -i "Security Options" | grep -i seccomp | head -1 || echo "none"'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='seccomp'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"DOCKER-SECCOMP-012","category":"容器安全","subsystem":"Docker","name":"启用默认 seccomp 配置","severity":"medium","expected":"匹配 seccomp","remediation":"确保 dockerd 未用 --seccomp-profile=unconfined；保持默认 seccomp。","reference":"CIS Docker Benchmark 5.5"'
_run_item

# ---- DOCKER-APPARMOR-013 (容器安全/Docker) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='docker info 2>/dev/null | grep -i "Security Options" | grep -iE "apparmor|selinux" | head -1 || echo "none"'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='apparmor|selinux'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"DOCKER-APPARMOR-013","category":"容器安全","subsystem":"Docker","name":"启用 AppArmor/SELinux 限制","severity":"medium","expected":"匹配 apparmor|selinux","remediation":"在支持 AppArmor/SELinux 的宿主启用对应 profile，未用 --security-opt apparmor=unconfined。","reference":"CIS Docker Benchmark 5.1"'
_run_item

# ---- DOCKER-UPD-014 (容器安全/Docker) ----
ITEM_CHECK='auto'
ITEM_MTYPE='shell'
ITEM_TIMEOUT='10'
ITEM_FORMAT=''
ITEM_JTYPE='regex_present'
ITEM_TE='fail'
ITEM_CMD='docker version --format '\''{{.Server.Version}}'\'' 2>/dev/null || echo "unknown"'
ITEM_PC=''
ITEM_SECTION=''
ITEM_KEY=''
ITEM_PROC=''
ITEM_PORT=''
ITEM_JVAL='[0-9]+\.[0-9]+'
ITEM_MDESC=''
ITEM_STATIC='"item_id":"DOCKER-UPD-014","category":"容器安全","subsystem":"Docker","name":"及时升级 Docker 到安全版本","severity":"medium","expected":"匹配 [0-9]+\\.[0-9]+","remediation":"升级 Docker Engine 至已修复已知漏洞的版本。","reference":"CIS Docker Benchmark 1.1"'
_run_item
# ---------------------------------------------------------------------------
# 主机元数据 + 汇总 + 输出
# ---------------------------------------------------------------------------
HOSTNAME=$(hostname 2>/dev/null || echo unknown)
OSVER=$( (cat /etc/os-release 2>/dev/null | awk -F= '/^PRETTY_NAME=/{v=$2; gsub(/"/,"",v); print v; exit}') )
KERNEL=$(uname -r 2>/dev/null || echo "")
COLLECTED=$(date -Iseconds 2>/dev/null || date "+%Y-%m-%dT%H:%M:%S")
CATALOG_ID="infra_docker"
CATALOG_VER="1.0.0"
VERSIONS='{"db2":"1.0.0","db_mariadb":"1.0.0","db_mongodb":"1.0.0","db_mysql_linux":"1.0.0","db_mysql_win":"1.0.0","db_oracle_linux":"1.0.0","db_oracle_win":"1.0.0","db_postgresql":"1.0.0","db_redis":"1.0.0","db_sqlserver_win":"1.0.0","host_linux":"1.0.0","host_windows":"1.0.0","infra_docker":"1.0.0"}'

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
