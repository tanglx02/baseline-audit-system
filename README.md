# 安全基线核查系统（Node.js 版）

一套「**收集脚本在目标服务器执行 → 结果上报 → 平台生成基线报告**」的安全基线核查系统，运行时**零 Python 依赖**。
基线核查项以 YAML 作为**单一事实来源**，收集脚本与 Web 平台共用，解耦协作。

> 后端为 **Node.js + Express + 内置 `node:sqlite`**，目标机收集脚本为**纯 bash（Linux）/ 纯 PowerShell（Windows）**。
> 已从 Python/Flask 重写为 Node.js，并新增：按类型拆分的独立收集脚本、报告导出（HTML/CSV/Excel）、在线/离线升级、设备标签、整改追踪、合规趋势对比等。
> **运行环境要求：Node.js ≥ 22.13.0**（`node:sqlite` 自该版本起免 `--experimental-sqlite` 标志即可使用）。

## 系统能做什么

- **覆盖广**：内置 **20 个基线目录、297 个核查项**，涵盖 Windows/Linux 主机、常用中间件（Nginx/Apache/Tomcat/WebLogic/IIS）、主流数据库（Redis/MySQL/MariaDB/PostgreSQL/MongoDB/Oracle/SQL Server/DB2）及基础设施（Docker/K8s/网络）。
- **平台无关采集**：每个类型（每个数据库、每个中间件、每个主机）都生成**独立**的收集脚本，Linux 用纯 bash、Windows 用系统自带 PowerShell，目标机**无需安装 Python**。
- **中心化报告**：上传目标机产出的 JSON 结果，自动生成概览仪表盘、逐台服务器/逐次扫描的明细报告。
- **报告导出**：支持 **HTML / CSV / Excel** 三种格式，单文件可直接发送或入表。
- **快速报告**：勾选基线模块、按 IP 与核查项逐项打分，直接生成最终合规报告（每个模块单独一份 HTML）。
- **整改追踪**：对不合规项逐项记录整改状态、责任人与期限，并导出整改清单 Excel。
- **趋势与对比**：展示合规率趋势曲线，并对比上一次扫描的结果变化。
- **设备标签与分组**：为设备打标签、按标签筛选，仪表盘给出「不合规 TOP 设备」与「平台分布」。
- **在线 / 离线升级**：支持通过 git 远程仓库在线升级，或上传源码压缩包离线升级，升级前自动备份。

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
│       ├── collect_db_redis.sh
│       ├── collect_mw_iis.ps1
│       ├── collect_host_windows.ps1
│       ├── collect_infra_network.sh / .ps1
│       └── manifest.json      # 下载页枚举清单
├── server/                   # Node.js + Express Web 平台（中心化报告）
│   ├── server.js             # 入口
│   ├── db.js                 # node:sqlite 数据层（数据文件 server/instance/app.db）
│   ├── upgrade.js            # 在线(git)/离线(压缩包) 升级：版本比对、备份、应用、重启
│   ├── config.js             # 项目配置（git 远程仓库、分支、是否自动重启），持久化 config.json
│   ├── baseline_reader.js    # 读 baseline YAML 供 /catalog 展示
│   ├── export.js             # 导出 HTML / CSV / Excel
│   ├── quick_report.js       # 快速报告模块
│   └── views/                # EJS 模板
├── version.json              # 当前版本号（升级比对依据）
├── config.json              # 升级配置（git 远程/分支/自动重启），用户配置不随升级覆盖
├── static/                   # 前端样式
├── package.json             # Node 依赖与脚本
└── docs/design.md            # 设计文档
```

## 部署

### 环境要求
- **Node.js ≥ 22.13.0**（后端使用内置 `node:sqlite`）。
- 目标被核查服务器：Linux 仅需 bash + coreutils；Windows 仅需系统自带 PowerShell（≥ 3.0）。**均无需安装 Node.js 或 Python**。

### 步骤

1. **安装依赖**（在平台所在机器，需 Node.js）
   ```bash
   npm install        # 安装 express/ejs/multer/exceljs/js-yaml/adm-zip（纯 JS，无原生编译）
   ```

2. **启动服务**
   ```bash
   npm start          # 默认监听 http://127.0.0.1:5000
   ```
   可通过环境变量指定端口：`PORT=8080 npm start`。
   开发模式（文件变更自动重启）：`npm run dev`。

3. **（可选）生产环境守护**
   - 使用进程管理器（如 `pm2 start server/server.js --name baseline-audit`）保持常驻；
   - 或在使用面板（如宝塔「Node 项目」）中以 `npm start` 守护运行；
   - 如需外网访问，可在前面加 Nginx 反向代理并配置 HTTPS。

4. **（可选）生成收集脚本**
   平台「下载脚本」页已提供各类型脚本；若需重新生成（例如修改了 YAML）：
   ```bash
   node collectors/build_collectors.js
   ```

> 数据持久化在 `server/instance/app.db`（SQLite），首次启动自动建表，无需手动初始化。

## 使用流程

### 1. 在目标服务器执行收集脚本（目标机无需 Python）
从平台「**下载脚本**」页按类型下载对应脚本（如 `collect_db_redis.sh` / `collect_mw_iis.ps1`），在**目标服务器**上执行：

```bash
# Linux（建议 root 运行以获取完整权限）
bash collect_db_redis.sh -o /tmp
bash collect_mw_nginx.sh  -o /tmp

# Windows（管理员 PowerShell，≥3.0）
powershell -ExecutionPolicy Bypass -File collect_db_sqlserver_win.ps1 -Out C:\tmp
```

脚本只跑**只读**命令，命令来自 YAML，不拼接用户输入；超时/无权限/文件缺失自动降级为 `unknown`，绝不改系统。生成的 `results_<host>_<时间戳>.json` 即上报文件。

### 2. 在平台上传并生成报告
打开「上传报告」，上传上一步的 `results_*.json`，平台自动生成：
- 概览仪表盘（服务器数、扫描数、平均合规率、平台分布、不合规 TOP 设备）；
- 每台服务器 / 每次扫描的报告（按类别/子系统分组，标注 通过 / 不合规 / 待人工 / 未知 与严重级别）；
- 合规率趋势曲线与「与上次扫描对比」；
- 历史记录、基线目录浏览、**下载脚本**页。

### 3. 整改追踪（可选）
在报告页的不合规项上填写整改状态、责任人与期限并保存；可一键导出「整改清单 Excel」。

## 系统升级（在线 / 离线）

- **在线升级（git）**：在「升级」页填写 git 远程仓库地址与分支并保存 → 点「检查更新」→ 系统 `git fetch` 比对远端 `version.json` → 若有新版点「立即更新」即拉取并（如需）重装依赖，随后自动重启。
- **离线升级（压缩包）**：在「升级」页上传含 `version.json` 的源码 `.zip` → 系统比对版本号，仅当比当前更新时才覆盖应用（排除 `node_modules` / `server/instance` / `config.json` / `dist-exe` / `backups`），随后自动重启。
- **安全**：任何更新前自动把当前源码备份到 `backups/<online|offline>-时间戳/`；自动重启可开关（设置项）。
- 当前版本见 `version.json`。

## 合规率口径

`合规率 = passed / (passed + failed)`。`manual`（待人工）与 `unknown`（检测异常）不计入分母，避免「未设置 = 通过」式虚高。

## 新增 / 修改核查项

1. 在对应目录 YAML 中按 `_schema.md` 增加 `item`，保证 `id` 全局唯一。
2. `method.type` 选 `shell / powershell / config_file / process / port / manual`。
3. `auto` 项必须配 `judge`，并尽量设置 `treat_empty_as` 兜底。
4. 跨发行版路径差异写进 `collectors/configs/paths.yaml`，YAML 只引用变量名。
5. 改语义时递增 `catalog.version`，跑 `node baseline/validate.js`。
6. 重新生成目标机脚本：`node collectors/build_collectors.js`，再在平台「下载脚本」页获取最新脚本。

## 导出格式

| 格式 | 路由 | 说明 |
|---|---|---|
| HTML | `/export/:id/html` | 单文件、内联 CSS，含目录/概述/分类统计/风险图表/不合规 TOP/失败列表 |
| CSV  | `/export/:id/csv`  | 含 UTF-8 BOM，Excel 直接打开不乱码 |
| Excel| `/export/:id/excel` | `.xlsx`，按分组多 sheet，便于汇总 |

JSON 数据可通过 `/api/reports/:id` 获取，便于对接第三方平台。

详见 `docs/design.md`。
