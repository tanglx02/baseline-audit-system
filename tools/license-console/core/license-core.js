'use strict';
/**
 * license-core.js — 授权后台软件核心算法（与 server/license.js 完全对齐）
 *
 * 集成两种签发方式：
 *   1) 卡密（card）：不绑定机器，可跨服务器使用；网站端激活时一次性核销。
 *   2) 机器码许可证（machine）：绑定指定机器码，仅该机器可激活。
 *
 * 算法：
 *   令牌 = base64url(payload).HMAC_SHA256(SECRET, base64url(payload))
 *   payload = { v:1, typ:'card'|'machine', mc?, exp:'YYYY-MM-DD'|null, feat:[...], iat, rnd }
 *
 * 注意：本软件运行在作者机器上，用于为「目标服务器」签发令牌。
 *       因此 validateLicense 只校验签名+有效期，不与「本机」机器码比对。
 */
const crypto = require('crypto');

// 密钥：优先环境变量 LICENSE_SECRET，否则与 server/license.js 保持默认一致
const SECRET = process.env.LICENSE_SECRET || 'BASELINE-AUDIT-SYSTEM-VENDOR-SECRET-2026';

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
function verifySignature(payloadB64, sig) {
  const expected = sign(payloadB64);
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

function _payload({ typ, machineCode, expiresAt, features }) {
  return {
    v: 1,
    typ: typ || 'card',
    mc: typ === 'machine' ? (machineCode || '') : undefined,
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

// 卡密（不绑定机器）
function generateCardKey({ expiresAt, features } = {}) {
  return _encode(_payload({ typ: 'card', expiresAt, features }));
}
function generateCardKeys(count, { expiresAt, features } = {}) {
  const n = Math.max(1, parseInt(count, 10) || 1);
  const out = [];
  for (let i = 0; i < n; i++) out.push(generateCardKey({ expiresAt, features }));
  return out;
}

// 机器码许可证（绑定指定机器码）
function generateMachineLicense({ machineCode, expiresAt, features } = {}) {
  if (!machineCode) throw new Error('缺少 machineCode');
  return _encode(_payload({ typ: 'machine', machineCode, expiresAt, features }));
}

// 校验（只验签名+有效期，不比对本机机器码 —— 本软件用于签发，不用于激活）
function validateToken(str) {
  if (!str || typeof str !== 'string') return { valid: false, reason: 'NO_LICENSE' };
  const parts = str.trim().split('.');
  if (parts.length !== 2) return { valid: false, reason: 'MALFORMED' };
  const [p, sig] = parts;
  let payload;
  try { payload = JSON.parse(b64urlDecode(p).toString('utf-8')); }
  catch (e) { return { valid: false, reason: 'BAD_PAYLOAD' }; }
  if (!verifySignature(p, sig)) return { valid: false, reason: 'BAD_SIGNATURE' };
  const today = new Date().toISOString().slice(0, 10);
  if (payload.exp && payload.exp < today) return { valid: false, reason: 'EXPIRED', payload, daysLeft: -1 };
  const daysLeft = payload.exp ? Math.round((new Date(payload.exp) - new Date(today)) / 86400000) : null;
  const mode = payload.typ === 'machine' ? 'machine' : 'card';
  return { valid: true, payload, daysLeft, mode };
}

module.exports = {
  SECRET,
  generateCardKey,
  generateCardKeys,
  generateMachineLicense,
  validateToken,
};
