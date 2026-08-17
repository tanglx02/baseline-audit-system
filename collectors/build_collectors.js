#!/usr/bin/env node
/**
 * build_collectors.js — 由 baseline/*.yaml 生成「目标主机可直接执行」的原生收集脚本（Node 重写）。
 *
 * 关键变化（相对 Python 版）：
 * - 每个 catalog 生成【独立的】脚本文件：每个数据库类型 / 每个中间件类型各一个，
 *   Linux 为纯 bash（collect_<catalog>.sh），Windows 为 PowerShell（collect_<catalog>.ps1）。
 * - 单一事实来源仍是 baseline/*.yaml 与 collectors/configs/paths.yaml；本脚本只是「翻译器」。
 *
 * 产物（collectors/dist/）：
 *   collect_host_linux.sh  collect_db_mysql_linux.sh  collect_db_postgresql.sh ...
 *   collect_windows_host.ps1  collect_db_mssql.ps1  collect_mw_iis.ps1 ...
 *   manifest.json  （供 Web 平台「下载采集脚本」页面枚举）
 *
 * 用法：node collectors/build_collectors.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const ROOT = path.resolve(__dirname, '..');
const BASELINE_DIR = path.join(ROOT, 'baseline');
const PATHS_YAML = path.join(__dirname, 'configs', 'paths.yaml');
const DIST_DIR = path.join(__dirname, 'dist');
const TPL_DIR = path.join(__dirname, 'templates');

const COLLECTOR_VERSION_BASH = '2.0.0-bash';
const COLLECTOR_VERSION_PS1 = '2.0.0-ps1';

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------
function bashLit(s) {
  return "'" + String(s == null ? '' : s).replace(/'/g, "'\\''") + "'";
}
function jval(s) {
  return JSON.stringify(s == null ? '' : s);
}
function staticFragment(f) {
  const parts = [
    `"item_id":${jval(f.id)}`,
    `"category":${jval(f.category)}`,
    `"subsystem":${jval(f.subsystem)}`,
    `"name":${jval(f.name)}`,
    `"severity":${jval(f.severity)}`,
    `"expected":${jval(f.expected)}`,
    `"remediation":${jval(f.remediation)}`,
    `"reference":${jval(f.reference)}`,
  ];
  return parts.join(',');
}
function expectedText(judge) {
  if (!judge) return '';
  const jt = judge.type;
  const v = judge.value == null ? '' : judge.value;
  const m = {
    equals: `等于 ${v}`,
    not_equals: `不等于 ${v}`,
    contains: `包含 ${v}`,
    regex_present: `匹配 ${v}`,
    regex_absent: `不包含 ${v}`,
    numeric_leq: `≤ ${v}`,
    numeric_geq: `≥ ${v}`,
    file_perm_leq: `权限 ≤ ${v}`,
  };
  return m[jt] != null ? m[jt] : jt;
}
function loadPaths() {
  if (!fs.existsSync(PATHS_YAML)) return {};
  return yaml.load(fs.readFileSync(PATHS_YAML, 'utf-8')) || {};
}
function platformCandidates(pathCatalog, platform, paths) {
  const node = paths[pathCatalog];
  if (!node) return [];
  let cands = node[platform] != null ? node[platform] : node.linux;
  if (typeof cands === 'string') cands = [cands];
  return Array.isArray(cands) ? cands : [];
}
function extractFields(item, platform, paths) {
  const m = item.method || {};
  const mtype = m.type;
  const f = {
    id: item.id,
    category: item.category || '',
    subsystem: item.subsystem || '',
    name: item.name || '',
    severity: item.severity || '',
    check_type: item.check_type || 'auto',
    timeout: parseInt(item.timeout || 30, 10),
    expected: expectedText(item.judge),
    remediation: item.remediation || '',
    reference: item.reference || '',
    method_type: mtype,
    method_desc: mtype === 'manual' ? (m.description || '') : '',
    cmd: (mtype === 'shell' || mtype === 'powershell') ? (m.actual_cmd || '') : '',
    path_catalog: mtype === 'config_file' ? (m.path_catalog || '') : '',
    format: mtype === 'config_file' ? (m.format || '') : '',
    section: mtype === 'config_file' ? (m.section || '') : '',
    key: mtype === 'config_file' ? (m.key || '') : '',
    process_name: mtype === 'process' ? (m.name || '') : '',
    port: mtype === 'port' ? String(m.port || '') : '',
  };
  if (item.judge) {
    const j = item.judge;
    f.judge_type = j.type;
    f.judge_value = (['numeric_leq', 'numeric_geq', 'file_perm_leq'].includes(j.type) && !('value' in j))
      ? '' : String(j.value == null ? '' : j.value);
    f.judge_te = j.treat_empty_as || 'fail';
  } else {
    f.judge_type = '';
    f.judge_value = '';
    f.judge_te = '';
  }
  f.candidates = mtype === 'config_file' ? platformCandidates(f.path_catalog, platform, paths) : [];
  return f;
}

// ---------------------------------------------------------------------------
// bash 单条目块（无 ${} ，可安全用模板串）
// ---------------------------------------------------------------------------
function bashItemBlock(f) {
  const lines = [];
  lines.push(`# ---- ${f.id} (${f.category}/${f.subsystem}) ----`);
  lines.push(`ITEM_CHECK=${bashLit(f.check_type)}`);
  lines.push(`ITEM_MTYPE=${bashLit(f.method_type)}`);
  lines.push(`ITEM_TIMEOUT=${bashLit(f.timeout)}`);
  lines.push(`ITEM_FORMAT=${bashLit(f.format)}`);
  lines.push(`ITEM_JTYPE=${bashLit(f.judge_type)}`);
  lines.push(`ITEM_TE=${bashLit(f.judge_te)}`);
  lines.push(`ITEM_CMD=${bashLit(f.cmd)}`);
  lines.push(`ITEM_PC=${bashLit(f.candidates.join('\n'))}`);
  lines.push(`ITEM_SECTION=${bashLit(f.section)}`);
  lines.push(`ITEM_KEY=${bashLit(f.key)}`);
  lines.push(`ITEM_PROC=${bashLit(f.process_name)}`);
  lines.push(`ITEM_PORT=${bashLit(f.port)}`);
  lines.push(`ITEM_JVAL=${bashLit(f.judge_value)}`);
  lines.push(`ITEM_MDESC=${bashLit(f.method_desc)}`);
  lines.push(`ITEM_STATIC=${bashLit(staticFragment(f))}`);
  lines.push('_run_item');
  lines.push('');
  return lines.join('\n');
}

function buildBash(catalog, items, versions) {
  const header = fs.readFileSync(path.join(TPL_DIR, 'bash_header.txt'), 'utf-8')
    .replace('__COLLECTOR_VERSION__', COLLECTOR_VERSION_BASH);
  const tail = fs.readFileSync(path.join(TPL_DIR, 'bash_tail.txt'), 'utf-8')
    .replace('__CATALOG_ID__', catalog.id)
    .replace('__CATALOG_VER__', String(catalog.version || '0.0.0'))
    .replace('__VERSIONS_LIT__', bashLit(JSON.stringify(versions)));
  const body = items.map((it) => bashItemBlock(it)).join('\n');
  return header + '\n' + body + tail;
}

// ---------------------------------------------------------------------------
// PowerShell 数据 + 脚本
// ---------------------------------------------------------------------------
function buildPsData(catalog, items, paths, platform, versions) {
  const usedPaths = new Set();
  const outItems = [];
  for (const it of items) {
    const f = it; // 已是 extractFields 结果
    const m = { type: f.method_type };
    if (f.method_type === 'shell' || f.method_type === 'powershell') m.cmd = f.cmd;
    else if (f.method_type === 'config_file') {
      m.pathCatalog = f.path_catalog;
      m.format = f.format;
      m.section = f.section;
      m.key = f.key;
      if (f.path_catalog) usedPaths.add(f.path_catalog);
    } else if (f.method_type === 'process') m.processName = f.process_name;
    else if (f.method_type === 'port') m.port = f.port ? parseInt(f.port, 10) : 0;
    const obj = {
      id: f.id,
      category: f.category,
      subsystem: f.subsystem,
      name: f.name,
      severity: f.severity,
      check_type: f.check_type,
      timeout: f.timeout,
      expected: f.expected,
      remediation: f.remediation,
      reference: f.reference,
      methodDescription: f.method_desc,
      method: m,
    };
    if (f.judge_type) obj.judge = { type: f.judge_type, value: f.judge_value, treat_empty_as: f.judge_te };
    outItems.push(obj);
  }
  const pathsOut = {};
  for (const k of usedPaths) pathsOut[k] = paths[k] ? (paths[k][platform] != null ? paths[k][platform] : (paths[k].linux || [])) : [];
  return {
    collector_version: COLLECTOR_VERSION_PS1,
    catalog_id: catalog.id,
    catalog_version: String(catalog.version || '0.0.0'),
    all_versions: versions,
    paths: pathsOut,
    items: outItems,
  };
}
function buildPs1(catalog, items, versions, paths, platform) {
  const data = buildPsData(catalog, items, paths, platform, versions);
  const js = JSON.stringify(data, null, 1);
  return fs.readFileSync(path.join(TPL_DIR, 'ps1_header.txt'), 'utf-8')
    .replace('__COLLECTOR_VERSION__', COLLECTOR_VERSION_PS1)
    .replace('__CATALOG_JSON__', js);
}

// ---------------------------------------------------------------------------
// 主流程
// ---------------------------------------------------------------------------
// 四大分类（按「类型 + 平台」归并）：Windows主机 / Linux主机 / 中间件 / 数据库
// - 主机/基础设施类按运行平台归入 Windows/Linux 主机
// - 中间件(mw_*) / 数据库(db_*) 各自独立成类
function categoryOf(id, platform) {
  if (id === 'db2' || id.startsWith('db_')) return '数据库';
  if (id.startsWith('mw_')) return '中间件';
  if (platform === 'windows') return 'Windows主机';
  return 'Linux主机';
}
function applicable(items, platform) {
  return items.filter((it) => {
    if (!it.platforms) return true;
    return it.platforms.includes(platform);
  });
}

function main() {
  fs.mkdirSync(DIST_DIR, { recursive: true });
  const paths = loadPaths();
  const files = fs.readdirSync(BASELINE_DIR).filter((f) => f.endsWith('.yaml') && !f.startsWith('_'))
    .sort().map((f) => path.join(BASELINE_DIR, f));
  const versions = {};
  const manifest = [];
  let totalScripts = 0;

  for (const fp of files) {
    const cat = yaml.load(fs.readFileSync(fp, 'utf-8'));
    if (!cat || !cat.catalog) { console.warn('跳过（无 catalog）:', fp); continue; }
    const c = cat.catalog;
    const cid = c.id || path.basename(fp, '.yaml');
    const cplat = c.platform || 'linux';
    const cver = String(c.version || '0.0.0');
    const rawItems = c.items || [];
    versions[cid] = cver;

    const emit = (platform) => {
      const its = applicable(rawItems, platform).map((it) => extractFields(it, platform, paths));
      if (its.length === 0) return;
      const outName = `collect_${cid}.${platform === 'linux' ? 'sh' : 'ps1'}`;
      const outPath = path.join(DIST_DIR, outName);
      let script;
      if (platform === 'linux') script = buildBash(c, its, versions);
      else script = buildPs1(c, its, versions, paths, platform);
      // bash 禁止 BOM；ps1(GBK 代码页)需要 UTF-8 BOM（Node fs 不支持 'utf-8-sig'，手动加 BOM）
      if (platform === 'linux') {
        fs.writeFileSync(outPath, script, 'utf-8');
      } else {
        fs.writeFileSync(outPath, Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(script, 'utf-8')]));
      }
      const label = c.description || cid;
      const category = categoryOf(cid, platform);
      manifest.push({
        file: outName,
        platform,
        catalog_id: cid,
        label,
        category,
        items: its.length,
      });
      totalScripts++;
      console.log(`[生成] ${outName}  (${its.length} 项, ${platform}, ${category})`);
    };

    if (cplat === 'linux' || cplat === 'cross') emit('linux');
    if (cplat === 'windows' || cplat === 'cross') emit('windows');
  }

  fs.writeFileSync(path.join(DIST_DIR, 'manifest.json'), JSON.stringify({ generated_at: new Date().toISOString(), scripts: manifest }, null, 2), 'utf-8');
  console.log(`\n[完成] 共生成 ${totalScripts} 个独立采集脚本 -> collectors/dist/（manifest.json 已写入）`);
}

main();
