<script>
    import { files, activeFile, terminalLogs, buildArtifacts } from './lib/stores.js';
    import { uploadToDevice, rebootDevice } from './lib/filesystem.js';
    import NetlistView from './lib/NetlistView.svelte';
    import { onMount, onDestroy, afterUpdate } from 'svelte';
    import { basicSetup, EditorView } from 'codemirror';

    let editorContainer;
    let mainContainer;
    let editorView;
    let terminalContainer;
    let isSynthesizing = false;
    let synthesisWorker;
    let pendingBuild = null;
    let nextRunId = 0;
    let sourceRevision = 0;
    let activePanel = 'terminal';
    let panelSize = 42;
    let resizeStart = null;
    let isResizingPanel = false;

    let savedDirHandle = null;

    $: buildIsOutdated = $buildArtifacts.runId > 0 && $buildArtifacts.sourceRevision !== sourceRevision;
    $: hasCurrentBitstream = Boolean($buildArtifacts.bitstream) && !buildIsOutdated;

    onMount(() => {
        editorView = new EditorView({
            doc: $files[$activeFile],
            extensions: [basicSetup],
            parent: editorContainer,
            dispatch: (tr) => {
                editorView.update([tr]);
                if (tr.docChanged) {
                    sourceRevision += 1;
                    files.update((f) => ({ ...f, [$activeFile]: tr.state.doc.toString() }));
                }
            }
        });

        synthesisWorker = new Worker(new URL('./lib/synthesisWorker.js', import.meta.url), { type: 'module' });
        synthesisWorker.addEventListener('message', handleWorkerMessage);
    });

    onDestroy(() => {
        synthesisWorker?.removeEventListener('message', handleWorkerMessage);
        synthesisWorker?.terminate();
        if (pendingBuild) {
            pendingBuild.reject(new Error('Build cancelled because the page was closed.'));
            pendingBuild = null;
        }
    });

    afterUpdate(() => {
        if (terminalContainer) terminalContainer.scrollTop = terminalContainer.scrollHeight;
    });

    $: if (editorView && $activeFile && editorView.state.doc.toString() !== $files[$activeFile]) {
        editorView.dispatch({
            changes: { from: 0, to: editorView.state.doc.length, insert: $files[$activeFile] }
        });
    }

    function selectFile(filename) {
        activeFile.set(filename);
    }

    function beginResize(event) {
        if (event.button !== 0) return;
        event.preventDefault();
        event.currentTarget.setPointerCapture(event.pointerId);
        const height = mainContainer?.getBoundingClientRect().height ?? 0;
        if (!height) return;
        resizeStart = { y: event.clientY, size: panelSize, height };
        isResizingPanel = true;
    }

    function moveResize(event) {
        if (!resizeStart) return;
        const delta = ((event.clientY - resizeStart.y) / resizeStart.height) * 100;
        panelSize = Math.min(80, Math.max(20, resizeStart.size - delta));
    }

    function endResize() {
        resizeStart = null;
        isResizingPanel = false;
    }

    function resizeByKeyboard(event) {
        if (event.key === 'ArrowUp') panelSize = Math.min(80, panelSize + 2);
        else if (event.key === 'ArrowDown') panelSize = Math.max(20, panelSize - 2);
        else if (event.key === 'Home') panelSize = 20;
        else if (event.key === 'End') panelSize = 80;
        else return;
        event.preventDefault();
    }

    function handleWorkerMessage(event) {
        const message = event.data ?? {};
        if (!pendingBuild || message.runId !== pendingBuild.runId) return;

        if (message.type === 'LOG') {
            terminalLogs.update((logs) => logs + message.message + '\n');
            return;
        }
        if (message.type === 'LOGICAL_READY') {
            buildArtifacts.update((build) => ({ ...build, logicalJson: message.json, status: 'running' }));
            return;
        }
        if (message.type === 'MAPPED_READY') {
            buildArtifacts.update((build) => ({ ...build, mappedJson: message.json, status: 'running' }));
            return;
        }
        if (message.type === 'DONE') {
            const build = $buildArtifacts;
            buildArtifacts.set({ ...build, bitstream: message.bitstream, status: 'complete' });
            isSynthesizing = false;
            pendingBuild.resolve(message.bitstream);
            pendingBuild = null;
            terminalLogs.update((logs) => logs + 'Synthesis and bitstream packing successful.\n');
            return;
        }
        if (message.type === 'ERROR') {
            const build = $buildArtifacts;
            buildArtifacts.set({
                ...build,
                status: 'error',
                stageErrors: { ...build.stageErrors, [message.stage]: message.error }
            });
            isSynthesizing = false;
            terminalLogs.update((logs) => logs + `\n${message.stage} failed: ${message.error}\n`);
            pendingBuild.reject(new Error(`${message.stage} failed: ${message.error}`));
            pendingBuild = null;
        }
    }

    function startBuild() {
        if (isSynthesizing) return Promise.reject(new Error('A build is already running.'));
        if (!synthesisWorker) return Promise.reject(new Error('Synthesis worker is not ready.'));

        const runId = ++nextRunId;
        const sourceSnapshot = { ...$files };
        const snapshotRevision = sourceRevision;
        isSynthesizing = true;
        terminalLogs.set(`Starting build ${runId}…\n`);
        buildArtifacts.set({
            runId,
            status: 'running',
            sourceRevision: snapshotRevision,
            logicalJson: null,
            mappedJson: null,
            bitstream: null,
            stageErrors: {}
        });

        return new Promise((resolve, reject) => {
            pendingBuild = { runId, sourceRevision: snapshotRevision, resolve, reject };
            synthesisWorker.postMessage({ type: 'SYNTHESIZE', runId, files: sourceSnapshot });
        });
    }

    async function synthesize() {
        try {
            await startBuild();
        } catch {
            // The worker handler has already placed the stage failure in the terminal.
        }
    }

    async function runAll() {
        if (isSynthesizing) return;
        try {
            if (!savedDirHandle) {
                savedDirHandle = await window.showDirectoryPicker({ id: 'circuitpython', mode: 'readwrite', startIn: 'desktop' });
            }
            const serialPort = await navigator.serial.requestPort();
            const buffer = await startBuild();
            if ($buildArtifacts.sourceRevision !== sourceRevision) {
                throw new Error('Source changed while the build was running. Rebuild before programming.');
            }

            const updateLog = (msg, raw = false) => terminalLogs.update((logs) => logs + msg + (raw ? '' : '\n'));
            updateLog('Synthesis complete. Uploading bitstream…');
            const uploadRes = await uploadToDevice(buffer, updateLog, savedDirHandle);
            if (!uploadRes.success) throw new Error(`Upload failed: ${uploadRes.error}`);

            updateLog('Upload complete. Waiting for CircuitPython to reload…');
            await new Promise((resolve) => setTimeout(resolve, 2000));
            updateLog('Programming FPGA over serial…');
            const programRes = await rebootDevice(updateLog, serialPort);
            if (!programRes.success) throw new Error(`Programming failed: ${programRes.error}`);
            updateLog('Run All completed successfully.');
        } catch (error) {
            terminalLogs.update((logs) => logs + `\nRun All stopped: ${error.message}\n`);
        }
    }

    async function upload() {
        if (!hasCurrentBitstream) return;
        if (!savedDirHandle) {
            terminalLogs.update((logs) => logs + 'Select the CIRCUITPYTHON drive.\n');
            try {
                savedDirHandle = await window.showDirectoryPicker({ id: 'circuitpython', mode: 'readwrite', startIn: 'desktop' });
            } catch {
                return;
            }
        }
        const updateLog = (msg, raw = false) => terminalLogs.update((logs) => logs + msg + (raw ? '' : '\n'));
        const result = await uploadToDevice($buildArtifacts.bitstream, updateLog, savedDirHandle);
        if (result.success) terminalLogs.update((logs) => logs + 'Upload complete. Click Program via Serial to apply the bitstream.\n');
        else terminalLogs.update((logs) => logs + `Upload failed: ${result.error}\n`);
    }

    async function reboot() {
        if (!hasCurrentBitstream) return;
        try {
            const port = await navigator.serial.requestPort();
            const updateLog = (msg, raw = false) => terminalLogs.update((logs) => logs + msg + (raw ? '' : '\n'));
            const result = await rebootDevice(updateLog, port);
            if (result.success) terminalLogs.update((logs) => logs + '\nProgramming commands sent over Serial REPL.\n');
            else terminalLogs.update((logs) => logs + `\nSerial programming failed: ${result.error}\n`);
        } catch (error) {
            terminalLogs.update((logs) => logs + `\nSerial access failed: ${error.message}\n`);
        }
    }

    function downloadBitstream() {
        if (!$buildArtifacts.bitstream) return;
        const blob = new Blob([$buildArtifacts.bitstream], { type: 'application/octet-stream' });
        const url = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.download = 'tmp.bit';
        document.body.appendChild(anchor);
        anchor.click();
        anchor.remove();
        URL.revokeObjectURL(url);
    }
</script>

<div class:resizing={isResizingPanel} class="layout">
    <aside class="sidebar">
        <h2>Files</h2>
        <ul class="file-list">
            {#each Object.keys($files) as filename}
                <!-- svelte-ignore a11y-click-events-have-key-events -->
                <!-- svelte-ignore a11y-no-noninteractive-element-interactions -->
                <li class:active={$activeFile === filename} on:click={() => selectFile(filename)}>{filename}</li>
            {/each}
        </ul>
        <div class="actions">
            <button class="run-all-btn" on:click={runAll} disabled={isSynthesizing}>Run All (Synthesize → Program)</button>
            <button class="synth-btn" on:click={synthesize} disabled={isSynthesizing}>{isSynthesizing ? 'Building…' : 'Synthesize'}</button>
            <button class="upload-btn" on:click={upload} disabled={!hasCurrentBitstream}>Upload to Badge</button>
            <button class="reboot-btn" on:click={reboot} disabled={!hasCurrentBitstream}>Program via Serial</button>
            <button class="download-btn" on:click={downloadBitstream} disabled={!$buildArtifacts.bitstream}>Download Bitstream</button>
        </div>
        {#if buildIsOutdated}
            <p class="outdated">Source changed after this build. Synthesize again before uploading or programming.</p>
        {/if}
        <div class="instructions">
            <h3>How to Use</h3>
            <ol>
                <li>Plug the badge into USB and wait for the CIRCUITPYTHON drive.</li>
                <li>Click Run All and select the drive and serial port when prompted.</li>
                <li>Use the views below to inspect the logical netlist and mapped ECP5 cells.</li>
            </ol>
            <p>Device permissions are remembered until you refresh the page.</p>
        </div>
    </aside>

    <main class="main" bind:this={mainContainer}>
        <div class="editor" bind:this={editorContainer}></div>
        <!-- svelte-ignore a11y-no-noninteractive-tabindex -->
        <!-- svelte-ignore a11y-no-noninteractive-element-interactions -->
        <div
            class="resize-handle"
            role="separator"
            tabindex="0"
            aria-label="Resize build panel"
            aria-orientation="horizontal"
            aria-valuemin="20"
            aria-valuemax="80"
            aria-valuenow={Math.round(panelSize)}
            on:pointerdown={beginResize}
            on:pointermove={moveResize}
            on:pointerup={endResize}
            on:pointercancel={endResize}
            on:keydown={resizeByKeyboard}
        ></div>
        <section class="lower-panel" style={`flex-basis: ${panelSize}%`}>
            <nav class="panel-tabs" aria-label="Build output views">
                <button class:active={activePanel === 'terminal'} on:click={() => (activePanel = 'terminal')}>Terminal</button>
                <button class:active={activePanel === 'logical'} disabled={!$buildArtifacts.logicalJson} on:click={() => (activePanel = 'logical')}>Logical Netlist</button>
                <button class:active={activePanel === 'mapped'} disabled={!$buildArtifacts.mappedJson} on:click={() => (activePanel = 'mapped')}>Mapped ECP5</button>
                {#if buildIsOutdated}<span class="outdated-label">Outdated</span>{/if}
            </nav>
            <div class="panel-content">
                <div class:panel-hidden={activePanel !== 'terminal'} class="panel-layer terminal" bind:this={terminalContainer} aria-hidden={activePanel !== 'terminal'}>
                    <pre>{$terminalLogs}</pre>
                </div>
                {#if $buildArtifacts.logicalJson}
                    <div class:panel-hidden={activePanel !== 'logical'} class="panel-layer" aria-hidden={activePanel !== 'logical'}>
                        <NetlistView json={$buildArtifacts.logicalJson} runId={$buildArtifacts.runId} label="logical" />
                    </div>
                {/if}
                {#if $buildArtifacts.mappedJson}
                    <div class:panel-hidden={activePanel !== 'mapped'} class="panel-layer" aria-hidden={activePanel !== 'mapped'}>
                        <NetlistView json={$buildArtifacts.mappedJson} runId={$buildArtifacts.runId} label="mapped ECP5" />
                    </div>
                {/if}
            </div>
        </section>
    </main>
</div>

<style>
    .layout { display: flex; width: 100vw; height: 100vh; background: #1e1e1e; color: #d4d4d4; }
    .sidebar { display: flex; flex: 0 0 250px; flex-direction: column; padding: 10px; background: #252526; border-right: 1px solid #333; }
    .sidebar h2 { margin: 0 0 10px; color: #858585; font-size: 14px; text-transform: uppercase; }
    .file-list { flex: 1; min-height: 40px; overflow-y: auto; list-style: none; padding: 0; margin: 0 0 10px; }
    .file-list li { padding: 8px; margin-bottom: 4px; border-radius: 4px; cursor: pointer; font-family: monospace; }
    .file-list li:hover { background: #2a2d2e; }
    .file-list li.active { background: #37373d; color: #fff; }
    .actions { display: flex; flex-direction: column; gap: 8px; margin-bottom: 12px; }
    button { padding: 9px; border: 0; border-radius: 4px; cursor: pointer; font-weight: 600; }
    button:disabled { opacity: .45; cursor: not-allowed; }
    .run-all-btn { background: #e33e5a; color: white; }
    .synth-btn { background: #007acc; color: white; }
    .upload-btn { background: #28a745; color: white; }
    .reboot-btn { background: #6f42c1; color: white; }
    .download-btn { background: #d97d0d; color: white; }
    .instructions { padding: 10px; border-radius: 4px; background: #1e1e1e; color: #9cdcfe; font-size: 12px; }
    .instructions h3 { margin: 0 0 7px; color: #4fc1ff; font-size: 13px; }
    .instructions ol { padding-left: 18px; margin: 0; }
    .instructions li { margin-bottom: 5px; }
    .instructions p { margin: 7px 0 0; color: #858585; }
    .outdated { margin: 0 0 10px; padding: 8px; color: #ffd28a; background: #493b23; border-radius: 4px; font-size: 12px; }
    .main { display: flex; flex: 1; flex-direction: column; min-width: 0; min-height: 0; }
    .editor { flex: 1 1 0; min-height: 120px; overflow: hidden; }
    :global(.cm-editor) { height: 100%; }
    .resize-handle { z-index: 1; flex: 0 0 8px; position: relative; cursor: row-resize; touch-action: none; background: #252526; border-top: 1px solid #333; border-bottom: 1px solid #333; }
    .resize-handle::after { content: ''; position: absolute; width: 34px; height: 2px; left: 50%; top: 50%; transform: translate(-50%, -50%); background: #666; border-radius: 2px; }
    .resize-handle:hover::after, .resize-handle:focus-visible::after { width: 48px; background: #4fc1ff; }
    .resize-handle:focus-visible { outline: 1px solid #4fc1ff; outline-offset: -1px; }
    .layout.resizing { user-select: none; cursor: row-resize; }
    .lower-panel { display: flex; flex: 0 0 auto; flex-direction: column; min-height: 120px; border-top: 1px solid #333; }
    .panel-tabs { display: flex; flex: 0 0 auto; align-items: center; gap: 2px; min-height: 39px; padding: 4px 8px; background: #252526; }
    .panel-tabs button { padding: 7px 10px; color: #bbb; background: transparent; border-radius: 3px; font-size: 12px; }
    .panel-tabs button.active { color: #fff; background: #3b3b3b; }
    .panel-tabs button:disabled { opacity: .4; }
    .outdated-label { margin-left: auto; padding: 4px 7px; color: #ffd28a; font: 11px monospace; }
    .panel-content { position: relative; flex: 1; min-height: 0; }
    .panel-layer { position: absolute; inset: 0; }
    .panel-hidden { display: none; }
    .terminal { overflow: auto; padding: 10px; color: #ccc; background: #1e1e1e; font: 12px monospace; }
    .terminal pre { margin: 0; white-space: pre-wrap; overflow-wrap: anywhere; font: inherit; }
    @media (max-width: 850px) {
        .sidebar { flex-basis: 205px; }
        .panel-tabs { overflow-x: auto; }
        .panel-tabs button { white-space: nowrap; }
    }
</style>
