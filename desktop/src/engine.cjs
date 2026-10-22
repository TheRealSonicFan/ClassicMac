'use strict';
const { spawn } = require('node:child_process');
const { createServer } = require('node:net');
const { randomBytes } = require('node:crypto');
const { EventEmitter } = require('node:events');
const { argumentsFor } = require('./arguments.cjs');

async function availablePort() {
  const server = createServer();
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}
class Engine extends EventEmitter {
  constructor(machine, resources, binary, launchProcess = spawn) {
    super(); this.machine = machine; this.resources = resources; this.binary = binary;
    this.launchProcess = launchProcess;
    this.pending = new Map(); this.sequence = 0; this.paused = false; this.log = ''; this.stopping = false;
  }
  async start() {
    this.starting = true;
    let collisions = 0;
    try {
      for (;;) {
        this.exited = false; this.log = ''; this.initialized = false;
        try { return await this.launch(); }
        catch (error) {
          // A port can be claimed between the availability probe and QEMU's
          // bind. Retry only that pre-boot failure, with fresh display ports.
          if (/Failed to find an available port: Address already in use/.test(this.log) && ++collisions < 3) continue;
          // A missing host sound device must not prevent the first boot. Keep
          // the guest sound hardware/clock and the saved preference; use a
          // silent host backend for this session and tell the UI about it.
          if (!this.audioUnavailable && this.machine.config.sound &&
              /Could not initialize DirectSound|could not stat pidfile .*[/\\]pulse[/\\]pid|pa_context_connect(?:\(\))? failed/i.test(this.log)) {
            this.audioUnavailable = true;
            continue;
          }
          throw error;
        }
      }
    } finally { this.starting = false; }
  }
  async launch() {
    this.endpoint = { vncPort: await availablePort(), webSocketPort: await availablePort() };
    this.password = randomBytes(6).toString('base64').slice(0, 8);
    const args = argumentsFor(this.machine, this.resources, this.endpoint).map(value => {
      if (this.audioUnavailable && /^(?:dsound|pa|coreaudio),id=snd0$/.test(value)) return 'none,id=snd0';
      return process.env.CLASSICMAC_TEST_HOME && process.env.CLASSICMAC_TEST_TOOLS_IMAGE
        ? value.replace(require('node:path').join(this.resources,'ClassicMacTools.iso'), process.env.CLASSICMAC_TEST_TOOLS_IMAGE) : value;
    });
    this.child = this.launchProcess(this.binary, args, { cwd: require('node:path').join(this.resources, 'bin'), stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    const ready = new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('The emulation engine did not start. ' + this.log)), 15000);
      this.once('ready', () => { clearTimeout(timer); resolve(); });
      this.child.once('error', error => { clearTimeout(timer); reject(error); });
      this.child.once('exit', () => { clearTimeout(timer); reject(new Error('The emulation engine stopped. ' + this.log)); });
    });
    let buffer = '';
    this.child.stdout.setEncoding('utf8');
    this.child.stdout.on('data', chunk => {
      buffer += chunk;
      if (buffer.length > 1048576) { this.child.kill(); return; }
      let at;
      while ((at = buffer.indexOf('\n')) !== -1) {
        const line = buffer.slice(0, at); buffer = buffer.slice(at + 1);
        let msg; try { msg = JSON.parse(line); } catch { continue; }
        if (msg.QMP) this.emit('ready');
        if (msg.event === 'SHUTDOWN') this.shutdownReason = msg.data?.reason;
        if (msg.id && this.pending.has(msg.id)) {
          const p = this.pending.get(msg.id); this.pending.delete(msg.id); clearTimeout(p.timer);
          if (msg.error) p.reject(new Error(msg.error.desc)); else p.resolve(msg.return);
        }
      }
    });
    this.child.stderr.on('data', data => { this.log = (this.log + data.toString()).slice(-65536); });
    this.child.once('exit', (code, signal) => {
      this.exited = true;
      for (const p of this.pending.values()) { clearTimeout(p.timer); p.reject(new Error('The Mac has stopped. ' + JSON.stringify({ code, signal, reason: this.shutdownReason }) + ' ' + this.log)); }
      this.pending.clear();
      if (process.env.CLASSICMAC_TEST_HOME) console.error('Engine exit', JSON.stringify({ code, signal, reason: this.shutdownReason, log: this.log }));
      if (!this.starting) this.emit('exit', { code, signal, restart: (this.restarting && this.shutdownReason === 'guest-shutdown') || (!this.stopping && ['guest-reset', 'host-qmp-system-reset'].includes(this.shutdownReason)) });
    });
    try {
      await ready;
      await this.command('qmp_capabilities');
      await this.command('set_password', { protocol: 'vnc', password: this.password });
      this.initialized = true;
    } catch (error) {
      if (!this.exited) {
        const closed = new Promise(resolve => this.child.once('close', resolve));
        this.child.kill(); await closed;
      }
      throw error;
    }
    return { ...this.endpoint, password: this.password };
  }
  command(execute, args = {}) {
    if (this.exited || !this.child?.stdin.writable) return Promise.reject(new Error('The Mac is not running.'));
    const id = ++this.sequence;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error('The Mac did not respond.')); }, 5000);
      this.pending.set(id, { resolve, reject, timer });
      this.child.stdin.write(JSON.stringify({ execute, arguments: args, id }) + '\n', error => {
        if (error) { clearTimeout(timer); this.pending.delete(id); reject(error); }
      });
    });
  }
  hmp(command) { return this.command('human-monitor-command', { 'command-line': command }); }
  async restart() { await this.shutdown({ restart: true }); }
  async pause() { await this.command('stop'); this.paused = true; }
  async resume() { await this.command('cont'); this.paused = false; }
  async shutdown({ restart = false } = {}) {
    this.restarting = restart;
    this.stopping = true;
    if (this.paused) await this.resume();
    await this.hmp('sendkey power');
    await new Promise(resolve => setTimeout(resolve, 750));
    if (!this.exited) await this.hmp('sendkey ret');
    // Leave a nonresponsive Mac running until the person explicitly chooses
    // Force Off; a normal close must not silently kill a mounted HFS volume.
  }
  async forceOff() { this.restarting = false; this.stopping = true; try { await this.command('quit'); } catch { this.child?.kill(); } }
}
module.exports = { Engine, availablePort };
