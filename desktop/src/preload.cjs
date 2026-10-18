'use strict';
const { contextBridge, ipcRenderer } = require('electron');
const api = {};
for (const name of ['state', 'open', 'create', 'save', 'floppy', 'disc', 'start', 'pause', 'resume', 'shutdown', 'restart', 'forceOff', 'reveal', 'catalog', 'download', 'pauseDownload', 'paste', 'cancelPaste', 'chooseShare', 'platform']) {
  api[name] = (...args) => ipcRenderer.invoke(name, ...args);
}
api.onState = callback => { ipcRenderer.on('state', (_event, state) => callback(state)); };
api.onProblem = callback => { ipcRenderer.on('problem', (_event, message) => callback(message)); };
for (const [method,event] of [['onDownloadProgress','download-progress'],['onPasteProgress','paste-progress']]) api[method]=callback=>ipcRenderer.on(event,(_event,value)=>callback(value));
contextBridge.exposeInMainWorld('classicmac', api);
