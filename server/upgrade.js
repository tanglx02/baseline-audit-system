'use strict';
/**
 * upgrade.js — 在线(git) / 离线(压缩包) 升级模块
 *
 * 安全策略：
 *  - 任何更新前都会把当前源码备份到 backups/ 时间戳目录（排除 node_modules / 实例数据 / 压缩包本身）。
 *  - 应用更新时不会覆盖：node_modules、server/instance（数据库与许可证）、config.json、dist-exe、backups、.git。
 *  - 在线升级支持两种部署形态：
 *      1) 项目根是 git 仓库 → 走 git fetch + checkout（快速、保留历史）。
 *      2) 项目根没有 .git（zip 解压部署） → 走 git clone --depth 1 到临时目录 + 覆盖（兼容宝塔/zip 部署）。
 *  - 升级源为内置固定地址，用户界面不再提供任何地址输入框。
 */
const fs = require('fs');
const path = require('path');
const { execFileSync, spawn } = require('child_process');
const AdmZip = require('adm-zip');
const { ROOT } = require('./config');

const VERSION_FILE = path.join(ROOT, 'version.json');
const EXCLUDES = ['node_modules', 'server/instance', 'dist-exe', 'backups', '.git', 'config.json', '.workbuddy'];

// ---------------------------------------------------------------------------
// 内置升级源（固定地址，用户界面不做输入）
// ---------------------------------------------------------------------------
const UPGRADE_SOURCES = {
  gitee: {
    label: 'Gitee',
    url: 'https://gitee.com/tanglx02/baseline-audit-system',
    branch: 'main',    // Gitee 仓库默认分支
    altBranch: 'main', // 兜底（与主分支一致，避免无 master 分支时报错）
  },
  github: {
    label: 'GitHub',
    url: 'https://github.com/tanglx02/baseline-audit-system',
    branch: 'main',      // GitHub 默认分支
    altBranch: 'master', // 兜底
  },
};

function getSources() {
  return Object.keys(UPGRADE_SOURCES).map((k) => ({
    key: k,
    label: UPGRADE_SOURCES[k].label,
    url: UPGRADE_SOURCES[k].url,
  }));
}

const TEMP_BASE = path.join(ROOT, 'backups', '.tmp');

// ---------------------------------------------------------------------------
// 版本
// ---------------------------------------------------------------------------
function getCurrentVersion() {
  try {
    if (fs.existsSync(VERSION_FILE)) {
      const v = JSON.parse(fs.readFileSync(VERSION_FILE, 'utf-8'));
      return { version: v.version || '0.0.0', releasedAt: v.releasedAt || '', notes: v.notes || '' };
    }
  } catch (e) { /* ignore */ }
  return { version: '0.0.0', releasedAt: '', notes: '' };
}

function parseVersion(str) {
  return String(str || '0.0.0').split('.').map((x) => parseInt(x, 10) || 0);
}
function compareVersions(a, b) {
  const A = parseVersion(a), B = parseVersion(b);
  for (let i = 0; i < Math.max(A.length, B.length); i++) {
    const d = (A[i] || 0) - (B[i] || 0);
    if (d !== 0) return d;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------
function isExcluded(relPath) {
  const parts = relPath.split(path.sep);
  if (EXCLUDES.includes(parts[0])) return true;
  // 排除任意层级的工具 node_modules
  if (parts.includes('node_modules') && parts[0] === 'tools') return true;
  if (relPath === 'config.json') return true;
  return false;
}

function copyWithExclude(srcRoot, destRoot) {
  fs.cpSync(srcRoot, destRoot, {
    recursive: true,
    force: true,
    filter: (src) => {
      const rel = path.relative(srcRoot, src);
      if (!rel) return true;
      return !isExcluded(rel);
    },
  });
}

function ts() {
  return new Date().toISOString().replace(/[:T]/g, '-').slice(0, 19);
}

function backupSource(label) {
  const dest = path.join(ROOT, 'backups', `${label}-${ts()}`);
  copyWithExclude(ROOT, dest);
  return dest;
}

function gitAvailable() {
  try { execFileSync('git', ['--version'], { cwd: ROOT, stdio: 'pipe' }); return true; }
  catch (e) { return false; }
}

function isGitRepo() {
  try {
    const out = execFileSync('git', ['rev-parse', '--git-dir'], { cwd: ROOT, encoding: 'utf-8', stdio: 'pipe' });
    return !!(out && out.trim());
  } catch (e) { return false; }
}

function git(args) {
  return execFileSync('git', args, { cwd: ROOT, encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'] });
}

// 依次尝试主分支 / 兜底分支，返回成功执行命令的回调结果
function withBranch(src, fn) {
  const branches = [src.branch, src.altBranch].filter(Boolean);
  let lastErr = null;
  for (const b of branches) {
    try {
      const result = fn(b);
      return { ok: true, branch: b, result };
    } catch (e) {
      lastErr = e;
    }
  }
  return { ok: false, error: String((lastErr && (lastErr.stderr || lastErr.message)) || '').slice(0, 400) };
}

function rmrfSync(p) {
  try { fs.rmSync(p, { recursive: true, force: true }); } catch (e) { /* ignore */ }
}

// ---------------------------------------------------------------------------
// 无 .git 部署时：git clone 到临时目录
// ---------------------------------------------------------------------------
function cloneLatest(sourceKey) {
  const src = UPGRADE_SOURCES[sourceKey];
  const branches = [src.branch, src.altBranch].filter(Boolean);
  const tmpDir = path.join(TEMP_BASE, `online-${sourceKey}-${ts()}`);
  let lastErr = '';

  for (const b of branches) {
    rmrfSync(tmpDir);
    try {
      execFileSync('git', ['clone', '--depth', '1', '--branch', b, '--single-branch', src.url, tmpDir], {
        encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 10 * 1024 * 1024,
      });
      const vfPath = path.join(tmpDir, 'version.json');
      if (!fs.existsSync(vfPath)) throw new Error('克隆后未找到 version.json');
      const version = JSON.parse(fs.readFileSync(vfPath, 'utf-8'));
      return { ok: true, branch: b, version, tmpDir };
    } catch (e) {
      lastErr = String(e.stderr || e.message || e).slice(0, 400);
      rmrfSync(tmpDir);
    }
  }
  return { ok: false, error: lastErr || '无法从任何分支克隆更新' };
}

function resolveExtractedRoot(dir) {
  // 有些压缩包会把所有文件放在一个子目录里（如 baseline-audit-system-main/）
  // 如果 dir 下只有一个子目录且该子目录包含 version.json，则返回该子目录
  try {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    const dirs = entries.filter((e) => e.isDirectory());
    if (dirs.length === 1 && entries.length === 1) {
      const candidate = path.join(dir, dirs[0].name);
      if (fs.existsSync(path.join(candidate, 'version.json'))) return candidate;
    }
  } catch (e) { /* ignore */ }
  return dir;
}

// ---------------------------------------------------------------------------
// 在线升级
// ---------------------------------------------------------------------------
function onlineCheck(sourceKey) {
  const src = UPGRADE_SOURCES[sourceKey];
  if (!src) return { available: false, error: 'UNKNOWN_SOURCE', message: '未知的升级源。' };

  let candidate, usedBranch;

  if (isGitRepo()) {
    if (!gitAvailable()) return { available: false, error: 'GIT_UNAVAILABLE', message: '服务器未安装 git，无法在线升级。请改用下方「离线升级」。' };
    const attempt = withBranch(src, (b) => {
      git(['fetch', '--depth', '1', src.url, b]);
      const raw = git(['show', 'FETCH_HEAD:version.json']);
      return JSON.parse(raw);
    });
    if (!attempt.ok) return { available: false, error: 'FETCH_FAILED', message: '拉取远程失败：' + attempt.error };
    candidate = attempt.result;
    usedBranch = attempt.branch;
  } else {
    // 无 .git 时通过 git clone 到临时目录检查版本
    if (!gitAvailable()) return { available: false, error: 'GIT_UNAVAILABLE', message: '当前目录不是 git 仓库，且服务器未安装 git，无法在线升级。请改用下方「离线升级」。' };
    const cl = cloneLatest(sourceKey);
    if (!cl.ok) return { available: false, error: 'FETCH_FAILED', message: '拉取远程失败：' + cl.error };
    candidate = cl.version;
    usedBranch = cl.branch;
    rmrfSync(cl.tmpDir);
  }

  const current = getCurrentVersion();
  const hasUpdate = compareVersions(candidate.version, current.version) > 0;
  return {
    available: true,
    source: sourceKey,
    sourceLabel: src.label,
    usedBranch,
    current: current.version,
    latest: candidate.version,
    hasUpdate,
    notes: candidate.notes || '',
  };
}

function applyOnline(sourceKey) {
  const src = UPGRADE_SOURCES[sourceKey];
  if (!src) return { ok: false, error: 'UNKNOWN_SOURCE', message: '未知的升级源。' };

  const backup = backupSource('online');

  if (isGitRepo()) {
    const attempt = withBranch(src, (b) => {
      git(['fetch', '--depth', '1', src.url, b]);
      git(['checkout', '-B', 'main', 'FETCH_HEAD']);
      return true;
    });
    if (!attempt.ok) return { ok: false, backup, error: 'CHECKOUT_FAILED', message: attempt.error };
  } else {
    if (!gitAvailable()) return { ok: false, backup, error: 'GIT_UNAVAILABLE', message: '当前目录不是 git 仓库，且服务器未安装 git，无法在线升级。请改用下方「离线升级」。' };
    const cl = cloneLatest(sourceKey);
    if (!cl.ok) return { ok: false, backup, error: 'FETCH_FAILED', message: cl.error };
    copyWithExclude(cl.tmpDir, ROOT);
    rmrfSync(cl.tmpDir);
  }

  // 判断 package.json 是否变更（与备份比较），变更则重装依赖
  const prevPkg = path.join(backup, 'package.json');
  const newPkg = path.join(ROOT, 'package.json');
  const pkgChanged = fs.existsSync(prevPkg) && fs.existsSync(newPkg) &&
    fs.readFileSync(prevPkg, 'utf-8') !== fs.readFileSync(newPkg, 'utf-8');
  if (pkgChanged) {
    try { execFileSync('npm', ['install', '--registry=https://registry.npmmirror.com/'], { cwd: ROOT, stdio: 'pipe' }); }
    catch (e) { /* 非致命 */ }
  }
  return { ok: true, backup, source: sourceKey, sourceLabel: src.label, current: getCurrentVersion().version, pkgChanged };
}

// ---------------------------------------------------------------------------
// 离线升级（压缩包）
// ---------------------------------------------------------------------------
function offlineCheck(zipPath) {
  let zip;
  try { zip = new AdmZip(zipPath); }
  catch (e) { return { error: 'ZIP_INVALID', message: '压缩包无法解压：' + e.message }; }
  const entries = zip.getEntries();
  const vf = entries.find((e) => e.entryName === 'version.json');
  if (!vf) return { error: 'NO_VERSION_FILE', message: '压缩包根目录未找到 version.json。' };
  let candidate;
  try { candidate = JSON.parse(vf.getData().toString('utf-8')); }
  catch (e) { return { error: 'VERSION_PARSE', message: 'version.json 解析失败。' }; }
  const current = getCurrentVersion();
  const newer = compareVersions(candidate.version, current.version) > 0;
  return { current: current.version, latest: candidate.version, newer, equal: compareVersions(candidate.version, current.version) === 0, notes: candidate.notes || '' };
}

function applyOffline(zipPath) {
  const backup = backupSource('offline');
  const tmp = path.join(TEMP_BASE, ts());
  fs.mkdirSync(tmp, { recursive: true });
  try {
    const zip = new AdmZip(zipPath);
    zip.extractAllTo(tmp, true);
  } catch (e) {
    return { ok: false, backup, error: 'EXTRACT_FAILED', message: e.message };
  }
  const extractedRoot = resolveExtractedRoot(tmp);
  // 覆盖写源码（排除受保护目录）
  copyWithExclude(extractedRoot, ROOT);
  // 若新版含 package.json 变更，重新安装依赖
  const newPkg = path.join(extractedRoot, 'package.json');
  if (fs.existsSync(newPkg)) {
    try { execFileSync('npm', ['install', '--registry=https://registry.npmmirror.com/'], { cwd: ROOT, stdio: 'pipe' }); }
    catch (e) { /* 非致命 */ }
  }
  rmrfSync(tmp);
  return { ok: true, backup, current: getCurrentVersion().version };
}

// ---------------------------------------------------------------------------
// 重启
// ---------------------------------------------------------------------------
function restartService() {
  try {
    const child = spawn(process.execPath, ['server/server.js'], {
      cwd: ROOT, detached: true, stdio: 'ignore', env: process.env,
    });
    child.unref();
    setTimeout(() => process.exit(0), 1500);
    return true;
  } catch (e) {
    return false;
  }
}

module.exports = {
  getCurrentVersion, compareVersions,
  getSources, onlineCheck, applyOnline,
  offlineCheck, applyOffline,
  backupSource, restartService, gitAvailable,
};
