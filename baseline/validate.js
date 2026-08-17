#!/usr/bin/env node
'use strict';
/**
 * baseline/validate.js — 校验全部 baseline YAML 的合法性与 id 唯一性（Node 版，零 Python 依赖）。
 *
 * 用法:
 *   node baseline/validate.js
 *
 * 退出码 0 = 全部通过；1 = 存在错误。
 */

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const BASELINE_DIR = __dirname;

const VALID_SEVERITY = new Set(['high', 'medium', 'low', 'info']);
const VALID_CHECK_TYPE = new Set(['auto', 'manual']);
const VALID_METHOD_TYPE = new Set(['shell', 'powershell', 'config_file', 'process', 'port', 'manual']);
const VALID_JUDGE_TYPE = new Set([
  'equals', 'not_equals', 'contains',
  'regex_present', 'regex_absent',
  'numeric_leq', 'numeric_geq', 'file_perm_leq',
]);
const VALID_CATEGORY = new Set(['主机安全', '数据库安全', '中间件安全', '容器安全', '网络安全']);
const JUDGE_REQUIRES_VALUE = new Set(['equals', 'not_equals', 'contains', 'numeric_leq', 'numeric_geq', 'file_perm_leq']);

function discoverYamlFiles() {
  return fs.readdirSync(BASELINE_DIR)
    .filter((f) => f.endsWith('.yaml') && fs.statSync(path.join(BASELINE_DIR, f)).isFile())
    .map((f) => path.join(BASELINE_DIR, f))
    .sort();
}

function validateItem(item, source) {
  const errs = [];
  for (const field of ['id', 'category', 'name', 'severity', 'check_type', 'method']) {
    if (!(field in item)) errs.push(`${source}: item 缺少必填字段 '${field}' (id=${item.id})`);
  }
  if ('severity' in item && !VALID_SEVERITY.has(item.severity)) {
    errs.push(`${source}: 非法 severity '${item.severity}' (id=${item.id})`);
  }
  if ('check_type' in item && !VALID_CHECK_TYPE.has(item.check_type)) {
    errs.push(`${source}: 非法 check_type '${item.check_type}' (id=${item.id})`);
  }
  if ('category' in item && !VALID_CATEGORY.has(item.category)) {
    errs.push(`${source}: 非法 category '${item.category}' (id=${item.id})`);
  }
  const m = item.method;
  if (m && typeof m === 'object' && !('type' in m)) {
    errs.push(`${source}: method 缺少 type (id=${item.id})`);
  } else if (m && !VALID_METHOD_TYPE.has(m.type)) {
    errs.push(`${source}: 非法 method.type '${m.type}' (id=${item.id})`);
  }
  if (item.check_type === 'auto') {
    if (!('judge' in item)) {
      errs.push(`${source}: auto 项缺少 judge (id=${item.id})`);
    } else {
      const j = item.judge;
      if (!j || typeof j !== 'object' || !('type' in j)) {
        errs.push(`${source}: judge 缺少 type (id=${item.id})`);
      } else if (!VALID_JUDGE_TYPE.has(j.type)) {
        errs.push(`${source}: 非法 judge.type '${j.type}' (id=${item.id})`);
      } else if (JUDGE_REQUIRES_VALUE.has(j.type) && !('value' in j)) {
        errs.push(`${source}: judge.type=${j.type} 缺少 value (id=${item.id})`);
      }
    }
  }
  return errs;
}

function validateAll() {
  const files = discoverYamlFiles();
  const errors = [];
  const seenIds = {};
  for (const p of files) {
    let data;
    try {
      data = yaml.load(fs.readFileSync(p, 'utf-8'));
    } catch (e) {
      errors.push(`${p}: YAML 解析失败 - ${e.message}`);
      continue;
    }
    if (!data || typeof data !== 'object' || !('catalog' in data)) {
      errors.push(`${p}: 缺少顶层 'catalog' 结构`);
      continue;
    }
    const cat = data.catalog;
    const cid = cat.id || path.basename(p);
    for (const it of (cat.items || [])) {
      errors.push(...validateItem(it, `${p}(${cid})`));
      const iid = it.id;
      if (iid) {
        if (iid in seenIds) errors.push(`id 重复: ${iid} 同时出现在 ${seenIds[iid]} 与 ${cid}`);
        else seenIds[iid] = cid;
      }
    }
  }
  return errors;
}

function main() {
  const errors = validateAll();
  const counts = {};
  for (const p of discoverYamlFiles()) {
    try {
      const data = yaml.load(fs.readFileSync(p, 'utf-8')) || {};
      const cat = data.catalog || {};
      const cid = cat.id || path.basename(p);
      counts[cid] = (cat.items || []).length;
    } catch (e) {
      counts[path.basename(p)] = -1;
    }
  }
  const total = Object.values(counts).filter((v) => v > 0).reduce((a, b) => a + b, 0);
  console.log(`发现 ${Object.keys(counts).length} 个 catalog 文件，共 ${total} 个核查项。`);
  for (const [cid, n] of Object.entries(counts).sort()) console.log(`  - ${cid}: ${n} 项`);
  if (errors.length) {
    console.log('\n校验失败:');
    for (const e of errors) console.log('  -', e);
    process.exit(1);
  }
  console.log('\n✅ 全部 baseline YAML 校验通过');
  process.exit(0);
}

main();
