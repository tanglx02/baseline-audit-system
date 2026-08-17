'use strict';
/**
 * main.js — 授权管理机（Electron 主进程）
 * 提供 GUI：本机机器码 / 生成许可证 / 激活 / 校验 / 吊销。
 * 所有加密逻辑在 Node 主进程完成（core/license-core.js），渲染进程通过 preload 调用。
 */
const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const core = require('./core/license-core');

let win = null;

function createWindow() {
  win = new BrowserWindow({
    width: 920,
    height: 720,
    minWidth: 760,
    minHeight: 560,
    title: '基线核查系统 - 授权管理机',
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

// ---------------------------------------------------------------------------
// IPC：渲染进程 -> 主进程
// ---------------------------------------------------------------------------
ipcMain.handle('machine-info', () => ({
  machineCode: core.getMachineCode(),
  hostname: require('os').hostname(),
  platform: require('os').platform(),
  release: require('os').release(),
  arch: require('os').arch(),
}));

ipcMain.handle('generate', (e, { machineCode, expiresAt, features, secret }) => {
  if (secret) process.env.LICENSE_SECRET = secret; // 临时覆盖密钥以匹配目标服务器
  const lic = core.generateLicense({ machineCode, expiresAt, features: features || ['all'] });
  return lic;
});

ipcMain.handle('verify', (e, { license, secret }) => {
  if (secret) process.env.LICENSE_SECRET = secret;
  return core.validateLicense(license);
});

ipcMain.handle('activate', (e, { license, dir, secret }) => {
  if (secret) process.env.LICENSE_SECRET = secret;
  const v = core.validateLicense(license);
  if (!v.valid) return { ok: false, reason: v.reason };
  const keyPath = path.join(dir || '.', 'license.key');
  core.writeLicenseFile(keyPath, license);
  return { ok: true, path: keyPath };
});

ipcMain.handle('deactivate', (e, { dir }) => {
  const keyPath = path.join(dir || '.', 'license.key');
  core.deleteLicenseFile(keyPath);
  return { ok: true, path: keyPath };
});

ipcMain.handle('read-local', (e, { dir }) => {
  const keyPath = path.join(dir || '.', 'license.key');
  const txt = core.readLicenseFile(keyPath);
  return { exists: !!txt, text: txt || '', path: keyPath };
});

// 选择服务器 instance 目录（license.key 所在目录）
ipcMain.handle('choose-instance-dir', async () => {
  const r = await dialog.showOpenDialog(win, { title: '选择服务器 instance 目录', properties: ['openDirectory'] });
  if (r.canceled || !r.filePaths.length) return null;
  return r.filePaths[0];
});

// 保存许可证字符串到文件
ipcMain.handle('save-license-file', async (e, { text }) => {
  const r = await dialog.showSaveDialog(win, { title: '保存许可证', defaultPath: 'license.key', filters: [{ name: 'License', extensions: ['key', 'txt'] }] });
  if (r.canceled || !r.filePath) return null;
  core.writeLicenseFile(r.filePath, text);
  return r.filePath;
});

// 读取许可证文件
ipcMain.handle('load-license-file', async () => {
  const r = await dialog.showOpenDialog(win, { title: '打开许可证文件', properties: ['openFile'], filters: [{ name: 'License', extensions: ['key', 'txt'] }] });
  if (r.canceled || !r.filePaths.length) return null;
  return core.readLicenseFile(r.filePaths[0]) || '';
});
