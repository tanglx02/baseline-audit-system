'use strict';
function featArray() {
  const v = document.getElementById('feat').value;
  return v === 'all' ? ['all'] : [v];
}
async function gen() {
  const count = parseInt(document.getElementById('count').value, 10) || 1;
  const expiresAt = document.getElementById('exp').value.trim() || null;
  const features = featArray();
  const r = await window.api.gen({ count, expiresAt, features });
  const msg = document.getElementById('genMsg');
  if (!r.ok) { msg.className = 'msg err'; msg.style.display = 'block'; msg.textContent = '生成失败：' + r.error; return; }
  document.getElementById('out').value = r.keys.join('\n');
  msg.className = 'msg ok'; msg.style.display = 'block';
  msg.textContent = `成功生成 ${r.keys.length} 个卡密（有效期：${expiresAt || '永久'}）。注意：卡密为一次性使用，在目标系统「授权」页激活后立即失效，不可重复激活；如要再次授权，请使用新的卡密。`;
}
function clearOut() {
  document.getElementById('out').value = '';
  const msg = document.getElementById('genMsg'); msg.style.display = 'none';
}
async function saveFile() {
  const keys = document.getElementById('out').value.split('\n').filter(Boolean);
  if (!keys.length) { alert('请先生成卡密'); return; }
  const r = await window.api.saveKeys({ keys });
  if (r.ok) { const msg = document.getElementById('genMsg'); msg.className = 'msg info'; msg.style.display = 'block'; msg.textContent = '已导出至：' + r.filePath; }
  else if (!r.canceled) { alert('导出失败：' + r.error); }
}
async function verify() {
  const key = document.getElementById('verifyIn').value.trim();
  const msg = document.getElementById('verifyMsg');
  if (!key) { msg.className = 'msg err'; msg.style.display = 'block'; msg.textContent = '请粘贴卡密'; return; }
  const r = await window.api.verify({ key });
  if (r.valid) {
    msg.className = 'msg ok'; msg.style.display = 'block';
    msg.textContent = `有效 · 有效期：${r.payload.exp || '永久'}${r.daysLeft != null ? ' · 剩余 ' + r.daysLeft + ' 天' : ''} · 功能：${(r.payload.feat || []).join(',')}`;
  } else {
    msg.className = 'msg err'; msg.style.display = 'block';
    const reasons = { MALFORMED: '格式错误', BAD_PAYLOAD: '内容解析失败', BAD_SIGNATURE: '签名校验失败（密钥不匹配或被篡改）', EXPIRED: '已过期' };
    msg.textContent = '无效：' + (reasons[r.reason] || r.reason);
  }
}
