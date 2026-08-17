'use strict';
/**
 * cardkey-core.js — 卡密核心（与 server/license.js 共用同一算法与默认密钥）
 *
 * 卡密 = base64url(JSON).HMAC-SHA256(SECRET)，payload 不含机器码，离线校验。
 * 生成机与网站必须 SECRET 一致，否则签发的卡密无法被网站激活。
 */
const crypto = require('crypto');

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

function _payload({ expiresAt, features }) {
  return {
    v: 1,
    typ: 'card',
    mc: undefined,
    exp: expiresAt || null,
    feat: Array.isArray(features) ? features : (features ? [features] : ['all']),
    iat: new Date().toISOString().slice(0, 10),
    rnd: crypto.randomBytes(6).toString('hex'),
  };
}
function _encode(payload) {
  const p = b64url(JSON.stringify(payload));
  return p + '.' + sign(p);
}
function generateCardKey({ expiresAt, features } = {}) {
  return _encode(_payload({ expiresAt, features }));
}
function generateCardKeys(count, { expiresAt, features } = {}) {
  const n = Math.max(1, parseInt(count, 10) || 1);
  const out = [];
  for (let i = 0; i < n; i++) out.push(generateCardKey({ expiresAt, features }));
  return out;
}
function validateCardKey(str) {
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
  return { valid: true, payload, daysLeft };
}

module.exports = { SECRET, generateCardKey, generateCardKeys, validateCardKey };
