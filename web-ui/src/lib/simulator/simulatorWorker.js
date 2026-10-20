import { prepareSimulation, compileModel } from './engine.js';

let sim, id = 0, revision = 0, timer, running = false, lastFrame = 0, wallStart = 0, startCycles = 0;
let wasmModule, createCompiler;
const send = (type, data = {}, transfer = []) => self.postMessage({ type, simulationId: id, sourceRevision: revision, ...data }, transfer);

function snapshot(withPixels = true) {
  if (!sim) return;
  const snap = sim.snapshot(withPixels);
  const elapsed = (performance.now() - wallStart) / 1000;
  send('FRAME', { ...snap, speed: elapsed > 0 ? (snap.cycles - startCycles) / elapsed : 0 }, snap.pixels ? [snap.pixels.buffer] : []);
  if (withPixels) lastFrame = performance.now();
}
function pause() { running = false; clearTimeout(timer); timer = undefined; }
function fail(error) { pause(); send('ERROR', { error: error.message ?? String(error) }); }
function batch() {
  if (!running || !sim) return;
  try {
    const end = performance.now() + 8;
    do { sim.advance(32); } while (running && performance.now() < end);
    if (performance.now() - lastFrame >= 34) snapshot();
    if (sim.runtime.isFinished() || sim.runtime.isStopped()) { pause(); send('PAUSED'); snapshot(); }
    else timer = setTimeout(batch, 0);
  } catch (error) { fail(error); }
}
self.onmessage = async ({ data }) => {
  try {
    if (data.type === 'COMPILE') {
      pause(); sim = null; id = data.simulationId; revision = data.sourceRevision;
      const request = id;
      send('PROGRESS', { message: 'Elaborating source and checking board ports…' });
      const prepared = await prepareSimulation(data.files, data.mode, data.externalHz);
      if (request !== id) return;
      send('PROGRESS', { message: 'Compiling the interactive simulation model…' });
      if (!createCompiler) {
        const base = new URL('simulator/', data.baseUrl);
        const loader = await import(/* @vite-ignore */ new URL('verilator.mjs', base).href);
        createCompiler = loader.default;
        const response = await fetch(new URL('verilator_bin.wasm', base));
        if (!response.ok) throw new Error(`Simulation compiler download failed (${response.status}).`);
        wasmModule = await WebAssembly.compile(await response.arrayBuffer());
      }
      if (request !== id) return;
      sim = compileModel(prepared, createCompiler, wasmModule, message => send('LOG', { message }));
      wallStart = performance.now(); startCycles = 0;
      const { files, ...info } = prepared;
      send('READY', { info }); snapshot();
      return;
    }
    if (data.simulationId !== id || data.sourceRevision !== revision || !sim) return;
    switch (data.type) {
      case 'RUN':
        if (running) return;
        running = true; wallStart = performance.now(); startCycles = sim.cycles;
        send('RUNNING'); batch(); break;
      case 'PAUSE': pause(); snapshot(); send('PAUSED'); break;
      case 'STEP': pause(); sim.advance(1); snapshot(); send('PAUSED'); break;
      case 'RESTART': pause(); sim.restart(); wallStart = performance.now(); startCycles = 0; snapshot(); send('PAUSED'); break;
      case 'INPUT': sim.setInputs(data.buttons, data.pmodResetn); snapshot(false); break;
    }
  } catch (error) { fail(error); }
};
