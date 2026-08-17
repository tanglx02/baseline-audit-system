'use strict';
// renderer.js — 授权管理机 UI 逻辑
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

function showOut(el, text) { el.textContent = text; el.classList.remove('hidden'); }

// 本机机器码
(async () => {
  const info = await window.api.machineInfo();
  $('mc').value = info.machineCode;
  $('os').value = `${info.hostname} | ${info.platform} ${info.release} | ${info.arch}`;
  $('gen-mc').value = info.machineCode; // 默认填本机，便于自签自测
})();

// 生成
$('btn-gen').addEventListener('click', async () => {
  const mc = $('gen-mc').value.trim();
  const exp = $('gen-exp').value.trim();
  const feat = $('gen-feat').value.split(',').map((s) => s.trim()).filter(Boolean);
  const secret = $('gen-secret').value.trim();
  if (!mc || !exp) { showOut($('gen-out'), '请填写机器码与有效期'); return; }
  const lic = await window.api.generate({ machineCode: mc, expiresAt: exp, features: feat, secret });
  showOut($('gen-out'), lic);
});
$('btn-gen-copy').addEventListener('click', () => { navigator.clipboard.writeText($('gen-out').textContent); });
$('btn-gen-save').addEventListener('click', async () => {
  const txt = $('gen-out').textContent; if (!txt) return;
  await window.api.saveLicenseFile({ text: txt });
});

// 激活
$('btn-act-pick').addEventListener('click', async () => {
  const dir = await window.api.chooseInstanceDir();
  if (dir) $('act-dir').value = dir;
});
$('btn-act').addEventListener('click', async () => {
  const dir = $('act-dir').value.trim();
  const lic = $('act-lic').value.trim();
  if (!dir || !lic) { showOut($('act-out'), '请选择 instance 目录并粘贴许可证'); return; }
  const r = await window.api.activate({ license: lic, dir });
  showOut($('act-out'), r.ok ? `激活成功，已写入：${r.path}` : `激活失败（许可证无效）：${r.reason}`);
});
$('btn-act-load').addEventListener('click', async () => {
  const txt = await window.api.loadLicenseFile(); if (txt) $('act-lic').value = txt;
});
$('btn-act-revoke').addEventListener('click', async () => {
  const dir = $('act-dir').value.trim(); if (!dir) { showOut($('act-out'), '请先选择 instance 目录'); return; }
  if (!confirm('确认吊销本机许可证（删除 license.key）？')) return;
  const r = await window.api.deactivate({ dir });
  showOut($('act-out'), r.ok ? `已吊销：${r.path}` : '吊销失败');
});

// 校验
$('btn-ver').addEventListener('click', async () => {
  const lic = $('ver-lic').value.trim();
  const secret = $('ver-secret').value.trim();
  if (!lic) { showOut($('ver-out'), '请粘贴许可证'); return; }
  const r = await window.api.verify({ license: lic, secret });
  if (r.valid) showOut($('ver-out'), `有效 ✅\n有效期至：${r.payload.exp}\n剩余天数：${r.daysLeft}\n功能：${(r.payload.feat || []).join(', ')}`);
  else showOut($('ver-out'), `无效 ❌ 原因：${r.reason}${r.payload ? '\n到期/机器：' + r.payload.exp : ''}`);
});
$('btn-ver-load').addEventListener('click', async () => {
  const txt = await window.api.loadLicenseFile(); if (txt) $('ver-lic').value = txt;
});
