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
 "catalog_id": "mw_iis",
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
  "infra_network": "1.0.0",
  "mw_apache": "1.0.0",
  "mw_iis": "1.0.0"
 },
 "paths": {},
 "items": [
  {
   "id": "IIS-LOGPATH-001",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "更改 Web 日志默认存放路径",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "将日志目录位置更改为独立分区。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "IIS管理器→站点→日志，已修改默认日志目录位置则合规。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-AUDIT-002",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "配置审核策略(成功+失败)",
   "severity": "high",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "将上述 9 类审核策略设为审核成功和失败。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "本地安全策略→审核策略：策略更改、登录事件、对象访问、进程跟踪、目录服务访问、特权使用、系统事件、账户登录事件、账户管理均审核成功与失败则合规。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-FTP-003",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "卸载不必要的 FTP/SMTP 服务组件",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 20,
   "expected": "不包含 Running",
   "remediation": "服务器管理器→Web服务器(IIS)角色，移除 FTP 与 SMTP 角色服务。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "(Get-Service -Name MSFTPSVC -ErrorAction SilentlyContinue).Status + ',' + (Get-Service -Name SMTPSVC -ErrorAction SilentlyContinue).Status"
   },
   "judge": {
    "type": "regex_absent",
    "value": "Running",
    "treat_empty_as": "pass"
   }
  },
  {
   "id": "IIS-ASPNET-004",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "管理 ASP.NET 功能扩展",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "移除或禁用 ASP.NET 服务扩展（如业务无需）。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "业务不需要 ASP 支持时应禁用 ASP.NET Web 服务扩展。需人工核查角色服务。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-LOG-005",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "启用日志功能(IIS格式)",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "启用日志功能并将日志格式设为 IIS。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "站点→日志，已启用日志记录且格式为 IIS 则合规。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-PATH-006",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "更改默认安装/物理路径",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "将站点物理路径设置到非系统盘自定义目录。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "站点基本设置中物理路径非默认 %SystemDrive%\\inetpub\\wwwroot 则合规。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-DEF-007",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "删除危险实例/示例目录",
   "severity": "high",
   "check_type": "auto",
   "timeout": 20,
   "expected": "不包含 FOUND:",
   "remediation": "删除 inetpub\\scripts、IISSamples、IISHelp、Printers 等示例/危险目录。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "@('C:\\inetpub\\scripts','C:\\inetpub\\scripts\\IISSamples','C:\\inetpub\\wwwroot\\IISSamples','C:\\inetpub\\wwwroot\\IISHelp','C:\\inetpub\\wwwroot\\printers') | ForEach-Object { if (Test-Path $_) { 'FOUND:' + $_ } }"
   },
   "judge": {
    "type": "regex_absent",
    "value": "FOUND:",
    "treat_empty_as": "pass"
   }
  },
  {
   "id": "IIS-MAP-008",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "删除不必要脚本映射(IIS6)",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "删除上述危险脚本映射扩展名。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "主目录→配置→映射，不存在 .htr/.idc/.stm/.shtm/.shtml/.printer/.htw/.ida/.idq 映射则合规。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-FTP6-009",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "卸载 FTP/SMTP 组件(IIS6)",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 20,
   "expected": "不包含 Running",
   "remediation": "添加/删除 Windows 组件→应用程序服务器→IIS，移除 FTP 与 SMTP。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "(Get-Service -Name MSFTPSVC -ErrorAction SilentlyContinue).Status + ',' + (Get-Service -Name SMTPSVC -ErrorAction SilentlyContinue).Status"
   },
   "judge": {
    "type": "regex_absent",
    "value": "Running",
    "treat_empty_as": "pass"
   }
  },
  {
   "id": "IIS-PATH6-010",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "更改默认安装路径(IIS6)",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "将主目录设置到非系统盘自定义位置。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "站点属性→主目录→本地路径非 %SystemDrive%\\Inetpub\\wwwroot 则合规。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-LOGP6-011",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "更改 Web 日志默认路径(IIS6)",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "修改默认日志文件路径到独立分区。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "站点属性→网站→日志属性，日志目录非 C:\\WINDOWS\\system32\\LogFiles 则合规。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-LOG6-012",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "启用日志功能(IIS6)",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "启用日志记录并采用 Microsoft IIS 日志文件格式。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "站点属性，已启用日志记录且采用 IIS 日志格式则合规。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-ASPNET6-013",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "管理 ASP.NET 功能扩展(IIS6)",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "禁用 ASP.NET Web 服务扩展。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "Web 服务扩展中已禁用 ASP.NET（如业务无需）则合规。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-MAP6-014",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "删除不必要脚本映射(IIS7+)",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "删除上述危险处理程序映射。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "处理程序映射中不存在 htr/idc/stm/shtm/shtml/printer/htw/ida/idq 映射则合规。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-TOUT6-015",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "连接超时设置(IIS6,120秒)",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "将连接超时设为 120 秒。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "站点属性→网站，超时时间为 120 秒则合规。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-TOUT-016",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "连接超时设置(IIS7+,120秒)",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "将连接超时设为 120 秒。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "站点→高级设置→限制→连接超时=120秒则合规。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-LOGD6-017",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "日志文件权限及审计字段(IIS6)",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "勾选记录日期、时间和扩展属性。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "日志属性→高级，记录日期、时间和扩展属性则合规。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "IIS-MAXCONN-018",
   "category": "中间件安全",
   "subsystem": "IIS",
   "name": "最大并发连接数(1000)",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "将最大并发连接数设为 1000。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "站点→高级设置→限制→最大并发连接数=1000 则合规。需人工核查。",
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
