'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { Engine } = require('../src/engine.cjs');
const { freshConfig } = require('../src/machines.cjs');
function processFactory(failures, message) {
  const calls = [];
  function launch(_binary, args) {
    calls.push(args);
    const child = new EventEmitter(); child.stdout = new EventEmitter(); child.stderr = new EventEmitter();
    child.stdout.setEncoding = () => {};
    child.stdin = { writable: true, write(data, callback) {
      const command = JSON.parse(data);
      queueMicrotask(() => child.stdout.emit('data', JSON.stringify({ id: command.id, return: {} }) + '\n'));
      callback?.();
    } };
    child.kill = () => { child.emit('exit', 1, null); child.emit('close', 1, null); };
    queueMicrotask(() => {
      if (calls.length <= failures) { child.stderr.emit('data', Buffer.from(message)); child.kill(); }
      else child.stdout.emit('data', '{"QMP":{}}\n');
    });
    return child;
  }
  return { launch, calls };
}
const collision = 'qemu-system-ppc: Failed to find an available port: Address already in use';
test('A pre-boot display-port collision retries without reporting a stopped Mac', async () => {
  const fake = processFactory(1, collision);
  const engine = new Engine({ folder: '/test/Mac.classic', config: freshConfig('Mac') }, '/runtime', '/qemu', fake.launch);
  let exits = 0; engine.on('exit', () => exits++);
  const display = await engine.start();
  assert.equal(fake.calls.length, 2); assert.equal(exits, 0);
  assert.equal(engine.initialized, true); assert.equal(engine.exited, false);
  assert(display.vncPort > 0 && display.webSocketPort > 0);
  engine.child.kill(); assert.equal(exits, 1);
});
test('Display retries are bounded and unrelated startup failures are reported immediately', async () => {
  for (const [message, attempts] of [[collision, 3], ['Missing firmware', 1]]) {
    const fake = processFactory(10, message);
    const engine = new Engine({ folder: '/test/Mac.classic', config: freshConfig('Mac') }, '/runtime', '/qemu', fake.launch);
    await assert.rejects(engine.start(), /emulation engine stopped/);
    assert.equal(fake.calls.length, attempts); assert.equal(engine.initialized, false);
  }
});
