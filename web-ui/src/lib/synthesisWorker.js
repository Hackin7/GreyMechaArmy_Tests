import { runYosys } from '@yowasp/yosys';
import { runNextpnrEcp5, runEcppack } from '@yowasp/nextpnr-ecp5';

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function asText(value) {
    return typeof value === 'string' ? value : decoder.decode(value);
}

function artifact(fs, filename) {
    const value = fs?.[filename];
    if (!(value instanceof Uint8Array) && typeof value !== 'string') {
        throw new Error(`Expected output ${filename} was not created.`);
    }
    return typeof value === 'string' ? encoder.encode(value) : value;
}

function sendArtifact(type, runId, payload) {
    const copy = payload.slice();
    self.postMessage({ type, runId, json: copy }, [copy.buffer]);
}

function postLog(runId, message) {
    self.postMessage({ type: 'LOG', runId, message });
}

self.onmessage = async (event) => {
    const { type, runId, files } = event.data ?? {};
    if (type !== 'SYNTHESIZE' || typeof runId !== 'number' || !files) return;

    const inputFs = {};
    for (const [filename, content] of Object.entries(files)) {
        inputFs[filename] = encoder.encode(content);
    }
    const verilogFiles = Object.keys(files).filter((filename) => filename.endsWith('.v'));

    try {
        postLog(runId, 'Running ECP5 synthesis...');
        let fs;
        try {
            fs = await runYosys(
                ['-p', 'synth_ecp5 -top top -json out.json', '-l', 'yosys.log', ...verilogFiles],
                inputFs
            );
        } catch (error) {
            const errFs = error.files || inputFs;
            if (errFs['yosys.log']) postLog(runId, asText(errFs['yosys.log']));
            throw Object.assign(new Error(`Yosys failed: ${error.message}`), { stage: 'yosys' });
        }
        if (fs['yosys.log']) postLog(runId, asText(fs['yosys.log']));
        const mappedJson = artifact(fs, 'out.json');
        sendArtifact('MAPPED_READY', runId, mappedJson);

        postLog(runId, 'Generating logical netlist...');
        try {
            const logicalFs = await runYosys(
                ['-p', 'synth_ecp5 -top top -run begin:coarse; select *; proc; select top; write_json -selected logical.json', '-l', 'logical-yosys.log', ...verilogFiles],
                { ...inputFs }
            );
            if (logicalFs['logical-yosys.log']) postLog(runId, asText(logicalFs['logical-yosys.log']));
            sendArtifact('LOGICAL_READY', runId, artifact(logicalFs, 'logical.json'));
        } catch (error) {
            const errFs = error.files || {};
            if (errFs['logical-yosys.log']) postLog(runId, asText(errFs['logical-yosys.log']));
            postLog(runId, `Warning: logical schematic unavailable: ${error.message}`);
        }

        postLog(runId, 'Running nextpnr placement and routing...');
        let routedFs;
        try {
            routedFs = await runNextpnrEcp5([
                '--json', 'out.json',
                '--textcfg', 'out.config',
                '--write', 'place.json',
                '--report', 'report.json',
                '--25k',
                '--package', 'CABGA256',
                '--lpf', 'pinout.lpf',
                '--log', 'nextpnr.log'
            ], fs);
        } catch (error) {
            const errFs = error.files || fs;
            if (errFs['nextpnr.log']) postLog(runId, asText(errFs['nextpnr.log']));
            throw Object.assign(new Error(`nextpnr failed: ${error.message}`), { stage: 'nextpnr' });
        }
        if (routedFs['nextpnr.log']) postLog(runId, asText(routedFs['nextpnr.log']));
        const placementJson = artifact(routedFs, 'place.json').slice();
        const reportJson = artifact(routedFs, 'report.json').slice();
        self.postMessage({ type: 'ROUTED_READY', runId, placementJson, reportJson }, [placementJson.buffer, reportJson.buffer]);
        postLog(runId, 'Packing FPGA bitstream...');
        let packedFs;
        try {
            packedFs = await runEcppack(['--input', 'out.config', '--bit', 'tmp.bit'], routedFs);
        } catch (error) {
            const errFs = error.files || routedFs;
            if (errFs['ecppack.log']) postLog(runId, asText(errFs['ecppack.log']));
            throw Object.assign(new Error(`ecppack failed: ${error.message}`), { stage: 'ecppack' });
        }
        if (packedFs['ecppack.log']) postLog(runId, asText(packedFs['ecppack.log']));
        const bitstream = artifact(packedFs, 'tmp.bit').slice();
        self.postMessage({ type: 'DONE', runId, bitstream }, [bitstream.buffer]);
    } catch (error) {
        const stage = error.stage || 'synthesis';
        self.postMessage({ type: 'ERROR', runId, stage, error: error.message || String(error) });
    }
};
