'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { promisify } = require('node:util');
const run = promisify(require('node:child_process').execFile);
const { freshConfig, writeJSON } = require('./machines.cjs');

function rawDiskArguments(file, sizeGB, platform = process.platform) {
  // The Windows file backend does not expose raw preallocation options.
  return ['create', '-f', 'raw', ...(platform === 'win32' ? [] : ['-o', 'preallocation=off']), file, `${sizeGB}G`];
}

// A first-run Mac uses safe defaults and keeps its installation CD with it.
// mkdir reserves a unique package; a failed copy/image build removes only
// files created by this invocation, leaving existing machines untouched.
async function createInstallerMac({ name, machineFamily, cd, directory, imageTool, pramSeed }) {
  const config = freshConfig(name, machineFamily);
  if (!cd || !(await fs.stat(cd)).isFile()) throw new Error('Choose a Mac OS installation CD image first.');
  if (!['.iso', '.img', '.toast', '.cdr'].includes(path.extname(cd).toLowerCase())) throw new Error('Choose an ISO, IMG, Toast or CDR image.');
  config.diskSizeGB = machineFamily === 'quadra800' ? 2 : 32;
  await fs.mkdir(directory, { recursive: true });
  const base = config.name.replace(/[<>:"/\\|?*]/g, '-').replace(/[. ]+$/, '') || 'Mac OS';
  let folder;
  for (let counter = 1; ; counter++) {
    folder = path.join(directory, `${base}${counter === 1 ? '' : ` ${counter}`}.classic`);
    try { await fs.mkdir(folder); break; } catch (error) { if (error.code !== 'EEXIST') throw error; }
  }
  const cdName = 'Install CD' + path.extname(cd).toLowerCase();
  try {
    await fs.copyFile(cd, path.join(folder, cdName), require('node:fs').constants.COPYFILE_EXCL);
    await run(imageTool, rawDiskArguments(path.join(folder, 'disk.img'), config.diskSizeGB), { windowsHide: true });
    if (machineFamily === 'quadra800') await fs.copyFile(pramSeed, path.join(folder, 'pram.img'));
    config.cdImagePath = path.join(folder, cdName);
    config.bootFromCD = true;
    await writeJSON(path.join(folder, 'config.json'), config);
    return folder;
  } catch (error) {
    for (const file of [cdName, 'disk.img', 'pram.img', 'config.json']) await fs.rm(path.join(folder, file), { force: true });
    await fs.rmdir(folder);
    throw error;
  }
}
module.exports = { createInstallerMac, rawDiskArguments };
