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
const quickReport = require('./quick_report');
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
app.locals.appVersion = () => upgrade.getCurrentVersion().version;

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
  res.render('dashboard', {
    stats: db.getDashboardStats(),
    servers: db.getServers(),
    topDevices: db.getTopNonCompliantServers(5),
    platforms: db.getPlatformDistribution(),
    tags: db.getAllTags(),
  });
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
  const v = license.validateLicense(lic);
  if (!v.valid) return res.json(v);
  // 卡密（一次性）：激活时核销，重复激活将被拒绝
  if (v.mode === 'card') {
    const r = license.redeemCardKey(lic);
    if (!r.ok) return res.json(r);
    return res.json({ valid: true, mode: 'card', daysLeft: r.daysLeft, payload: r.payload, message: '卡密激活成功（已核销，不可重复使用）。' });
  }
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
  // 设备标签（采集脚本可在 doc.tags 或 doc.host.tags 携带，逗号分隔）
  const rawTags = doc.tags || (doc.host && doc.host.tags);
  if (rawTags != null) db.updateServerTags(server.id, rawTags);
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

app.get('/servers', (req, res) => {
  let servers = db.getServers();
  const tag = req.query.tag;
  if (tag) servers = servers.filter((s) => (s.tags || '').split(',').map((x) => x.trim()).includes(tag));
  res.render('servers', { servers, tags: db.getAllTags(), activeTag: tag || '' });
});

app.post('/servers/:id/delete', (req, res) => {
  db.deleteServer(parseInt(req.params.id, 10));
  res.redirect('/servers');
});

app.post('/servers/:id/tags', (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!db.getServer(id)) return res.status(404).json({ error: '服务器不存在' });
  const s = db.updateServerTags(id, req.body.tags || '');
  res.json({ ok: true, server: s });
});

app.get('/servers/:id', (req, res) => {
  const id = parseInt(req.params.id, 10);
  const report = buildReport(id);
  if (!report) return res.status(404).send('服务器不存在');
  const trend = db.getServerScanCompliance(id);
  const remRows = db.getRemediations(id);
  const remMap = {};
  for (const r of remRows) remMap[r.item_id] = r;
  // 与上期对比：最新扫描 vs 上一扫描 的不合规项集合差异
  const scans = db.getServerScans(id);
  let compare = null;
  if (scans.length >= 2) {
    const latestFails = new Set(db.getScanFindings(scans[0].id).filter((f) => f.status === 'fail').map((f) => f.item_id));
    const prevFails = new Set(db.getScanFindings(scans[1].id).filter((f) => f.status === 'fail').map((f) => f.item_id));
    const newFail = [...latestFails].filter((x) => !prevFails.has(x));
    const fixed = [...prevFails].filter((x) => !latestFails.has(x));
    const persistent = [...latestFails].filter((x) => prevFails.has(x));
    compare = { has: true, newFail, fixed, persistent, prevCompliance: trend.length >= 2 ? trend[trend.length - 2].compliance : null };
  }
  res.render('report', { report, single: false, trend, remMap, compare });
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

app.get('/quick-report', (req, res) => {
  res.render('quick_report', { modules: quickReport.listModules() });
});

// 返回某模块的检查项清单（供前端逐项展开勾选/打分）
app.get('/api/quick-report/catalog/:id', (req, res) => {
  const cat = quickReport.getCatalogItems(req.params.id);
  if (!cat) return res.status(404).json({ error: 'catalog not found' });
  res.json({
    id: cat.id,
    label: cat.description || cat.id,
    items: (cat.items || []).map((it) => ({
      id: it.id || '',
      name: it.name || '',
      category: it.category || '未分类',
      severity: it.severity || '—',
    })),
  });
});

app.post('/api/quick-report/generate', (req, res) => {
  const { ip, hostname, title, modules } = req.body;
  if (!ip || !String(ip).trim()) return res.status(400).json({ error: '请输入目标 IP' });
  let mods;
  try { mods = typeof modules === 'string' ? JSON.parse(modules) : (modules || []); }
  catch (e) { return res.status(400).json({ error: 'modules 解析失败' }); }
  if (!Array.isArray(mods) || mods.length === 0) return res.status(400).json({ error: '请至少勾选一个基线模块' });

  const ts = new Date().toISOString().slice(0, 10);
  const ipSafe = String(ip).trim().replace(/[^\w.-]/g, '_');
  const host = hostname && String(hostname).trim();
  const titleArg = title && String(title).trim();

  // 单模块：直接返回一份 HTML
  if (mods.length === 1) {
    const report = quickReport.buildReport({ ip, hostname: host, title: titleArg, modules: [mods[0]] });
    const html = exporter.exportHtml(report);
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="quick_report_${ipSafe}_${mods[0].catalogId}_${ts}.html"`);
    return res.send(html);
  }

  // 多模块：每个模块单独一份 HTML，打包为 ZIP
  const AdmZip = require('adm-zip');
  const zip = new AdmZip();
  for (const m of mods) {
    const report = quickReport.buildReport({ ip, hostname: host, title: titleArg, modules: [m] });
    const html = exporter.exportHtml(report);
    zip.addFile(`quick_report_${ipSafe}_${m.catalogId}_${ts}.html`, Buffer.from(html, 'utf-8'));
  }
  const buf = zip.toBuffer();
  res.setHeader('Content-Type', 'application/zip');
  res.setHeader('Content-Disposition', `attachment; filename="quick_reports_${ipSafe}_${ts}.zip"`);
  return res.send(buf);
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

// 整改清单 Excel：serverId 必填；rows 为 {item_id,name,severity,expected,actual,remediation,status,owner,due_date,note}
app.post('/export/:id/remediation', async (req, res) => {
  const id = parseInt(req.params.id, 10);
  const server = db.getServer(id);
  if (!server) return res.status(404).send('服务器不存在');
  const rows = Array.isArray(req.body.rows) ? req.body.rows : [];
  try {
    const buf = await exporter.exportRemediationExcel(server, rows);
    const ts = new Date().toISOString().slice(0, 10);
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename="remediation_${server.hostname}_${ts}.xlsx"`);
    return res.send(buf);
  } catch (e) {
    return res.status(500).send('整改清单导出失败：' + e.message);
  }
});

app.get('/health', (req, res) => res.json({ ok: true, licensed: isLicensed() }));

// ---------------------------------------------------------------------------
// 整改跟踪 API
// ---------------------------------------------------------------------------
app.get('/api/servers/:id/remediation', (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!db.getServer(id)) return res.status(404).json({ error: '服务器不存在' });
  res.json({ ok: true, rows: db.getRemediations(id) });
});

app.post('/api/servers/:id/remediation', (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!db.getServer(id)) return res.status(404).json({ error: '服务器不存在' });
  const { item_id, status, owner, due_date, note } = req.body || {};
  if (!item_id) return res.status(400).json({ error: '缺少 item_id' });
  const row = db.upsertRemediation({ server_id: id, item_id, status, owner, due_date, note });
  res.json({ ok: true, row });
});

// ---------------------------------------------------------------------------
// 升级 & 设置
// ---------------------------------------------------------------------------
app.get('/upgrade', (req, res) => {
  const cfg = config.getConfig();
  res.render('upgrade', {
    cfg,
    sources: upgrade.getSources(),
    current: upgrade.getCurrentVersion(),
    gitAvailable: upgrade.gitAvailable(),
  });
});

app.get('/settings', (req, res) => {
  res.render('settings', { cfg: config.getConfig() });
});

app.post('/settings', (req, res) => {
  const { autoRestart } = req.body;
  const merged = config.saveConfig({
    upgrade: {
      autoRestart: autoRestart === 'true' || autoRestart === true,
    },
  });
  res.json({ ok: true, config: merged });
});

app.post('/api/upgrade/check', (req, res) => {
  const { source } = req.body || {};
  res.json(upgrade.onlineCheck(source));
});

app.post('/api/upgrade/online', (req, res) => {
  const { source } = req.body || {};
  const r = upgrade.applyOnline(source);
  if (r.ok && config.getConfig().upgrade.autoRestart) { res.json({ ...r, restarting: true }); upgrade.restartService(); }
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
