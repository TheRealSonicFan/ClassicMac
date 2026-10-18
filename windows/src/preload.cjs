'use strict';
const { contextBridge, ipcRenderer } = require('electron');
const api = {};
for (const name of ['state', 'open', 'create', 'save', 'disc', 'start', 'pause', 'resume', 'shutdown', 'restart', 'forceOff', 'reveal', 'libraryHelp']) {
  api[name] = (...args) => ipcRenderer.invoke(name, ...args);
}
api.onState = callback => { ipcRenderer.on('state', (_event, state) => callback(state)); };
api.onProblem = callback => { ipcRenderer.on('problem', (_event, message) => callback(message)); };
contextBridge.exposeInMainWorld('classicmac', api);
