<script>
  import { onMount, onDestroy } from 'svelte';
  export let files = {};
  export let sourceRevision = 0;
  export let isSynthesizing = false;
  export let active = false;

  const assetBase = `${import.meta.env.BASE_URL}simulator/`;
  let mode = 'pixel', externalHz = 10000000, status = 'idle', message = '';
  let worker, simulationId = 0, compiledRevision = -1, watchdog;
  let info, frame, canvas, panel, zoom = 1, buttons = 127, pmodResetn = 1;
  let logs = '', error = '', previousActive = false;
  let boardViewport, fitted = true;
  const heldKeys = new Set(), heldPointers = new Set();
  $: ready = Boolean(worker && info && compiledRevision === sourceRevision && ['running', 'paused'].includes(status));
  $: if (worker && compiledRevision !== sourceRevision) stop('outdated');
  $: if (isSynthesizing || (!active && previousActive)) {
    if (isSynthesizing && status === 'compiling') stop(); else pause();
    releaseAll();
  }
  $: previousActive = active;
  $: if (canvas && frame?.pixels) draw(frame.pixels);

  function draw(pixels) {
    const context = canvas.getContext('2d');
    context.putImageData(new ImageData(new Uint8ClampedArray(pixels), 240, 240), 0, 0);
  }
  function command(type, data = {}) {
    worker?.postMessage({ type, simulationId, sourceRevision: compiledRevision, ...data });
  }
  function start() {
    if (isSynthesizing) return;
    stop(); error = ''; logs = ''; info = undefined; frame = undefined;
    canvas?.getContext('2d').clearRect(0, 0, 240, 240);
    compiledRevision = sourceRevision; simulationId++;
    status = 'compiling'; message = 'Loading browser simulation tools…';
    const currentId = simulationId;
    worker = new Worker(new URL('./simulator/simulatorWorker.js', import.meta.url), { type: 'module' });
    watchdog = setTimeout(() => { error = 'Simulation compilation timed out. Stop, simplify the design, or retry.'; stop('error'); }, 120000);
    worker.onerror = event => { error = event.message || 'Simulation worker failed.'; stop('error'); };
    worker.onmessage = ({ data }) => {
      if (currentId !== simulationId || data.simulationId !== simulationId || data.sourceRevision !== sourceRevision || !worker) return;
      switch (data.type) {
        case 'PROGRESS': message = data.message; break;
        case 'LOG': logs = (logs + data.message + '\n').slice(-12000); break;
        case 'READY':
          clearTimeout(watchdog); info = data.info; status = 'paused'; message = 'Compiled.';
          command('INPUT', { buttons, pmodResetn });
          if (active && !isSynthesizing) command('RUN');
          break;
        case 'RUNNING': status = 'running'; break;
        case 'PAUSED': status = 'paused'; break;
        case 'FRAME': frame = { ...data, pixels: data.pixels ?? frame?.pixels }; break;
        case 'ERROR': error = data.error; stop('error'); break;
      }
    };
    worker.postMessage({ type: 'COMPILE', simulationId, sourceRevision: compiledRevision, files: { ...files }, mode, externalHz: Number(externalHz), baseUrl: new URL(import.meta.env.BASE_URL, window.location.href).href });
  }
  export function pause() {
    if (status === 'running') { command('PAUSE'); status = 'paused'; }
  }
  function stop(nextStatus = 'stopped') {
    clearTimeout(watchdog); worker?.terminate(); worker = undefined; buttons = 127; pmodResetn = 1;
    heldKeys.clear(); heldPointers.clear();
    status = nextStatus;
  }
  function changeMode() { if (worker || info) start(); }
  function input(index, pressed, source = 'pointer') {
    if (info && index >= info.btnWidth) return;
    const held = source === 'keyboard' ? heldKeys : heldPointers;
    if (pressed) held.add(index); else held.delete(index);
    buttons = 127;
    for (const button of [...heldKeys, ...heldPointers]) buttons &= ~(1 << button);
    command('INPUT', { buttons, pmodResetn });
  }
  function releaseAll() {
    heldKeys.clear(); heldPointers.clear();
    buttons = 127;
    command('INPUT', { buttons, pmodResetn });
  }
  function pointerDown(event, index) {
    event.preventDefault(); panel.focus({ preventScroll: true });
    event.currentTarget.setPointerCapture(event.pointerId); input(index, true);
  }
  function key(event, pressed) {
    if (pressed && ['INPUT', 'SELECT', 'TEXTAREA', 'BUTTON'].includes(event.target.tagName)) return;
    const index = Number(event.key) - 1;
    if (index >= 0 && index <= 6 && /^\d$/.test(event.key)) { event.preventDefault(); input(index, pressed, 'keyboard'); }
  }
  function blur(event) { if (!panel.contains(event.relatedTarget)) releaseAll(); }
  function togglePmod() { pmodResetn = pmodResetn ? 0 : 1; command('INPUT', { buttons, pmodResetn }); }
  function frequency(value) { return value >= 1000000 ? `${(value / 1000000).toFixed(2)} MHz` : `${value.toFixed(1)} Hz`; }
  function fit() { fitted = true; if (boardViewport?.clientWidth) zoom = Math.min(1, Math.max(.3, (boardViewport.clientWidth - 16) / 650)); }
  onMount(() => { const observer = new ResizeObserver(() => { if (fitted) fit(); }); observer.observe(boardViewport); return () => observer.disconnect(); });
  onDestroy(() => stop());
</script>

<svelte:window on:blur={releaseAll} />
<!-- svelte-ignore a11y-no-noninteractive-tabindex -->
<!-- svelte-ignore a11y-no-noninteractive-element-interactions -->
<section class="simulator" bind:this={panel} tabindex="0" aria-label="GreyMecha simulator keyboard controls" on:keydown={event => key(event, true)} on:keyup={event => key(event, false)} on:focusout={blur}>
  <div class="toolbar">
    <div class="title"><span class="eyebrow">VIRTUAL BADGE</span><h2>GreyMecha / Army</h2></div>
    <label>OLED rendering
      <select aria-label="OLED rendering" bind:value={mode} on:change={changeMode} disabled={isSynthesizing || status === 'compiling'}>
        <option value="pixel">Pixel Preview</option><option value="spi">SPI Simulation</option>
      </select>
    </label>
    <button on:click={start} disabled={isSynthesizing || status === 'compiling'}>Compile &amp; Run</button>
    <button on:click={() => status === 'running' ? pause() : command('RUN')} disabled={!ready || isSynthesizing}>{status === 'running' ? 'Pause' : 'Resume'}</button>
    <button on:click={() => command('STEP')} disabled={!ready || status === 'running' || isSynthesizing}>Step Cycle</button>
    <button on:click={() => { command('RESTART'); releaseAll(); }} disabled={!ready || isSynthesizing}>Restart</button>
    <button on:click={() => stop()} disabled={!worker}>Stop</button>
    <span class="state" class:running={status === 'running'} data-testid="sim-status" role="status">{status}</span>
  </div>
  {#if error}<pre class="error" role="alert">{error}</pre>{/if}
  {#if status === 'compiling'}<p class="progress" role="status">{message}</p>{/if}
  {#if status === 'outdated'}<p class="notice">Source changed. Compile again to simulate the current design.</p>{/if}
  <div class="workspace">
    <div class="board-scroll" bind:this={boardViewport}>
      <div class="board" style={`width:${650 * zoom}px;height:${440 * zoom}px`}>
        <div class="board-face" style={`transform:scale(${zoom})`}>
          <img class="badge-art" src={`${assetBase}art/greymecha.png`} alt="Official GreyMecha badge artwork" />
          <div class="screen-shell">
            <canvas bind:this={canvas} width="240" height="240" aria-label="OLED display" data-testid="oled-display"></canvas>
            <span>240 × 240 · RGB565</span>
          </div>
          <div class="led-strip" aria-label="Badge LEDs">
            {#each Array(8) as _, index}
              <div class="led-unit"><span class:lit={Boolean((frame?.led ?? 0) & (1 << index))} class="led" data-testid={`led-${index}`} data-value={((frame?.led ?? 0) >> index) & 1}></span><small>LED {index}</small></div>
            {/each}
          </div>
          <div class="button-bank" aria-label="Badge buttons">
            {#each Array(7) as _, index}
              <button class:pressed={!(buttons & (1 << index))} disabled={Boolean(info && index >= info.btnWidth)} aria-label={`BTN ${index}`} aria-pressed={!(buttons & (1 << index))}
                on:pointerdown={event => pointerDown(event, index)} on:pointerup={() => input(index, false)} on:pointercancel={() => input(index, false)} on:lostpointercapture={() => input(index, false)}
                on:keydown={event => { if ([' ', 'Enter'].includes(event.key)) { event.preventDefault(); input(index, true, 'keyboard'); } }}
                on:keyup={event => { if ([' ', 'Enter'].includes(event.key)) { event.preventDefault(); input(index, false, 'keyboard'); } }}>
                <span>{index}</span><small>BTN {index}</small>
              </button>
            {/each}
          </div>
          <div class="board-brand"><strong>GREYMECHA / ARMY</strong><span>FPGA · interactive digital simulation</span></div>
        </div>
      </div>
    </div>
    <aside class="details">
      <h3>Simulation</h3>
      <dl>
        <div><dt>Cycles</dt><dd data-testid="sim-cycles">{(frame?.cycles ?? 0).toLocaleString()}</dd></div>
        <div><dt>Simulated time</dt><dd>{((frame?.seconds ?? 0) * 1000).toFixed(3)} ms</dd></div>
        <div><dt>Speed</dt><dd>{((frame?.speed ?? 0) / 1000000).toFixed(2)} Mcycles/s</dd></div>
        <div><dt>Frames</dt><dd data-testid="sim-frames">{frame?.frames ?? 0}</dd></div>
        <div><dt>Pixel writes</dt><dd data-testid="sim-writes">{frame?.writes ?? 0}</dd></div>
        <div><dt>Buttons</dt><dd data-testid="sim-buttons">{buttons.toString(2).padStart(7, '0')}</dd></div>
      </dl>
      {#if info}<p class="clock-info">{info.pllHz ? `PLL ${frequency(info.pllHz)} · ` : ''}{info.oscHz ? `OSCG ${frequency(info.oscHz)} (nominal)` : `External ${frequency(info.externalHz)}`}</p>{/if}
      <label>External clock (Hz)<input aria-label="External clock frequency" type="number" min="1" max="200000000" bind:value={externalHz} on:change={changeMode} disabled={status === 'compiling' || isSynthesizing} /></label>
      <button class="pmod" aria-pressed={!pmodResetn} on:click={togglePmod} disabled={!ready || !info?.hasPmod}>PMOD J1[0]: {pmodResetn ? 'high' : 'reset low'}</button>
      <div class="zoom"><button aria-label="Zoom out board" on:click={() => { fitted = false; zoom = Math.max(.3, zoom - .1); }}>−</button><button on:click={fit}>Fit / Reset zoom</button><button aria-label="Zoom in board" on:click={() => { fitted = false; zoom = Math.min(2, zoom + .1); }}>+</button></div>
      <p>Focus the board and hold keys <strong>1–7</strong>, or hold the buttons. Pressed inputs are low.</p>
      <p class="mode-note">{mode === 'pixel' ? 'Pixel Preview: four clock cycles per pixel. SPI is bypassed; driver status LEDs are virtual.' : 'SPI Simulation: the original driver and display protocol run. Initialization may take longer.'}</p>
      {#if info && !info.hasDisplay}<p>{info.hasOledPins ? 'No compatible pixel wrapper detected. Choose SPI Simulation to use the OLED pins.' : 'No OLED interface detected. Buttons and LEDs remain available.'}</p>{/if}
      <p class="limits">Functional, two-state simulation. No electrical timing, metastability, or peripheral emulation.</p>
      <details><summary>Compiler diagnostics</summary><pre>{logs || 'No compiler diagnostics.'}</pre></details>
      <a href="https://github.com/NUSGreyhats/greybadge25" target="_blank" rel="noreferrer">Official artwork · GreyCTF 2025</a>
      <p><a href={`${assetBase}art/fpga_placement.svg`} target="_blank" rel="noreferrer">Official FPGA pin placement reference</a></p>
      <p><a href={`${assetBase}NOTICE.md`} target="_blank" rel="noreferrer">Simulator source and licenses</a></p>
    </aside>
  </div>
</section>

<style>
  .simulator{height:100%;overflow:auto;color:#dce6f2;background:#10161f;outline:none}.simulator:focus-visible{box-shadow:inset 0 0 0 2px #7ccabd}.toolbar{display:flex;gap:8px;align-items:center;flex-wrap:wrap;padding:14px 18px;border-bottom:1px solid #2e3b4a;background:#18212c}.title{margin-right:12px}h2{margin:3px 0 0;font-size:17px;color:#f0f4f8}.eyebrow{font-size:10px;letter-spacing:2px;color:#91cdbc}.toolbar label{font-size:11px;display:grid;gap:4px}button,select,input{border:1px solid #465568;border-radius:5px;background:#263344;color:#e8edf3;padding:7px 10px;font:inherit;font-size:12px}button{cursor:pointer}button:hover:not(:disabled){background:#364a5f}button:disabled{opacity:.4;cursor:default}select,input{max-width:180px}.state{font:12px monospace;color:#bdc7d4;margin-left:auto}.state.running{color:#8ee4aa}.workspace{display:grid;grid-template-columns:minmax(300px,1fr) 245px;gap:16px;padding:16px}.board-scroll{overflow:auto;min-height:300px;border:1px solid #293746;border-radius:12px;background:radial-gradient(ellipse at 45% 45%,#2e3f4a,#111923)}.board{position:relative;margin:auto}.board-face{width:650px;height:440px;transform-origin:top left;position:relative;overflow:hidden}.badge-art{position:absolute;width:370px;height:350px;object-fit:contain;left:5px;top:10px;opacity:.95;pointer-events:none}.screen-shell{position:absolute;left:375px;top:25px;text-align:center}.screen-shell canvas{display:block;width:240px;height:240px;border-radius:50%;background:#000;border:7px solid #080c11;box-shadow:0 0 0 2px #71816a,0 9px 35px #0009;image-rendering:pixelated}.screen-shell span{display:block;font:10px monospace;color:#9caebe;margin-top:9px}.led-strip{position:absolute;left:35px;top:306px;display:flex;gap:14px}.led-unit{display:grid;gap:8px;text-align:center}.led{display:block;width:17px;height:17px;margin:auto;border:2px solid #42634b;border-radius:5px;background:#182b20}.led.lit{background:#a5ff87;box-shadow:0 0 13px #8eff55b0;border-color:#d5ffb9}.led-unit small{font:10px monospace;color:#a4b4be}.button-bank{position:absolute;left:31px;top:354px;display:flex;gap:12px}.button-bank button{display:grid;gap:3px;width:52px;height:52px;padding:6px;border-radius:9px;background:#111922;border:2px solid #4b5969;box-shadow:0 3px 0 #060b10}.button-bank button span{font-weight:700;font-size:16px}.button-bank button small{font:8px monospace;color:#b6c3d3}.button-bank button.pressed{background:#9cdec1;border-color:#c1f8d2;color:#15241d;transform:translateY(2px);box-shadow:none}.board-brand{position:absolute;left:450px;top:365px;display:grid;gap:5px;max-width:170px}.board-brand strong{font:11px monospace;letter-spacing:1px;color:#dfedbe}.board-brand span{font-size:10px;color:#879cac}.details{font-size:12px;line-height:1.5}.details h3{font-size:13px;margin:0 0 12px;color:#b7c9d9}.details dl{margin:0 0 12px}.details dl div{display:flex;justify-content:space-between;border-bottom:1px solid #293442;padding:4px 0}.details dt{color:#a0adbb}.details dd{margin:0;font-family:monospace}.details label{display:grid;gap:4px}.pmod{margin-top:10px;width:100%}.zoom{display:flex;gap:4px;margin-top:12px}.clock-info,.mode-note{color:#bddec6}.limits{color:#929fae}.details pre,.error{white-space:pre-wrap;overflow-wrap:anywhere;font:11px monospace;max-height:180px;overflow:auto}.details a{color:#91cdbc;font-size:10px}.error{margin:12px 18px;padding:12px;background:#432525;color:#ffcdcd;border-radius:5px}.notice,.progress{margin:12px 18px;color:#dbe9a8;font-size:12px}@media(max-width:900px){.workspace{grid-template-columns:1fr}.details{max-width:650px}.board-scroll{min-height:440px}}
  .badge-art{width:550px;height:550px;left:-140px;top:-100px;object-fit:contain}
  .board-brand{left:490px;max-width:130px}
  .button-bank button{touch-action:none}
</style>
