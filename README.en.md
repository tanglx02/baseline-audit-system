# Security Baseline Audit System (Node.js)

A security baseline auditing system that works as **"run a collector on the target server → upload the result → the platform generates a baseline report"**, with **zero Python dependency** at runtime. Baseline check items are defined in YAML as the **single source of truth**, shared by both the collectors and the web platform for decoupled collaboration.

> The backend is **Node.js + Express + built-in `node:sqlite`**; the target-machine collectors are **pure bash (Linux) / pure PowerShell (Windows)**. The system was rewritten from Python/Flask to Node.js, and adds: per-type standalone collectors, report export (HTML/CSV/Excel), online/offline upgrade, device tagging, remediation tracking, and compliance trend comparison.
> **Runtime requirement: Node.js ≥ 22.13.0** (`node:sqlite` is available without the `--experimental-sqlite` flag from this version).

## What the system does

- **Broad coverage**: ships with **20 baseline catalogs and 297 check items**, covering Windows/Linux hosts, common middleware (Nginx/Apache/Tomcat/WebLogic/IIS), mainstream databases (Redis/MySQL/MariaDB/PostgreSQL/MongoDB/Oracle/SQL Server/DB2) and infrastructure (Docker/K8s/network).
- **Platform-independent collection**: each type (each database, each middleware, each host) gets its **own standalone collector** — pure bash on Linux and built-in PowerShell on Windows, so the target machine **does not need Python installed**.
- **Centralized reporting**: upload the JSON result produced on the target machine and the platform automatically builds an overview dashboard plus per-server / per-scan detailed reports.
- **Report export**: **HTML / CSV / Excel** formats, single-file output ready to send or import into a spreadsheet.
- **Quick report**: pick baseline modules, score each check item by IP, and generate a final compliance report directly (one standalone HTML per module).
- **Remediation tracking**: record remediation status, owner and due date for each non-compliant item, and export a remediation checklist as Excel.
- **Trend & comparison**: show the compliance-rate trend curve and compare it against the previous scan.
- **Device tags & grouping**: tag devices, filter by tag, and surface the "top non-compliant devices" and "platform distribution" on the dashboard.
- **Online / offline upgrade**: upgrade via a git remote repository online, or by uploading a source zip offline; the system backs up automatically before any update.

## Directory layout

```
baseline-audit-system/
├── baseline/                 # Single source of truth: all baseline catalog YAML
│   ├── _schema.md            # item structure convention (read first)
│   ├── validate.js           # validator (Node, zero-dep): node baseline/validate.js
│   └── *.yaml                # catalogs (20 in total)
├── collectors/               # Collector scripts (run on the target server)
│   ├── build_collectors.js   # generator (Node): reads baseline/*.yaml -> emits native scripts
│   ├── templates/            # bash / powershell collection engine templates
│   ├── configs/paths.yaml    # config-file path mapping (cross-distro / cross-OS)
│   └── dist/                 # generated artifacts (zero-dep, copy straight to target)
│       ├── collect_db_redis.sh
│       ├── collect_mw_iis.ps1
│       ├── collect_host_windows.ps1
│       ├── collect_infra_network.sh / .ps1
│       └── manifest.json      # download-page manifest
├── server/                   # Node.js + Express web platform (centralized reports)
│   ├── server.js             # entry point
│   ├── db.js                 # node:sqlite data layer (DB file: server/instance/app.db)
│   ├── upgrade.js            # online(git)/offline(zip) upgrade: version compare, backup, apply, restart
│   ├── config.js             # project config (git remote, branch, auto-restart), persisted to config.json
│   ├── baseline_reader.js    # reads baseline YAML for the /catalog view
│   ├── export.js             # export HTML / CSV / Excel
│   ├── quick_report.js       # quick report module
│   └── views/                # EJS templates
├── version.json              # current version (used for upgrade comparison)
├── config.json              # upgrade config (git remote/branch/auto-restart); not overwritten by upgrade
├── static/                   # front-end styles
├── package.json             # Node dependencies and scripts
└── docs/design.md            # design document
```

## Deployment

### Requirements
- **Node.js ≥ 22.13.0** (the backend uses the built-in `node:sqlite`).
- Target audited servers: Linux needs only bash + coreutils; Windows needs only built-in PowerShell (≥ 3.0). **Neither needs Node.js or Python installed.**

### Steps

1. **Install dependencies** (on the machine that runs the platform; needs Node.js)
   ```bash
   npm install        # installs express/ejs/multer/exceljs/js-yaml/adm-zip (pure JS, no native build)
   ```

2. **Start the service**
   ```bash
   npm start          # listens on http://127.0.0.1:5000 by default
   ```
   Override the port via environment variable: `PORT=8080 npm start`.
   Development mode (auto-restart on change): `npm run dev`.

3. **(Optional) production daemon**
   - Use a process manager (e.g. `pm2 start server/server.js --name baseline-audit`) to keep it running;
   - or run it under a hosting panel (e.g. the "Node project" in Baota) with `npm start`;
   - if public access is needed, put Nginx in front as a reverse proxy and enable HTTPS.

4. **(Optional) generate collector scripts**
   The platform's "Download scripts" page already serves per-type scripts; to regenerate them (e.g. after editing YAML):
   ```bash
   node collectors/build_collectors.js
   ```

> Data is persisted in `server/instance/app.db` (SQLite). Tables are created automatically on first start — no manual initialization needed.

## Usage workflow

### 1. Run the collector on the target server (no Python needed)
Download the matching script from the platform's "**Download scripts**" page (e.g. `collect_db_redis.sh` / `collect_mw_iis.ps1`) and run it on the **target server**:

```bash
# Linux (run as root for full visibility)
bash collect_db_redis.sh -o /tmp
bash collect_mw_nginx.sh  -o /tmp

# Windows (admin PowerShell, ≥3.0)
powershell -ExecutionPolicy Bypass -File collect_db_sqlserver_win.ps1 -Out C:\tmp
```

The script only runs **read-only** commands taken from the YAML and never concatenates user input; on timeout / no-permission / missing-file it degrades to `unknown` automatically and never modifies the system. The generated `results_<host>_<timestamp>.json` is the upload file.

### 2. Upload and generate the report on the platform
Open "Upload report", upload the `results_*.json` from step 1, and the platform automatically produces:
- an overview dashboard (server count, scan count, average compliance rate, platform distribution, top non-compliant devices);
- per-server / per-scan reports (grouped by category/subsystem, labeled pass / non-compliant / manual / unknown with severity);
- a compliance-rate trend curve and a "compare with previous scan" view;
- history, baseline catalog browser, and the "Download scripts" page.

### 3. Remediation tracking (optional)
On the report page, fill in remediation status, owner and due date for non-compliant items and save; export a "remediation checklist" as Excel with one click.

## System upgrade (online / offline)

- **Online upgrade (git)**: on the "Upgrade" page, enter the git remote URL and branch and save → click "Check for updates" → the system runs `git fetch` and compares the remote `version.json` → if a newer version exists, click "Update now" to pull (and reinstall deps if needed), then it restarts automatically.
- **Offline upgrade (zip)**: on the "Upgrade" page, upload a source `.zip` containing `version.json` → the system compares versions and only applies it when newer (excluding `node_modules` / `server/instance` / `config.json` / `dist-exe` / `backups`), then restarts automatically.
- **Safety**: before any update the current source is backed up to `backups/<online|offline>-timestamp/`; auto-restart is toggleable in settings.
- Current version is in `version.json`.

## Compliance-rate definition

`compliance rate = passed / (passed + failed)`. `manual` (needs human review) and `unknown` (detection error) are excluded from the denominator, avoiding the "not set = pass" inflation.

## Add / modify check items

1. In the matching catalog YAML, add an `item` per `_schema.md` and keep `id` globally unique.
2. Pick `method.type` from `shell / powershell / config_file / process / port / manual`.
3. `auto` items must have a `judge` and ideally a `treat_empty_as` fallback.
4. Cross-distro path differences go in `collectors/configs/paths.yaml`; the YAML only references the variable name.
5. When changing semantics, bump `catalog.version` and run `node baseline/validate.js`.
6. Regenerate target scripts: `node collectors/build_collectors.js`, then grab the latest scripts from the platform's "Download scripts" page.

## Export formats

| Format | Route | Notes |
|---|---|---|
| HTML | `/export/:id/html` | single file, inline CSS; includes TOC/overview/category stats/risk charts/top-fail list |
| CSV  | `/export/:id/csv`  | UTF-8 BOM so Excel opens it without mojibake |
| Excel| `/export/:id/excel` | `.xlsx`, grouped into multiple sheets for easy roll-up |

JSON data is available at `/api/reports/:id` for integrating with third-party platforms.

See `docs/design.md` for details.
