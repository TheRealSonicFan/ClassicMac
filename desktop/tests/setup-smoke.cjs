'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { createWriteStream } = require('node:fs');
(async () => {
  const exe = path.resolve(process.argv[2]), output = path.resolve(process.argv[3]);
  for (const route of ['installer', 'download']) {
    const home = path.join(output, route); await fs.mkdir(home, { recursive: true });
    const env = { ...process.env, CLASSICMAC_TEST_HOME: home, CLASSICMAC_TEST_SETUP: route };
    for (const name of ['CLASSICMAC_RUNTIME', 'CLASSICMAC_MAC_APP', 'CLASSICMAC_TEST_START']) delete env[name];
    const child = spawn(exe, ['--disable-gpu'], { env, stdio: ['ignore', 'pipe', 'pipe'] });
    const log = createWriteStream(path.join(home, 'desktop.log')); child.stdout.pipe(log); child.stderr.pipe(log);
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => { child.kill(); reject(new Error('Setup smoke timed out.')); }, 700000);
      child.once('error', error => { clearTimeout(timer); reject(error); });
      child.once('exit', code => { clearTimeout(timer); code === 0 ? resolve() : reject(new Error(`Setup ${route} exited ${code}`)); });
    });
    const report = JSON.parse(await fs.readFile(path.join(home, 'setup-report.json')));
    if (!report.passed) throw new Error('Setup qualification failed.');
    console.log('Packaged first-run ' + route + ': passed.');
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
