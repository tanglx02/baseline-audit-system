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
 "catalog_id": "db_sqlserver_win",
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
  "db_sqlserver_win": "1.0.0"
 },
 "paths": {},
 "items": [
  {
   "id": "MSSQL-AUTH-001",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "禁用混合身份验证(仅 Windows -auth)",
   "severity": "high",
   "check_type": "auto",
   "timeout": 10,
   "expected": "等于 1",
   "remediation": "将 LoginMode 设为 1（仅 Windows 身份验证），重启服务生效。",
   "reference": "CIS SQL Server Benchmark",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "(Get-ItemProperty \"HKLM:\\SOFTWARE\\Microsoft\\Microsoft SQL Server\\*\\MSSQLServer\" -ErrorAction SilentlyContinue).LoginMode"
   },
   "judge": {
    "type": "equals",
    "value": "1",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "MSSQL-SA-002",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "禁用或重命名 sa 账户",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "ALTER LOGIN sa DISABLE; 或 sp_rename 'sa','新名';",
   "reference": "CIS SQL Server Benchmark",
   "methodDescription": "执行 SELECT is_disabled FROM sys.sql_logins WHERE name='sa'; 应为 1(禁用)或已重命名。需连库确认。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MSSQL-PWD-003",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "强制口令策略与过期",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "ALTER LOGIN <login> WITH CHECK_POLICY=ON, CHECK_EXPIRATION=ON;",
   "reference": "CIS SQL Server Benchmark",
   "methodDescription": "所有登录应启用 CHECK_POLICY=ON 与 CHECK_EXPIRATION=ON，且无空口令。需连库核查 sys.sql_logins。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MSSQL-XP-004",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "禁用 xp_cmdshell",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "EXEC sp_configure 'xp_cmdshell',0; RECONFIGURE;",
   "reference": "CIS SQL Server Benchmark",
   "methodDescription": "exec sp_configure 'xp_cmdshell'; 应显示 run_value=0。需连库确认。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MSSQL-XP-005",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "禁用危险扩展过程(xp_delete_file 等)",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "DROP EXTENDED PROCEDURE xp_xxx; 或撤销 PUBLIC 执行权限。",
   "reference": "CIS SQL Server Benchmark",
   "methodDescription": "确认未注册/未启用 xp_regwrite、xp_delete_file、xp_dirtree 等危险扩展存储过程。需连库核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MSSQL-CLR-006",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "禁用 CLR 严格安全之外的危险 CLR",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "EXEC sp_configure 'clr enabled',0; RECONFIGURE;",
   "reference": "CIS SQL Server Benchmark",
   "methodDescription": "sp_configure 'clr enabled' 应为 0（除非业务强依赖）。需连库确认。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MSSQL-AUDIT-007",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "启用审计(Audit/SQL Audit)",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "CREATE SERVER AUDIT ... WITH (STATE=ON); 并关联 Audit Specification。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "应创建服务器级/库级审计并将操作写入安全位置。需人工核查 SSMS 审计配置。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MSSQL-PORT-008",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "修改默认端口(非1433)/隐藏实例",
   "severity": "low",
   "check_type": "auto",
   "timeout": 10,
   "expected": "不等于 1433",
   "remediation": "在 SQL Server 配置管理器将 TCP 端口改为非 1433，并可设置 HideInstance=1。",
   "reference": "CIS SQL Server Benchmark",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "(Get-ItemProperty \"HKLM:\\SOFTWARE\\Microsoft\\Microsoft SQL Server\\*\\MSSQLServer\\SuperSocketNetLib\\Tcp\" -ErrorAction SilentlyContinue).TcpPort"
   },
   "judge": {
    "type": "not_equals",
    "value": "1433",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "MSSQL-SVC-009",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "SQL Server 服务以专用低权账户运行",
   "severity": "high",
   "check_type": "auto",
   "timeout": 10,
   "expected": "不包含 (?i)LocalSystem|NT AUTHORITY\\SYSTEM",
   "remediation": "将 SQL Server 服务账户改为专用虚拟账户(如 NT SERVICE\\MSSQLSERVER)或低权域账户。",
   "reference": "CIS SQL Server Benchmark",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "(Get-WmiObject Win32_Service -Filter \"Name LIKE 'MSSQL$%' OR Name='MSSQLSERVER'\" | Select-Object -First 1).StartName"
   },
   "judge": {
    "type": "regex_absent",
    "value": "(?i)LocalSystem|NT AUTHORITY\\SYSTEM",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "MSSQL-ENC-010",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "启用透明数据加密(TDE)",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "CREATE DATABASE ENCRYPTION KEY ...; ALTER DATABASE <db> SET ENCRYPTION ON;",
   "reference": "CIS SQL Server Benchmark",
   "methodDescription": "敏感库应启用 TDE（sys.dm_database_encryption_keys 状态 ENCRYPTED）。需连库确认。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MSSQL-LINK-011",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "清理未授权链接服务器",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "EXEC sp_dropserver '<name>'; 移除多余链接服务器。",
   "reference": "CIS SQL Server Benchmark",
   "methodDescription": "sys.servers 中仅保留必要链接服务器，且不使用 sa 凭据。需连库核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MSSQL-LOGIN-012",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "限制 sysadmin 角色成员",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "ALTER SERVER ROLE sysadmin DROP MEMBER <login>;",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "SELECT * FROM sys.server_role_members WHERE role_principal_id=3; 仅必要账号为 sysadmin。需连库确认。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MSSQL-BAK-013",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "备份文件权限与加密",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "通过 NTFS ACL 收紧备份目录权限。",
   "reference": "CIS SQL Server Benchmark",
   "methodDescription": "备份目录应仅对 DBA 与备份账户可写，备份文件建议加密存储。需人工核查 NTFS ACL。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MSSQL-PATCH-014",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "安装最新 Service Pack/CU",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 10,
   "expected": "匹配 [0-9]+\\.[0-9]+",
   "remediation": "安装最新 Service Pack / Cumulative Update 以修复已知漏洞。",
   "reference": "CIS SQL Server Benchmark",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "(Get-ItemProperty \"HKLM:\\SOFTWARE\\Microsoft\\Microsoft SQL Server\\*\\MSSQLServer\\CurrentVersion\" -ErrorAction SilentlyContinue).CurrentVersion"
   },
   "judge": {
    "type": "regex_present",
    "value": "[0-9]+\\.[0-9]+",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "MSSQL-LOG-015",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "错误日志与登录失败审计保留",
   "severity": "low",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "配置多错误日志文件与登录失败审计。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "错误日志应保留多份并定期回收，登录失败应被记录。需人工核查日志配置。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "MSSQL-REM-016",
   "category": "数据库安全",
   "subsystem": "SQLServer",
   "name": "禁用 SQL Server Browser 服务(如非必需)",
   "severity": "low",
   "check_type": "auto",
   "timeout": 10,
   "expected": "不等于 Running",
   "remediation": "若不使用命名实例/动态端口，停止并禁用 SQL Server Browser 服务。",
   "reference": "CIS SQL Server Benchmark",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "(Get-Service SQLBrowser -ErrorAction SilentlyContinue).Status"
   },
   "judge": {
    "type": "not_equals",
    "value": "Running",
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
