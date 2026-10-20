import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
const root=new URL('../',import.meta.url);
const manifest=JSON.parse(await readFile(new URL('vendor/simulator-manifest.json',root),'utf8'));
for(const entry of manifest.files) {
  const data=await readFile(new URL(entry.path,root));
  assert.equal(createHash('sha256').update(data).digest('hex'),entry.sha256,`${entry.path} differs from the pinned simulator asset`);
}
assert.equal(await readFile(new URL('public/simulator/verilator.mjs',root),'utf8'),(await readFile(new URL('public/simulator/verilator_bin.js',root),'utf8'))+'\nexport default verilator_bin;\n');
assert.equal(await readFile(new URL('public/simulator/COPYING',root),'utf8'),await readFile(new URL('vendor/8bitworkshop/LICENSE',root),'utf8'));
console.log('Pinned simulator source, compiler, artwork, patches and license hashes verified.');
