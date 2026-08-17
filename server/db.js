'use strict';
/**
 * db.js — 数据层（Node 内置 node:sqlite，零原生依赖）
 * 存储：servers / scans / findings / issued_licenses
 */
const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const INSTANCE_DIR = path.join(__dirname, 'instance');
fs.mkdirSync(INSTANCE_DIR, { recursive: true });
fs.mkdirSync(path.join(INSTANCE_DIR, 'uploads'), { recursive: true });

const DB_PATH = path.join(INSTANCE_DIR, 'app.db');

const db = new DatabaseSync(DB_PATH);
db.exec('PRAGMA journal_mode = WAL;');
db.exec('PRAGMA foreign_keys = ON;');

db.exec(`
CREATE TABLE IF NOT EXISTS servers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  hostname TEXT NOT NULL,
  platform TEXT,
  os TEXT,
  os_version TEXT,
  kernel TEXT,
  collector_version TEXT,
  first_seen TEXT,
  last_seen TEXT,
  UNIQUE(hostname, platform)
);
CREATE TABLE IF NOT EXISTS scans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id INTEGER NOT NULL,
  catalog_id TEXT,
  target_type TEXT,
  target_label TEXT,
  platform TEXT,
  collector_version TEXT,
  created_at TEXT,
  summary TEXT,
  FOREIGN KEY(server_id) REFERENCES servers(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS findings (
  scan_id INTEGER NOT NULL,
  item_id TEXT,
  category TEXT,
  subsystem TEXT,
  name TEXT,
  severity TEXT,
  status TEXT,
  actual TEXT,
  expected TEXT,
  message TEXT,
  remediation TEXT,
  reference TEXT,
  FOREIGN KEY(scan_id) REFERENCES scans(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_findings_scan ON findings(scan_id);
CREATE INDEX IF NOT EXISTS idx_scans_server ON scans(server_id);
CREATE TABLE IF NOT EXISTS issued_licenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  machine_code TEXT,
  expires_at TEXT,
  features TEXT,
  issued_at TEXT,
  note TEXT,
  raw_license TEXT
);
CREATE TABLE IF NOT EXISTS used_cardkeys (
  signature TEXT PRIMARY KEY,
  card_payload TEXT,
  redeemed_at TEXT,
  redeemed_by TEXT,
  raw_license TEXT
);
`);

// ---------------------------------------------------------------------------
// servers
// ---------------------------------------------------------------------------
function upsertServer(host) {
  const now = new Date().toISOString();
  const existing = db.prepare('SELECT * FROM servers WHERE hostname = ? AND platform = ?')
    .get(host.hostname || 'unknown', host.platform || 'unknown');
  if (existing) {
    db.prepare(`UPDATE servers SET os=?, os_version=?, kernel=?, collector_version=?, last_seen=? WHERE id=?`)
      .run(host.os || existing.os, host.os_version || '', host.kernel || '', host.collector_version || '', now, existing.id);
    return existing;
  }
  const info = db.prepare(`INSERT INTO servers (hostname, platform, os, os_version, kernel, collector_version, first_seen, last_seen)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(host.hostname || 'unknown', host.platform || 'unknown', host.os || '', host.os_version || '', host.kernel || '', host.collector_version || '', now, now);
  return db.prepare('SELECT * FROM servers WHERE id = ?').get(info.lastInsertRowid);
}

function getServers() {
  return db.prepare(`SELECT s.*,
    (SELECT COUNT(*) FROM scans WHERE server_id = s.id) AS scan_count,
    (SELECT MAX(created_at) FROM scans WHERE server_id = s.id) AS last_scan
    FROM servers s ORDER BY last_seen DESC`).all();
}

function getServer(id) {
  return db.prepare('SELECT * FROM servers WHERE id = ?').get(id);
}

function deleteServer(id) {
  db.prepare('DELETE FROM servers WHERE id = ?').run(id);
}

function getServerScans(id) {
  return db.prepare('SELECT * FROM scans WHERE server_id = ? ORDER BY created_at DESC').all();
}

// 返回某服务器所有 findings，并附带所属 scan 的 catalog/target 信息
function getServerFindings(id) {
  return db.prepare(`SELECT f.*, sc.catalog_id, sc.target_type, sc.target_label, sc.created_at AS scan_at
    FROM findings f JOIN scans sc ON f.scan_id = sc.id
    WHERE sc.server_id = ? ORDER BY sc.created_at DESC, f.category, f.item_id`).all(id);
}

// ---------------------------------------------------------------------------
// scans + findings
// ---------------------------------------------------------------------------
function insertScan({ server_id, catalog_id, target_type, target_label, platform, collector_version, summary }) {
  const info = db.prepare(`INSERT INTO scans (server_id, catalog_id, target_type, target_label, platform, collector_version, created_at, summary)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(server_id, catalog_id || 'unknown', target_type || catalog_id || 'unknown', target_label || '', platform || '', collector_version || '', new Date().toISOString(), JSON.stringify(summary || {}));
  return info.lastInsertRowid;
}

function insertFindings(scan_id, results) {
  const stmt = db.prepare(`INSERT INTO findings (scan_id, item_id, category, subsystem, name, severity, status, actual, expected, message, remediation, reference)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  db.exec('BEGIN');
  try {
    for (const r of results || []) {
      stmt.run(scan_id, r.item_id || '', r.category || '', r.subsystem || '', r.name || '', r.severity || '',
        r.status || 'unknown', r.actual == null ? null : String(r.actual), r.expected || '', r.message || '', r.remediation || '', r.reference || '');
    }
    db.exec('COMMIT');
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}

function getScan(id) {
  return db.prepare('SELECT * FROM scans WHERE id = ?').get(id);
}

function getScanFindings(id) {
  return db.prepare('SELECT * FROM findings WHERE scan_id = ? ORDER BY category, item_id').all(id);
}

function getDashboardStats() {
  const servers = db.prepare('SELECT COUNT(*) c FROM servers').get().c;
  const scans = db.prepare('SELECT COUNT(*) c FROM scans').get().c;
  const f = db.prepare(`SELECT
      SUM(CASE WHEN status='pass' THEN 1 ELSE 0 END) pass,
      SUM(CASE WHEN status='fail' THEN 1 ELSE 0 END) fail,
      SUM(CASE WHEN status='manual' THEN 1 ELSE 0 END) manual,
      SUM(CASE WHEN status='unknown' THEN 1 ELSE 0 END) unknown,
      COUNT(*) total FROM findings`).get();
  const denom = (f.pass || 0) + (f.fail || 0);
  return {
    servers, scans,
    findings: f,
    compliance: denom > 0 ? (f.pass / denom) : null,
  };
}

// ---------------------------------------------------------------------------
// issued licenses（授权后台历史）
// ---------------------------------------------------------------------------
function insertIssuedLicense({ machine_code, expires_at, features, note, raw_license }) {
  const info = db.prepare(`INSERT INTO issued_licenses (machine_code, expires_at, features, issued_at, note, raw_license)
    VALUES (?, ?, ?, ?, ?, ?)`)
    .run(machine_code, expires_at, JSON.stringify(features || []), new Date().toISOString(), note || '', raw_license);
  return info.lastInsertRowid;
}

function getIssuedLicenses() {
  return db.prepare('SELECT * FROM issued_licenses ORDER BY id DESC').all();
}

// ---------------------------------------------------------------------------
// 卡密核销（一次性使用）
// ---------------------------------------------------------------------------
function isCardKeyUsed(signature) {
  const row = db.prepare('SELECT 1 FROM used_cardkeys WHERE signature = ?').get(signature);
  return !!row;
}

function markCardKeyUsed({ signature, payload, raw_license, redeemed_by }) {
  db.prepare(`INSERT OR IGNORE INTO used_cardkeys (signature, card_payload, redeemed_at, redeemed_by, raw_license)
    VALUES (?, ?, ?, ?, ?)`)
    .run(signature, JSON.stringify(payload || {}), new Date().toISOString(), redeemed_by || '', raw_license || '');
}

function getUsedCardKeys() {
  return db.prepare('SELECT * FROM used_cardkeys ORDER BY id DESC').all();
}

module.exports = {
  db,
  upsertServer,
  getServers,
  getServer,
  deleteServer,
  getServerScans,
  getServerFindings,
  insertScan,
  insertFindings,
  getScan,
  getScanFindings,
  getDashboardStats,
  insertIssuedLicense,
  getIssuedLicenses,
  isCardKeyUsed,
  markCardKeyUsed,
  getUsedCardKeys,
  INSTANCE_DIR,
};
