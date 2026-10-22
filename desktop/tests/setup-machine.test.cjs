'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { createInstallerMac } = require('../src/setup-machine.cjs');
const { readMachine } = require('../src/machines.cjs');
const imageTool = process.env.CLASSICMAC_TEST_IMAGE_TOOL || path.resolve(__dirname, '../../output/desktop/runtime/bin/qemu-img' + (process.platform === 'win32' ? '.exe' : ''));
async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'classicmac-setup-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const cd = path.join(root, 'Mac OS.iso'); await fs.writeFile(cd, 'installation media');
  return { name: 'My First Mac', machineFamily: 'powerMacG4', cd, directory: path.join(root, 'Macs'), imageTool, pramSeed: path.resolve(__dirname, '../../shared/pram-seed.img') };
}
test('Installer creation keeps a CD copy, boot defaults and existing same-named Macs', async t => {
  try { await fs.access(imageTool); } catch { return t.skip('Set CLASSICMAC_TEST_IMAGE_TOOL to a built qemu-img'); }
  const options = await fixture(t);
  for (const family of ['powerMacG4', 'quadra800']) {
    options.machineFamily = family;
    const folder = await createInstallerMac(options);
    const m = await readMachine(folder);
    assert.equal(m.config.machineFamily, family);
    assert.equal(m.config.bootFromCD, true);
    assert.equal(m.config.diskSizeGB, family === 'quadra800' ? 2 : 32);
    assert.equal(await fs.readFile(m.config.cdImagePath, 'utf8'), 'installation media');
    assert.notEqual(m.config.cdImagePath, options.cd);
    assert.equal((await fs.stat(path.join(folder, 'disk.img'))).size, m.config.diskSizeGB * 1073741824);
  }
  assert.equal((await fs.readdir(options.directory)).length, 2);
});
test('A failed image build removes its CD and partial machine, preserving existing files', async t => {
  const options = await fixture(t);
  await fs.mkdir(options.directory);
  const existing = path.join(options.directory, 'My First Mac.classic'); await fs.mkdir(existing);
  await fs.writeFile(path.join(existing, 'keep.txt'), 'keep');
  await assert.rejects(createInstallerMac({ ...options, imageTool: path.join(options.directory, 'missing-tool') }));
  assert.deepEqual(await fs.readdir(options.directory), ['My First Mac.classic']);
  assert.equal(await fs.readFile(path.join(existing, 'keep.txt'), 'utf8'), 'keep');
});
test('Missing installation media cannot create a blank first-run Mac', async t => {
  const options = await fixture(t);
  await assert.rejects(createInstallerMac({ ...options, cd: undefined }), /Choose a Mac OS/);
  await assert.rejects(fs.access(options.directory));
});
