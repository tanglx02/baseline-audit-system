'use strict';
/**
 * server.js — 安全基线核查系统（Node.js + Express + 内置 node:sqlite）
 * 提供：仪表盘 / 上传报告 / 服务器与报告 / 历史 / 基线目录 / 下载采集脚本 / 导出 / 授权后台
 */
const path = require('path');
const fs = require('fs');
const express = require('express');

const db = require('./db');
const license = require('./license');
const baseline = require('./baseline_reader');
const exporter = require('./export');
const config = require('./config');
const upgrade = require('./upgrade');
const multer = require('multer');

const ROOT = path.resolve(__dirname, '..');
const DIST_DIR = path.join(ROOT, 'collectors', 'dist');
const PORT = process.env.PORT || 5000;
const UPLOAD_DIR = path.join(ROOT, 'backups', '.uploads');
fs.mkdirSync(UPLOAD_DIR, { recursive: true });
const upload = multer({ dest: UPLOAD_DIR, limits: { fileSize: 300 * 1024 * 1024 } });

const app = express();
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(express.json({ limit: '8mb' }));
app.use(express.urlencoded({ extended: true }));
app.use('/static', express.static(path.join(ROOT, 'static')));
app.use('/dist', express.static(DIST_DIR));

// ---------------------------------------------------------------------------
// 授权网关：未授权时仅放行 /license 与只读参考页
// ---------------------------------------------------------------------------
function isLicensed() { return license.loadActiveLicense().valid; }
const ALLOWED = ['/license', '/catalog', '/download', '/health', '/static', '/dist', '/upgrade', '/settings'];
app.use((req, res, next) => {
  if (ALLOWED.some((p) => req.path === p || req.path.startsWith(p + '/'))) return next();
  if (req.path.startsWith('/license')) return next();
  if (req.path.startsWith('/api/upgrade') || req.path.startsWith('/api/settings')) return next();
  if (isLicensed()) return next();
  if (req.method === 'GET') return res.redirect('/license');
  return res.status(403).json({ error: '系统未授权，请到 /license 激活许可证。' });
});
app.locals.licenseStatus = () => license.loadActiveLicense();
app.locals.now = () => new Date();

// ---------------------------------------------------------------------------
// 报告聚合
// ---------------------------------------------------------------------------
function countStatus(items) {
  const c = { pass: 0, fail: 0, manual: 0, unknown: 0 };
  for (const f of items) c[f.status] = (c[f.status] || 0) + 1;
  return c;
}
function compRate(c) {
  const d = c.pass + c.fail;
  return d > 0 ? c.pass / d : null;
}
function groupFindings(rows) {
  const map = new Map();
  for (const f of rows) {
    const key = f.target_type || f.catalog_id || 'unknown';
    if (!map.has(key)) map.set(key, { target_type: key, target_label: f.target_label || key, platform: f.platform || '', items: [], seen: new Set() });
    const g = map.get(key);
    if (!g.seen.has(f.item_id)) { g.seen.add(f.item_id); g.items.push(f); }
  }
  const groups = [...map.values()].map((g) => {
    delete g.seen;
    g.counts = countStatus(g.items);
    g.compliance = compRate(g.counts);
    return g;
  });
  groups.sort((a, b) => a.target_type.localeCompare(b.target_type));
  return groups;
}
function buildReport(serverId) {
  const server = db.getServer(serverId);
  if (!server) return null;
  const findings = db.getServerFindings(serverId);
  const groups = groupFindings(findings);
  const all = groups.flatMap((g) => g.items);
  const totals = countStatus(all);
  totals.compliance = compRate(totals);
  totals.total = all.length;
  return { server, scans: db.getServerScans(serverId), groups, totals };
}
function buildScanReport(scanId) {
  const scan = db.getScan(scanId);
  if (!scan) return null;
  const findings = db.getScanFindings(scanId);
  const groups = groupFindings(findings.map((f) => ({ ...f, target_type: scan.target_type, target_label: scan.target_label, platform: scan.platform })));
  const all = groups.flatMap((g) => g.items);
  const totals = countStatus(all);
  totals.compliance = compRate(totals);
  totals.total = all.length;
  return { server: db.getServer(scan.server_id), scans: [scan], groups, totals, single: true };
}

// ---------------------------------------------------------------------------
// 页面路由
// ---------------------------------------------------------------------------
app.get('/', (req, res) => {
  res.render('dashboard', { stats: db.getDashboardStats(), servers: db.getServers() });
});

app.get('/license', (req, res) => {
  const status = license.loadActiveLicense();
  res.render('license', {
    machineCode: license.getMachineCode(),
    status,
    issued: db.getIssuedLicenses(),
  });
});

app.post('/license/generate', (req, res) => {
  const { machineCode, expiresAt, features, note } = req.body;
  if (!machineCode || !expiresAt) return res.status(400).json({ error: '缺少 machineCode 或 expiresAt' });
  const lic = license.generateLicense({ machineCode, expiresAt, features: features || ['all'] });
  db.insertIssuedLicense({ machine_code: machineCode, expires_at: expiresAt, features: features || ['all'], note: note || '', raw_license: lic });
  res.json({ license: lic });
});

app.post('/license/activate', (req, res) => {
  const { license: lic } = req.body;
  if (!lic) return res.status(400).json({ error: '缺少 license' });
  const saved = license.saveActiveLicense(lic);
  res.json(saved);
});

app.post('/license/deactivate', (req, res) => {
  license.deleteActiveLicense();
  res.json({ ok: true });
});

app.get('/upload', (req, res) => res.render('upload'));

app.post('/upload', (req, res) => {
  let doc;
  try { doc = JSON.parse(req.body.json); }
  catch (e) { return res.status(400).send('JSON 解析失败：' + e.message); }
  if (!doc || !doc.host || !Array.isArray(doc.results)) return res.status(400).send('缺少 host 或 results 字段');
  const server = db.upsertServer(doc.host);
  const catalogId = (doc.catalog && doc.catalog.id) || 'unknown';
  const scanId = db.insertScan({
    server_id: server.id,
    catalog_id: catalogId,
    target_type: catalogId,
    target_label: catalogId,
    platform: doc.host.platform || 'unknown',
    collector_version: doc.host.collector_version || '',
    summary: doc.summary || {},
  });
  db.insertFindings(scanId, doc.results);
  res.json({ ok: true, server_id: server.id, scan_id: scanId });
});

app.get('/servers', (req, res) => res.render('servers', { servers: db.getServers() }));

app.post('/servers/:id/delete', (req, res) => {
  db.deleteServer(parseInt(req.params.id, 10));
  res.redirect('/servers');
});

app.get('/servers/:id', (req, res) => {
  const report = buildReport(parseInt(req.params.id, 10));
  if (!report) return res.status(404).send('服务器不存在');
  res.render('report', { report, single: false });
});

app.get('/reports/:scanId', (req, res) => {
  const report = buildScanReport(parseInt(req.params.scanId, 10));
  if (!report) return res.status(404).send('扫描不存在');
  res.render('report', { report, single: true });
});

app.get('/history', (req, res) => {
  const servers = db.getServers();
  const all = [];
  for (const s of servers) for (const sc of db.getServerScans(s.id)) all.push({ ...sc, hostname: s.hostname });
  all.sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
  res.render('history', { scans: all });
});

app.get('/catalog', (req, res) => res.render('catalog', { catalogs: baseline.getCatalogs() }));

app.get('/download', (req, res) => {
  let manifest = { scripts: [] };
  try { manifest = JSON.parse(fs.readFileSync(path.join(DIST_DIR, 'manifest.json'), 'utf-8')); } catch (e) {}
  res.render('download', { scripts: manifest.scripts });
});

app.get('/download/:name', (req, res) => {
  const name = req.params.name;
  if (!/^[A-Za-z0-9_.-]+$/.test(name)) return res.status(400).send('非法文件名');
  let manifest = { scripts: [] };
  try { manifest = JSON.parse(fs.readFileSync(path.join(DIST_DIR, 'manifest.json'), 'utf-8')); } catch (e) {}
  if (!manifest.scripts.some((s) => s.file === name)) return res.status(404).send('文件不存在');
  const fp = path.join(DIST_DIR, name);
  if (!fs.existsSync(fp)) return res.status(404).send('文件不存在');
  res.download(fp, name);
});

// ---------------------------------------------------------------------------
// API + 导出
// ---------------------------------------------------------------------------
app.get('/api/reports/:id', (req, res) => {
  const report = buildReport(parseInt(req.params.id, 10));
  if (!report) return res.status(404).json({ error: 'not found' });
  res.json(report);
});

app.get('/export/:id/:fmt', async (req, res) => {
  const id = parseInt(req.params.id, 10);
  const report = buildReport(id);
  if (!report) return res.status(404).send('报告不存在');
  const host = report.server.hostname;
  const ts = new Date().toISOString().slice(0, 10);
  if (req.params.fmt === 'html') {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="baseline_report_${host}_${ts}.html"`);
    return res.send(exporter.exportHtml(report));
  }
  if (req.params.fmt === 'csv') {
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="baseline_report_${host}_${ts}.csv"`);
    return res.send(exporter.exportCsv(report));
  }
  if (req.params.fmt === 'excel') {
    try {
      const buf = await exporter.exportExcel(report);
      res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      res.setHeader('Content-Disposition', `attachment; filename="baseline_report_${host}_${ts}.xlsx"`);
      return res.send(buf);
    } catch (e) {
      return res.status(500).send('Excel 导出失败：' + e.message);
    }
  }
  res.status(400).send('不支持的格式');
});

app.get('/health', (req, res) => res.json({ ok: true, licensed: isLicensed() }));

// ---------------------------------------------------------------------------
// 升级 & 设置
// ---------------------------------------------------------------------------
app.get('/upgrade', (req, res) => {
  const cfg = config.getConfig();
  res.render('upgrade', { cfg, current: upgrade.getCurrentVersion(), gitAvailable: upgrade.gitAvailable() });
});

app.get('/settings', (req, res) => {
  res.render('settings', { cfg: config.getConfig() });
});

app.post('/settings', (req, res) => {
  const { gitRemote, gitBranch, autoRestart } = req.body;
  const merged = config.saveConfig({
    upgrade: {
      gitRemote: (gitRemote || '').trim(),
      gitBranch: (gitBranch || 'main').trim(),
      autoRestart: autoRestart === 'true' || autoRestart === true,
    },
  });
  res.json({ ok: true, config: merged });
});

app.post('/api/upgrade/check', (req, res) => {
  const cfg = config.getConfig();
  res.json(upgrade.onlineCheck(cfg.upgrade.gitRemote, cfg.upgrade.gitBranch));
});

app.post('/api/upgrade/online', (req, res) => {
  const cfg = config.getConfig();
  const r = upgrade.applyOnline(cfg.upgrade.gitRemote, cfg.upgrade.gitBranch);
  if (r.ok && cfg.upgrade.autoRestart) { res.json({ ...r, restarting: true }); upgrade.restartService(); }
  else res.json(r);
});

app.post('/api/upgrade/offline', upload.single('package'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: '缺少上传的升级包' });
  const check = upgrade.offlineCheck(req.file.path);
  if (check.error) return res.json({ ok: false, ...check });
  if (!check.newer) {
    return res.json({ ok: false, current: check.current, latest: check.latest, error: check.equal ? 'ALREADY_LATEST' : 'OLDER', message: '上传的版本不比当前新。' });
  }
  const r = upgrade.applyOffline(req.file.path);
  if (r.ok && config.getConfig().upgrade.autoRestart) { res.json({ ...r, restarting: true }); upgrade.restartService(); }
  else res.json(r);
});

// ---------------------------------------------------------------------------
function startServer(port, tries) {
  tries = tries || 0;
  const server = app.listen(port);
  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE' && tries < 30) {
      console.log(`[基线核查系统] 端口 ${port} 暂被占用，重试(${tries + 1})…`);
      setTimeout(() => startServer(port, tries + 1), 500);
    } else {
      console.error('[基线核查系统] 启动失败:', err.message);
      process.exit(1);
    }
  });
  server.on('listening', () => {
    const lic = license.loadActiveLicense();
    console.log(`[基线核查系统] http://127.0.0.1:${port}  (授权状态: ${lic.valid ? '已授权' : '未授权(' + lic.reason + ')'})`);
  });
}
startServer(PORT);

module.exports = app;
