'use strict';
/**
 * license.js — 授权模块
 *
 * 两种激活方式：
 *  1) 机器码许可证（旧，向后兼容）：machine_code + 有效期 + HMAC 签名，绑定本机。
 *  2) 卡密（新，推荐）：带签名的令牌，离线本地校验，不绑定机器，可带有效期。
 *     - 卡密生成由「卡密生成机」(tools/cardkey-generator) 完成，与本站共用同一 SECRET。
 *     - 网站端粘贴卡密即可激活，换机/重装无需重新授权。
 *
 * 授权网关未授权时仅放行 /license* /catalog /download /health /static /dist。
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { INSTANCE_DIR } = require('./db');

// 供应商签名密钥（实际部署应放在环境变量/配置中，生成机与本站须一致）
const SECRET = process.env.LICENSE_SECRET || 'BASELINE-AUDIT-SYSTEM-VENDOR-SECRET-2026';
const LICENSE_PATH = path.join(INSTANCE_DIR, 'license.key');

// ---------------------------------------------------------------------------
// 机器码（仅机器码许可证使用）
// ---------------------------------------------------------------------------
function getMachineCode() {
  const ifaces = os.networkInterfaces();
  let mac = '';
  outer: for (const name of Object.keys(ifaces)) {
    for (const ni of ifaces[name] || []) {
      if (!ni.internal && ni.mac && ni.mac !== '00:00:00:00:00:00') { mac = ni.mac; break outer; }
    }
  }
  const raw = [os.hostname(), os.platform(), os.release(), mac || 'no-mac'].join('|');
  return crypto.createHash('sha256').update(raw).digest('hex');
}

// ---------------------------------------------------------------------------
// 编解码
// ---------------------------------------------------------------------------
function b64url(buf) {
  return Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64urlDecode(s) {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  return Buffer.from(s, 'base64');
}

function sign(payloadB64) {
  return b64url(crypto.createHmac('sha256', SECRET).update(payloadB64).digest());
}

// ---------------------------------------------------------------------------
// 签发
// ---------------------------------------------------------------------------
function _payload({ machineCode, expiresAt, features, typ }) {
  return {
    v: 1,
    typ: typ || (machineCode ? 'machine' : 'card'),
    mc: machineCode || undefined,
    exp: expiresAt || null, // 'YYYY-MM-DD' 或 null(永久)
    feat: Array.isArray(features) ? features : (features ? [features] : ['all']),
    iat: new Date().toISOString().slice(0, 10),
    rnd: crypto.randomBytes(6).toString('hex'),
  };
}

function _encode(payload) {
  const p = b64url(JSON.stringify(payload));
  return p + '.' + sign(p);
}

// 机器码许可证（旧）
function generateLicense({ machineCode, expiresAt, features }) {
  return _encode(_payload({ machineCode, expiresAt, features, typ: 'machine' }));
}

// 卡密（新）：不绑定机器
function generateCardKey({ expiresAt, features } = {}) {
  return _encode(_payload({ machineCode: null, expiresAt, features, typ: 'card' }));
}

// 批量生成卡密
function generateCardKeys(count, { expiresAt, features } = {}) {
  const n = Math.max(1, parseInt(count, 10) || 1);
  const out = [];
  for (let i = 0; i < n; i++) out.push(generateCardKey({ expiresAt, features }));
  return out;
}

// ---------------------------------------------------------------------------
// 校验
// ---------------------------------------------------------------------------
function verifySignature(payloadB64, sig) {
  const expected = sign(payloadB64);
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

function validateLicense(licenseStr) {
  if (!licenseStr || typeof licenseStr !== 'string') return { valid: false, reason: 'NO_LICENSE' };
  const parts = licenseStr.trim().split('.');
  if (parts.length !== 2) return { valid: false, reason: 'MALFORMED' };
  const [p, sig] = parts;
  let payload;
  try { payload = JSON.parse(b64urlDecode(p).toString('utf-8')); }
  catch (e) { return { valid: false, reason: 'BAD_PAYLOAD' }; }
  if (!verifySignature(p, sig)) return { valid: false, reason: 'BAD_SIGNATURE' };
  const today = new Date().toISOString().slice(0, 10);
  if (payload.exp && payload.exp < today) return { valid: false, reason: 'EXPIRED', payload, daysLeft: -1 };
  // 机器码许可证才校验本机；卡密不绑定机器
  if (payload.typ === 'machine' && payload.mc) {
    const mc = getMachineCode();
    if (payload.mc !== mc) return { valid: false, reason: 'MACHINE_MISMATCH', payload, currentMachine: mc };
  }
  const daysLeft = payload.exp ? Math.round((new Date(payload.exp) - new Date(today)) / 86400000) : null;
  const mode = payload.typ === 'card' ? 'card' : 'machine';
  return { valid: true, payload, daysLeft, mode };
}

function loadActiveLicense() {
  try {
    if (!fs.existsSync(LICENSE_PATH)) return { valid: false, reason: 'NO_LICENSE' };
    const txt = fs.readFileSync(LICENSE_PATH, 'utf-8').trim();
    return validateLicense(txt);
  } catch (e) {
    return { valid: false, reason: 'READ_ERROR', error: String(e) };
  }
}

function saveActiveLicense(licenseStr) {
  fs.writeFileSync(LICENSE_PATH, licenseStr.trim(), 'utf-8');
  return loadActiveLicense();
}

function deleteActiveLicense() {
  if (fs.existsSync(LICENSE_PATH)) fs.unlinkSync(LICENSE_PATH);
}

module.exports = {
  SECRET,
  LICENSE_PATH,
  getMachineCode,
  generateLicense,
  generateCardKey,
  generateCardKeys,
  validateLicense,
  loadActiveLicense,
  saveActiveLicense,
  deleteActiveLicense,
};
