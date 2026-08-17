# 设计文档：安全基线核查系统（Node.js 版）

## 1. 目标与定位

把分散在运维/安全笔记里的「安全基线核查项」沉淀为一套可执行的系统：

- **收集脚本**在目标服务器上执行（只读），产出结构化 JSON；
- **Web 平台**接收上报结果，落地为数据库，呈现合规/不合规/待人工核查报告并支持导出。

设计原则：**单一事实来源**（baseline YAML）、**数据驱动检测**（YAML 声明命令与判定）、
**命令不注入**（命令来自 YAML，执行时不拼接用户输入）、**异常安全降级**（不改系统、不 sudo）、
**运行时零 Python 依赖**（后端 Node.js，目标机纯 bash/PowerShell）。

## 2. 总体架构

```
            运维机（有 Node.js ≥ 22.5）                  目标服务器（无 Python）
┌───────────────────────────┐  build_collectors.js ┌──────────────────────────┐
│ baseline/*.yaml            │ ── 翻译/生成 ─────────▶ │ collect_<type>.sh         │
│  (唯一事实来源)            │                        │ collect_<type>.ps1        │
│ baseline/validate.js       │                        │  （纯 bash / PowerShell） │
│ collectors/templates/      │                        └────────────┬─────────────┘
└───────────────────────────┘                                     │ 执行(只读)
                                                                   │ 产出 results_*.json
                                                                   ▼
┌──────────────────────────┐    results_*.json     ┌──────────────────────────┐
│ 目标服务器                │  ───────────────────▶ │ Node.js + Express 平台     │
│ (把脚本拷过来执行)         │   上传(/upload)        │  server/                  │
│                           │                        │   _ingest → node:sqlite    │
└──────────────────────────┘                        │   报告/历史/导出/下载脚本  │
                                                    │   授权网关(license.js)      │
                                                    └──────────────────────────┘
```

- **baseline/**：唯一事实来源。每个文件一个 `catalog`（id/platform/version/items）。`validate.js` 校验全部 YAML。
- **collectors/build_collectors.js**：生成器（仅运维机运行，需 Node）。读取全部 YAML，为**每个 catalog**
  产出**独立**的原生收集脚本到 `collectors/dist/`。脚本内嵌该 catalog 与判定逻辑，**目标机无需 Python**。
- **collectors/templates/**：bash / powershell 采集引擎模板（含判定求值、配置解析、进程/端口检查、JSON 构造）。
- **collectors/dist/**：生成产物，按类型命名的独立脚本（`collect_db_redis.sh`、`collect_mw_iis.ps1` …）+ `manifest.json`。
- **server/**：中心化平台，只做存储与呈现，不执行任何检测命令；`license.js` 提供授权机。

## 3. 收集脚本生成（按类型拆分）

与早期「一个大脚本覆盖全部」不同，本版为**每个 catalog 生成独立脚本**：

- 数据库每类一个（`collect_db_redis.sh`、`collect_db_mysql_win.ps1` …），中间件每类一个
  （`collect_mw_nginx.sh`、`collect_mw_iis.ps1` …），主机/容器/网络同理。
- 跨平台 catalog（`mysql`/`host`/`infra_network`）同时产出 `.sh` 与 `.ps1` 两个文件。
- 好处：目标机只需下载并运行**关心的那一类**，减小体积、降低权限面、便于按组件审计。

生成器把每个 item 翻译为原生脚本里的一段执行逻辑，运行时流程：

1. 采集主机元数据：hostname/os/platform/collector_version/collected_at。
2. 逐 item 执行：
   - `manual` → `status=manual`，message 取 description（不执行任何命令）。
   - `auto` → 采集实际值，再按 `judge` 判定 pass/fail。
   - 任何异常（超时 / 无权限 / 文件缺失 / 命令不存在）→ `status=unknown`，不中断其它项。
3. 汇总 `summary` 并写出 `results_<host>_<ts>.json`（UTF-8 无 BOM）。

> 原生脚本里所有中文/特殊字符以 **base64** 编码载荷形式内嵌，避免引号与转义问题；
> bash 端 `base64 -d` 解码、PowerShell 端还原。

### 3.1 method.type 分派

| type | 采集内容 |
|---|---|
| `shell` | 执行 `actual_cmd`（Linux，`sh -c`），取 stdout |
| `powershell` | 执行 `actual_cmd`（Windows），取 stdout |
| `config_file` | 按 `format`（ini/yaml/json/key_value/conf）解析 `path_catalog` 指向的配置文件，取 `section.key`（支持 dotted 路径） |
| `process` | 检查进程是否存在及启动用户（`running:user` / `not_running`） |
| `port` | 检查监听地址（可选 `expect_bind`） |
| `manual` | 不执行，仅人工核查说明 |

`config_file` 的路径通过 `collectors/configs/paths.yaml` 的 `path_catalog` 解析，
按 platform 取候选路径列表，取第一个存在的文件；支持 `$VAR` / `%VAR%` 展开。

## 4. 判定求值器（judge）

`judge.type` 白名单：`equals / not_equals / contains / regex_present / regex_absent /
numeric_leq / numeric_geq / file_perm_leq`。

- `treat_empty_as`：实际值为空时的兜底 `pass/fail`（**强烈建议配置**，避免「未设置=通过」误判）。
- `expected`：给报告展示的期望描述。

## 5. 结果 JSON 契约（collectors ↔ server）

```json
{
  "schema_version": 1,
  "host": {"hostname","os","os_version","kernel","platform","collector_version","collected_at"},
  "catalog": {"id","version","all_versions":{...}},
  "summary": {"total","passed","failed","manual","unknown","compliance_rate"},
  "results": [
    {"item_id","category","subsystem","name","severity","status",
     "actual","expected","message","remediation","reference"}
  ]
}
```

服务器以 `(hostname, platform)` 唯一复用 `Server`，每次上传新建一条 `Scan` 与多条 `Finding`。
`/upload` 接收 `body.json`（JSON 字符串），解析 `host` + `results` 后落地。

## 6. 合规率口径

`compliance_rate = passed / (passed + failed)`。`manual` 与 `unknown` 不计入分母。
理由：人工项与检测异常项无法判定是否合规，计入分母会虚高或虚低合规率。

## 7. 授权机（license.js + 独立授权管理机 LicenseManager.exe）

- **机器码** `getMachineCode()` = `SHA256(hostname | platform | release | 首块网卡 MAC)`。
- **签发** `generateLicense({ machineCode, expiresAt, features })`：`base64url(JSON).HMAC-SHA256(SECRET)`。
  SECRET 默认 `'BASELINE-AUDIT-SYSTEM-VENDOR-SECRET-2026'`，可用 `LICENSE_SECRET` 覆盖（需两端一致）。
- **校验** `validateLicense(str)`：验证签名、未过期（`exp`）、机器码匹配，返回 `{valid, payload, daysLeft, reason}`。
- **独立授权管理机**：签发 / 激活 / 校验 / 吊销统一由 `tools/license-manager`（Electron GUI）完成，
  打包为独立 Windows 程序 `LicenseManager.exe`（`npm run pack` → `dist-exe/LicenseManager-win32-x64/LicenseManager.exe`）。
  其 `core/license-core.js` 与 `server/license.js` **共用同一算法与默认密钥**，已交叉验证可互相签发/校验。
- **网站 `/license` 页为只读状态页**：仅展示本机机器码与授权状态，不再提供签发/激活表单。
- **网关**：`server.js` 中未授权时仅放行 `/license`、`/catalog`、`/download`、`/health`、
  `/static`、`/dist`；其余 GET 重定向至 `/license`，POST 返回 403。
- 许可证存于 `server/instance/license.key`（由授权管理机「激活」写入），无重启即生效。

## 8. 平台页面与导出

- 路由：`/`（概览）、`/upload`、`/servers`、`/servers/<id>`、`/reports/<id>`、
  `/history`、`/catalog`、`/download`（按四大类分组）、`/download/<name>`、`/license`（只读状态页）、
  `/servers/<id>/delete`、`/export/<id>/{html,csv,excel}`、`/api/reports/<id>`、`/health`。
- 导出实现（`export.js`）：
  - **HTML**：内联 CSS 单文件（`exportHtml`）；
  - **CSV**：含 UTF-8 BOM（`exportCsv`），Excel 直接打开不乱码；
  - **Excel**：`exceljs` 生成 `.xlsx`，按分组多 sheet（`exportExcel`，异步）。
- 存储：`node:sqlite`（Node 22 内置，零原生编译），建表 `servers/scans/findings/issued_licenses`，开启 WAL 与外键。

## 9. 覆盖范围决策（与原始笔记的关系）

原始笔记只覆盖部分基线。本系统在笔记基础上：

- **实现笔记已写明项**（host_linux/windows、db_mysql_linux、db_oracle_linux、各 mw_*）。
- **补全空白章节**：Redis、PostgreSQL、MongoDB、MariaDB、Oracle(Windows)、SQL Server(Windows)、
  MySQL(Windows)、DB2。
- **新增类别**：Docker、Kubernetes、网络设备（交换机/路由器/防火墙）。

## 10. 关键实现说明与已知约定

- **目标机零 Python 依赖**：Linux 仅要 bash + coreutils，Windows 仅要系统自带 PowerShell(≥3.0)。
  生成器 `build_collectors.js` 是唯一的 Node 运行时（在运维机跑）。
- **跨平台兼容**：Linux 主机脚本端口检测内置 `/proc/net/tcp` 回退、进程检测内置 `ps` 回退，
  兼容无 `ss/netstat`/`pgrep` 的极简/容器发行版；Windows 主机脚本内置 CIM→WMI、netstat 回退，兼容 Win7+/2008R2+。
- 收集脚本只跑只读命令；`actual_cmd` 禁止 `>`/`rm`/`systemctl restart` 等副作用。
- shell 命令均以 `timeout --kill-after=5s` 包裹（无 timeout 时降级为「后台+wait+sleep kill」），
  即便命令忽略 SIGTERM 也会被强制结束，杜绝卡死；极简容器也能跑。
- 配置文件解析器支持 `ini/key_value/conf/yaml/json`；yaml 与 json 均支持 dotted 路径。
- **编码约定**：`*.sh` 必须**纯 UTF-8 无 BOM**（否则 shebang 被破坏）；
  `*.ps1` 必须 **UTF-8 BOM**（PowerShell 5.1 在 GBK 代码页下才能正确读中文）。
  生成器对此分别处理（ps1 手动拼 BOM 字节），勿手改文件头。
- 判定中的正则使用单引号 YAML 标量以避免反斜杠转义问题。
- 后端依赖均为纯 JS（`express/ejs/multer/exceljs/js-yaml`），`node:sqlite` 为内置模块，无需原生编译。

## 11. 验证

- 结构校验：`node baseline/validate.js`（20 目录 / 297 项 / 0 错误）。
- 生成：运行 `node collectors/build_collectors.js`，`collectors/dist/` 产出 21 个独立脚本 + `manifest.json`；
  `bash -n collect_*.sh` 应通过语法检查。
- 端到端（已在 Windows 主机验证）：
  - Linux 类脚本（如 `collect_db_redis.sh`）产出 JSON，上传后 `/servers/<id>`、`/api/reports/<id>` 正常；
  - Windows 类脚本（`collect_infra_network.ps1`）产出 UTF-8 JSON，上传后生成 `platform=windows` 的服务器与扫描；
  - `/export/<id>/{html,csv,excel}` 均返回 200 且内容有效（Excel 为合法 `.xlsx`，CSV 带 BOM）；
  - 平台「下载脚本」页可枚举并下载全部类型脚本；授权网关在无效许可证时正确拦截。
