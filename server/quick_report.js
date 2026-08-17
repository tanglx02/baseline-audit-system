'use strict';
/**
 * quick_report.js — 快速报告模块（独立模块）
 *
 * 用途：有时没时间上传脚本到服务器跑，但又急着要一份报告。
 * 本模块允许直接「选择基线模块 + 输入 IP + 指定每个模块合格/不合格」，
 * 由系统基于真实的基线检查项构造最终的 HTML 报告（格式与正常扫描报告一致）。
 *
 * 注意：这是“快速生成”的报告，并未实际执行核查脚本，仅按用户指定的
 * 合格/不合格状态填充真实检查项。请如实标注用于演示/预检场景。
 */
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const BASELINE_DIR = path.join(__dirname, '..', 'baseline');

// 读取全部 catalog 的轻量元数据（供页面勾选）
function listModules() {
  if (!fs.existsSync(BASELINE_DIR)) return [];
  const files = fs.readdirSync(BASELINE_DIR).filter((f) => f.endsWith('.yaml') && !f.startsWith('_')).sort();
  const out = [];
  for (const f of files) {
    let cat;
    try { cat = yaml.load(fs.readFileSync(path.join(BASELINE_DIR, f), 'utf-8')); }
    catch (e) { continue; }
    if (!cat || !cat.catalog) continue;
    const c = cat.catalog;
    const items = c.items || [];
    const cats = {};
    for (const it of items) cats[it.category || '未分类'] = (cats[it.category || '未分类'] || 0) + 1;
    out.push({
      id: c.id,
      label: c.description || c.id,
      platform: c.platform || 'linux',
      version: String(c.version || ''),
      description: c.description || c.id,
      file: f,
      item_count: items.length,
      categories: cats,
    });
  }
  return out;
}

// 读取某 catalog 的完整检查项
function getCatalogItems(catalogId) {
  if (!fs.existsSync(BASELINE_DIR)) return null;
  const f = path.join(BASELINE_DIR, catalogId + '.yaml');
  if (!fs.existsSync(f)) {
    // 兼容带平台后缀的 id（如 db_mysql_linux 对应 db_mysql_linux.yaml）
    const alt = fs.readdirSync(BASELINE_DIR).find((x) => x.replace(/\.yaml$/, '') === catalogId);
    if (!alt) return null;
    f = path.join(BASELINE_DIR, alt);
  }
  let cat;
  try { cat = yaml.load(fs.readFileSync(f, 'utf-8')); }
  catch (e) { return null; }
  if (!cat || !cat.catalog) return null;
  return cat.catalog;
}

function countStatus(items) {
  const c = { pass: 0, fail: 0, manual: 0, unknown: 0 };
  for (const f of items) c[f.status] = (c[f.status] || 0) + 1;
  return c;
}
function compRate(c) {
  const d = c.pass + c.fail;
  return d > 0 ? c.pass / d : null;
}

/**
 * 构造与 export.exportHtml 兼容的 report 对象。
 *
 * @param {Object} opts
 * @param {string} opts.ip           目标 IP（必填）
 * @param {string} [opts.hostname]   主机名（可选，缺省用 IP）
 * @param {string} [opts.title]      报告标题（可选）
 * @param {Array}  opts.modules       每项形如：
 *        { catalogId, items?: [{ id, status:'pass'|'fail', score?:0..100 }] }
 *        - 不传 items 或 items 为空：该模块全部按「合格」(score 100) 处理。
 *        - 传了 items：仅按你指定的逐项状态/分数填充；模块得分=逐项均分。
 */
function buildReport({ ip, hostname, title, modules }) {
  const serverName = (hostname && hostname.trim()) || (ip && ip.trim()) || '未命名设备';
  const groups = [];
  let mainPlatform = 'linux';

  for (const m of modules || []) {
    const catalog = getCatalogItems(m.catalogId);
    if (!catalog) continue;
    // 用户的逐项选择：id -> {status, score}
    const userSel = {};
    if (Array.isArray(m.items)) for (const it of m.items) if (it && it.id) userSel[String(it.id)] = it;
    const hasSel = Object.keys(userSel).length > 0;

    const items = (catalog.items || []).map((it) => {
      const sel = userSel[String(it.id)] || {};
      const status = sel.status === 'fail' ? 'fail' : 'pass';
      let score = sel.score;
      if (score === '' || score == null) score = status === 'pass' ? 100 : 0;
      score = Math.max(0, Math.min(100, Number(score) || 0));
      return {
        item_id: it.id || '',
        category: it.category || '未分类',
        subsystem: it.subsystem || '',
        name: it.name || '',
        severity: it.severity || '—',
        status,
        score,
        actual: status === 'pass' ? '符合' : '不符合',
        expected: (it.judge && it.judge.value) ? String(it.judge.value) : '',
        message: '',
        remediation: it.remediation || '',
        reference: it.reference || '',
      };
    });

    const counts = countStatus(items);
    const totalScore = items.reduce((a, f) => a + (Number(f.score) || 0), 0);
    const avgScore = items.length ? Math.round(totalScore / items.length) : 0;
    groups.push({
      target_type: catalog.id,
      target_label: catalog.description || catalog.id,
      platform: catalog.platform || 'linux',
      catalog_version: String(catalog.version || ''),
      items,
      counts,
      compliance: compRate(counts),
      score: avgScore,
    });
    if (catalog.platform === 'windows') mainPlatform = 'windows';
    // 标记是否使用了逐项选择（便于调试/校验，不影响渲染）
    void hasSel;
  }

  const all = groups.flatMap((g) => g.items);
  const totals = countStatus(all);
  totals.compliance = compRate(totals);
  totals.total = all.length;
  // 全局得分 = 各模块得分的算术平均（按模块等权，更贴近「整体得分」直觉）
  if (groups.length) {
    const sum = groups.reduce((a, g) => a + (Number(g.score) || 0), 0);
    totals.score = Math.round(sum / groups.length);
  }

  const nowIso = new Date().toISOString();
  return {
    server: {
      hostname: serverName,
      platform: mainPlatform,
      os: mainPlatform === 'windows' ? 'Windows' : 'Linux',
      os_version: '',
      kernel: '',
      collector_version: 'quick-report',
    },
    scans: [{ created_at: nowIso, summary: { quick: true, title: title || '' } }],
    groups,
    totals,
  };
}

module.exports = { listModules, getCatalogItems, buildReport };
