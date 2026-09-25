import { copyFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const webRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const publicVendor = join(webRoot, 'public', 'vendor');
const sources = [
  [join(webRoot, 'node_modules', 'elkjs', 'lib', 'elk-api.js'), 'elk-api.js'],
  [join(webRoot, 'node_modules', 'elkjs', 'lib', 'elk-worker.js'), 'elk-worker.js'],
  [join(webRoot, 'node_modules', 'netlistsvg', 'built', 'netlistsvg.bundle.js'), 'netlistsvg.bundle.js'],
  [join(webRoot, 'node_modules', 'netlistsvg', 'LICENSE'), 'NETLISTSVG-LICENSE.txt'],
  [join(webRoot, 'node_modules', 'elkjs', 'LICENSE'), 'ELK-LICENSE.txt']
];

await mkdir(publicVendor, { recursive: true });
for (const [source, name] of sources) {
  await copyFile(source, join(publicVendor, name));
}
