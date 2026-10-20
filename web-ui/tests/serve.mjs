import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
const root = path.resolve('dist'), prefix = '/GreyMechaArmy_Tests/';
const types = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html', '.svg': 'image/svg+xml', '.png': 'image/png', '.css': 'text/css' };
createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://127.0.0.1');
    if (!url.pathname.startsWith(prefix)) { response.writeHead(404).end(); return; }
    const name = path.resolve(root, decodeURIComponent(url.pathname.slice(prefix.length) || 'index.html'));
    if (!name.startsWith(root + path.sep)) { response.writeHead(403).end(); return; }
    const data = await readFile(name);
    response.writeHead(200, { 'Content-Type': types[path.extname(name)] ?? 'application/octet-stream', 'Cache-Control': 'no-store' });
    response.end(data);
  } catch { response.writeHead(404).end(); }
}).listen(4188, '127.0.0.1', () => console.log(`Simulator test preview: http://127.0.0.1:4188${prefix}`));
