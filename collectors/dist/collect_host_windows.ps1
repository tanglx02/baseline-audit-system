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
 "catalog_id": "host_windows",
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
  "host_windows": "1.0.0"
 },
 "paths": {},
 "items": [
  {
   "id": "WIN-PWD-001",
   "category": "主机安全",
   "subsystem": "口令策略",
   "name": "密码策略（复杂性/长度/生存期）",
   "severity": "high",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "在本地安全策略中启用密码复杂性、设长度最小值8、最长180天、最短1天、强制历史5、禁用可还原加密存储。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "本地安全策略→帐户策略→密码策略：密码必须符合复杂性要求=已启用、长度最小值=8、最长使用期限=180、最短=1、强制历史=5、禁用可还原加密存储。需人工核查 secedit 导出。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-PWD-002",
   "category": "主机安全",
   "subsystem": "口令策略",
   "name": "账户锁定策略",
   "severity": "high",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "设置帐户锁定阈值为5次无效登录、锁定时间5分钟、复位计数器3分钟。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "本地安全策略→帐户策略→帐户锁定策略：锁定阈值=5次、锁定时间=5分钟、复位计数器=3分钟。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-RIGHT-003",
   "category": "主机安全",
   "subsystem": "用户权限",
   "name": "用户权限分配（远程关机/关闭系统/取得所有权）",
   "severity": "high",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "将上述用户权限仅保留 Administrators 组。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "本地安全策略→本地策略→用户权限分配：从远程系统强制关机、关闭系统、取得文件或其他对象的所有权仅保留 Administrators。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-ACC-004",
   "category": "主机安全",
   "subsystem": "账号管理",
   "name": "禁用 Guest 来宾帐户",
   "severity": "high",
   "check_type": "auto",
   "timeout": 15,
   "expected": "不等于 True",
   "remediation": "计算机管理→本地用户和组→Guest 属性→禁用帐户。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { (Get-LocalUser -Name 'Guest' -ErrorAction Stop).Enabled } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "not_equals",
    "value": "True",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-ACC-005",
   "category": "主机安全",
   "subsystem": "账号管理",
   "name": "修改管理员帐号名称",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "将 Administrator 重命名为非默认名称。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "Administrators 组中不存在名为 Administrator 的帐号则合规。需人工核查并更名。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-AUDIT-006",
   "category": "主机安全",
   "subsystem": "安全审计",
   "name": "审核策略（9类事件成功+失败）",
   "severity": "high",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "将 9 类审核策略设置为审核成功和失败。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "本地安全策略→本地策略→审核策略：帐户登录、帐户管理、目录服务访问、登录、对象访问、策略更改、特权使用、进程追踪、系统事件均审核成功与失败。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-SVC-007",
   "category": "主机安全",
   "subsystem": "服务",
   "name": "关闭不必要的服务（Messenger/Alerter/Telnet/Remote Registry 等）",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 20,
   "expected": "不包含 Running",
   "remediation": "将 Messenger、Alerter、Telnet、Remote Registry 等服务设为禁用并停止。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "('Messenger','Alerter','Telnet','RemoteRegistry','ClipSrv','Browser','TlntSvr' | ForEach-Object { (Get-Service -Name $_ -ErrorAction SilentlyContinue).Status }) -join ','"
   },
   "judge": {
    "type": "regex_absent",
    "value": "Running",
    "treat_empty_as": "pass"
   }
  },
  {
   "id": "WIN-SVC-008",
   "category": "主机安全",
   "subsystem": "服务",
   "name": "关闭不必要的服务（SMTP/SNMP/Web 发布）",
   "severity": "low",
   "check_type": "auto",
   "timeout": 20,
   "expected": "不包含 Running",
   "remediation": "将 SMTP、SNMP Service、World Wide Web Publishing 等不需要的服务设为禁用并停止。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "('SMTPSVC','SNMP','W3SVC' | ForEach-Object { (Get-Service -Name $_ -ErrorAction SilentlyContinue).Status }) -join ','"
   },
   "judge": {
    "type": "regex_absent",
    "value": "Running",
    "treat_empty_as": "pass"
   }
  },
  {
   "id": "WIN-SNMP-009",
   "category": "主机安全",
   "subsystem": "服务",
   "name": "加固 SNMP 团体名",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "修改 SNMP 团体名为高强度字符串（非 public、长度≥8）。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "SNMP Service 的 community strings 不为 public 且长度≥8。需人工核查服务属性安全选项卡。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-FS-010",
   "category": "主机安全",
   "subsystem": "文件系统",
   "name": "使用 NTFS 文件系统",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 15,
   "expected": "等于 NTFS",
   "remediation": "使用 convert C: /FS:NTFS 将系统盘转换为 NTFS。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { (Get-Volume -DriveLetter C -ErrorAction Stop).FileSystemType } Catch { 'UNKNOWN' }"
   },
   "judge": {
    "type": "equals",
    "value": "NTFS",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-SCREEN-011",
   "category": "主机安全",
   "subsystem": "会话安全",
   "name": "屏幕保护（5分钟+恢复登录）",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "控制面板→个性化→屏幕保护程序，启用并设置等待5分钟、勾选恢复时显示登录屏幕。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "启用屏幕保护、等待时间5分钟、恢复时显示登录屏幕。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-SHARE-012",
   "category": "主机安全",
   "subsystem": "文件共享",
   "name": "文件共享权限不为 everyone",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "将共享权限仅授予指定账户，移除 everyone。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "共享文件夹权限未授予 everyone。需人工核查计算机管理→共享文件夹。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-AV-013",
   "category": "主机安全",
   "subsystem": "防病毒",
   "name": "安装防病毒软件",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "安装防病毒软件并保持病毒库更新。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "已安装并及时更新防病毒软件。需人工核查控制面板→程序。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-FW-014",
   "category": "主机安全",
   "subsystem": "防火墙",
   "name": "启用 Windows 防火墙",
   "severity": "high",
   "check_type": "auto",
   "timeout": 20,
   "expected": "匹配 True",
   "remediation": "控制面板→Windows Defender 防火墙，启用所有配置文件的防火墙。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "(Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Enabled) -join ','"
   },
   "judge": {
    "type": "regex_present",
    "value": "True",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-SHARE-015",
   "category": "主机安全",
   "subsystem": "文件共享",
   "name": "删除默认共享（AutoShareServer/WKS=0）",
   "severity": "high",
   "check_type": "auto",
   "timeout": 15,
   "expected": "匹配 (?i)AutoShareServer=0",
   "remediation": "注册表 lanmanserver\\parameters 下设 AutoShareServer=0、AutoShareWKS=0，并删除默认共享。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { $p=Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\lanmanserver\\parameters' -ErrorAction Stop; \"$('AutoShareServer='+$p.AutoShareServer) $($('AutoShareWKS='+$p.AutoShareWKS)\" } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "regex_present",
    "value": "(?i)AutoShareServer=0",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-NET-016",
   "category": "主机安全",
   "subsystem": "会话安全",
   "name": "网络服务挂起时间（15分钟）",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "本地安全策略→安全选项，设置空闲挂起前时间为15分钟。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "安全选项『Microsoft 网络服务器: 暂停会话前所需的空闲时间量』=15分钟。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-AUTO-017",
   "category": "主机安全",
   "subsystem": "系统加固",
   "name": "关闭驱动器自动播放",
   "severity": "low",
   "check_type": "auto",
   "timeout": 15,
   "expected": "不等于 NOTFOUND",
   "remediation": "组策略→管理模板→Windows组件→自动播放策略，启用『关闭自动播放』并选所有驱动器。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { (Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer' -Name NoDriveTypeAutoRun -ErrorAction Stop).NoDriveTypeAutoRun } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "not_equals",
    "value": "NOTFOUND",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-TIME-018",
   "category": "主机安全",
   "subsystem": "时间同步",
   "name": "时间服务器时钟同步（w32time）",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 20,
   "expected": "匹配 (?i)state=Running",
   "remediation": "服务中启动 Windows Time 并设为自动，配置 NtpServer 时间服务器地址。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "$s=(Get-Service -Name w32time -ErrorAction SilentlyContinue).Status; $m=(Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\w32time\\Parameters' -Name NtpServer -ErrorAction SilentlyContinue).NtpServer; \"$('state='+$s) $($('ntp='+$m)\""
   },
   "judge": {
    "type": "regex_present",
    "value": "(?i)state=Running",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-LOGIN-019",
   "category": "主机安全",
   "subsystem": "会话安全",
   "name": "登录超时强制注销",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "本地安全策略→安全选项，启用上述两项。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "安全选项『网络安全: 在超过登录时间后强制注销』与『登录时间过期后断开连接』已启用。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-SESSION-020",
   "category": "主机安全",
   "subsystem": "会话安全",
   "name": "会话限制（不显示最后用户名/Ctrl+Alt+Del）",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "本地安全策略→安全选项，配置上述会话限制项。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "不显示最后的用户名=启用、交互式登录无须按 Ctrl+Alt+Del=禁用、过期前提示改密≠0。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-LOG-021",
   "category": "主机安全",
   "subsystem": "安全审计",
   "name": "系统/安全/应用日志大小≥51200KB",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 20,
   "expected": "匹配 (5[1-9][0-9]{3}|[6-9][0-9]{4})",
   "remediation": "事件查看器→Windows 日志，应用/系统/安全日志大小设≥51200KB 并按需改写事件。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "(Get-EventLog -List -ErrorAction SilentlyContinue | Where-Object { $_.Log -in 'Application','System','Security' } | ForEach-Object { [int]($_.MaximumSize/1KB) }) -join ','"
   },
   "judge": {
    "type": "regex_present",
    "value": "(5[1-9][0-9]{3}|[6-9][0-9]{4})",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-ANON-022",
   "category": "主机安全",
   "subsystem": "访问控制",
   "name": "限制匿名用户连接（SAM 匿名枚举）",
   "severity": "high",
   "check_type": "auto",
   "timeout": 15,
   "expected": "匹配 (?i)RestrictAnonymousSAM=1",
   "remediation": "本地安全策略→安全选项，启用『不允许 SAM 帐户的匿名枚举』与『不允许 SAM 帐户和共享的匿名枚举』。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { $lsa=Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Lsa' -ErrorAction Stop; \"$('RestrictAnonymousSAM='+$lsa.RestrictAnonymousSAM) $($('RestrictAnonymous='+$lsa.RestrictAnonymous)\" } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "regex_present",
    "value": "(?i)RestrictAnonymousSAM=1",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-DDOS-023",
   "category": "主机安全",
   "subsystem": "网络加固",
   "name": "SYN 攻击保护（SynAttackProtect=1）",
   "severity": "high",
   "check_type": "auto",
   "timeout": 15,
   "expected": "≥ 1",
   "remediation": "Tcpip\\Parameters 下设 SynAttackProtect=1、TcpMaxPortsExhausted=5、TcpMaxHalfOpen=500、TcpMaxHalfOpenRetried=400。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { (Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters' -Name SynAttackProtect -ErrorAction Stop).SynAttackProtect } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "numeric_geq",
    "value": "1",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-CHAN-024",
   "category": "主机安全",
   "subsystem": "网络加固",
   "name": "域成员安全通道数字加密/签名",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "本地安全策略→安全选项，启用上述域成员安全通道相关项。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "安全选项『域成员: 对安全通道数据进行数字加密(如果可能)/或数字签名(始终)/数字签名(如果可能)/需要强会话密钥』均启用。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-DEP-025",
   "category": "主机安全",
   "subsystem": "系统加固",
   "name": "启用数据执行保护(DEP)",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "系统属性→高级→性能设置→DEP，设为仅为基本 Windows 程序和服务启用。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "系统属性→高级→性能→数据执行保护=仅为基本 Windows 程序和服务启用 DEP。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-REBOOT-026",
   "category": "主机安全",
   "subsystem": "系统加固",
   "name": "蓝屏后自动重启",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "系统属性→高级→启动和故障恢复，勾选『自动重新启动』。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "启动和故障恢复→系统失败→自动重新启动已勾选。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-CLEARVM-027",
   "category": "主机安全",
   "subsystem": "系统加固",
   "name": "关机前清除虚拟内存页面",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "gpedit.msc→本地策略→安全选项，启用『关机: 清除虚拟内存页面文件』。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "安全选项『关机: 清除虚拟内存页面文件』已启用。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-STARTUP-028",
   "category": "主机安全",
   "subsystem": "系统加固",
   "name": "关闭不必要的自启动项",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "msconfig 或任务管理器，取消不必要的启动项。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "任务管理器/msconfig 中已关闭不必要的启动项。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-ACC-029",
   "category": "主机安全",
   "subsystem": "账号管理",
   "name": "停用不使用的帐号",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "计算机管理→本地用户和组，停用或删除非业务账号。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "非业务账号已停用或删除。需人工核查本地用户和组。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-NETACC-030",
   "category": "主机安全",
   "subsystem": "用户权限",
   "name": "从网络访问此计算机仅 Administrators",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "本地安全策略→用户权限分配，将『从网络访问此计算机』仅设为 Administrators 组。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "用户权限分配『从网络访问此计算机』仅包含 Administrators 组。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-PATCH-031",
   "category": "主机安全",
   "subsystem": "补丁",
   "name": "安装必要安全补丁",
   "severity": "high",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "通过 Windows Update 安装最新安全补丁。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "控制面板→程序→显示更新，确认已安装必要安全补丁。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-RDP-032",
   "category": "主机安全",
   "subsystem": "远程维护",
   "name": "远程桌面网络级身份验证(NLA)",
   "severity": "high",
   "check_type": "auto",
   "timeout": 15,
   "expected": "等于 1",
   "remediation": "系统属性→远程，勾选『仅允许运行带网络级身份验证的远程桌面的计算机连接』。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { (Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Terminal Server\\WinStations\\RDP-Tcp' -Name UserAuthentication -ErrorAction Stop).UserAuthentication } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "equals",
    "value": "1",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-SOFT-033",
   "category": "主机安全",
   "subsystem": "系统加固",
   "name": "无多余软件",
   "severity": "low",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "卸载与业务无关的多余软件。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "控制面板→程序，无多余/不必要软件。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-ACL-034",
   "category": "主机安全",
   "subsystem": "访问控制",
   "name": "关键目录 everyone 无写入权限",
   "severity": "high",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "取消其他用户对关键目录的完全控制权限。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "系统盘/应用/数据目录的安全 ACL 中，除 administrators 与 system 外其他用户无完全控制。需人工核查。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-MTU-035",
   "category": "主机安全",
   "subsystem": "网络加固",
   "name": "防止碎片攻击（EnablePMTUDiscovery=0）",
   "severity": "low",
   "check_type": "auto",
   "timeout": 15,
   "expected": "等于 0",
   "remediation": "Tcpip\\Parameters 下设 EnablePMTUDiscovery=0。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { (Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters' -Name EnablePMTUDiscovery -ErrorAction Stop).EnablePMTUDiscovery } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "equals",
    "value": "0",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-SYN-036",
   "category": "主机安全",
   "subsystem": "网络加固",
   "name": "启用 SYN 攻击保护（阈值）",
   "severity": "high",
   "check_type": "auto",
   "timeout": 15,
   "expected": "匹配 (?i)Syn=([1-9]|[1-9][0-9])",
   "remediation": "Tcpip\\Parameters 下设 SynAttackProtect=1、TcpMaxPortsExhausted=5、TcpMaxHalfOpen=500、TcpMaxHalfOpenRetried=400。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { $p=Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters' -ErrorAction Stop; \"$('Syn='+$p.SynAttackProtect) $($('Exh='+$p.TcpMaxPortsExhausted) $($('Half='+$p.TcpMaxHalfOpen) $($('Ret='+$p.TcpMaxHalfOpenRetried)))\" } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "regex_present",
    "value": "(?i)Syn=([1-9]|[1-9][0-9])",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-SRCROUTE-037",
   "category": "主机安全",
   "subsystem": "网络加固",
   "name": "防止源路由欺骗（DisableIPSourceRouting=1）",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 15,
   "expected": "≥ 1",
   "remediation": "Tcpip\\Parameters 下设 DisableIPSourceRouting=1（或2）。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { (Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters' -Name DisableIPSourceRouting -ErrorAction Stop).DisableIPSourceRouting } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "numeric_geq",
    "value": "1",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-ICMP-038",
   "category": "主机安全",
   "subsystem": "网络加固",
   "name": "禁止 ICMP 重定向（EnableICMPRedirect=0）",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 15,
   "expected": "等于 0",
   "remediation": "Tcpip\\Parameters 下设 EnableICMPRedirect=0。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { (Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters' -Name EnableICMPRedirect -ErrorAction Stop).EnableICMPRedirect } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "equals",
    "value": "0",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-IUSR-039",
   "category": "主机安全",
   "subsystem": "账号管理",
   "name": "禁用 Internet 来宾帐户",
   "severity": "medium",
   "check_type": "manual",
   "timeout": 15,
   "expected": "",
   "remediation": "计算机管理→本地用户和组，禁用 Internet 来宾帐户。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "Internet 来宾帐户（如 IUSR/IWAM）已禁用。需人工核查本地用户和组。",
   "method": {
    "type": "manual"
   }
  },
  {
   "id": "WIN-RDP-040",
   "category": "主机安全",
   "subsystem": "远程维护",
   "name": "关闭远程桌面服务",
   "severity": "high",
   "check_type": "auto",
   "timeout": 15,
   "expected": "等于 1",
   "remediation": "系统属性→远程，取消『允许远程连接到此计算机』（或注册表 fDenyTSConnections=1）。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { (Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Terminal Server' -Name fDenyTSConnections -ErrorAction Stop).fDenyTSConnections } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "equals",
    "value": "1",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-RDP-041",
   "category": "主机安全",
   "subsystem": "远程维护",
   "name": "修改默认远程登录端口（非3389）",
   "severity": "medium",
   "check_type": "auto",
   "timeout": 15,
   "expected": "不等于 3389",
   "remediation": "修改 RDP-Tcp\\PortNumber 为非 3389 的端口并重启。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { (Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Terminal Server\\WinStations\\RDP-Tcp' -Name PortNumber -ErrorAction Stop).PortNumber } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "not_equals",
    "value": "3389",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-AUTOLOG-042",
   "category": "主机安全",
   "subsystem": "系统加固",
   "name": "禁止用户开机自动登录（AutoAdminLogon=0）",
   "severity": "high",
   "check_type": "auto",
   "timeout": 15,
   "expected": "等于 0",
   "remediation": "Winlogon 下设 AutoAdminLogon=0（或删除该值）。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { (Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon' -Name AutoAdminLogon -ErrorAction Stop).AutoAdminLogon } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "equals",
    "value": "0",
    "treat_empty_as": "fail"
   }
  },
  {
   "id": "WIN-IPC-043",
   "category": "主机安全",
   "subsystem": "访问控制",
   "name": "禁止 IPC$ 空连接（restrictanonymous=1）",
   "severity": "high",
   "check_type": "auto",
   "timeout": 15,
   "expected": "等于 1",
   "remediation": "Lsa 下设 restrictanonymous=1，禁止 IPC$ 空连接枚举。",
   "reference": "等保2.0 8.1.4",
   "methodDescription": "",
   "method": {
    "type": "powershell",
    "cmd": "Try { (Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Lsa' -Name restrictanonymous -ErrorAction Stop).restrictanonymous } Catch { 'NOTFOUND' }"
   },
   "judge": {
    "type": "equals",
    "value": "1",
    "treat_empty_as": "fail"
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
