'use strict';
/**
 * export.js — 报告导出：HTML(自包含) / Excel / CSV
 * 输入 report 结构见 server.js buildReport()。
 *
 * exportHtml 刻意模仿「云探合规管理系统 安全分析报告」版式：
 * 居中边框内容区、灰色章节标题栏、datagrid 表格、风险等级块、内联 SVG 图表（离线可用）。
 */
const ExcelJS = require('exceljs');

const CSS = `
* { box-sizing: border-box; padding: 0; margin: 0; }
ul, li { list-style: none; }
body { font-family: "Microsoft YaHei", "PingFang SC", system-ui, sans-serif; background: #f3f5f9; color: #303133; }
.content { width: 86%; margin: 18px auto; border: 1px solid #d3e1ed; background: #fff; }
.header { padding: 18px 0 6px; }
.title { font-size: 26px; color: #444; text-align: center; margin: 16px 0 30px; letter-spacing: 1px; }
.item-title { width: 100%; background-color: #f2f2f2; font-weight: bold; font-size: 17px; color: #303133; height: 46px; line-height: 46px; box-sizing: border-box; }
.item-title > span { padding-left: 12px; }
.item { margin-top: 18px; padding: 0 16px 8px; }
.catalog { padding-left: 26px; }
.catalog > li { font-size: 13px; display: block; margin: 14px 0; cursor: pointer; }
.catalog > li a { text-decoration: none; color: #333; }
.catalog > li a:hover { color: #1f6feb; }
table.datagrid { width: 100%; border-top: 1px solid #d3e1ed; border-right: 1px solid #d3e1ed; border-collapse: collapse; color: #303133; }
table.datagrid td { font-size: 12px; border-bottom: 1px solid #d3e1ed; border-left: 1px solid #d3e1ed; padding: 12px 10px; word-wrap: break-word; word-break: break-all; vertical-align: top; }
table.datagrid th { text-align: left; border-bottom: 1px solid #c8d8e7; border-left: 1px solid #c8d8e7; padding: 14px 10px; white-space: nowrap; }
table.datagrid thead tr { font-size: 12px; text-align: center; font-weight: 600; background-color: #ecf5ff; }
table.datagrid thead tr td { text-align: center; font-weight: 600; }
table.datagrid tbody tr:nth-child(even) { background: #fafcff; }
.level { display: flex; align-items: center; gap: 8px; }
.level .dot { width: 16px; height: 16px; border-radius: 4px; display: inline-block; }
.level > span { font-size: 15px; font-weight: 600; }
.chartPic { display: flex; align-items: center; justify-content: center; flex-wrap: wrap; gap: 24px; padding: 10px 0; }
.catbar { margin: 8px 0; }
.catbar .lab { font-size: 12px; }
.catbar .track { background: #eef1f5; border-radius: 6px; height: 14px; overflow: hidden; margin-top: 3px; }
.catbar .fill { height: 100%; background: #1a7f37; }
.rightItem > li { margin: 5px 0; font-size: 12px; }
.sev-high { color: #c0341d; font-weight: 700; }
.sev-medium { color: #9a6700; }
small { color: #8a94a6; }
`;

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}
function escAttr(s) { return esc(s); }
function pct(n) { return n == null ? '—' : (n * 100).toFixed(1) + '%'; }

function catOf(tt, platform) {
  if (tt.startsWith('db_') || tt === 'db2') return '数据库';
  if (tt.startsWith('mw_')) return '中间件';
  return platform === 'windows' ? 'Windows主机' : 'Linux主机';
}
function riskLevel(rate) {
  if (rate == null) return { text: '未知', color: '#8a94a6' };
  const p = rate * 100;
  if (p >= 90) return { text: '非常安全', color: '#1a7f37' };
  if (p >= 70) return { text: '比较安全', color: '#2f6fed' };
  if (p >= 50) return { text: '比较危险', color: '#e08a00' };
  return { text: '非常危险', color: '#c0341d' };
}

// 内联 SVG 环形图（离线可用，无需 echarts）
function svgDonut(parts) {
  const total = parts.reduce((a, p) => a + p.value, 0) || 1;
  const r = 64, cx = 90, cy = 90, C = 2 * Math.PI * r;
  let offset = 0, circles = '';
  for (const p of parts) {
    const len = (p.value / total) * C;
    circles += `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${p.color}" stroke-width="24" stroke-dasharray="${len.toFixed(2)} ${(C - len).toFixed(2)}" stroke-dashoffset="${(-offset).toFixed(2)}" transform="rotate(-90 ${cx} ${cy})"/>`;
    offset += len;
  }
  const legend = parts.filter((p) => p.value > 0).map((p) => `<span style="display:inline-block;margin:0 8px"><i class="dot" style="background:${p.color}"></i> ${p.label} ${p.value}</span>`).join('');
  return `<svg width="180" height="180" viewBox="0 0 180 180">${circles}<text x="${cx}" y="${cy - 4}" text-anchor="middle" font-size="16" fill="#303133">${total}</text><text x="${cx}" y="${cy + 14}" text-anchor="middle" font-size="11" fill="#8a94a6">检查项</text></svg><div class="rightItem" style="text-align:center;margin-top:4px">${legend}</div>`;
}

function catBars(cats) {
  return cats.map((c) => `<div class="catbar"><div class="lab">${esc(c.name)} <b>${c.score}%</b></div><div class="track"><div class="fill" style="width:${c.score}%"></div></div></div>`).join('');
}

// 单项得分：优先用传入的 score，否则按状态推导（合规 100 / 不合规 0 / 待人工 50）
function itemScore(f) {
  if (f.score != null && !isNaN(Number(f.score))) return Number(f.score);
  if (f.status === 'pass') return 100;
  if (f.status === 'fail') return 0;
  return 50;
}
function statusBadge(status) {
  const map = { pass: ['#1a7f37', '合规'], fail: ['#c0341d', '不合规'], manual: ['#e08a00', '待人工'], unknown: ['#8a94a6', '未知'] };
  const [color, text] = map[status] || ['#8a94a6', status || '未知'];
  return `<span style="color:${color};font-weight:600">${text}</span>`;
}

function exportHtml(report) {
  const s = report.server;
  const t = report.totals;
  const groups = report.groups || [];
  const rate = t.compliance;
  const lvl = riskLevel(rate);
  const now = new Date().toLocaleString('zh-CN');
  const firstScan = (report.scans && report.scans[0]) || null;
  const startTime = firstScan && firstScan.created_at ? firstScan.created_at.replace('T', ' ').slice(0, 19) : now;

  // 分类聚合
  const catMap = new Map();
  for (const g of groups) {
    const c = catOf(g.target_type, g.platform);
    if (!catMap.has(c)) catMap.set(c, { name: c, devices: 0, total: 0, pass: 0, fail: 0, manual: 0, unknown: 0 });
    const x = catMap.get(c);
    x.devices += 1;
    x.total += g.counts.pass + g.counts.fail + g.counts.manual + g.counts.unknown;
    x.pass += g.counts.pass; x.fail += g.counts.fail; x.manual += g.counts.manual; x.unknown += g.counts.unknown;
  }
  const cats = [...catMap.values()];

  // 不合规 / 失败 项
  const failItems = [], unknownItems = [];
  for (const g of groups) {
    for (const f of g.items) {
      if (f.status === 'fail') failItems.push({ g, f });
      else if (f.status === 'unknown') unknownItems.push({ g, f });
    }
  }
  const failTop = failItems.slice(0, 10);

  const parts = [
    { label: '合规', value: t.pass, color: '#1a7f37' },
    { label: '不合规', value: t.fail, color: '#c0341d' },
    { label: '待人工', value: t.manual, color: '#e08a00' },
    { label: '未知', value: t.unknown, color: '#8a94a6' },
  ];

  const overview = `
  <div class="item">
    <h2 class="item-title"><span id="title1">1.概述信息</span></h2>
    <table class="datagrid">
      <tr><td style="width:20%">风险等级</td><td style="width:80%"><div class="level"><span class="dot" style="background:${lvl.color}"></span><span style="color:${lvl.color}">${lvl.text}</span></div></td></tr>
      <tr><td>任务名称</td><td>${esc(s.hostname)}</td></tr>
      <tr><td>策略名称</td><td>安全基线核查（${t.total} 项）</td></tr>
      <tr><td>检查设备数</td><td>1</td></tr>
      <tr><td>合规率</td><td><b style="color:${lvl.color}">${pct(rate)}</b></td></tr>
      <tr><td>下达任务用户</td><td>—</td></tr>
      <tr><td>时间统计</td><td><ol class="rightItem"><li><span>1.开始时间：</span><span>${startTime}</span></li><li><span>2.结束时间：</span><span>${now}</span></li><li><span>3.报告生成时间：</span><span>${now}</span></li></ol></td></tr>
      <tr><td>设备统计</td><td><ol class="rightItem"><li><span>1.检查设备数：</span><span>1</span></li><li><span>2.检查成功设备数：</span><span>1</span></li><li><span>3.检查失败设备数：</span><span>0</span></li></ol></td></tr>
      <tr><td>检查项情况</td><td><ol class="rightItem"><li><span>1.总数：</span><span>${t.total}</span></li><li><span>2.合规数：</span><span>${t.pass}</span></li><li><span>3.不合规数：</span><span>${t.fail}</span></li><li><span>4.人工确认数：</span><span>${t.manual}</span></li><li><span>5.失败数：</span><span>${t.unknown}</span></li></ol></td></tr>
    </table>
    <div class="chartPic">${svgDonut(parts)}</div>
  </div>`;

  const classifyRows = cats.map((c) => `<tr style="text-align:center"><td>${esc(c.name)}</td><td>1</td><td>${c.total}</td><td>${c.pass}</td><td>${c.fail}</td><td>${c.manual}</td><td>${c.unknown}</td></tr>`).join('');
  const classify = `
  <div class="item">
    <h2 class="item-title"><span id="title2">2.设备分类统计</span></h2>
    <table class="datagrid">
      <thead><tr><td style="width:16%">类型</td><td>设备数</td><td>检查总数</td><td>合规数</td><td>不合规数</td><td>人工确认数</td><td>失败数</td></tr></thead>
      <tbody>${classifyRows || '<tr><td colspan="7" style="text-align:center">无数据</td></tr>'}</tbody>
    </table>
  </div>`;

  const catScoreRows = cats.map((c) => ({ name: c.name, score: c.total ? ((c.pass / c.total) * 100).toFixed(1) : '0.0' }));
  const topChart = `
  <div class="item">
    <h2 class="item-title"><span id="title3">3.设备风险等级 TOP</span></h2>
    <div class="chartPic">${catBars(catScoreRows)}</div>
  </div>`;

  const summaryRows = groups.map((g) => {
    const score = g.counts.pass + g.counts.fail + g.counts.manual + g.counts.unknown;
    const sc = g.score != null ? Number(g.score).toFixed(1) : (score ? ((g.counts.pass / score) * 100).toFixed(1) : '0.0');
    return `<tr style="text-align:center"><td>${esc(s.hostname)}</td><td>—</td><td>${esc(g.target_label || g.target_type)}</td><td>${sc}%</td><td>${score}</td><td>${g.counts.pass}</td><td>${g.counts.fail}</td><td>${g.counts.manual}</td><td>${g.counts.unknown}</td></tr>`;
  }).join('');
  const summary = `
  <div class="item">
    <h2 class="item-title"><span id="title4">4.设备风险等级汇总</span></h2>
    <table class="datagrid">
      <thead><tr><td rowspan="2" style="width:18%">设备名称</td><td rowspan="2" style="width:12%">设备IP</td><td rowspan="2" style="width:20%">设备类型</td><td rowspan="2" style="width:10%">得分</td><td colspan="5" style="text-align:center">检查项</td></tr>
      <tr><td>总数</td><td>合规数</td><td>不合规数</td><td>人工确认数</td><td>失败数</td></tr></thead>
      <tbody>${summaryRows || '<tr><td colspan="9" style="text-align:center">无数据</td></tr>'}</tbody>
    </table>
  </div>`;

  const failRow = (it) => `<tr style="text-align:center"><td style="text-align:left">${esc(it.f.name)}</td><td>${esc(it.f.item_id)}</td><td>${esc(it.g.target_label || it.g.target_type)}</td><td>${esc(it.f.severity || '—')}</td><td>1</td><td>1</td><td>${esc(s.hostname)}</td></tr>`;
  const failTopRows = failTop.map(failRow).join('') || '<tr><td colspan="7" style="text-align:center">无不符合项 🎉</td></tr>';
  const failAllRows = failItems.map(failRow).join('') || '<tr><td colspan="7" style="text-align:center">无不符合项 🎉</td></tr>';
  const topFail = `
  <div class="item">
    <h2 class="item-title"><span id="title5">5.不合规检查项 TOP 10</span></h2>
    <table class="datagrid"><thead><tr><td style="width:24%">名称</td><td>编号</td><td>类别</td><td>权重</td><td>受影响主机数</td><td>出现次数</td><td>受影响主机</td></tr></thead><tbody>${failTopRows}</tbody></table>
  </div>`
    + `
  <div class="item">
    <h2 class="item-title"><span id="title6">6.不合规检查项汇总</span></h2>
    <table class="datagrid"><thead><tr><td style="width:24%">名称</td><td>编号</td><td>类别</td><td>权重</td><td>受影响主机数</td><td>出现次数</td><td>受影响主机</td></tr></thead><tbody>${failAllRows}</tbody></table>
  </div>`;

  const failListRows = unknownItems.map((it) => `<tr style="text-align:center"><td style="text-align:left">${esc(it.f.name)}</td><td>—</td><td>${esc(it.g.target_label || it.g.target_type)}</td><td style="text-align:left">${esc(it.f.message)}</td></tr>`).join('') || '<tr><td colspan="4" style="text-align:center">无核查失败项</td></tr>';
  const failList = `
  <div class="item">
    <h2 class="item-title"><span id="title7">7.核查失败列表</span></h2>
    <table class="datagrid"><thead><tr><td style="width:30%">名称</td><td>IP</td><td>类别</td><td>失败原因</td></tr></thead><tbody>${failListRows}</tbody></table>
  </div>`;

  // 核查项明细：逐项列出每个检查项（编号/核查项/类别/级别/实测值/期望/状态/得分）
  const detailSection = groups.map((g) => {
    const rows = g.items.map((f) => `<tr style="text-align:center"><td class="mono" style="text-align:left">${esc(f.item_id)}</td><td style="text-align:left">${esc(f.name)}</td><td>${esc(f.category || '—')}</td><td>${esc(f.severity || '—')}</td><td style="text-align:left">${esc(f.actual == null ? '' : f.actual)}</td><td>${esc(f.expected || '')}</td><td>${statusBadge(f.status)}</td><td><b>${itemScore(f)}</b></td></tr>`).join('') || '<tr><td colspan="8" style="text-align:center">无检查项</td></tr>';
    return `<div class="item"><h2 class="item-title"><span>${esc(g.target_label || g.target_type)} 核查项明细（${g.items.length} 项）</span></h2><table class="datagrid"><thead><tr><td style="width:14%">编号</td><td style="width:26%">核查项</td><td>类别</td><td>级别</td><td>实测值</td><td>期望</td><td>状态</td><td>得分</td></tr></thead><tbody>${rows}</tbody></table></div>`;
  }).join('');

  const toc = `
  <ul class="catalog">
    <li><a href="#title1">1.概述信息</a></li>
    <li><a href="#title2">2.设备分类统计</a></li>
    <li><a href="#title3">3.设备风险等级 TOP</a></li>
    <li><a href="#title4">4.设备风险等级汇总</a></li>
    <li><a href="#title5">5.不合规检查项 TOP 10</a></li>
    <li><a href="#title6">6.不合规检查项汇总</a></li>
    <li><a href="#title7">7.核查失败列表</a></li>
    <li><a href="#title8">8.核查项明细</a></li>
  </ul>`;

  const body = `
  <div class="header"><div class="title">"安全基线核查系统"安全分析报告</div></div>
  <div class="main-content">
    <h2 class="item-title"><span>目录</span></h2>
    ${toc}
    ${overview}
    ${classify}
    ${topChart}
    ${summary}
    ${topFail}
    ${failList}
    <div class="item"><h2 class="item-title"><span id="title8">8.核查项明细</span></h2></div>
    ${detailSection}
  </div>`;

  return `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><title>安全基线核查系统 安全分析报告 - ${esc(s.hostname)}</title><style>${CSS}</style></head><body><div class="content">${body}</div></body></html>`;
}

function exportCsv(report) {
  const header = ['编号', '类别', '级别', '核查项', '状态', '实测值', '期望', '说明', '加固建议', '依据', '来源类型'];
  const lines = [header.map((h) => `"${h}"`).join(',')];
  for (const g of report.groups) {
    for (const f of g.items) {
      const row = [f.item_id, f.category, f.severity, f.name, f.status, f.actual == null ? '' : f.actual, f.expected, f.message, f.remediation, f.reference, g.target_type];
      lines.push(row.map((c) => `"${String(c == null ? '' : c).replace(/"/g, '""')}"`).join(','));
    }
  }
  return '﻿' + lines.join('\n'); // BOM 便于 Excel 正确识别 UTF-8
}

async function exportExcel(report) {
  const wb = new ExcelJS.Workbook();
  wb.creator = '基线核查系统';
  wb.created = new Date();
  const ws = wb.addWorksheet('基线报告');
  const s = report.server;
  ws.columns = [
    { header: '编号', key: 'id', width: 18 },
    { header: '类别', key: 'cat', width: 14 },
    { header: '来源类型', key: 'tt', width: 18 },
    { header: '级别', key: 'sev', width: 8 },
    { header: '核查项', key: 'name', width: 28 },
    { header: '状态', key: 'status', width: 10 },
    { header: '实测值', key: 'actual', width: 30 },
    { header: '期望', key: 'expected', width: 20 },
    { header: '说明', key: 'msg', width: 24 },
    { header: '加固建议', key: 'rem', width: 36 },
    { header: '依据', key: 'ref', width: 18 },
  ];
  ws.getRow(1).font = { bold: true };
  ws.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFF0F4FA' } };
  const statusColor = { pass: 'FFE6F6EC', fail: 'FFFDE8E8', manual: 'FFFFF4E0', unknown: 'FFEEF1F5' };
  for (const g of report.groups) {
    const title = ws.addRow([`【${g.target_label || g.target_type}】(${g.target_type} · ${g.platform})`]);
    title.font = { bold: true };
    title.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFDCE6F7' } };
    for (const f of g.items) {
      const r = ws.addRow({
        id: f.item_id, cat: f.category, tt: g.target_type, sev: f.severity, name: f.name,
        status: f.status, actual: f.actual == null ? '' : f.actual, expected: f.expected, msg: f.message,
        rem: f.remediation, ref: f.reference,
      });
      if (statusColor[f.status]) r.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: statusColor[f.status] } };
    }
  }
  const buf = await wb.xlsx.writeBuffer();
  return Buffer.from(buf);
}

module.exports = { exportHtml, exportCsv, exportExcel };
