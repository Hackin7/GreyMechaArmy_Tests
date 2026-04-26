<script>
    import { files, activeFile, terminalLogs } from './lib/stores.js';
    import { uploadToDevice, rebootDevice } from './lib/filesystem.js';
    import { onMount, afterUpdate } from 'svelte';
    import { basicSetup, EditorView } from 'codemirror';

    let editorContainer;
    let editorView;
    let terminalContainer;
    let isSynthesizing = false;
    let synthesisWorker;
    let bitstreamBuffer = null;

    let savedDirHandle = null;
    let savedPort = null;
    let serialWriter = null;

    onMount(() => {
        editorView = new EditorView({
            doc: $files[$activeFile],
            extensions: [basicSetup],
            parent: editorContainer,
            dispatch: (tr) => {
                editorView.update([tr]);
                if (tr.docChanged) {
                    files.update(f => ({...f, [$activeFile]: tr.state.doc.toString()}));
                }
            }
        });

        // Worker initialization
        synthesisWorker = new Worker(new URL('./lib/synthesisWorker.js', import.meta.url), { type: 'module' });
        synthesisWorker.addEventListener('message', (e) => {
            const { type, message, bitstream, error } = e.data;
            if (type === 'LOG') {
                terminalLogs.update(logs => logs + message + '\n');
            } else if (type === 'DONE') {
                terminalLogs.update(logs => logs + 'Synthesis successful!\n');
                bitstreamBuffer = bitstream;
                isSynthesizing = false;
            } else if (type === 'ERROR') {
                terminalLogs.update(logs => logs + `Error: ${error}\n`);
                isSynthesizing = false;
            }
        });
    });

    afterUpdate(() => {
        if (terminalContainer) {
            terminalContainer.scrollTop = terminalContainer.scrollHeight;
        }
    });

    $: if (editorView && $activeFile) {
        if (editorView.state.doc.toString() !== $files[$activeFile]) {
            editorView.dispatch({
                changes: { from: 0, to: editorView.state.doc.length, insert: $files[$activeFile] }
            });
        }
    }

    function selectFile(filename) {
        activeFile.set(filename);
    }

    function synthesize() {
        if (isSynthesizing) return;
        isSynthesizing = true;
        terminalLogs.set('Starting synthesis...\n');
        bitstreamBuffer = null;
        synthesisWorker.postMessage({ type: 'SYNTHESIZE', files: $files });
    }

    function synthesizeAsync() {
        return new Promise((resolve, reject) => {
            if (isSynthesizing) return reject(new Error("Already synthesizing"));
            isSynthesizing = true;
            terminalLogs.set('Starting synthesis...\n');
            bitstreamBuffer = null;
            
            const handler = (e) => {
                const { type, bitstream, error } = e.data;
                if (type === 'DONE') {
                    synthesisWorker.removeEventListener('message', handler);
                    resolve(bitstream);
                } else if (type === 'ERROR') {
                    synthesisWorker.removeEventListener('message', handler);
                    reject(new Error(error));
                }
            };
            synthesisWorker.addEventListener('message', handler);
            synthesisWorker.postMessage({ type: 'SYNTHESIZE', files: $files });
        });
    }

    async function initSerial() {
        if (!savedPort) {
            savedPort = await navigator.serial.requestPort();
            await savedPort.open({ baudRate: 115200 });
            serialWriter = savedPort.writable.getWriter();
            
            // Start global background reader
            (async () => {
                const reader = savedPort.readable.getReader();
                const decoder = new TextDecoder();
                try {
                    while (true) {
                        const { value, done } = await reader.read();
                        if (done) break;
                        if (value) {
                            const text = decoder.decode(value);
                            terminalLogs.update(logs => logs + text);
                        }
                    }
                } catch (e) {
                    console.error("Serial reader error:", e);
                } finally {
                    reader.releaseLock();
                }
            })();
        }
    }

    async function runAll() {
        if (isSynthesizing) return;
        
        let serialPort;
        try {
            if (!savedDirHandle) {
                savedDirHandle = await window.showDirectoryPicker({ id: 'circuitpython', mode: 'readwrite', startIn: 'desktop' });
            }
            serialPort = await navigator.serial.requestPort();
        } catch (e) {
            terminalLogs.update(logs => logs + `Permissions cancelled: ${e.message}\n`);
            return;
        }

        try {
            const buffer = await synthesizeAsync();
            const updateLog = (msg, raw=false) => terminalLogs.update(logs => logs + msg + (raw ? '' : '\n'));
            
            updateLog('Synthesis complete! Proceeding to upload...');
            const uploadRes = await uploadToDevice(buffer, updateLog, savedDirHandle);
            if (!uploadRes.success) throw new Error("Upload failed: " + uploadRes.error);
            
            updateLog('Upload complete! Waiting for CircuitPython to auto-reload (2s)...');
            await new Promise(r => setTimeout(r, 2000));
            
            updateLog('Proceeding to program FPGA...');
            const rebootRes = await rebootDevice(updateLog, serialPort);
            if (!rebootRes.success) throw new Error("Programming failed: " + rebootRes.error);
            
            updateLog('\nAll steps completed successfully!\n');
        } catch (e) {
            terminalLogs.update(logs => logs + `\nRun All Failed: ${e.message}\n`);
        }
    }

    async function upload() {
        if (!bitstreamBuffer) return;
        
        if (!savedDirHandle) {
            terminalLogs.update(logs => logs + 'Requesting device access... Select the CIRCUITPYTHON drive.\n');
            try {
                savedDirHandle = await window.showDirectoryPicker({ id: 'circuitpython', mode: 'readwrite', startIn: 'desktop' });
            } catch (e) { return; }
        }
        
        const updateLog = (msg, raw=false) => terminalLogs.update(logs => logs + msg + (raw ? '' : '\n'));
        const result = await uploadToDevice(bitstreamBuffer, updateLog, savedDirHandle);
        if (result.success) {
            terminalLogs.update(logs => logs + 'Upload complete! Now click "Program via Serial" to apply the bitstream.\n');
        } else {
            terminalLogs.update(logs => logs + `Upload failed: ${result.error}\n`);
        }
    }

    async function reboot() {
        try {
            await initSerial();
        } catch (e) { return; }
        
        terminalLogs.update(logs => logs + 'Requesting Serial Port to program FPGA...\n');
        
        const updateLog = (msg, raw=false) => terminalLogs.update(logs => logs + msg + (raw ? '' : '\n'));
        const result = await rebootDevice(updateLog);
        if (result.success) {
            terminalLogs.update(logs => logs + '\nProgramming commands sent over Serial REPL! Watch the log for output.\n');
        } else {
            terminalLogs.update(logs => logs + `\nSerial programming failed: ${result.error}\n`);
        }
    }

    function downloadBitstream() {
        if (!bitstreamBuffer) return;
        const blob = new Blob([bitstreamBuffer], { type: "application/octet-stream" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'tmp.bit';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }
</script>

<div class="layout">
    <div class="sidebar">
        <h2>Files</h2>
        <ul>
            {#each Object.keys($files) as filename}
                <!-- svelte-ignore a11y-click-events-have-key-events -->
                <!-- svelte-ignore a11y-no-noninteractive-element-interactions -->
                <li 
                    class:active={$activeFile === filename} 
                    on:click={() => selectFile(filename)}>
                    {filename}
                </li>
            {/each}
        </ul>
        <div class="actions">
            <button class="run-all-btn" on:click={runAll} disabled={isSynthesizing}>
                🚀 Run All (Synth -> Program)
            </button>
            <button class="synth-btn" on:click={synthesize} disabled={isSynthesizing}>
                {isSynthesizing ? 'Synthesizing...' : 'Synthesize'}
            </button>
            <button class="upload-btn" on:click={upload} disabled={!bitstreamBuffer}>
                Upload to Badge
            </button>
            <button class="reboot-btn" on:click={reboot} disabled={!bitstreamBuffer}>
                Program via Serial
            </button>
            <button class="download-btn" on:click={downloadBitstream} disabled={!bitstreamBuffer}>
                Download Bitstream
            </button>
        </div>
        <div class="instructions">
            <h3>How to Use:</h3>
            <ol>
                <li>Plug badge into USB.</li>
                <li>Wait for <strong>CIRCUITPYTHON</strong> drive.</li>
                <li>Click <strong>🚀 Run All</strong>.</li>
                <li>When prompted, select the <strong>CIRCUITPYTHON</strong> drive.</li>
                <li>When prompted, select the badge's <strong>Serial Port</strong>.</li>
            </ol>
            <p style="margin-top: 5px; color: #858585;">Note: Selections are remembered until you refresh the page.</p>
        </div>
    </div>
    <div class="main">
        <div class="editor" bind:this={editorContainer}></div>
        <div class="terminal" bind:this={terminalContainer}>
            <pre>{$terminalLogs}</pre>
        </div>
    </div>
</div>

<style>
    .layout {
        display: flex;
        width: 100vw;
        height: 100vh;
        background: #1e1e1e;
        color: #d4d4d4;
    }
    .sidebar {
        width: 250px;
        background: #252526;
        border-right: 1px solid #333;
        display: flex;
        flex-direction: column;
        padding: 10px;
    }
    .sidebar h2 {
        font-size: 14px;
        text-transform: uppercase;
        color: #858585;
        margin-bottom: 10px;
    }
    .sidebar ul {
        list-style: none;
        padding: 0;
        margin: 0;
        flex: 1;
    }
    .sidebar li {
        padding: 8px;
        cursor: pointer;
        border-radius: 4px;
        margin-bottom: 4px;
        font-family: monospace;
    }
    .sidebar li:hover {
        background: #2a2d2e;
    }
    .sidebar li.active {
        background: #37373d;
        color: #fff;
    }
    .actions {
        display: flex;
        flex-direction: column;
        gap: 10px;
        margin-bottom: 20px;
    }
    button {
        padding: 10px;
        border: none;
        border-radius: 4px;
        cursor: pointer;
        font-weight: bold;
        transition: opacity 0.2s;
    }
    button:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }
    .run-all-btn { background: #e33e5a; color: white; margin-bottom: 5px; }
    .synth-btn { background: #007acc; color: white; }
    .upload-btn { background: #28a745; color: white; }
    .reboot-btn { background: #6f42c1; color: white; }
    .download-btn { background: #d97d0d; color: white; }
    
    .instructions {
        font-size: 12px;
        color: #9cdcfe;
        background: #1e1e1e;
        padding: 10px;
        border-radius: 4px;
    }
    .instructions h3 {
        margin-top: 0;
        font-size: 13px;
        color: #4fc1ff;
    }
    .instructions ol {
        padding-left: 20px;
        margin-bottom: 0;
    }
    .instructions li {
        margin-bottom: 5px;
    }

    .main {
        flex: 1;
        display: flex;
        flex-direction: column;
        min-width: 0;
    }
    .editor {
        flex: 2;
        overflow: hidden;
    }
    /* Simple CodeMirror styling adjustment */
    :global(.cm-editor) {
        height: 100%;
    }
    
    .terminal {
        flex: 1;
        background: #1e1e1e;
        border-top: 1px solid #333;
        padding: 10px;
        font-family: monospace;
        font-size: 12px;
        overflow-y: auto;
        color: #cccccc;
    }
    .terminal pre {
        margin: 0;
        white-space: pre-wrap;
        word-wrap: break-word;
        font-family: 'Consolas', 'Courier New', monospace;
    }
</style>
