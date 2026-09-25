# GreyMechaArmy Web FPGA Environment

This browser app edits the FPGA source, runs the Yosys → nextpnr → ecppack build, and can inspect the logical netlist, mapped ECP5 netlist, and placement and routing results.

## Run and verify

```sh
npm ci
npm run dev
```

For a production build and a local toolchain smoke test:

```sh
npm run build
npm run verify:toolchain
npm run verify:wokwi
```

The production build contains the main editor. Vite bundles netlistsvg and ELK locally. `npm run prebuild` copies the netlist renderer bundles and licenses into the generated `public/vendor` directory.

## Build views

Each synthesis run produces artifacts as they become available. The **Terminal** tab shows build output. The **Logical Netlist** tab shows the coarse ECP5 synthesis result before final cell mapping. **Mapped ECP5** shows the JSON from `synth_ecp5`; it can be much denser because logic has been lowered into device-specific cells. Both diagrams allow module selection, pan, zoom, fit, and reset. **P&R Export** provides `place.json` and `report.json` from nextpnr as separate downloads. To view them, open the [nextpnr-viewer](https://edacation.github.io/nextpnr-viewer/), choose **Family: ECP5** and **Device: 25K**, then upload `place.json` as the placement file and `report.json` as the report file. Use both files from the same build.

If the source changes after synthesis, the views are marked **Outdated** and the old bitstream cannot be uploaded or programmed; synthesize again to refresh them.

## Wokwi import

The **Wokwi Import** tab accepts a downloaded `diagram.json` or pasted JSON text. It validates supported digital parts and wiring, previews structural Verilog, and can replace `top.v` or replace it and synthesize immediately. An invalid diagram leaves the editor untouched. Applying a valid diagram clears artifacts from the previous source. See [the example circuits](../wokwi/README.md) for supported parts and Wokwi usage.

## Badge programming

Synthesis, viewing, and bitstream download work in browsers without hardware access. Programming requires a secure context (HTTPS or localhost), Web Serial support, permission to connect to the badge, and the browser's directory access capability used by the existing programming workflow.
