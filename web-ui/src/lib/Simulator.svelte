<script>
  import { onMount, onDestroy } from 'svelte';
  import boardLayout from './simulator/boardLayout.json';
  export let files = {};
  export let sourceRevision = 0;
  export let isSynthesizing = false;
  export let active = false;

  const assetBase = `${import.meta.env.BASE_URL}simulator/`;
  const pixelsPerMm = 6;
  const boardWidth = boardLayout.outline.width * pixelsPerMm;
  const boardHeight = boardLayout.outline.height * pixelsPerMm;
  const componentStyle = part => `left:${part.x * pixelsPerMm}px;top:${part.y * pixelsPerMm}px;--angle:${part.rotation}deg;--part-width:${part.width * pixelsPerMm}px;--part-height:${part.height * pixelsPerMm}px;`;
  const display = boardLayout.display;
  let mode = 'pixel', externalHz = 10000000, status = 'idle', message = '';
  let worker, simulationId = 0, compiledRevision = -1, watchdog;
  let info, frame, canvas, panel, zoom = 1, buttons = 127, pmodResetn = 1;
  let logs = '', error = '', previousActive = false;
  let boardViewport, fitted = true;
  const heldKeys = new Set(), heldPointers = new Set();
  $: ready = Boolean(worker && info && compiledRevision === sourceRevision && ['running', 'paused'].includes(status));
  $: if (worker && compiledRevision !== sourceRevision) stop('outdated');
  $: syncVisibility(active, isSynthesizing);
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
        case 'RUNNING':
          if (!active || isSynthesizing) pause(); else status = 'running';
          break;
        case 'PAUSED': status = 'paused'; break;
        case 'FRAME': frame = { ...data, pixels: data.pixels ?? frame?.pixels }; break;
        case 'ERROR': error = data.error; stop('error'); break;
      }
    };
    worker.postMessage({ type: 'COMPILE', simulationId, sourceRevision: compiledRevision, files: { ...files }, mode, externalHz: Number(externalHz), baseUrl: new URL(import.meta.env.BASE_URL, window.location.href).href });
  }
  export function pause() {
    // Queue PAUSE even if RUNNING has not arrived yet from a preceding RUN.
    if (worker && info && status !== 'compiling') { command('PAUSE'); status = 'paused'; }
  }
  function syncVisibility(visible, building) {
    if (building || (!visible && previousActive)) {
      if (building && status === 'compiling') stop(); else pause();
      releaseAll();
    }
    previousActive = visible;
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
  function fit() {
    fitted = true;
    if (boardViewport?.clientWidth && boardViewport.clientHeight)
      zoom = Math.min(1.5, Math.max(.25, Math.min((boardViewport.clientWidth - 36) / boardWidth, (boardViewport.clientHeight - 36) / boardHeight)));
  }
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
      <div class="board" data-testid="pcb-board" style={`width:${boardWidth * zoom}px;height:${boardHeight * zoom}px`}>
        <div class="board-face" data-testid="pcb-face" style={`width:${boardWidth}px;height:${boardHeight}px;transform:scale(${zoom})`}>
          <img class="pcb-image" src={`${assetBase}board/front.svg`} alt="Greybadge26 front PCB outline, silkscreen artwork, and exposed pads exported from KiCad" draggable="false" />
          <div class="screen-shell" data-testid="pcb-screen" style={`left:${display.x * pixelsPerMm}px;top:${display.y * pixelsPerMm}px;width:${display.diameter * pixelsPerMm}px;height:${display.diameter * pixelsPerMm}px;--display-angle:${display.rotation}deg;--active-size:${display.activeDiameter * pixelsPerMm}px`}>
            <canvas bind:this={canvas} width="240" height="240" aria-label="OLED display" data-testid="oled-display"></canvas>
          </div>
          {#each boardLayout.leds as part}
            <span class:lit={Boolean((frame?.led ?? 0) & (1 << part.index))} class="pcb-led" role="img"
              aria-label={`LED ${part.index} (${part.reference}): ${((frame?.led ?? 0) >> part.index) & 1 ? 'on' : 'off'}`}
              title={`LED ${part.index} · ${part.reference} · ${part.net}`} data-testid={`led-${part.index}`} data-value={((frame?.led ?? 0) >> part.index) & 1}
              data-reference={part.reference} data-net={part.net} style={componentStyle(part)}></span>
          {/each}
          {#each boardLayout.buttons as part}
            <button class="pcb-button" class:pressed={!(buttons & (1 << part.index))} disabled={Boolean(info && part.index >= info.btnWidth)} aria-label={`BTN ${part.index}`} aria-pressed={!(buttons & (1 << part.index))}
              title={`BTN ${part.index} · ${part.reference} · ${part.net} · Key ${part.index + 1}`} data-reference={part.reference} data-net={part.net}
              style={`${componentStyle(part)}--body-size:${Math.min(part.width, part.height) * pixelsPerMm}px`}
              on:pointerdown={event => pointerDown(event, part.index)} on:pointerup={() => input(part.index, false)} on:pointercancel={() => input(part.index, false)} on:lostpointercapture={() => input(part.index, false)}
              on:keydown={event => { if ([' ', 'Enter'].includes(event.key)) { event.preventDefault(); input(part.index, true, 'keyboard'); } }}
              on:keyup={event => { if ([' ', 'Enter'].includes(event.key)) { event.preventDefault(); input(part.index, false, 'keyboard'); } }}>
              <span class="switch-body"><span class="switch-cap"></span></span>
            </button>
          {/each}
        </div>
      </div>
    </div>
    <aside class="details">
      <h3>Simulation</h3>
      <p class="board-caption">Greybadge26 · assembled front<br />240 × 240 RGB565 display</p>
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
      <details class="pin-legend"><summary>Board controls and pin mapping</summary>
        <ul>{#each boardLayout.buttons as part}<li>Key {part.index + 1}: btn[{part.index}] · {part.reference} · {part.net}</li>{/each}</ul>
        <ul>{#each boardLayout.leds as part}<li>led[{part.index}] · {part.reference} · {part.net}: {((frame?.led ?? 0) >> part.index) & 1}</li>{/each}</ul>
      </details>
      <p><a href={`${assetBase}board/front.svg`} target="_blank" rel="noreferrer">KiCad front PCB export · art by Shuqing</a></p>
      <p><a href={`${assetBase}NOTICE.md`} target="_blank" rel="noreferrer">Simulator source and licenses</a></p>
    </aside>
  </div>
</section>

<style>
  .simulator{height:100%;overflow:auto;display:flex;flex-direction:column;container-type:inline-size;color:#dce6f2;background:#10161f;outline:none}
  .simulator:focus-visible{box-shadow:inset 0 0 0 2px #7ccabd}
  .toolbar{display:flex;flex-shrink:0;gap:8px;align-items:center;flex-wrap:wrap;padding:14px 18px;border-bottom:1px solid #2e3b4a;background:#18212c}
  .title{margin-right:12px}h2{margin:3px 0 0;font-size:17px;color:#f0f4f8}
  .eyebrow{font-size:10px;letter-spacing:2px;color:#91cdbc}
  .toolbar label{font-size:11px;display:grid;gap:4px}
  button,select,input{border:1px solid #465568;border-radius:5px;background:#263344;color:#e8edf3;padding:7px 10px;font:inherit;font-size:12px}
  button{cursor:pointer}button:hover:not(:disabled){background:#364a5f}button:disabled{opacity:.4;cursor:default}
  button:focus-visible,select:focus-visible,input:focus-visible{outline:2px solid #9ce1ed;outline-offset:3px}
  select,input{max-width:180px}.state{font:12px monospace;color:#bdc7d4;margin-left:auto}.state.running{color:#8ee4aa}
  .workspace{display:grid;flex:1;min-height:0;grid-template-columns:minmax(0,1fr) 245px;grid-template-rows:minmax(0,1fr);gap:16px;padding:16px;overflow:auto}
  .board-scroll{height:100%;min-height:300px;overflow:auto;padding:16px;box-sizing:border-box;border:1px solid #293746;border-radius:12px;background:radial-gradient(ellipse at 50% 45%,#2b3740,#111923)}
  .board{position:relative;margin:auto;filter:drop-shadow(0 9px 11px #0008)}
  .board-face{transform-origin:top left;position:relative}
  .pcb-image{display:block;position:absolute;inset:0;width:100%;height:100%;user-select:none;pointer-events:none}
  .screen-shell{position:absolute;display:grid;place-items:center;transform:translate(-50%,-50%) rotate(var(--display-angle));border-radius:50%;background:linear-gradient(130deg,#84827d,#45494b 30%,#95958d 55%,#333a3d 80%);box-shadow:0 1px 3px #0009;pointer-events:none}
  .screen-shell canvas{display:block;width:var(--active-size);height:var(--active-size);border-radius:50%;background:#030405;image-rendering:pixelated}
  .pcb-led{position:absolute;display:block;width:var(--part-width);height:var(--part-height);transform:translate(-50%,-50%) rotate(var(--angle));border:1px solid #867d6b;border-radius:1px;box-sizing:border-box;background:linear-gradient(90deg,#b6b7b3 0 16%,#d8b8a0 17% 83%,#b6b7b3 84%);z-index:2}
  .pcb-led.lit{background:linear-gradient(90deg,#d9b8a9 0 16%,#fff2e6 24% 76%,#d9b8a9 84%);border-color:#ff9a89;box-shadow:0 0 4px 2px #ff3029,0 0 13px 5px #ff140b99,0 0 25px 10px #ff140b44}
  .pcb-button{position:absolute;width:var(--part-width);height:var(--part-height);transform:translate(-50%,-50%) rotate(var(--angle));padding:0;border:0;border-radius:4px;background:transparent;display:grid;place-items:center;touch-action:none;z-index:3}
  .pcb-button:hover:not(:disabled){background:transparent}
  .switch-body{display:grid;place-items:center;width:var(--body-size);height:var(--body-size);box-sizing:border-box;border:2px solid #90989a;border-radius:4px;background:linear-gradient(125deg,#e5e4db,#969b98 32%,#535d5e 56%,#d2d7d1);box-shadow:0 2px 2px #000b,inset 0 0 0 2px #bfc3b2}
  .switch-cap{display:block;width:55%;height:55%;border-radius:50%;box-sizing:border-box;background:radial-gradient(circle at 38% 32%,#e5d78f,#ab9860 57%,#7a744b 68%,#d7d2a9 75%,#6d7164 90%);box-shadow:0 1px 1px #363e39}
  .pcb-button.pressed .switch-cap{background:radial-gradient(circle,#817343,#a6995c 65%,#bdb893 78%,#4f574a);box-shadow:inset 0 2px 3px #2229;transform:scale(.93)}
  .pcb-button:hover .switch-body{border-color:#d9e2d3}
  .pcb-button:focus-visible{outline:2px solid #9ce1ed;outline-offset:4px}
  .details{font-size:12px;line-height:1.5;overflow:auto;min-height:0}.details h3{font-size:13px;margin:0 0 12px;color:#b7c9d9}
  .board-caption{color:#92a9b4;margin-top:-6px;font-size:11px}
  .details dl{margin:0 0 12px}.details dl div{display:flex;justify-content:space-between;border-bottom:1px solid #293442;padding:4px 0}
  .details dt{color:#a0adbb}.details dd{margin:0;font-family:monospace}.details label{display:grid;gap:4px}
  .pmod{margin-top:10px;width:100%}.zoom{display:flex;gap:4px;margin-top:12px}.clock-info,.mode-note{color:#bddec6}.limits{color:#929fae}
  .details pre,.error{white-space:pre-wrap;overflow-wrap:anywhere;font:11px monospace;max-height:180px;overflow:auto}
  .details a{color:#91cdbc;font-size:10px}.error{margin:12px 18px;padding:12px;background:#432525;color:#ffcdcd;border-radius:5px}
  .notice,.progress{margin:12px 18px;color:#dbe9a8;font-size:12px}.pin-legend{margin-top:12px}.pin-legend ul{padding-left:15px;font:11px/1.8 monospace}
  @container(max-width:700px){.workspace{grid-template-columns:1fr;grid-template-rows:auto auto;align-content:start}.details{max-width:650px;overflow:visible}.board-scroll{height:640px;max-height:70vh}}
</style>
