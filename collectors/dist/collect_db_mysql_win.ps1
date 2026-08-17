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
 "catalog_id": "db_mysql_win",
 "catalog_version": "1.0.0",
 "all_versions": {
  "db2": "1.0.0",
  "db_mariadb": "1.0.0",
  "db_mongodb": "1.0.0",
  "db_mysql_linux": "1.0.0",
  "db_mysql_win": "1.0.0"
 },
 "paths": {
  "mysql_conf": [
   "C:\\ProgramData\\MySQL\\MySQL Server 8.0\\my.ini",
   "C:\\ProgramData\\MySQL\\MySQL Server 5.7\\my.ini",
   "C:\\my.ini"
  ]
 },
 "items": [
  {
   "id": "MYSQLW-LOG-001",
   "category": "数据库安全",
   "subsystem": "MySQL",
   "name": "配置日志功能",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 10,
   "expected": "匹配 (?=.*log_error)(?=.*log_bin|.*general_log)",
   "remediation": "在 my.ini [mysqld] 增加 log_error、log_bin、general_log 并重启 MySQL 服务。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "shell",
    "cmd": "(Get-Content (Resolve-Path \"C:\\ProgramData\\MySQL\\MySQL Server 8.0\\my.ini\" -ErrorAction SilentlyContinue).Path -ErrorAction SilentlyContinue) -join \"`n\" | Select-String -Pattern \"log_error|log_bin|general_log\" | Where-Object { $_.Line -notmatch '^\\s*#' } | ForEach-Object { $_.Line } | Out-String -Stream | Select-Object -First 5 | ForEach-Object { $_ }"
   },
   "judge": {
    "type": "regex_present",
    "value": "(?=.*log_error)(?=.*log_bin|.*general_log)",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "MYSQLW-ACCT-002",
   "category": "数据库安全",
   "subsystem": "MySQL",
   "name": "删除匿名/无关账号",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "DROP USER ''@'localhost'; DROP USER ''@'%';",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "SELECT count(*) FROM mysql.user WHERE user=''; 结果为 0 则合规。需连库确认。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MYSQLW-ACCT-003",
   "category": "数据库安全",
   "subsystem": "MySQL",
   "name": "更改 root 用户名称",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "RENAME USER 'root'@'localhost' TO '新用户名'@'localhost';",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "SELECT count(*) FROM mysql.user WHERE user='root'; 为 0 则合规。需连库确认。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MYSQLW-CONN-004",
   "category": "数据库安全",
   "subsystem": "MySQL",
   "name": "设置最大连接数",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 10,
   "expected": "等于 OK",
   "remediation": "在 my.ini [mysqld] 设置 max_connections=1000。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "shell",
    "cmd": "$f=(Resolve-Path \"C:\\ProgramData\\MySQL\\MySQL Server 8.0\\my.ini\" -ErrorAction SilentlyContinue).Path; if(-not $f){\"FAIL\"}else{$c=(Select-String -Path $f -Pattern 'max_connections\\s*=' | ForEach-Object {($_.Line -replace '.*=\\s*','').Trim()} | Select-Object -First 1); if($c -and [int]$c -le 1000){\"OK\"}else{\"FAIL\"}}"
   },
   "judge": {
    "type": "equals",
    "value": "OK",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "MYSQLW-PWD-005",
   "category": "数据库安全",
   "subsystem": "MySQL",
   "name": "避免弱口令/空密码账号",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "为所有空密码/默认密码账号设置强口令：ALTER USER '<user>' IDENTIFIED BY '强口令';",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "SELECT * FROM mysql.user WHERE authentication_string='' OR authentication_string IS NULL; 无结果则合规。需连库确认。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MYSQLW-SVC-006",
   "category": "数据库安全",
   "subsystem": "MySQL",
   "name": "MySQL 服务以专用低权账户运行",
   "severity": "high",
   "check_type": "auto",
   "timeout": 10,
   "expected": "不包含 (?i)LocalSystem|NT AUTHORITY\\SYSTEM",
   "remediation": "将 MySQL 服务启动账户改为专用低权本地/域账户。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "(Get-WmiObject Win32_Service -Filter \"Name LIKE 'MySQL%'\" | Select-Object -First 1).StartName"
   },
   "judge": {
    "type": "regex_absent",
    "value": "(?i)LocalSystem|NT AUTHORITY\\SYSTEM",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "MYSQLW-NET-007",
   "category": "数据库安全",
   "subsystem": "MySQL",
   "name": "修改默认端口(非3306)",
   "severity": "low",
   "check_type": "auto",
   "timeout": 10,
   "expected": "不等于 3306",
   "remediation": "在 my.ini [mysqld] 设置 port=<非3306> 并重启 MySQL 服务。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "config_file",
    "pathCatalog": "mysql_conf",
    "format": "ini",
    "section": "mysqld",
    "key": "port"
   },
   "judge": {
    "type": "not_equals",
    "value": "3306",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "MYSQLW-FILE-008",
   "category": "数据库安全",
   "subsystem": "MySQL",
   "name": "数据目录权限(非 Everyone 可写)",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "通过 NTFS ACL 收紧数据目录权限。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "MySQL 数据目录应仅对 mysql 服务账户与管理员可访问，禁止 Everyone 可写。需人工核查 NTFS ACL。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MYSQLW-HIST-009",
   "category": "数据库安全",
   "subsystem": "MySQL",
   "name": "命令历史记录保护",
   "severity": "low",
   "check_type": "auto",
   "timeout": 10,
   "expected": "匹配 link|none",
   "remediation": "将 .mysql_history 重定向至 NUL 或受限位置。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "$p=\"$env:USERPROFILE\\.mysql_history\"; if(Test-Path $p -PathType Container){\"link\"}elseif(Test-Path $p){\"exists\"}else{\"none\"}"
   },
   "judge": {
    "type": "regex_present",
    "value": "link|none",
    "treat_empty_as": "pass"
   }
  },
  {
   "id": "MYSQLW-PWD-010",
   "category": "数据库安全",
   "subsystem": "MySQL",
   "name": "口令复杂度策略(validate_password)",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 10,
   "expected": "匹配 (?i)validate_password.policy\\s*[= ]\\s*(1|MEDIUM|2|STRONG)",
   "remediation": "在 my.ini 加载 validate_password 组件并设置 policy=MEDIUM。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "shell",
    "cmd": "(Get-Content (Resolve-Path \"C:\\ProgramData\\MySQL\\MySQL Server 8.0\\my.ini\" -ErrorAction SilentlyContinue).Path -ErrorAction SilentlyContinue) -join \"`n\" | Select-String -Pattern \"validate_password\" | Where-Object { $_.Line -notmatch '^\\s*#' } | ForEach-Object { $_.Line } | Out-String -Stream | Select-Object -First 3 | ForEach-Object { $_ }"
   },
   "judge": {
    "type": "regex_present",
    "value": "(?i)validate_password.policy\\s*[= ]\\s*(1|MEDIUM|2|STRONG)",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "MYSQLW-LOCAL-011",
   "category": "数据库安全",
   "subsystem": "MySQL",
   "name": "禁用 local_infile",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 10,
   "expected": "等于 0",
   "remediation": "在 my.ini [mysqld] 设置 local_infile=0。",
   "reference": "CIS MySQL Benchmark",
   "methodDescription": "",
   "method": {
    "type": "config_file",
    "pathCatalog": "mysql_conf",
    "format": "ini",
    "section": "mysqld",
    "key": "local_infile"
   },
   "judge": {
    "type": "equals",
    "value": "0",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "MYSQLW-SKIP-012",
   "category": "数据库安全",
   "subsystem": "MySQL",
   "name": "禁用 skip-grant-tables",
   "severity": "high",
   "check_type": "auto",
   "timeout": 10,
   "expected": "不包含 (?i)skip-grant-tables",
   "remediation": "确保 my.ini 不存在 skip-grant-tables，否则任何人均可无密码登录。",
   "reference": "CIS MySQL Benchmark",
   "methodDescription": "",
   "method": {
    "type": "shell",
    "cmd": "(Get-Content (Resolve-Path \"C:\\ProgramData\\MySQL\\MySQL Server 8.0\\my.ini\" -ErrorAction SilentlyContinue).Path -ErrorAction SilentlyContinue) -join \"`n\" | Select-String -Pattern \"skip-grant-tables\" | Where-Object { $_.Line -notmatch '^\\s*#' } | ForEach-Object { $_.Line } | Select-Object -First 1"
   },
   "judge": {
    "type": "regex_absent",
    "value": "(?i)skip-grant-tables",
    "treat_empty_as": "pass"
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
