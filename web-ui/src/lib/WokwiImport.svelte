<script>
  import { convertWokwiDiagram } from './wokwiConverter.js';

  export let onUseDesign;
  export let onUseAndSynthesize;
  export let disabled = false;

  let filename = '';
  let preview = null;
  let fileError = '';
  let selectionId = 0;
  let diagramText = '';
  const diagramPlaceholder = '{\n  "version": 1,\n  "parts": [],\n  "connections": []\n}';

  function invalidatePreview() {
    selectionId += 1;
    filename = '';
    preview = null;
    fileError = '';
  }

  function previewPastedDiagram() {
    selectionId += 1;
    filename = '';
    preview = null;
    fileError = '';
    if (!diagramText.trim()) {
      fileError = 'Paste a diagram.json before previewing it.';
      return;
    }
    if (new Blob([diagramText]).size > 2_000_000) {
      fileError = 'The diagram is larger than the 2 MB import limit.';
      return;
    }
    preview = convertWokwiDiagram(diagramText);
  }

  async function chooseFile(event) {
    const currentSelection = ++selectionId;
    const file = event.currentTarget.files?.[0];
    filename = file?.name ?? '';
    preview = null;
    fileError = '';
    if (!file) return;
    if (file.size > 2_000_000) {
      fileError = 'The diagram is larger than the 2 MB import limit.';
      return;
    }
    try {
      const text = await file.text();
      if (currentSelection !== selectionId) return;
      diagramText = text;
      preview = convertWokwiDiagram(text);
    } catch (error) {
      if (currentSelection !== selectionId) return;
      fileError = `Could not read diagram: ${error.message}`;
    }
  }
</script>

<div class="importer">
  <h2>Import a Wokwi digital circuit</h2>
  <p>Choose a downloaded <code>diagram.json</code> or paste its contents below. Preview and validate the generated <code>top.v</code> before applying it.</p>
  <p class="supported">Supported: GreyMecha chip, named buttons and LEDs, or Tiny Tapeout input/output blocks; constants, buffer, NOT, AND, OR, XOR, XNOR, NAND, 2:1 MUX, D/DSR flip-flops, and one clock generator.</p>
  <label class="picker">Diagram file <input type="file" accept=".json,application/json" on:change={chooseFile} /></label>
  {#if filename}<p class="filename">{filename}</p>{/if}
  <label class="paste-label" for="diagram-json">Or paste diagram.json</label>
  <textarea id="diagram-json" bind:value={diagramText} placeholder={diagramPlaceholder} on:input={invalidatePreview}></textarea>
  <button class="preview-button" on:click={previewPastedDiagram}>Preview pasted diagram</button>
  {#if fileError}<div class="error" role="alert">{fileError}</div>{/if}
  {#if preview}
    {#if preview.errors.length}
      <div class="error" role="alert">
        <strong>Import needs changes</strong>
        <ul>{#each preview.errors as error}<li>{error}</li>{/each}</ul>
      </div>
    {:else}
      {#if preview.summary.format === 'Tiny Tapeout'}
        <p class="summary"><strong>Tiny Tapeout diagram detected.</strong> Pressing badge buttons 0–4 drives IN0–IN4 high; OUT0–OUT7 drive badge LEDs 0–7. IN5–IN7 are ignored.</p>
        <p class="clock">CLK uses the divided on-chip oscillator when needed. RST_N uses PMOD J1 pin 0 when needed.</p>
        {#if preview.summary.resetUsed}
          <p class="clock">Drive PMOD J1 pin 0 high normally and low to reset. This pin is configured for 2.5 V I/O; provide a defined level at all times.</p>
        {/if}
      {/if}
      <p class="summary">Detected {preview.summary.buttons} button inputs, {preview.summary.leds} LED outputs, {preview.summary.gates} gates, and {preview.summary.flipFlops} flip-flops.</p>
      {#if preview.summary.approximateClock}
        <p class="clock">Clock request: {preview.summary.clockHz} Hz. The badge frequency is approximate because the on-chip oscillator varies.</p>
      {/if}
      <div class="actions">
        <button disabled={disabled} on:click={() => onUseDesign(preview.verilog)}>Use Design</button>
        <button disabled={disabled} on:click={() => onUseAndSynthesize(preview.verilog)}>Use Design &amp; Synthesize</button>
      </div>
      <h3>Generated top.v</h3>
      <pre>{preview.verilog}</pre>
    {/if}
  {/if}
</div>

<style>
  .importer { height: 100%; overflow: auto; box-sizing: border-box; padding: 18px 24px; background: #1e1e1e; color: #ddd; }
  h2 { margin: 0 0 8px; font-size: 17px; }
  h3 { margin: 16px 0 8px; font-size: 14px; }
  p { max-width: 800px; margin: 7px 0; color: #bbb; font-size: 13px; }
  code { color: #9cdcfe; }
  .picker { display: block; margin-top: 15px; font-size: 13px; }
  input { display: block; margin-top: 7px; color: #ddd; }
  .filename { color: #9cdcfe; }
  .paste-label { display: block; margin-top: 14px; color: #ccc; font-size: 13px; }
  textarea { display: block; width: 100%; max-width: 900px; height: 150px; box-sizing: border-box; margin-top: 6px; padding: 10px; resize: vertical; border: 1px solid #444; border-radius: 3px; background: #171717; color: #ddd; font: 12px/1.5 monospace; }
  .preview-button { margin-top: 8px; }
  .error { margin-top: 12px; padding: 10px; border-radius: 3px; color: #9b1d16; background: #fff1f0; font-size: 13px; }
  .error ul { margin: 5px 0 0; padding-left: 20px; }
  .summary { margin-top: 12px; color: #a9dfa9; }
  .clock { color: #ffd28a; }
  .actions { display: flex; flex-wrap: wrap; gap: 8px; margin: 14px 0; }
  button { padding: 8px 12px; border: 0; border-radius: 3px; color: white; background: #007acc; cursor: pointer; font-weight: 600; }
  button:disabled { opacity: .5; cursor: not-allowed; }
  pre { width: max-content; min-width: 100%; box-sizing: border-box; padding: 12px; background: #171717; color: #ddd; font-size: 12px; }
</style>
