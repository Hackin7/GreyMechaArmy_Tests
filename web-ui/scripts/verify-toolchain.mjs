import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { get } from 'svelte/store';
import { files } from '../src/lib/stores.js';
import { normalizeForNetlistSvg } from '../src/lib/netlistUtils.js';

const require = createRequire(import.meta.url);
const netlistsvg = require('netlistsvg');
const digitalSkin = await readFile(new URL('../node_modules/netlistsvg/lib/default.svg', import.meta.url), 'utf8');

const messages = [];
globalThis.self = {
  postMessage(message) {
    messages.push(message);
  }
};

await import('../src/lib/synthesisWorker.js');
assert.equal(typeof self.onmessage, 'function', 'synthesis worker handler should be installed');

const originalConsole = { log: console.log, info: console.info, warn: console.warn };
try {
  console.log = console.info = console.warn = () => {};
  await self.onmessage({
    data: {
      type: 'SYNTHESIZE',
      runId: 7,
      files: get(files)
    }
  });
} finally {
  Object.assign(console, originalConsole);
}

const types = messages.filter((message) => message.runId === 7).map((message) => message.type);
if (!types.includes('LOGICAL_READY')) {
  const lines = messages.filter((message) => message.type === 'LOG').flatMap((message) => message.message.split('\n'));
  console.error(lines.filter((line) => /logical|error:/i.test(line)).slice(-20).join('\n'));
}
const failure = messages.find((message) => message.runId === 7 && message.type === 'ERROR');
if (failure) throw new Error(`${failure.stage}: ${failure.error}`);

assert.ok(types.includes('MAPPED_READY'), 'mapped Yosys JSON should be emitted');
assert.ok(types.includes('LOGICAL_READY'), 'logical Yosys JSON should be emitted');
assert.ok(types.includes('ROUTED_READY'), 'nextpnr placement and report JSON should be emitted');
assert.ok(types.includes('DONE'), 'ecppack bitstream should be emitted');

const mapped = messages.find((message) => message.type === 'MAPPED_READY').json;
const logical = messages.find((message) => message.type === 'LOGICAL_READY').json;
const routed = messages.find((message) => message.type === 'ROUTED_READY');
const done = messages.find((message) => message.type === 'DONE');
const mappedDesign = JSON.parse(new TextDecoder().decode(mapped));
const logicalDesign = JSON.parse(new TextDecoder().decode(logical));
assert.ok(mappedDesign.modules?.top, 'mapped JSON should contain top');
assert.ok(logicalDesign.modules?.top, 'logical JSON should contain top');
for (const [label, design] of [['logical', logicalDesign], ['mapped', mappedDesign]]) {
  const diagramInput = normalizeForNetlistSvg(design);
  for (const [moduleName, module] of Object.entries(diagramInput.modules)) {
    if (Object.hasOwn(module.attributes ?? {}, 'top')) {
      assert.ok([0, 1].includes(module.attributes.top), `${label} ${moduleName} top attribute should be numeric 0 or 1`);
    }
  }
  const svg = await netlistsvg.render(digitalSkin, diagramInput);
  assert.ok(typeof svg === 'string' && svg.startsWith('<svg'), `${label} netlist should render as SVG`);
}
assert.ok(done.bitstream instanceof Uint8Array && done.bitstream.byteLength > 0, 'bitstream should be non-empty');
assert.ok(JSON.parse(new TextDecoder().decode(routed.placementJson)), 'placement JSON should parse');
assert.ok(JSON.parse(new TextDecoder().decode(routed.reportJson)), 'timing report JSON should parse');

console.log(`Verified worker stages: ${types.filter((type) => type.endsWith('_READY')).join(', ')}, DONE`);
