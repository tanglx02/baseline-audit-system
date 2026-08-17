'use strict';
/**
 * license-core.js — 授权管理机核心算法（与 server/license.js 完全对齐）
 *
 * 供应商用「授权管理机」根据本机/客户机器码 + 有效期签发许可证，
 * 目标服务器上的 Web 系统用 server/license.js 校验，算法必须一致。
 *
 * 算法：
 *   机器码 = SHA256(hostname|platform|release|首块非内部网卡MAC)
 *   许可证 = base64url(payload).HMAC_SHA256(SECRET, base64url(payload))
 *   payload = { v:1, mc, exp:'YYYY-MM-DD', feat:['all'], iat:'YYYY-MM-DD' }
 */
const crypto = require('crypto');
const os = require('os');
const fs = require('fs');
const path = require('path');

// 密钥：优先环境变量 LICENSE_SECRET，否则与 server/license.js 保持默认一致
const SECRET = process.env.LICENSE_SECRET || 'BASELINE-AUDIT-SYSTEM-VENDOR-SECRET-2026';

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

function generateLicense({ machineCode, expiresAt, features }) {
  const payload = {
    v: 1,
    mc: machineCode,
    exp: expiresAt, // 'YYYY-MM-DD'
    feat: Array.isArray(features) ? features : (features ? [features] : ['all']),
    iat: new Date().toISOString().slice(0, 10),
  };
  const p = b64url(JSON.stringify(payload));
  return p + '.' + sign(p);
}

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
  const mc = getMachineCode();
  if (payload.mc && payload.mc !== mc) return { valid: false, reason: 'MACHINE_MISMATCH', payload, currentMachine: mc };
  const daysLeft = payload.exp ? Math.round((new Date(payload.exp) - new Date(today)) / 86400000) : null;
  return { valid: true, payload, daysLeft };
}

// 读写 license.key（与 server 的 LICENSE_PATH = instance/license.key 对应）
function writeLicenseFile(licenseKeyPath, licenseStr) {
  fs.mkdirSync(path.dirname(licenseKeyPath), { recursive: true });
  fs.writeFileSync(licenseKeyPath, licenseStr.trim(), 'utf-8');
  return licenseStr.trim();
}
function readLicenseFile(licenseKeyPath) {
  if (!fs.existsSync(licenseKeyPath)) return null;
  return fs.readFileSync(licenseKeyPath, 'utf-8').trim();
}
function deleteLicenseFile(licenseKeyPath) {
  if (fs.existsSync(licenseKeyPath)) fs.unlinkSync(licenseKeyPath);
}

module.exports = {
  SECRET,
  getMachineCode,
  generateLicense,
  validateLicense,
  writeLicenseFile,
  readLicenseFile,
  deleteLicenseFile,
};
