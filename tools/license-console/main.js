'use strict';
/**
 * main.js — 授权后台软件 LicenseConsole（Electron 主进程）
 * 集成两种签发方式：卡密生成 + 机器码许可证签发。所有加密在主进程完成。
 */
const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const core = require('./core/license-core');

let win = null;

function createWindow() {
  win = new BrowserWindow({
    width: 960,
    height: 760,
    minWidth: 800,
    minHeight: 600,
    title: '基线核查系统 · 授权后台软件',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  win.loadFile(path.join(__dirname, 'index.html'));
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });

// 卡密生成
ipcMain.handle('gen-cardkeys', (e, { count, expiresAt, features }) => {
  try {
    const keys = core.generateCardKeys(count, { expiresAt, features });
    return { ok: true, keys };
  } catch (err) { return { ok: false, error: String(err) }; }
});

// 机器码许可证签发
ipcMain.handle('gen-machine', (e, { machineCode, expiresAt, features }) => {
  try {
    const lic = core.generateMachineLicense({ machineCode, expiresAt, features });
    return { ok: true, license: lic };
  } catch (err) { return { ok: false, error: String(err) }; }
});

// 校验（卡密 / 机器码许可证通用）
ipcMain.handle('verify', (e, { token }) => core.validateToken(token));

// 保存文本到文件
ipcMain.handle('save-file', async (e, { text, defaultName }) => {
  const r = await dialog.showSaveDialog(win, {
    title: '保存到文件',
    defaultPath: defaultName || 'output.txt',
    filters: [{ name: 'Text', extensions: ['txt', 'key'] }],
  });
  if (r.canceled || !r.filePath) return { ok: false, canceled: true };
  fs.writeFileSync(r.filePath, text, 'utf-8');
  return { ok: true, filePath: r.filePath };
});
