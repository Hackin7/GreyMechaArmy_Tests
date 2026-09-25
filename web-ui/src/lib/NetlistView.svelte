<script>
  import { onMount, onDestroy } from 'svelte';
  import DOMPurify from 'dompurify';
  import { normalizeForNetlistSvg } from './netlistUtils.js';

  export let json = null;
  export let runId = 0;
  export let label = 'Netlist';

  let worker;
  let ready = false;
  let parsed;
  let moduleNames = [];
  let selectedModule = '';
  let renderedSvg = '';
  let status = 'Waiting for synthesis…';
  let error = '';
  let zoom = 1;
  let viewport;
  let lastArtifactKey = '';
  let lastRenderKey = '';
  let requestSequence = 0;
  const cache = new Map();

  $: artifactKey = `${runId}:${label}:${json?.byteLength ?? 0}`;
  $: if (worker && json && artifactKey !== lastArtifactKey) loadArtifact(json, artifactKey);

  onMount(() => {
    worker = new Worker(new URL('./netlistWorker.js', import.meta.url));
    worker.addEventListener('message', onWorkerMessage);
    const assetBase = new URL(`${import.meta.env.BASE_URL}vendor/`, window.location.href).href;
    worker.postMessage({ type: 'INIT', assetBase });
  });

  onDestroy(() => {
    worker?.removeEventListener('message', onWorkerMessage);
    worker?.terminate();
  });

  function onWorkerMessage(event) {
    const message = event.data ?? {};
    if (message.type === 'READY') {
      ready = true;
      status = 'Choose a module to render.';
      renderSelected();
      return;
    }
    if (message.type === 'ERROR' && !ready) {
      error = message.error;
      status = '';
      return;
    }
    if (message.requestId !== requestSequence) return;
    if (message.type === 'RENDERED') {
      renderedSvg = DOMPurify.sanitize(message.svg, { USE_PROFILES: { svg: true } });
      cache.set(lastRenderKey, renderedSvg);
      status = '';
      error = '';
    } else if (message.type === 'RENDER_ERROR') {
      status = '';
      error = message.error;
    }
  }

  function loadArtifact(bytes, key) {
    lastArtifactKey = key;
    lastRenderKey = '';
    selectedModule = '';
    renderedSvg = '';
    error = '';
    zoom = 1;
    try {
      parsed = JSON.parse(new TextDecoder().decode(bytes));
      moduleNames = Object.keys(parsed.modules ?? {});
      if (moduleNames.length === 0) throw new Error('The Yosys JSON contains no modules.');
      const top = moduleNames.find((name) => {
        const value = parsed.modules[name].attributes?.top;
        return value !== undefined && value !== '0' && value !== 0;
      });
      selectedModule = top ?? moduleNames[0];
      status = ready ? 'Preparing schematic…' : 'Loading diagram renderer…';
      renderSelected();
    } catch (loadError) {
      parsed = null;
      moduleNames = [];
      status = '';
      error = `Could not read ${label}: ${loadError.message}`;
    }
  }

  function renderSelected() {
    if (!ready || !parsed || !selectedModule || !worker) return;
    const key = `${runId}:${label}:${selectedModule}`;
    lastRenderKey = key;
    if (cache.has(key)) {
      renderedSvg = cache.get(key);
      status = '';
      error = '';
      return;
    }
    const requestId = ++requestSequence;
    status = `Laying out ${selectedModule}…`;
    error = '';
    renderedSvg = '';
    worker.postMessage({
      type: 'RENDER',
      requestId,
      moduleName: selectedModule,
      json: new TextEncoder().encode(JSON.stringify(normalizeForNetlistSvg(parsed)))
    });
  }

  function changeModule(event) {
    selectedModule = event.currentTarget.value;
    renderSelected();
  }

  function zoomBy(amount) {
    zoom = Math.min(4, Math.max(0.2, zoom + amount));
  }

  function fitToView() {
    const svg = viewport?.querySelector('svg');
    if (!svg || !viewport) return;
    const width = Number(svg.getAttribute('width'));
    const height = Number(svg.getAttribute('height'));
    if (!width || !height) return;
    zoom = Math.min((viewport.clientWidth - 24) / width, (viewport.clientHeight - 24) / height, 1);
  }
</script>

<section class="netlist-view" aria-label={`${label} graphical view`}>
  <div class="toolbar">
    <label>
      Module
      <select value={selectedModule} on:change={changeModule} disabled={moduleNames.length < 2}>
        {#each moduleNames as moduleName}
          <option value={moduleName}>{moduleName}</option>
        {/each}
      </select>
    </label>
    <div class="zoom-controls" aria-label="Schematic zoom controls">
      <button on:click={() => zoomBy(-0.2)} aria-label="Zoom out">−</button>
      <span>{Math.round(zoom * 100)}%</span>
      <button on:click={() => zoomBy(0.2)} aria-label="Zoom in">+</button>
      <button on:click={fitToView}>Fit</button>
      <button on:click={() => (zoom = 1)}>Reset</button>
    </div>
  </div>

  {#if error}
    <div class="message error" role="alert">{error}</div>
  {:else if status}
    <div class="message">{status}</div>
  {/if}

  <div class="viewport" bind:this={viewport}>
    {#if renderedSvg}
      <div class="diagram" style={`transform: scale(${zoom});`}>
        {@html renderedSvg}
      </div>
    {/if}
  </div>
</section>

<style>
  .netlist-view { display: flex; flex-direction: column; height: 100%; min-height: 0; background: #f7f7f7; color: #252525; }
  .toolbar { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-height: 42px; padding: 6px 10px; background: #252526; color: #ddd; }
  label { display: flex; align-items: center; gap: 8px; font-size: 12px; }
  select { max-width: 260px; padding: 5px 8px; }
  .zoom-controls { display: flex; align-items: center; gap: 6px; }
  .zoom-controls button { padding: 5px 8px; background: #3b3b3b; color: #eee; border: 1px solid #555; border-radius: 3px; cursor: pointer; }
  .zoom-controls span { min-width: 44px; text-align: center; font: 12px monospace; }
  .message { padding: 10px 12px; color: #555; font: 12px monospace; background: #f1f1f1; }
  .error { color: #a12622; background: #fff0ef; }
  .viewport { flex: 1; min-height: 0; overflow: auto; padding: 12px; }
  .diagram { width: max-content; min-width: 100%; transform-origin: top left; }
  :global(.diagram svg) { display: block; max-width: none; background: white; box-shadow: 0 1px 5px #0002; }
</style>
