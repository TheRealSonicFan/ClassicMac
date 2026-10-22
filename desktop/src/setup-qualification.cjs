'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const assert = require('node:assert/strict');

// Exercises the shipped renderer and IPC against a disposable profile. Only
// the native file picker is substituted; image creation/download/import run
// through the same handlers as a user's clicks.
async function qualify({ window, dialog, engines, home, route }) {
  const checks = [];
  const js = source => window.webContents.executeJavaScript(source);
  async function until(source, timeout = 180000) {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
      if (await js(source)) return;
      const problem = await js('document.getElementById("setup-error")?.textContent');
      if (problem && !problem.startsWith('Paused.')) throw new Error(problem);
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw new Error('Setup timed out: ' + source);
  }
  async function shot(name) { await fs.writeFile(path.join(home, name + '.png'), (await window.webContents.capturePage()).toPNG()); }
  await until('window.classicmacEvidence?.().setup?.active === true');
  assert.equal(await js('document.getElementById("setup-next").disabled'), true);
  await shot('welcome'); checks.push('License acknowledgment gates Continue');
  await js('document.getElementById("setup-license").click(); document.getElementById("setup-next").click()');
  await until('window.classicmacEvidence().setup.step === "source"');
  await shot('source');
  if (route === 'installer') {
    const cd = path.join(home, 'Test installer.iso'); await fs.writeFile(cd, 'Disposable CD copy fixture');
    const original = dialog.showOpenDialog;
    dialog.showOpenDialog = async () => ({ canceled: false, filePaths: [cd] });
    try {
      await js('document.querySelector("input[name=setup-source][value=installer]").click(); document.getElementById("setup-next").click()');
      assert.equal(await js('document.getElementById("setup-next").disabled'), true);
      await js('document.getElementById("setup-cd").click()');
      await until('document.getElementById("setup-next").disabled === false');
      await shot('installer');
      await js('document.getElementById("setup-next").click()');
      await until('window.classicmacEvidence().setup.step === "ready"');
      await shot('installer-ready');
      const rows = await js('window.classicmac.state()'); assert.equal(rows.length, 1);
      const config = JSON.parse(await fs.readFile(path.join(rows[0].folder, 'config.json')));
      assert.equal(config.bootFromCD, true); assert.notEqual(config.cdImagePath, cd);
      assert.equal(await fs.readFile(config.cdImagePath, 'utf8'), 'Disposable CD copy fixture');
      assert.equal((await fs.stat(path.join(rows[0].folder, 'disk.img'))).size, 32 * 1073741824);
      await js('document.getElementById("setup-later").click()');
      await until('window.classicmacEvidence().setup.active === false');
      checks.push('Own CD required; real sparse disk and CD copy created; ready screen survives registration; Later opens library');
    } finally { dialog.showOpenDialog = original; }
  } else {
    await js('document.getElementById("setup-next").click()');
    await until('document.getElementById("setup-edition").options.length > 0');
    await js('document.getElementById("setup-edition").value = "mac-os-9.2.1-gxmetal-2.3.0-32gb-v2"; document.getElementById("setup-edition").dispatchEvent(new Event("change"))');
    await shot('download');
    await js('document.getElementById("setup-next").click()');
    await until('!document.getElementById("setup-progress").hidden && document.getElementById("setup-activity").textContent.includes("Downloading")');
    await js('document.getElementById("setup-pause").click()');
    await until('document.getElementById("setup-next").textContent === "Resume Download" && !document.getElementById("setup-next").disabled');
    await js('document.getElementById("setup-next").click()');
    await until('window.classicmacEvidence().setup.step === "ready"', 360000);
    await shot('download-ready');
    const rows = await js('window.classicmac.state()'); assert.equal(rows.length, 1);
    await js('document.getElementById("setup-next").click()');
    await until('window.classicmacEvidence().setup.active === false');
    const engine = engines.get(rows[0].id); assert(engine);
    await require('./qualification.cjs').waitForFinder(engine, home);
    await until('window.classicmacEvidence().connected === true');
    await shot('first-boot');
    await engine.shutdown();
    const deadline = Date.now() + 40000;
    while (engines.size && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 100));
    assert.equal(engines.size, 0);
    checks.push('Real Library pause/resume, SHA-256, extraction, ready, Start Mac, Finder framebuffer and clean shutdown');
  }
  await fs.writeFile(path.join(home, 'setup-report.json'), JSON.stringify({ platform: process.platform, route, checks, passed: true }, null, 2));
}
module.exports = { qualify };
