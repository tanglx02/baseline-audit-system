'use strict';
/**
 * config.js — 项目级配置（持久化到项目根 config.json）
 * 目前主要存放升级相关设置：应用更新后是否自动重启服务。
 * 升级源（Gitee / GitHub）地址为内置固定值，见 server/upgrade.js，不在此配置。
 * 注意：config.json 属于用户配置，升级时不会被覆盖。
 */
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');
const CONFIG_PATH = path.join(ROOT, 'config.json');

const DEFAULTS = {
  upgrade: {
    autoRestart: true,  // 应用更新后是否自动重启服务
  },
};

function deepMerge(base, over) {
  const out = Array.isArray(base) ? base.slice() : Object.assign({}, base);
  if (!over || typeof over !== 'object') return out;
  for (const k of Object.keys(over)) {
    if (over[k] && typeof over[k] === 'object' && !Array.isArray(over[k]) && base[k] && typeof base[k] === 'object') {
      out[k] = deepMerge(base[k], over[k]);
    } else {
      out[k] = over[k];
    }
  }
  return out;
}

function getConfig() {
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      const raw = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));
      return deepMerge(DEFAULTS, raw);
    }
  } catch (e) { /* 损坏则回退默认 */ }
  return deepMerge(DEFAULTS, {});
}

function saveConfig(patch) {
  const merged = deepMerge(getConfig(), patch || {});
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(merged, null, 2), 'utf-8');
  return merged;
}

module.exports = { ROOT, CONFIG_PATH, getConfig, saveConfig, DEFAULTS };
