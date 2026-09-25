import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { get } from 'svelte/store';
import { files } from '../src/lib/stores.js';
import { addWorkspaceFiles, removeWorkspaceFile } from '../src/lib/workspaceFiles.js';

const source = new URL('../../io/fpga_oled_fast/', import.meta.url);
const snapshot = new URL('../src/lib/presets/oled-fast/', import.meta.url);
const modules = [
  'simple_spi_master.v', 'btn_debounce.v', 'ecp5_oled_pll.v',
  'oled_init.v', 'oled_stream.v', 'oled_gc9a01.v',
  'image_stretch.v', 'gc9a01_init_rom.vh'
];
const names = ['top.v', ...modules, 'stonks.mem', 'pinout.lpf'];
const demo = {};
for (const name of names) {
  const content = await readFile(new URL(name, snapshot), 'utf8');
  const originalPath = name === 'pinout.lpf' || name === 'stonks.mem' ? name : `src/${name}`;
  assert.equal(content, await readFile(new URL(originalPath, source), 'utf8'), `${name} differs from fpga_oled_fast`);
  demo[name] = content;
}

const initial = get(files);
const added = addWorkspaceFiles(initial, modules.map((name) => [name, demo[name]]));
assert.deepEqual(added.errors, []);
assert.equal(added.added.length, modules.length);
assert.equal(added.files['top.v'], initial['top.v']);
assert.equal(added.files['pinout.lpf'], initial['pinout.lpf']);
assert.equal(addWorkspaceFiles(added.files, [['top.v', 'overwrite']]).added.length, 0);
assert.ok(addWorkspaceFiles(initial, [['../bad.v', '']]).errors.length);
assert.ok(addWorkspaceFiles(initial, [['other.txt', '']]).errors.length);
assert.equal(removeWorkspaceFile(added.files, 'oled_init.v').files['oled_init.v'], undefined);
assert.ok(removeWorkspaceFile(added.files, 'top.v').error);
assert.ok(removeWorkspaceFile(added.files, 'pinout.lpf').error);

const messages = [];
globalThis.self = { postMessage(message) { messages.push(message); } };
await import('../src/lib/synthesisWorker.js');
const originalConsole = { log: console.log, info: console.info, warn: console.warn };
try {
  console.log = console.info = console.warn = () => {};
  await self.onmessage({ data: { type: 'SYNTHESIZE', runId: 87, files: added.files } });
  await self.onmessage({ data: { type: 'SYNTHESIZE', runId: 88, files: demo } });
} finally {
  Object.assign(console, originalConsole);
}
const error = messages.find((message) => message.type === 'ERROR');
if (error) {
  const logs = messages.filter((message) => message.runId === error.runId && message.type === 'LOG').map((message) => message.message).join('\n');
  throw new Error(`${error.stage}: ${error.error}\n${logs.slice(-6000)}`);
}
for (const runId of [87, 88]) {
  for (const type of ['MAPPED_READY', 'LOGICAL_READY', 'ROUTED_READY', 'DONE']) {
    assert.ok(messages.some((message) => message.runId === runId && message.type === type), `Build ${runId} missing ${type}`);
  }
}
assert.ok(messages.find((message) => message.runId === 88 && message.type === 'DONE').bitstream.byteLength > 0);
console.log('OLED preset files match source; modules-only and complete demo built through Yosys, nextpnr, ecppack.');
