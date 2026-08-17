# 安全基线核查系统（Node.js 版）

一套「**收集脚本在目标服务器执行 → 结果上报 → 平台生成基线报告**」的安全基线核查系统，运行时**零 Python 依赖**。
基线核查项以 YAML 作为**单一事实来源**，收集脚本与 Web 平台共用，解耦协作。

> 本系统后端为 **Node.js + Express + 内置 `node:sqlite`**，目标机收集脚本为**纯 bash（Linux）/ 纯 PowerShell（Windows）**。
> 自 v2 起已从 Python/Flask 重写为 Node.js，并新增：**按类型拆分的独立收集脚本**、**报告导出（HTML/CSV/Excel）**、**授权机（机器码 + 有效期绑定）**。
> **运行环境要求：Node.js ≥ 22.13.0**（`node:sqlite` 自该版本起免 `--experimental-sqlite` 标志即可使用；生产环境建议 ≥ 24.15.0，已升为 Release Candidate 可上生产）。

## 覆盖范围

当前内置 **20 个基线目录、297 个核查项**，按**四大分类**组织在「下载脚本」页（点开分类即可下载对应脚本）。每个类型（每个数据库、每个中间件、每个主机）都生成**独立**的收集脚本：

| 分类 | 独立脚本（collect_*.sh / .ps1） |
|---|---|
| **Windows主机** | `host_windows`（43）、`infra_network`（12，Windows 版） |
| **Linux主机** | `host_linux`（22）、`infra_docker`（14）、`infra_k8s`（14）、`infra_network`（12，Linux 版） |
| **中间件** | `mw_nginx`（4）、`mw_apache`（10）、`mw_tomcat`（12）、`mw_weblogic`（12）、`mw_iis`（18） |
| **数据库** | `db_redis`（8）、`db_mysql`（linux+win，各 12）、`db_mariadb`（12）、`db_postgresql`（10）、`db_mongodb`（10）、`db_oracle`（linux 28 / win 16）、`db_sqlserver_win`（16）、`db2`（12） |

- 可脚本化的项 → `auto`（配置/进程/端口/命令检查）
- 纯控制台 / 安全策略 / 需连库确认的项 → `manual`（报告里单列「待人工核查」）

### 跨平台兼容性
- **Linux主机脚本**：兼容 RHEL/CentOS/Rocky/Alma、Ubuntu/Debian、SUSE、Alpine 等主流发行版。端口检测内置 `/proc/net/tcp` 解析回退（无需 `ss`/`netstat`），进程检测内置 `pgrep`→`ps` 回退；仅依赖 bash + coreutils。
- **Windows主机脚本**：兼容 **Windows 7+ / Server 2008R2+** 自带 PowerShell（≥3.0）。操作系统信息优先 `Get-CimInstance`，旧版自动回退 `Get-WmiObject`；端口检测优先 `Get-NetTCPConnection`，旧版回退 `netstat`；UTF-8 写文件用 `New-Object` 以兼容 PS3+。

> 跨平台目录（`mysql`/`oracle`/`host`/`infra_network`）会同时产出 `.sh`（Linux）与 `.ps1`（Windows）两个脚本；其余按目录 `platform` 字段产出对应平台脚本。Linux主机 / Windows主机 分类即按「运行平台」归并。

## 目录结构

```
基线核查系统/
├── baseline/                 # 单一事实来源：所有基线目录 YAML
│   ├── _schema.md            # item 结构约定（必读）
│   ├── validate.js           # 校验脚本（Node，零依赖）：node baseline/validate.js
│   └── *.yaml                # 各目录（20 个）
├── collectors/               # 收集脚本（在目标服务器执行）
│   ├── build_collectors.js   # 生成器（Node）：读 baseline/*.yaml → 产出各类型原生脚本
│   ├── templates/            # bash / powershell 采集引擎模板（含判定/解析逻辑）
│   ├── configs/paths.yaml    # 配置文件路径映射（跨发行版/系统）
│   └── dist/                 # 生成产物（零依赖，直接拷到目标机执行）
│       ├── collect_db_redis.sh        # 数据库：按类型独立
│       ├── collect_db_mysql_win.ps1
│       ├── collect_mw_nginx.sh        # 中间件：按类型独立
│       ├── collect_mw_iis.ps1
│       ├── collect_host_windows.ps1
│       ├── collect_infra_network.sh / .ps1
│       └── manifest.json              # 下载页枚举清单
├── server/                   # Node.js + Express Web 平台（中心化报告）
│   ├── server.js             # 入口（含授权网关中间件）
│   ├── db.js                 # node:sqlite 数据层
│   ├── license.js            # 授权校验（机器码 / 许可证校验，与 exe 同源算法）
│   ├── baseline_reader.js    # 读 baseline YAML 供 /catalog 展示
│   ├── export.js             # 导出 HTML / CSV / Excel
│   └── views/                # EJS 模板（含只读 /license 状态页）
├── tools/license-manager/    # 独立「授权管理机」（Electron GUI，打包为 Windows .exe）
│   ├── main.js / preload.js / index.html / renderer.js
│   ├── core/license-core.js  # 签发/校验算法，与 server/license.js 完全一致
│   └── package.json          # npm run pack -> dist-exe/LicenseManager-*.exe
├── static/                   # 前端样式
├── package.json / .npmrc      # Node 依赖与镜像配置
└── docs/design.md            # 设计文档
```

## 快速开始

### 1. 在目标服务器执行收集脚本（**目标机无需 Python**）

> 目标主机只跑原生脚本，**不安装 Python**：Linux 用纯 bash，Windows 用系统自带 PowerShell。

获取脚本（二选一）：
- 从 Web 平台「**下载脚本**」页按类型下载（如 `collect_db_redis.sh` / `collect_mw_iis.ps1`）；
- 或在运维机（有 Node）用生成器产出全部脚本：`node collectors/build_collectors.js`。

在**目标服务器**上执行（可只跑某一类）：

```bash
# Linux（仅需 bash + coreutils，建议 root 运行以获取完整权限）
bash collect_db_redis.sh -o /tmp
bash collect_mw_nginx.sh  -o /tmp

# Windows（管理员 PowerShell，≥3.0）
powershell -ExecutionPolicy Bypass -File collect_db_sqlserver_win.ps1 -Out C:\tmp
```

脚本只跑**只读**命令，命令来自 YAML，不拼接用户输入；超时/无权限/文件缺失自动降级为 `unknown`，绝不改系统。
生成的 `results_<host>_<时间戳>.json` 即上报文件。

### 2. 启动 Web 平台、授权、上报结果

```bash
npm install                 # 安装 express/ejs/multer/exceljs/js-yaml（纯 JS，无原生编译）
npm start                   # 监听 http://127.0.0.1:5000
```

首次打开会进入「**授权状态**」页（只读）。许可证的签发 / 激活 / 校验 / 吊销统一由独立的 **授权管理机（LicenseManager.exe）** 完成：

1. 在目标部署服务器上运行 `LicenseManager.exe` →「本机机器码」，复制其机器码；
2. 厂商侧用 `LicenseManager.exe` →「生成许可证」填入机器码 + 有效期，得到许可证字符串；
3. 客户在「激活」页选择服务器 `instance` 目录并粘贴许可证 → 写入 `server/instance/license.key`，平台即转为已授权（**无需重启**）。

> 网站 `/license` 页仅展示本机机器码与授权状态，不再提供签发/激活表单；签发能力已移到 `LicenseManager.exe`。
> 未授权时仅 `/license`、`/catalog`、`/download`、`/health` 可访问，其余页面重定向至授权页。

**构建授权管理机（开发时）：**
```bash
cd tools/license-manager
npm install                                  # 安装 electron / electron-packager（走 npmmirror 镜像）
npm run pack                                 # 打包为 dist-exe/LicenseManager-win32-x64/LicenseManager.exe
```
该 `.exe` 为独立 Windows 程序（GUI），算法与 `server/license.js` 完全一致，生成的许可证可直接被 Web 系统激活。

打开「上传报告」，上传第 1 步的 `results_*.json`，平台自动生成：
- 概览仪表盘（服务器、扫描数、平均合规率）
- 每台服务器/每次扫描的报告（按类别/子系统分组，标注 通过 / 不合规 / 待人工 / 未知 与严重级别）
- 历史记录、基线目录浏览、**下载脚本**页
- 导出：**HTML / CSV / Excel**（单文件，可直接发送或入表）

### 3. 校验基线目录 / 重新生成脚本（开发时，仅需 Node）

```bash
node baseline/validate.js                # 校验全部 YAML 合法、id 全局唯一、judge/method 类型白名单
node collectors/build_collectors.js      # 改完 YAML 后重新生成 collectors/dist/ 下各类型脚本
```

## 授权机制（授权机）

- **机器码** = `SHA256(hostname | platform | release | 首块网卡 MAC)`，本机唯一且稳定。
- **许可证** = `base64url(payload).HMAC-SHA256(SECRET)`，payload = `{ machineCode, exp, feat, iat }`。
  - `exp`：有效期（`YYYY-MM-DD`），过期即失效；
  - `feat`：功能范围（如 `all`）；
  - 签名密钥默认 `'BASELINE-AUDIT-SYSTEM-VENDOR-SECRET-2026'`，可用环境变量 `LICENSE_SECRET` 覆盖。
- **校验**：每次请求校验签名合法性、未过期、机器码匹配；任一不满足即视为未授权。
- **签发入口**：独立的授权管理机 `tools/license-manager`（Electron GUI，打包为 `LicenseManager.exe`）负责签发 / 激活 / 校验 / 吊销；其 `core/license-core.js` 与 `server/license.js` 共用同一算法与默认密钥 `BASELINE-AUDIT-SYSTEM-VENDOR-SECRET-2026`（可用 `LICENSE_SECRET` 覆盖，需两端一致）。网站 `/license` 页为只读状态页。

## 合规率口径

`合规率 = passed / (passed + failed)`。`manual`（待人工）与 `unknown`（检测异常）不计入分母，
避免「未设置=通过」式虚高。

## 新增 / 修改核查项

1. 在对应目录 YAML 中按 `_schema.md` 增加 `item`，保证 `id` 全局唯一。
2. `method.type` 选 `shell / powershell / config_file / process / port / manual`。
3. `auto` 项必须配 `judge`，并尽量设置 `treat_empty_as` 兜底。
4. 跨发行版路径差异写进 `collectors/configs/paths.yaml`，YAML 只引用变量名。
5. 改语义时递增 `catalog.version`，跑 `node baseline/validate.js`。
6. 重新生成目标机脚本：`node collectors/build_collectors.js`，
   再在平台「下载脚本」页获取最新的各类型脚本。

## 导出格式

| 格式 | 路由 | 说明 |
|---|---|---|
| HTML | `/export/:id/html` | 内联 CSS 单文件，可直接邮件发送或打印 |
| CSV  | `/export/:id/csv`  | 含 UTF-8 BOM，Excel 直接打开不乱码 |
| Excel| `/export/:id/excel` | `.xlsx`，按分组多 sheet，便于汇总 |

JSON 数据可通过 `/api/reports/:id` 获取，便于对接第三方平台。

详见 `docs/design.md`。
