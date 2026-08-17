# 安全基线核查系统（Node.js 版）

一套「**收集脚本在目标服务器执行 → 结果上报 → 平台生成基线报告**」的安全基线核查系统，运行时**零 Python 依赖**。
基线核查项以 YAML 作为**单一事实来源**，收集脚本与 Web 平台共用，解耦协作。

> 本系统后端为 **Node.js + Express + 内置 `node:sqlite`**，目标机收集脚本为**纯 bash（Linux）/ 纯 PowerShell（Windows）**。
> 自 v2 起已从 Python/Flask 重写为 Node.js，并新增：**按类型拆分的独立收集脚本**、**报告导出（HTML/CSV/Excel）**、**卡密激活（离线、不绑机器、可设有效期）**、**在线(git)/离线(压缩包) 升级**、**卡密生成机 exe**。
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
│   ├── license.js            # 授权校验（卡密 / 机器码许可证，与生成机同源算法）
│   ├── upgrade.js            # 在线(git)/离线(压缩包) 升级：版本比对、备份、应用、重启
│   ├── config.js             # 项目配置（git 远程仓库、分支、是否自动重启），持久化 config.json
│   ├── baseline_reader.js    # 读 baseline YAML 供 /catalog 展示
│   ├── export.js             # 导出 HTML / CSV / Excel（HTML 为云探同款版式）
│   └── views/                # EJS 模板（/license 卡密激活页、/upgrade 升级页 等）
├── tools/cardkey-generator/  # 独立「卡密生成机」（Electron GUI，打包为 Windows .exe）
│   ├── main.js / preload.js / index.html / renderer.js
│   ├── core/cardkey-core.js  # 卡密签发/校验算法，与 server/license.js 完全一致
│   └── package.json          # npm run pack -> dist-exe/CardKeyGenerator-*.exe
├── tools/license-manager/    # 旧的机器码授权管理机（已弃用，保留以备兼容）
├── version.json              # 当前版本号（升级比对依据）
├── config.json              # 升级配置（git 远程/分支/自动重启），用户配置不随升级覆盖
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

首次打开会进入「**授权状态**」页。本系统使用**卡密激活**：在页面粘贴卡密即可激活，**无需登录服务器改文件、不绑定机器**。

1. 供应商使用独立的「**卡密生成机（CardKeyGenerator.exe）**」批量生成卡密（可指定数量、有效期、功能范围）；
2. 用户向供应商（**联系作者 QQ：54312795**）获取卡密；
3. 在网站「授权状态」页把卡密粘贴进文本框 → 点「激活卡密」→ **即时生效，无需重启**。

> 卡密为离线签名令牌（`HMAC-SHA256`，算法与网站一致），不绑定机器，换机/重装后可重贴同一卡密。
> 未授权时仅 `/license`、`/catalog`、`/download`、`/health`、`/upgrade` 可访问，其余页面重定向至授权页。

**构建卡密生成机（开发时）：**
```bash
cd tools/cardkey-generator
npm install                                  # 安装 electron / electron-packager（走 npmmirror 镜像）
npm run pack                                 # 打包为 dist-exe/CardKeyGenerator-win32-x64/CardKeyGenerator.exe
```
该 `.exe` 为独立 Windows 程序（GUI），其 `core/cardkey-core.js` 与 `server/license.js` 共用同一算法与默认密钥，生成的卡密可直接被网站激活。

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

## 授权机制（卡密）

- **卡密** = `base64url(payload).HMAC-SHA256(SECRET)`，payload = `{ typ:'card', exp, feat, iat, rnd }`。
  - `typ:'card'`：卡密模式，校验时**不绑定机器**，可跨服务器使用；
  - `exp`：有效期（`YYYY-MM-DD`，留空为永久），过期即失效；
  - `feat`：功能范围（如 `all`）；
  - 签名密钥默认 `'BASELINE-AUDIT-SYSTEM-VENDOR-SECRET-2026'`，可用环境变量 `LICENSE_SECRET` 覆盖。
- **校验**：每次请求校验签名合法性、未过期；卡密不校验机器码。任一不满足即视为未授权。
- **签发入口**：独立的「**卡密生成机**」`tools/cardkey-generator`（Electron GUI，打包为 `CardKeyGenerator.exe`）负责批量生成卡密；其 `core/cardkey-core.js` 与 `server/license.js` 共用同一算法与默认密钥（可用 `LICENSE_SECRET` 覆盖，需两端一致）。
- 网站 `/license` 页直接在浏览器粘贴卡密即可激活（写入 `server/instance/license.key`），无需登录服务器。

## 系统升级（在线 / 离线）

- **在线升级（git）**：在「升级」页填写 git 远程仓库地址与分支并保存 → 点「检查更新」→ 系统 `git fetch` 比对远端 `version.json` → 若有新版点「立即更新」即 `git checkout` 拉取并（如需）重装依赖，随后自动重启。
- **离线升级（压缩包）**：在「升级」页上传含 `version.json` 的源码 `.zip` → 系统比对版本号，仅当比当前更新时才覆盖应用（排除 `node_modules` / `server/instance` / `config.json` / `dist-exe` / `backups`），随后自动重启。
- **安全**：任何更新前自动把当前源码备份到 `backups/<online|offline>-时间戳/`；自动重启可开关（设置项）。
- 当前版本见 `version.json`；部署时通过宝塔「Node 项目」守护进程运行，`npm start` 即 `node server/server.js`。

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
| HTML | `/export/:id/html` | 单文件、内联 CSS，版式对齐「云探合规管理系统安全分析报告」（目录/概述/分类统计/风险图表/不合规 TOP/失败列表） |
| CSV  | `/export/:id/csv`  | 含 UTF-8 BOM，Excel 直接打开不乱码 |
| Excel| `/export/:id/excel` | `.xlsx`，按分组多 sheet，便于汇总 |

JSON 数据可通过 `/api/reports/:id` 获取，便于对接第三方平台。

详见 `docs/design.md`。
