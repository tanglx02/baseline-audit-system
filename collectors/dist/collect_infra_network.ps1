# ===========================================================================
# 基线核查收集脚本（Windows）— 由 baseline/*.yaml 自动生成，零 Python 依赖
# 适用：Windows 7+/Server 2008R2+ 自带 PowerShell（≥3.0）
# 用法（PowerShell 中）：
#   powershell -ExecutionPolicy Bypass -File collect_xxx.ps1
#   powershell -ExecutionPolicy Bypass -File collect_xxx.ps1 -Out C:\tmp
# 说明：仅执行只读检测（注册表/服务/进程/端口/配置文件）；不修改系统。
#       建议以管理员身份运行以获取完整权限。不更改系统 PowerShell 执行策略。
# ===========================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'
$CollectorVersion = "2.0.0-ps1"

$CATALOG_JSON = @'
{
 "collector_version": "2.0.0-ps1",
 "catalog_id": "infra_network",
 "catalog_version": "1.0.0",
 "all_versions": {
  "db2": "1.0.0",
  "db_mariadb": "1.0.0",
  "db_mongodb": "1.0.0",
  "db_mysql_linux": "1.0.0",
  "db_mysql_win": "1.0.0",
  "db_oracle_linux": "1.0.0",
  "db_oracle_win": "1.0.0",
  "db_postgresql": "1.0.0",
  "db_redis": "1.0.0",
  "db_sqlserver_win": "1.0.0",
  "host_linux": "1.0.0",
  "host_windows": "1.0.0",
  "infra_docker": "1.0.0",
  "infra_k8s": "1.0.0",
  "infra_network": "1.0.0"
 },
 "paths": {},
 "items": [
  {
   "id": "NET-AUTH-001",
   "category": "网络安全",
   "subsystem": "网络设备",
   "name": "修改默认口令/无空口令",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "修改所有默认账号口令为不规律强口令；删除/禁用无用账号。",
   "reference": "等保2.0 8.1.4 / CIS Network",
   "methodDescription": "登录设备确认所有账号均使用强口令，无 admin/admin、空口令或厂商默认凭据。需 console/SSH 核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "NET-TELNET-002",
   "category": "网络安全",
   "subsystem": "网络设备",
   "name": "禁用 Telnet 明文管理",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "no telnet-server; 启用 line vty 仅 transport input ssh。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "设备管理仅允许 SSHv2，确认未开放 telnet server。需登录设备核查 running-config。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "NET-SSH-003",
   "category": "网络安全",
   "subsystem": "网络设备",
   "name": "仅启用 SSHv2 并限制源",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "ip ssh version 2; 配置 ACL 限制管理源地址。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "ip ssh version 2；管理 ACL 限制仅运维网段可 SSH。需核查配置。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "NET-SNMP-004",
   "category": "网络安全",
   "subsystem": "网络设备",
   "name": "禁用 SNMP v1/v2c(仅 v3)",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "no snmp-server community public; snmp-server group v3 配合 auth/priv。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "确认未使用 public/private 社区字，SNMP 仅启用 v3 带认证与加密。需核查配置。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "NET-ACL-005",
   "category": "网络安全",
   "subsystem": "网络设备",
   "name": "配置访问控制列表(ACL)",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "部署入向/出向 ACL，按最小授权放行必要流量。",
   "reference": "等保2.0 8.1.3",
   "methodDescription": "边界与互联系应有 ACL 控制互访，默认拒绝非法流量。需核查策略。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "NET-LOG-006",
   "category": "网络安全",
   "subsystem": "网络设备",
   "name": "启用日志并集中收集",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "logging host <syslog-server>; logging trap informational。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "设备应配置 syslog 指向日志服务器，记录登录与策略变更。需核查 logging host 配置。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "NET-NTP-007",
   "category": "网络安全",
   "subsystem": "网络设备",
   "name": "配置 NTP 时间同步",
   "severity": "low",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "配置 ntp server 指向内网/受信时间源。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "设备应指向受信 NTP 服务器并保持时间一致。需核查 ntp server 配置。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "NET-PORT-008",
   "category": "网络安全",
   "subsystem": "网络设备",
   "name": "关闭未使用物理/逻辑端口",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "interface range 未用端口 shutdown; switchport mode access。",
   "reference": "CIS Network",
   "methodDescription": "未用端口应 shutdown 并置于未用 VLAN；access 端口关闭 DTP/协商。需核查接口配置。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "NET-BANNER-009",
   "category": "网络安全",
   "subsystem": "网络设备",
   "name": "配置登录告警横幅",
   "severity": "low",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "配置 banner login 与 banner motd 法律声明。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "登录前应展示法律/授权告警横幅(banner login)。需核查配置。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "NET-AUDIT-010",
   "category": "网络安全",
   "subsystem": "网络设备",
   "name": "启用操作审计与账户锁定",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "启用 aaa authentication 与 login block-for 防暴破。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "失败登录应触发锁定/延时，关键操作应审计。需核查 aaa/.login block 配置。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "NET-FW-011",
   "category": "网络安全",
   "subsystem": "防火墙",
   "name": "防火墙默认拒绝策略",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "将默认策略设为拒绝，按白名单放行。",
   "reference": "等保2.0 8.1.3",
   "methodDescription": "防火墙安全策略默认动作应为 deny/deny-all，按需放行业务。需核查默认策略与规则排序。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "NET-FW-012",
   "category": "网络安全",
   "subsystem": "防火墙",
   "name": "启用会话日志与入侵防护",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "开启会话与威胁日志，启用 IPS 规则集并外发至 SIEM。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "防火墙应记录会话/威胁日志并启用 IPS(如支持)，日志外发至 SIEM。需人工核查。",
   "method": {
    "type": "manual"
   }
  }
 ]
}
'@
$data = $CATALOG_JSON | ConvertFrom-Json

function Expand-Candidates($pathCatalog) {
  $raw = $data.paths.$pathCatalog
  if ($null -eq $raw) { return @() }
  $out = @()
  foreach ($c in $raw) {
    $exp = [Environment]::ExpandEnvironmentVariables($c)
    try {
      $hits = Resolve-Path -Path $exp -ErrorAction SilentlyContinue
      foreach ($h in $hits) {
        if (Test-Path -Path $h.Path -PathType Leaf) { $out += $h.Path }
      }
    } catch {}
  }
  return $out
}

function Parse-Config($content, $fmt, $section, $key) {
  if ($fmt -eq 'json') {
    try { $o = $content | ConvertFrom-Json } catch { return $null }
    $node = $o
    if ($section) { foreach ($p in ($section -split '\.')) { if ($null -ne $node.$p) { $node = $node.$p } else { return $null } } }
    foreach ($p in ($key -split '\.')) { if ($null -ne $node.$p) { $node = $node.$p } else { return $null } }
    if ($node -is [bool]) { return $node.ToString().ToLower() }
    return [string]$node
  }
  if ($fmt -eq 'yaml') {
    $want = if ($section) { "$section.$key" } else { $key }
    $stack = @()
    foreach ($l in ($content -split "`n")) {
      if ($l -match '^\s*#') { continue }
      $indent = ($l -replace '^( *).*', '$1').Length
      while ($stack.Count -gt 0 -and $stack[-1].indent -ge $indent) { $stack = $stack[0..($stack.Count-2)] }
      if ($l -match '^\s*([^:]+):\s*(.*)$') {
        $kk = $matches[1].Trim(); $vv = $matches[2].Trim()
        $path = (@($stack | ForEach-Object { $_.key }) + $kk) -join '.'
        if ($vv -eq '') { $stack += [PSCustomObject]@{ key=$kk; indent=$indent } }
        else { if ($path -eq $want) { return $vv.Trim('"', "'") } }
      }
    }
    return $null
  }
  # key_value / ini / conf
  $lines = $content -split "`n"
  $inSection = if ($section) { $false } else { $true }
  foreach ($l in $lines) {
    $ls = $l.Trim()
    if ($ls -match '^\s*#') { continue }
    if ($section -and $ls -match '^\s*\[\s*([^\]]+)\s*\]') { $inSection = ($matches[1].Trim() -eq $section); continue }
    if (-not $inSection) { continue }
    if ($ls -match ("^\s*{0}\s*[=:]\s*(.*)" -f [regex]::Escape($key))) {
      $v = $matches[1].Trim()
      $v = $v -replace ';.*$', ''
      return $v.Trim('"', "'")
    }
  }
  return $null
}

function Get-ConfigValue($it) {
  $cands = Expand-Candidates $it.method.pathCatalog
  if ($cands.Count -eq 0) { return '__NOFILE__' }
  $found = $cands[0]
  try { $content = [System.IO.File]::ReadAllText($found) } catch { return '__NOPERM__' }
  return (Parse-Config $content $it.method.format $it.method.section $it.method.key)
}

function Test-Process($name) {
  $p = Get-Process -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p) { return "running:$($p.UserName)" }
  return 'not_running'
}

function Test-Port($port) {
  $addrs = $null
  # Win8+/Server2012+ 推荐；旧版无此 cmdlet 时回退 netstat
  try { $addrs = (Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalAddress) -join ',' } catch {}
  if (-not $addrs) {
    try {
      $hit = (netstat -ano -p tcp 2>$null | Where-Object { $_ -match ":$port\s" -and $_ -match 'LISTENING' })
      if ($hit) { $addrs = ($hit -join ',') }
    } catch {}
  }
  if ($addrs) { return $addrs } else { return 'not_listening' }
}

function Invoke-Judge($j, $actual) {
  $v = [string]$j.value
  $opt = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
  switch ($j.type) {
    'equals'        { return ("$actual") -eq $v }
    'not_equals'    { return ("$actual") -ne $v }
    'contains'      { return ("$actual").Contains($v) }
    'regex_present' { return [regex]::IsMatch("$actual", $v, $opt) }
    'regex_absent'  { return -not [regex]::IsMatch("$actual", $v, $opt) }
    'numeric_leq'   { $na = ([regex]::Matches("$actual", '-?\d+(\.\d+)?') | Select-Object -First 1).Value; if (-not $na) { return $false }; return ([double]$na) -le ([double]$v) }
    'numeric_geq'   { $na = ([regex]::Matches("$actual", '-?\d+(\.\d+)?') | Select-Object -First 1).Value; if (-not $na) { return $false }; return ([double]$na) -ge ([double]$v) }
    'file_perm_leq' { $pa = (Parse-Perm "$actual"); if ($null -eq $pa) { return $false }; return $pa -le [int]$v }
    default         { return $false }
  }
}

function Parse-Perm($s) {
  if ($s -match '^[-dlpscb][rwx-]{9}$') {
    $u = $s.Substring(1,3); $g = $s.Substring(4,3); $o = $s.Substring(7,3); $f=0;$gu=0;$go=0
    foreach ($grp in @($u,$g,$o)) {
      $v=0; if ($grp[0] -eq 'r'){ $v+=4 }; if ($grp[1] -eq 'w'){ $v+=2 }; if ($grp[2] -eq 'x'){ $v+=1 }
      if ($grp -eq $u){ $f=$v } elseif ($grp -eq $g){ $gu=$v } else { $go=$v }
    }
    return ($f*64 + $gu*8 + $go)
  }
  $d = ($s -replace '[^0-7]', '')
  if ($d -eq '') { return $null }
  $val=0; foreach ($ch in $d.ToCharArray()) { $val = $val*8 + [int]::Parse($ch) }
  return $val
}

# 操作系统信息：优先 CIM(Win8+/PS3+)；旧版无 CIM 时回退 WMI(PS2/Win7/2008R2)
function Get-OSCaptionVersion {
  $cap = $null; $ver = $null
  try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -First 1; if ($os) { $cap = $os.Caption; $ver = $os.Version } } catch {}
  if (-not $cap) { try { $os = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -First 1; if ($os) { $cap = $os.Caption; $ver = $os.Version } } catch {} }
  return $cap, $ver
}

$results = @()
foreach ($it in $data.items) {
  $actual = $null
  $status = 'unknown'
  $msg = ''
  if ($it.check_type -eq 'manual') {
    $status = 'manual'
    $msg = $it.methodDescription
    $actual = $null
  } else {
    $resolved = $true
    switch ($it.method.type) {
      'shell'       { $actual = (powershell -NoProfile -Command $it.method.cmd 2>$null) -join "`n" }
      'powershell'  { $actual = (powershell -NoProfile -Command $it.method.cmd 2>$null) -join "`n" }
      'config_file' {
        $actual = Get-ConfigValue $it
        if ($actual -eq '__NOFILE__') { $status='unknown'; $actual=$null; $msg='配置文件不存在'; $resolved=$false }
        elseif ($actual -eq '__NOPERM__') { $status='unknown'; $actual=$null; $msg='无权限读取配置文件'; $resolved=$false }
      }
      'process'     { $actual = Test-Process $it.method.processName }
      'port'        { $actual = Test-Port $it.method.port }
    }
    if ($resolved) {
      if ($null -eq $actual -or "$actual" -eq '') {
        if ($it.judge.treat_empty_as -eq 'pass') { $status='pass' } else { $status='fail' }
        $msg = '实际值为空，按 treat_empty_as 判定'
        $actual = ''
      } else {
        if (Invoke-Judge $it.judge $actual) { $status='pass' } else { $status='fail'; msg='不满足合规判定条件' }
      }
    }
  }
  $results += [PSCustomObject]@{
    item_id = $it.id
    category = $it.category
    subsystem = $it.subsystem
    name = $it.name
    severity = $it.severity
    status = $status
    actual = if ($null -eq $actual) { $null } else { "$actual" }
    expected = $it.expected
    message = $msg
    remediation = $it.remediation
    reference = $it.reference
  }
}

$hostname = $env:COMPUTERNAME
$osInfo = Get-OSCaptionVersion
$osName = $osInfo[0]
$osVer = $osInfo[1]
$collected = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
$passed = ($results | Where-Object { $_.status -eq 'pass' }).Count
$failed = ($results | Where-Object { $_.status -eq 'fail' }).Count
$manual = ($results | Where-Object { $_.status -eq 'manual' }).Count
$unknown = ($results | Where-Object { $_.status -eq 'unknown' }).Count
$total = $results.Count
$denom = $passed + $failed
$compliance = if ($denom -gt 0) { [math]::Round($passed / $denom, 4) } else { $null }

$doc = [PSCustomObject]@{
  schema_version = 1
  generator = 'baseline-collector-ps1'
  host = [PSCustomObject]@{
    hostname = $hostname; os = "$osName"; os_version = "$osVer"; kernel = ''
    platform = 'windows'; collector_version = $CollectorVersion; collected_at = $collected
  }
  catalog = [PSCustomObject]@{ id = $data.catalog_id; version = $data.catalog_version; all_versions = $data.all_versions }
  summary = [PSCustomObject]@{ total=$total; passed=$passed; failed=$failed; manual=$manual; unknown=$unknown; compliance_rate=$compliance }
  results = $results
}

$json = $doc | ConvertTo-Json -Depth 6
$OutDir = '.'
if ($args -contains '-Out') { $i = $args.IndexOf('-Out'); if ($i+1 -lt $args.Count) { $OutDir = $args[$i+1] } }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$ts = (Get-Date).ToString('yyyyMMdd_HHmmss')
$outFile = Join-Path $OutDir "results_${hostname}_${ts}.json"
# UTF-8 无 BOM，避免 JSON 解析器（含 Web 平台上传）因 BOM 失败（New-Object 兼容 PS3+）
[System.IO.File]::WriteAllText($outFile, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "基线结果已写入: $outFile" -ForegroundColor Green
Write-Output $json
