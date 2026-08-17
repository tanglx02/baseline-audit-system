'use strict';
/**
 * baseline_reader.js — 读取 baseline/*.yaml 供「基线目录」页面展示（只读元数据）。
 */
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const BASELINE_DIR = path.join(__dirname, '..', 'baseline');

function getCatalogs() {
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
    const methods = {};
    for (const it of items) {
      const t = (it.method && it.method.type) || 'manual';
      methods[t] = (methods[t] || 0) + 1;
    }
    out.push({
      id: c.id,
      platform: c.platform || 'linux',
      version: String(c.version || '0.0.0'),
      description: c.description || c.id,
      file: f,
      item_count: items.length,
      categories: cats,
      methods,
    });
  }
  return out;
}

module.exports = { getCatalogs };
