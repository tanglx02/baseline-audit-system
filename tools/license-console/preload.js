'use strict';
/**
 * preload.js — 在隔离上下文中向渲染进程暴露安全 API（仅 ipc 调用）
 */
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  genCardKeys: (opts) => ipcRenderer.invoke('gen-cardkeys', opts),
  genMachine: (opts) => ipcRenderer.invoke('gen-machine', opts),
  verify: (opts) => ipcRenderer.invoke('verify', opts),
  saveFile: (opts) => ipcRenderer.invoke('save-file', opts),
});
