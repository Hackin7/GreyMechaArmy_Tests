import { mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const engine = '09d99f2c3028e27b397df8471baec29975ec154b';
const badge = '3ce9bfbf0061ee36e17dca1274c2f65ae9a5bb07';
const root = new URL('../', import.meta.url);
const sources = [
  ...['hdltypes.ts', 'hdlruntime.ts', 'vxmlparser.ts'].map(name => [
    `https://raw.githubusercontent.com/sehugg/8bitworkshop/${engine}/src/common/hdl/${name}`,
    `vendor/8bitworkshop/hdl/${name}`
  ]),
  ...['util.ts', 'workertypes.ts', 'waveform.ts', 'waveformcore.ts'].map(name => [
    `https://raw.githubusercontent.com/sehugg/8bitworkshop/${engine}/src/common/${name}`,
    `vendor/8bitworkshop/${name}`
  ]),
  ...['verilator_bin.js', 'verilator_bin.wasm'].map(name => [
    `https://raw.githubusercontent.com/sehugg/8bitworkshop/${engine}/src/worker/wasm/${name}`,
    `public/simulator/${name}`
  ]),
  [`https://raw.githubusercontent.com/sehugg/8bitworkshop/${engine}/LICENSE`, 'vendor/8bitworkshop/LICENSE'],
  ...['greymecha.png'].map(name => [
    `https://raw.githubusercontent.com/NUSGreyhats/greybadge25/${badge}/hardware/artwork/${name}`,
    `public/simulator/art/${name}`
  ]),
  [`https://raw.githubusercontent.com/NUSGreyhats/greybadge25/${badge}/hardware/fpga_placement.svg`, 'public/simulator/art/fpga_placement.svg'],
  ['https://raw.githubusercontent.com/8bitworkshop/verilator/6c3efcd5d869ba772e4ed1365727e155fd9210da/LICENSE', 'public/simulator/VERILATOR-LICENSE'],
  ['https://raw.githubusercontent.com/sehugg/8bitworkshop-compilers/b5c38a4ca090434e1ee2304e8b2b0dee0ffa9c2f/oldemsrc/verilator/verilator.txt', 'vendor/verilator-build.txt'],
  ['https://raw.githubusercontent.com/sehugg/8bitworkshop-compilers/b5c38a4ca090434e1ee2304e8b2b0dee0ffa9c2f/oldemsrc/verilator/Makefile.local', 'vendor/verilator-Makefile.local']
];

const manifest = await Promise.all(sources.map(async ([url, path]) => {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url}: ${response.status}`);
  const data = Buffer.from(await response.arrayBuffer());
  const target = new URL(path, root);
  await mkdir(new URL('.', target), { recursive: true });
  await writeFile(target, data);
  console.log(`${path}: ${data.length} bytes`);
  return { url, path, upstreamSha256: createHash('sha256').update(data).digest('hex') };
}));
// Emscripten's upstream module is UMD. Keep the original and provide an ESM
// copy for the module worker; there are no other changes to its generated code.
const { readFile } = await import('node:fs/promises');
const loader = await readFile(new URL('public/simulator/verilator_bin.js', root), 'utf8');
await writeFile(new URL('public/simulator/verilator.mjs', root), loader + '\nexport default verilator_bin;\n');
const runtimePath = new URL('vendor/8bitworkshop/hdl/hdlruntime.ts', root);
const runtime = await readFile(runtimePath, 'utf8');
const oldArrayLength = 'let arrlen = dt.high.cvalue - dt.low.cvalue + 1;\n            if (arrlen < 0) arrlen = -arrlen; // TODO?';
if (!runtime.includes(oldArrayLength)) throw new Error('Upstream array allocation changed; review the GreyMecha patch.');
await writeFile(runtimePath, runtime.replace(oldArrayLength, '// GreyMecha: both [0:N] and [N:0] contain N+1 elements.\n            let arrlen = Math.abs(dt.high.cvalue - dt.low.cvalue) + 1;'));
const parserPath = new URL('vendor/8bitworkshop/hdl/vxmlparser.ts', root);
const parser = await readFile(parserPath, 'utf8');
const oldReadmem = 'visit_readmem(node: XMLNode) { return this.__visit_func(node); }';
if (!parser.includes(oldReadmem)) throw new Error('Upstream readmem parser changed; review the GreyMecha patch.');
await writeFile(parserPath, parser.replace(oldReadmem, `visit_readmem(node: XMLNode) {
        // GreyMecha supplies the source-resolved hex/binary selection.
        const call = this.__visit_func(node) as HDLFuncCall;
        if (node.attrs['hex'] == null) throw new CompileError(this.cur_loc, \`Missing readmem format: \${JSON.stringify(node.attrs)}\`);
        const value = (cvalue: number) => ({ cvalue, dtype: {left:31, right:0, signed:false} } as HDLConstant);
        while (call.args.length < 4) call.args.push(value(call.args.length === 2 ? 0 : 0xffffffff));
        call.args.push(value(node.attrs['hex'] === 'true' || node.attrs['hex'] === '1' ? 1 : 0));
        return call;
    }`));
for (const entry of manifest) entry.sha256 = createHash('sha256').update(await readFile(new URL(entry.path,root))).digest('hex');
await writeFile(new URL('public/simulator/COPYING',root), await readFile(new URL('vendor/8bitworkshop/LICENSE',root)));
await writeFile(new URL('vendor/simulator-manifest.json', root), JSON.stringify({ engine, badge, compilerVersion:'Verilator 4.205 devel rev UNKNOWN.REV (mod)', files: manifest }, null, 2) + '\n');
