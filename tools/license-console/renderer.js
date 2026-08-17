'use strict';
// renderer.js — 授权后台软件 LicenseConsole UI 逻辑
const $ = (id) => document.getElementById(id);

// 切换标签页
document.querySelectorAll('.tab').forEach((t) => {
  t.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach((x) => x.classList.remove('active'));
    document.querySelectorAll('section.panel').forEach((s) => s.classList.add('hidden'));
    t.classList.add('active');
    $('tab-' + t.dataset.tab).classList.remove('hidden');
  });
});

function showMsg(el, cls, text) { el.className = 'msg ' + cls; el.classList.remove('hidden'); el.textContent = text; }
function hideMsg(el) { el.classList.add('hidden'); }

function featArray(selId) {
  const v = $(selId).value;
  return v === 'all' ? ['all'] : [v];
}
function featList(inputId) {
  return $(inputId).value.split(',').map((s) => s.trim()).filter(Boolean);
}

// ---------- 卡密生成 ----------
$('btn-card-gen').addEventListener('click', async () => {
  const count = parseInt($('card-count').value, 10) || 1;
  const expiresAt = $('card-exp').value.trim() || null;
  const features = featArray('card-feat');
  const r = await window.api.genCardKeys({ count, expiresAt, features });
  const msg = $('card-msg');
  if (!r.ok) { showMsg(msg, 'err', '生成失败：' + r.error); return; }
  $('card-out').value = r.keys.join('\n');
  showMsg(msg, 'ok', `成功生成 ${r.keys.length} 个卡密（有效期：${expiresAt || '永久'}）。卡密为一次性，在目标系统激活后立即失效，不可重复激活。`);
});
$('btn-card-copy').addEventListener('click', () => {
  const t = $('card-out').value; if (!t) return;
  navigator.clipboard.writeText(t);
  showMsg($('card-msg'), 'info', '已复制全部卡密到剪贴板。');
});
$('btn-card-save').addEventListener('click', async () => {
  const t = $('card-out').value; if (!t) { alert('请先生成卡密'); return; }
  const r = await window.api.saveFile({ text: t + '\n', defaultName: 'cardkeys.txt' });
  if (r.ok) showMsg($('card-msg'), 'info', '已导出至：' + r.filePath);
  else if (!r.canceled) alert('导出失败');
});
$('btn-card-clear').addEventListener('click', () => {
  $('card-out').value = ''; hideMsg($('card-msg'));
});

// ---------- 机器码许可证 ----------
$('btn-mc-gen').addEventListener('click', async () => {
  const machineCode = $('mc-input').value.trim();
  const expiresAt = $('mc-exp').value.trim() || null;
  const features = featList('mc-feat');
  const msg = $('mc-msg');
  if (!machineCode) { showMsg(msg, 'err', '请粘贴客户提供的机器码'); return; }
  const r = await window.api.genMachine({ machineCode, expiresAt, features });
  if (!r.ok) { showMsg(msg, 'err', '生成失败：' + r.error); return; }
  $('mc-out').value = r.license;
  showMsg(msg, 'ok', `已生成机器码许可证（有效期：${expiresAt || '永久'}）。该许可证绑定所填机器码，仅该机器可激活。`);
});
$('btn-mc-copy').addEventListener('click', () => {
  const t = $('mc-out').value; if (!t) return;
  navigator.clipboard.writeText(t);
  showMsg($('mc-msg'), 'info', '已复制许可证到剪贴板。');
});
$('btn-mc-save').addEventListener('click', async () => {
  const t = $('mc-out').value; if (!t) { alert('请先生成许可证'); return; }
  const r = await window.api.saveFile({ text: t, defaultName: 'license.key' });
  if (r.ok) showMsg($('mc-msg'), 'info', '已保存至：' + r.filePath);
  else if (!r.canceled) alert('保存失败');
});

// ---------- 校验 ----------
$('btn-ver').addEventListener('click', async () => {
  const token = $('ver-in').value.trim();
  const out = $('ver-out');
  if (!token) { out.classList.remove('hidden'); out.textContent = '请粘贴卡密或机器码许可证'; return; }
  const r = await window.api.verify({ token });
  if (r.valid) {
    const type = r.mode === 'machine' ? '机器码许可证（绑定机器）' : '卡密（不绑定机器）';
    const mc = r.payload.mc ? r.payload.mc : '—';
    out.classList.remove('hidden');
    out.textContent = `有效 ✅\n类型：${type}\n有效期至：${r.payload.exp || '永久'}${r.daysLeft != null ? '（剩余 ' + r.daysLeft + ' 天）' : ''}\n功能：${(r.payload.feat || []).join(', ')}\n绑定机器码：${mc}`;
  } else {
    const reasons = { MALFORMED: '格式错误', BAD_PAYLOAD: '内容解析失败', BAD_SIGNATURE: '签名校验失败（密钥不匹配或被篡改）', EXPIRED: '已过期' };
    out.classList.remove('hidden');
    out.textContent = `无效 ❌ 原因：${reasons[r.reason] || r.reason}`;
  }
});
