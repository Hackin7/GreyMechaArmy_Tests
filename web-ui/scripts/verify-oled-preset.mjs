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
assert.match(demo['pinout.lpf'], /LOCATE COMP "btn\[5\]" SITE "D12";/);
assert.match(demo['pinout.lpf'], /LOCATE COMP "btn\[6\]" SITE "C12";/);
assert.match(demo['top.v'], /input\s+wire\s+\[6:0\] btn/);
assert.doesNotMatch(demo['top.v'], /btn_mecha/);

const simple = {
  'top.v': await readFile(new URL('../src/lib/presets/oled-simple/top.v', import.meta.url), 'utf8'),
  ...Object.fromEntries(modules
    .filter((name) => !['btn_debounce.v', 'image_stretch.v'].includes(name))
    .map((name) => [name, demo[name]])),
  'pinout.lpf': demo['pinout.lpf']
};
assert.equal(Object.keys(simple).length, 8);
assert.match(simple['top.v'], /input\s+wire\s+\[6:0\] btn/);
assert.match(simple['top.v'], /assign pixel_data = 16'h07E0;/);
assert.match(simple['top.v'], /wire \[15:0\] pixel_index;/);
assert.doesNotMatch(simple['top.v'], /aspect_idx|\$readmem|image_stretch|btn_debounce/);

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
  await self.onmessage({ data: { type: 'SYNTHESIZE', runId: 89, files: simple } });
} finally {
  Object.assign(console, originalConsole);
}
const error = messages.find((message) => message.type === 'ERROR');
if (error) {
  const logs = messages.filter((message) => message.runId === error.runId && message.type === 'LOG').map((message) => message.message).join('\n');
  throw new Error(`${error.stage}: ${error.error}\n${logs.slice(-6000)}`);
}
for (const runId of [87, 88, 89]) {
  for (const type of ['MAPPED_READY', 'LOGICAL_READY', 'ROUTED_READY', 'DONE']) {
    assert.ok(messages.some((message) => message.runId === runId && message.type === type), `Build ${runId} missing ${type}`);
  }
  assert.ok(messages.find((message) => message.runId === runId && message.type === 'DONE').bitstream.byteLength > 0);
}
console.log('OLED snapshot matches source; modules-only, OLED, and OLED (Advanced) built through Yosys, nextpnr, ecppack.');
