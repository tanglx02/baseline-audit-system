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
 "catalog_id": "db_oracle_win",
 "catalog_version": "1.0.0",
 "all_versions": {
  "db2": "1.0.0",
  "db_mariadb": "1.0.0",
  "db_mongodb": "1.0.0",
  "db_mysql_linux": "1.0.0",
  "db_mysql_win": "1.0.0",
  "db_oracle_linux": "1.0.0",
  "db_oracle_win": "1.0.0"
 },
 "paths": {
  "oracle_listener_conf": [
   "C:\\app\\oracle\\product\\*\\dbhome_1\\network\\admin\\listener.ora",
   "%ORACLE_HOME%\\network\\admin\\listener.ora"
  ]
 },
 "items": [
  {
   "id": "ORAW-AUD-001",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "数据库审计策略(audit_trail)",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "alter system set audit_trail='OS' scope=spfile; 重启数据库。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "以 sysdba 执行 select value from v$parameter where name='audit_trail'; audit_trail 不为 NONE 则合规。需连库确认。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "ORAW-PWD-002",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "口令生存期(PASSWORD_LIFE_TIME<=90)",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "alter profile DEFAULT limit PASSWORD_LIFE_TIME 90;",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "select limit from dba_profiles where resource_name='PASSWORD_LIFE_TIME'; 值<=90 合规。需 SQL 核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "ORAW-PRIV-003",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "管理对象权限(除默认用户外无DBA角色)",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "revoke dba from <username>;",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "select a.username from dba_users a left join dba_role_privs b on a.username=b.grantee where granted_role='DBA' and a.username not in ('SYS','SYSMAN','SYSTEM'); 无其它 DBA 用户则合规。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "ORAW-DICT-004",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "启用数据字典保护(O7_DICTIONARY_ACCESSIBILITY=false)",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "alter system set O7_DICTIONARY_ACCESSIBILITY=FALSE scope=spfile; 重启。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "O7_DICTIONARY_ACCESSIBILITY 应为 false。需 SQL/参数核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "ORAW-PWD-005",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "最大认证失败次数(FAILED_LOGIN_ATTEMPTS<5)",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "alter profile DEFAULT limit FAILED_LOGIN_ATTEMPTS 5;",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "FAILED_LOGIN_ATTEMPTS 值<5(建议5)则合规。需 SQL 核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "ORAW-REM-006",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "限制SYSDBA远程登录(REMOTE_LOGIN_PASSWORDFILE=NONE)",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "alter system set REMOTE_LOGIN_PASSWORDFILE=NONE scope=spfile;",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "REMOTE_LOGIN_PASSWORDFILE 值为 NONE 则合规。需 SQL 核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "ORAW-NET-007",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "限制监听器远程管理(ADMIN_RESTRICTIONS)",
   "severity": "high",
   "check_type": "auto",
   "timeout": 10,
   "expected": "等于 ON",
   "remediation": "在 listener.ora 增加 ADMIN_RESTRICTIONS_LISTENER=ON 防止运行时被远程篡改。",
   "reference": "CIS Oracle Benchmark",
   "methodDescription": "",
   "method": {
    "type": "config_file",
    "pathCatalog": "oracle_listener_conf",
    "format": "key_value",
    "section": "",
    "key": "ADMIN_RESTRICTIONS_LISTENER"
   },
   "judge": {
    "type": "equals",
    "value": "ON",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "ORAW-NET-008",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "监听器启用口令验证(非默认空口令)",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "为监听器配置密码文件保护，禁用远程 listener 控制。",
   "reference": "CIS Oracle Benchmark",
   "methodDescription": "Windows 上 listener.ora 的 SID_LIST 不应明文暴露，且本地 OS 认证应受限。需人工核查监听器配置与密码文件。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "ORAW-SQL-009",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "关闭 SQLNET.ORA 危险参数",
   "severity": "high",
   "check_type": "auto",
   "timeout": 10,
   "expected": "不包含 (?i)SQLNET\\.AUTHENTICATION_SERVICES\\s*=\\s*\\(NONE\\)",
   "remediation": "确认 sqlnet.ora 未关闭认证服务；按需保留 NTSA 认证。",
   "reference": "CIS Oracle Benchmark",
   "methodDescription": "",
   "method": {
    "type": "shell",
    "cmd": "(Get-Content (Resolve-Path \"%ORACLE_HOME%\\network\\admin\\sqlnet.ora\" -ErrorAction SilentlyContinue).Path -ErrorAction SilentlyContinue) -join \" \""
   },
   "judge": {
    "type": "regex_absent",
    "value": "(?i)SQLNET\\.AUTHENTICATION_SERVICES\\s*=\\s*\\(NONE\\)",
    "treat_empty_as": "pass"
   }
  },
  {
   "id": "ORAW-SQL-010",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "启用 sqlnet 加密与校验(ENCRYPTION/CHECKSUM)",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 10,
   "expected": "匹配 (?i)SQLNET\\.ENCRYPTION_SERVER\\s*=\\s*REQUIRED|SQLNET\\.CRYPTO_CHECKSUM_SERVER\\s*=\\s*REQUIRED",
   "remediation": "在 sqlnet.ora 设置 SQLNET.ENCRYPTION_SERVER=REQUIRED 与 SQLNET.CRYPTO_CHECKSUM_SERVER=REQUIRED。",
   "reference": "CIS Oracle Benchmark",
   "methodDescription": "",
   "method": {
    "type": "shell",
    "cmd": "(Get-Content (Resolve-Path \"%ORACLE_HOME%\\network\\admin\\sqlnet.ora\" -ErrorAction SilentlyContinue).Path -ErrorAction SilentlyContinue) -join \" \""
   },
   "judge": {
    "type": "regex_present",
    "value": "(?i)SQLNET\\.ENCRYPTION_SERVER\\s*=\\s*REQUIRED|SQLNET\\.CRYPTO_CHECKSUM_SERVER\\s*=\\s*REQUIRED",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "ORAW-LST-011",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "监听器日志与跟踪开启",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "在 listener.ora 增加 LOG_DIRECTORY_LISTENER 与 LOG_FILE_LISTENER 配置。",
   "reference": "CIS Oracle Benchmark",
   "methodDescription": "listener.ora 应配置 LOG_DIRECTORY_LISTENER / LOG_FILE_LISTENER，确保监听器日志可用。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "ORAW-SVC-012",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "Oracle 服务以专用低权账户运行",
   "severity": "high",
   "check_type": "auto",
   "timeout": 10,
   "expected": "不包含 (?i)LocalSystem|NT AUTHORITY\\SYSTEM",
   "remediation": "将 Oracle 服务启动账户改为专用低权限域/本地账户，避免使用 LocalSystem。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "(Get-WmiObject Win32_Service -Filter \"Name LIKE 'OracleService%' OR Name='OracleOraDB19Home1TNSListener'\" | Select-Object -First 1).StartName"
   },
   "judge": {
    "type": "regex_absent",
    "value": "(?i)LocalSystem|NT AUTHORITY\\SYSTEM",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "ORAW-FILE-013",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "数据库文件/口令文件权限",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "通过 NTFS ACL 收紧 ORACLE_HOME 与口令文件权限。",
   "reference": "CIS Oracle Benchmark",
   "methodDescription": "ORACLE_HOME 及数据文件目录应限制为 DBA 组与管理员访问，口令文件(orapw)权限应受限。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "ORAW-ACCT-014",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "无默认/空口令账号(SCOTT 等)",
   "severity": "high",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "alter user SCOTT account lock; 或 drop user SCOTT;",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "锁定或删除 SCOTT、HR 等预置示例账号；确认无空口令账号。需连库核查 dba_users。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "ORAW-PATCH-015",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "已安装最新安全补丁(PSU/CPU)",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "下载并应用 Oracle 最新季度安全补丁(CPU)。",
   "reference": "CIS Oracle Benchmark",
   "methodDescription": "opatch lsinventory 确认已应用最新 CPU 补丁。需人工核查补丁级别。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "ORAW-LOG-016",
   "category": "数据库安全",
   "subsystem": "Oracle",
   "name": "审计记录归档与防篡改",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 10,
   "expected": "",
   "remediation": "将审计目录权限收紧并接入集中日志。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "审计轨迹(audit_trail=OS 时的 .aud 文件)应写入受保护目录并纳入日志收集。需人工核查。",
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
