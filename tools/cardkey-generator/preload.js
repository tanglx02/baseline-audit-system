'use strict';
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('api', {
  gen: (opts) => ipcRenderer.invoke('gen', opts),
  verify: (opts) => ipcRenderer.invoke('verify', opts),
  saveKeys: (opts) => ipcRenderer.invoke('save-keys', opts),
});
