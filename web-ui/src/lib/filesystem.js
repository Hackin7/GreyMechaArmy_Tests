export async function uploadToDevice(bitstreamBuffer, updateLog, providedDirHandle = null) {
    try {
        // Request directory picker for CIRCUITPYTHON drive if not provided
        const dirHandle = providedDirHandle || await window.showDirectoryPicker({
            id: 'circuitpython',
            mode: 'readwrite',
            startIn: 'desktop'
        });

        // Ensure we're targeting the right drive
        try {
            await dirHandle.getFileHandle('boot_out.txt');
        } catch (e) {
            updateLog("Warning: Could not find boot_out.txt, maybe not a standard CircuitPython drive. Proceeding...");
        }

        // Navigate to /hardware/bitstreams/
        const hwDir = await dirHandle.getDirectoryHandle('hardware', { create: true });
        const bitDir = await hwDir.getDirectoryHandle('bitstreams', { create: true });

        // Write tmp.bit
        const bitFile = await bitDir.getFileHandle('tmp.bit', { create: true });
        const bitWritable = await bitFile.createWritable();

        updateLog("Writing tmp.bit to USB drive (this may take a few seconds)...");
        await bitWritable.write(bitstreamBuffer);

        updateLog("Syncing files (do not unplug)...");
        await bitWritable.close();

        return { success: true };
    } catch (error) {
        console.error("Upload failed:", error);
        return { success: false, error: error.message };
    }
}

export async function rebootDevice(updateLog, providedPort = null) {
    let port = providedPort;
    try {
        if (!port) {
            port = await navigator.serial.requestPort();
        }
        await port.open({ baudRate: 115200 });

        const reader = port.readable.getReader();
        const textDecoder = new TextDecoder();
        let programmingFinished = false;

        // Background reader — streams serial output to the log
        const readPromise = (async () => {
            try {
                while (!programmingFinished) {
                    const { value, done } = await reader.read();
                    if (done) break;
                    if (value && updateLog) {
                        const text = textDecoder.decode(value);
                        updateLog(text, true);
                        if (text.includes("FPGA Programmed Successfully!")) {
                            break;
                        }
                    }
                }
            } catch (e) {
                // Reader cancelled or errored — expected during cleanup
            } finally {
                reader.releaseLock();
            }
        })();

        // Wait for board to finish booting (opening port triggers DTR reset)
        await new Promise(r => setTimeout(r, 1500));

        const writer = port.writable.getWriter();
        const encoder = new TextEncoder();

        // Interrupt any running code and enter REPL
        await writer.write(encoder.encode('\x03'));
        await new Promise(r => setTimeout(r, 300));
        await writer.write(encoder.encode('\x03'));
        await new Promise(r => setTimeout(r, 500));

        // Clear prompt
        await writer.write(encoder.encode('\r\n'));
        await new Promise(r => setTimeout(r, 100));

        // Send commands line-by-line
        const pyCmds = [
            "import displayio",
            "displayio.release_displays()",
            "import hardware.fpga",
            "print('Programming FPGA with tmp.bit...')",
            "hardware.fpga.upload_bitstream('/hardware/bitstreams/tmp.bit').deinit()",
            "print('FPGA Programmed Successfully!')"
        ];

        for (const cmd of pyCmds) {
            await writer.write(encoder.encode(cmd + '\r\n'));
            await new Promise(r => setTimeout(r, 200));
        }

        writer.releaseLock();

        // Wait up to 10 seconds for programming to finish
        await Promise.race([
            readPromise,
            new Promise(r => setTimeout(r, 10000))
        ]);

        programmingFinished = true;

        try { await reader.cancel(); } catch (e) { }
        await readPromise;

        await port.close();
        return { success: true };
    } catch (error) {
        console.error("Serial command failed:", error);
        try { await port.close(); } catch (e) { }
        return { success: false, error: error.message };
    }
}
