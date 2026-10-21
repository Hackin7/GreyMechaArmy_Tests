<script>
  import { WaveformCanvas, formatTime, recordAt } from './simulator/waveformView.js';
  import { formatTraceValue } from './simulator/trace.js';
  export let expanded = false;
  export let trace;
  export let catalog = [];
  export let selectedKeys = [];
  export let ready = false;
  export let outdated = false;
  export let onToggle = () => {};
  export let onSelection = () => {};
  export let onClear = () => {};
  let canvas, viewport, view, query = '', picker = false, radix = 16, height = 320, drag;
  let state = { t0: 0, span: 1e6, follow: true, time: -1, sequence: undefined };
  $: matches = catalog.filter(signal => `${signal.label} ${signal.key}`.toLowerCase().includes(query.toLowerCase()));
  $: cursor = recordAt(trace, state.time < 0 ? trace?.endPs ?? 0 : state.time, state.sequence);
  $: if (view) { view.setTrace(trace, radix); sync(); }
  function sync() {
    state = { t0: view.t0, span: view.span, follow: view.follow, time: view.tsel, sequence: view.selectedSequence };
  }
  function action(fn) { fn(); sync(); }
  function toggleSignal(key, checked) {
    onSelection(checked ? [...selectedKeys, key] : selectedKeys.filter(item => item !== key));
  }
  function point(event) {
    if (!view || !trace?.records.length) return;
    const x = event.clientX - canvas.getBoundingClientRect().left - view.labelWidth;
    if (x < 0) return;
    action(() => view.selectTime(view.t0 + x / view.zoom));
  }
  function pointerDown(event) { if (event.button !== 0) return; canvas.setPointerCapture(event.pointerId); point(event); }
  function wheel(event) {
    if (!view) return;
    if (event.ctrlKey || event.metaKey) { event.preventDefault(); action(() => view.setZoom(view.zoom * (event.deltaY < 0 ? 2 : .5))); }
    else if (event.shiftKey || Math.abs(event.deltaX) > Math.abs(event.deltaY)) {
      event.preventDefault(); action(() => view.pan((event.deltaX || event.deltaY) / Math.max(1, view.pageWidth)));
    }
  }
  function key(event) {
    if (['INPUT', 'SELECT', 'BUTTON'].includes(event.target.tagName)) return;
    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') { event.preventDefault(); action(() => view.selectRecord(event.key === 'ArrowLeft' ? -1 : 1)); }
    else if (event.key === '+' || event.key === '=') { event.preventDefault(); action(() => view.setZoom(view.zoom * 2)); }
    else if (event.key === '-') { event.preventDefault(); action(() => view.setZoom(view.zoom / 2)); }
  }
  function resizeStart(event) { event.currentTarget.setPointerCapture(event.pointerId); drag = { y: event.clientY, height }; }
  function resizeMove(event) { if (drag) height = Math.max(180, Math.min(720, drag.height + drag.y - event.clientY)); }
  function resizeKey(event) {
    if (!['ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault(); height = event.key === 'Home' ? 180 : event.key === 'End' ? 720 : Math.max(180, Math.min(720, height + (event.key === 'ArrowUp' ? 20 : -20)));
  }
  function attach(node) {
    canvas = node; const renderer = new WaveformCanvas(canvas, sync); view = renderer; view.radix = radix; view.setTrace(trace);
    const observer = new ResizeObserver(() => { if (view === renderer && node.isConnected) { renderer.resize(node.parentElement.clientWidth); sync(); } });
    queueMicrotask(() => { if (node.isConnected) observer.observe(node.parentElement); });
    return { destroy() { observer.disconnect(); if (view === renderer) view = undefined; } };
  }
</script>

<!-- svelte-ignore a11y-no-noninteractive-element-interactions -->
<section class="waveforms" aria-label="Simulation waveforms" on:keydown={key}>
  {#if expanded}
    <!-- svelte-ignore a11y-no-noninteractive-tabindex -->
    <div class="resize" role="separator" aria-label="Resize waveforms" aria-orientation="horizontal" aria-valuemin="180" aria-valuemax="720" aria-valuenow={height} tabindex="0"
      on:pointerdown={resizeStart} on:pointermove={resizeMove} on:pointerup={() => drag = undefined} on:pointercancel={() => drag = undefined} on:keydown={resizeKey}></div>
  {/if}
  <div class="heading">
    <button class="toggle" aria-expanded={expanded} on:click={() => onToggle(!expanded)}>{expanded ? '▾' : '▸'} Waveforms</button>
    <span>{outdated ? 'Outdated — compile again' : expanded && ready ? 'Recording while simulation runs' : 'Settled digital signals'}</span>
  </div>
  {#if expanded}
    <div class="body" style={`height:${height}px`} data-testid="waveform-body">
      <div class="controls">
        <button on:click={() => picker = !picker} aria-expanded={picker}>Signals ({selectedKeys.length}/32)</button>
        <button aria-label="Zoom waveform in" disabled={!trace?.records.length} on:click={() => action(() => view.setZoom(view.zoom * 2))}>+</button>
        <button aria-label="Zoom waveform out" disabled={!trace?.records.length} on:click={() => action(() => view.setZoom(view.zoom / 2))}>−</button>
        <button disabled={!trace?.records.length} on:click={() => action(() => view.fit())}>Fit History</button>
        <button class:active={state.follow} aria-pressed={state.follow} on:click={() => action(() => { view.follow = !view.follow; view.setTrace(trace); })}>Follow Latest</button>
        <button disabled={!ready} on:click={onClear}>Clear Capture</button>
        <select aria-label="Waveform number format" bind:value={radix}><option value={16}>Hex</option><option value={10}>Decimal</option></select>
      </div>
      {#if picker}
        <div class="picker">
          <input aria-label="Search waveform signals" placeholder="Search ports and internal signals…" bind:value={query} />
          <p>Choose up to 32 signals. Memories and compiler temporaries are omitted; optimized-away signals are unavailable.</p>
          <div class="signals">
            {#each matches as signal (signal.key)}
              <label title={signal.key}><input type="checkbox" checked={selectedKeys.includes(signal.key)} disabled={!ready || (!selectedKeys.includes(signal.key) && selectedKeys.length >= 32)}
                on:change={event => toggleSignal(signal.key, event.currentTarget.checked)} />{signal.label} <span>[{signal.width} bits]</span></label>
            {/each}
            {#if !matches.length}<p>{catalog.length ? 'No matching signals.' : 'Compile a design to discover its signals.'}</p>{/if}
          </div>
        </div>
      {/if}
      <div class="viewport" bind:this={viewport}>
        <!-- svelte-ignore a11y-no-noninteractive-tabindex a11y-no-noninteractive-element-interactions -->
        <canvas use:attach tabindex="0" aria-label="Digital waveform traces. Left and right select transitions; plus and minus zoom." data-testid="waveform-canvas"
          on:pointerdown={pointerDown} on:pointermove={event => { if (event.buttons === 1) point(event); }} on:wheel={wheel}></canvas>
        {#if !trace?.records.length || !selectedKeys.length}<p class="empty">{outdated ? 'Source changed. Compile again to capture this design.' : ready ? 'Select signals to inspect their values.' : 'Compile & Run a design to capture waveforms.'}</p>{/if}
      </div>
      <div class="navigation">
        <button aria-label="Pan waveforms left" on:click={() => action(() => view.pan(-.5))}>←</button>
        <input type="range" aria-label="Waveform horizontal position" min={trace?.records[0]?.timePs ?? 0} max={Math.max(trace?.records[0]?.timePs ?? 0, trace?.endPs ?? 0)} step="any" value={state.t0}
          on:input={event => action(() => { view.follow = false; view.setOrgTime(Number(event.currentTarget.value)); })} />
        <button aria-label="Pan waveforms right" on:click={() => action(() => view.pan(.5))}>→</button>
        <button aria-label="Previous waveform transition" on:click={() => action(() => view.selectRecord(-1))}>‹</button>
        <button aria-label="Next waveform transition" on:click={() => action(() => view.selectRecord(1))}>›</button>
      </div>
      <div class="readout" aria-live="off" data-testid="waveform-cursor">
        <span>Cursor: {formatTime(state.time < 0 ? trace?.endPs ?? 0 : state.time)}{cursor ? ` · event ${cursor.sequence}` : ''}</span>
        {#each trace?.signals ?? [] as signal, i}<span title={signal.key} data-testid="waveform-value">{signal.label}: {formatTraceValue(cursor?.values[i], signal, radix)}</span>{/each}
      </div>
      <p class="note" data-testid="waveform-history">{trace?.records.length ?? 0}/8192 records{trace?.dropped ? ` · ${trace.dropped} earlier records discarded` : ''}. Settled, two-state values; no propagation delays, glitches, or metastability.</p>
    </div>
  {/if}
</section>

<style>
  .waveforms{flex-shrink:0;border-top:1px solid #333;background:#1e1e1e;min-width:0;color:#d4d4d4}
  .heading{display:flex;align-items:center;gap:10px;padding:5px 10px;background:#252526}.heading span{font-size:11px;color:#858585}
  button,input,select{font:inherit;font-size:12px;color:#d4d4d4;background:#333;border:1px solid #555;border-radius:4px;padding:5px 8px}
  button{cursor:pointer;font-size:12px;white-space:nowrap}button:hover:not(:disabled){background:#454545}button:disabled{opacity:.45;cursor:not-allowed}
  button:focus-visible,input:focus-visible,select:focus-visible,canvas:focus-visible,.resize:focus-visible{outline:2px solid #4fc1ff;outline-offset:-2px}
  .toggle{border:0;background:transparent;font-weight:600}.active{border-color:#007acc;color:#9cdcfe}
  .body{display:flex;flex-direction:column;min-height:180px;overflow:hidden}.controls{display:flex;align-items:center;flex-wrap:wrap;gap:5px;padding:7px 10px;border-bottom:1px solid #333}
  .resize{height:7px;cursor:row-resize;touch-action:none;background:#252526;position:relative}.resize::after{content:'';position:absolute;left:calc(50% - 18px);top:2px;width:36px;height:2px;background:#666}
  .picker{flex-shrink:0;padding:8px 10px;border-bottom:1px solid #333}.picker>input{width:100%;box-sizing:border-box;background:#1e1e1e}.picker p{margin:5px 0;font-size:11px;color:#858585}
  .signals{max-height:120px;overflow:auto}.signals label{display:flex;gap:6px;align-items:center;font:11px Consolas,monospace;padding:3px 0;overflow-wrap:anywhere}.signals span{color:#858585;white-space:nowrap}.signals input{margin:0}
  .viewport{flex:1;min-height:65px;overflow:auto;position:relative}canvas{display:block;width:100%;touch-action:none}.empty{position:absolute;top:8px;left:12px;right:12px;color:#858585;font-size:12px;pointer-events:none}
  .navigation{display:flex;align-items:center;gap:4px;padding:3px 10px}.navigation input{flex:1;min-width:40px;padding:0;accent-color:#007acc}
  .readout{display:flex;flex-wrap:wrap;gap:5px 14px;padding:3px 10px;max-height:55px;overflow:auto;font:11px Consolas,monospace;color:#9cdcfe}
  .note{flex-shrink:0;margin:4px 10px 7px;font-size:10px;color:#858585}
  @media(max-width:500px){.heading span{display:none}.controls{gap:4px;padding:6px}.controls button{padding:5px 6px}}
</style>
