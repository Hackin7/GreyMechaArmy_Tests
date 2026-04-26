// src/lib/synthesisWorker.js
import { runYosys } from '@yowasp/yosys';
import { runNextpnrEcp5, runEcppack } from '@yowasp/nextpnr-ecp5';

self.onmessage = async (e) => {
    const { type, files } = e.data;
    
    if (type === 'SYNTHESIZE') {
        const textEncoder = new TextEncoder();
        let fs = {};
        
        // Populate virtual filesystem
        for (const [filename, content] of Object.entries(files)) {
            fs[filename] = textEncoder.encode(content);
        }

        const log = (msg) => self.postMessage({ type: 'LOG', message: msg });
        const decode = (data) => typeof data === 'string' ? data : new TextDecoder().decode(data);

        const readLog = (fsObj, filename) => {
            if (!fsObj) return null;
            if (fsObj[filename]) return decode(fsObj[filename]);
            return null;
        };

        try {
            // 1. Yosys
            log("Running Yosys...");
            const vFiles = Object.keys(files).filter(f => f.endsWith('.v'));
            let args = ["-p", "synth_ecp5 -top top -json out.json", "-l", "yosys.log", ...vFiles];
            try {
                fs = await runYosys(args, fs);
                const logData = readLog(fs, 'yosys.log');
                if (logData) log(logData);
            } catch (err) {
                const errFs = err.files || fs;
                const logData = readLog(errFs, 'yosys.log');
                if (logData) log(logData);
                throw new Error("Yosys failed with status " + (err.code || err.exit_code || 1));
            }
            log("Yosys completed.");

            // 2. NextPNR
            log("Running NextPNR...");
            args = ["--json", "out.json", "--textcfg", "out.config", "--25k", "--package", "CABGA256", "--lpf", "pinout.lpf", "--log", "nextpnr.log"];
            try {
                fs = await runNextpnrEcp5(args, fs);
                const logData = readLog(fs, 'nextpnr.log');
                if (logData) log(logData);
            } catch (err) {
                const errFs = err.files || fs;
                const logData = readLog(errFs, 'nextpnr.log');
                if (logData) log(logData);
                throw new Error("NextPNR failed with status " + (err.code || err.exit_code || 1));
            }
            log("NextPNR completed.");

            // 3. ecppack
            log("Running ecppack...");
            args = ["--input", "out.config", "--bit", "tmp.bit"];
            try {
                fs = await runEcppack(args, fs);
                const logData = readLog(fs, 'ecppack.log');
                if (logData) log(logData);
            } catch (err) {
                const errFs = err.files || fs;
                const logData = readLog(errFs, 'ecppack.log');
                if (logData) log(logData);
                throw new Error("ecppack failed with status " + (err.code || err.exit_code || 1));
            }
            log("ecppack completed.");

            // Output the bitstream
            const bitstream = fs["tmp.bit"];
            self.postMessage({ type: 'DONE', bitstream });

        } catch (err) {
            log("Error: " + err.message);
            self.postMessage({ type: 'ERROR', error: err.message });
        }
    }
};
