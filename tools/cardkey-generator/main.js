'use strict';
const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const core = require('./core/cardkey-core');

function createWindow() {
  const win = new BrowserWindow({
    width: 760, height: 640,
    title: '卡密生成机 · 安全基线核查系统',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false },
  });
  win.loadFile(path.join(__dirname, 'index.html'));
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });

ipcMain.handle('gen', (e, { count, expiresAt, features }) => {
  try {
    const keys = core.generateCardKeys(count, { expiresAt, features });
    return { ok: true, keys };
  } catch (err) { return { ok: false, error: String(err) }; }
});

ipcMain.handle('verify', (e, { key }) => core.validateCardKey(key));

ipcMain.handle('save-keys', async (e, { keys }) => {
  const { canceled, filePath } = await dialog.showSaveDialog({
    title: '导出卡密', defaultPath: 'cardkeys.txt', filters: [{ name: 'Text', extensions: ['txt'] }],
  });
  if (canceled || !filePath) return { ok: false, canceled: true };
  fs.writeFileSync(filePath, keys.join('\n') + '\n', 'utf-8');
  return { ok: true, filePath };
});
