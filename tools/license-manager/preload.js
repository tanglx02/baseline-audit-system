'use strict';
/**
 * preload.js — 在隔离上下文中向渲染进程暴露安全 API（仅 ipc 调用）
 */
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  machineInfo: () => ipcRenderer.invoke('machine-info'),
  generate: (args) => ipcRenderer.invoke('generate', args),
  verify: (args) => ipcRenderer.invoke('verify', args),
  activate: (args) => ipcRenderer.invoke('activate', args),
  deactivate: (args) => ipcRenderer.invoke('deactivate', args),
  readLocal: (args) => ipcRenderer.invoke('read-local', args),
  chooseInstanceDir: () => ipcRenderer.invoke('choose-instance-dir'),
  saveLicenseFile: (args) => ipcRenderer.invoke('save-license-file', args),
  loadLicenseFile: () => ipcRenderer.invoke('load-license-file'),
});
