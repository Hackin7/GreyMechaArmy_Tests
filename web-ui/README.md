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
npm run verify:tinytapeout
npm run verify:oled-preset
```

The production build contains the main editor. Vite bundles netlistsvg and ELK locally. `npm run prebuild` copies the netlist renderer bundles and licenses into the generated `public/vendor` directory.

## Build views

The **Simulator** sidebar action opens a resizable panel to the right of the editor. Its interactive GreyMecha/Army board uses the Greybadge26 PCB outline, artwork and component positions, with an enlarged OLED aligned to the artwork's face and selectable **Pixel Preview** or **SPI Simulation**. It runs entirely in the browser and does not require synthesis or a physical badge. Closing the panel pauses simulation; the terminal and other build views remain below the editor. See [simulator usage, PCB refresh, supported hardware, and verification](SIMULATOR.md).

Each synthesis run produces artifacts as they become available. The **Terminal** tab shows build output. The **Logical Netlist** tab shows the coarse ECP5 synthesis result before final cell mapping. **Mapped ECP5** shows the JSON from `synth_ecp5`; it can be much denser because logic has been lowered into device-specific cells. Both diagrams allow module selection, pan, zoom, fit, and reset. **P&R Export** provides `place.json` and `report.json` from nextpnr as separate downloads. To view them, open the [nextpnr-viewer](https://edacation.github.io/nextpnr-viewer/), choose **Family: ECP5** and **Device: 25K**, then upload `place.json` as the placement file and `report.json` as the report file. Use both files from the same build.

If the source changes after synthesis, the views are marked **Outdated** and the old bitstream cannot be uploaded or programmed; synthesize again to refresh them.

## Source files and OLED example

Use the sidebar to create a blank `.v` file, upload local `.v`, `.vh`, or `.mem` files, and remove added files. `top.v` and `pinout.lpf` remain present. Duplicate filenames are skipped so existing edits are preserved. Source file changes mark the previous build outdated.

The **Other** tab contains **Add OLED Modules**, **Load OLED**, **Load OLED (Advanced)**, bitstream download, badge upload, and serial programming. **Add OLED Modules** adds the seven supporting Verilog modules and their ROM header from `io/fpga_oled_fast`, leaving your current `top.v` and pinout in place.

**Load OLED** replaces the in-memory design with a minimal solid-green starter, its driver modules, ROM header, and pinout. Edit `pixel_data = {5'b00000, 6'b11111, 5'b00000};` inside the `always @(*)` block in `top.v` to change the RGB565 color (5 red bits, 6 green bits, 5 blue bits). Keep `pixel_data` declared as `reg` for procedural assignment, and assign it on every path if adding conditions. The driver exposes `pixel_index` (0–57599) for adding patterns later. The system clock is nominally 75 MHz; initialization starts automatically after programming, and holding active-low `btn[6]` resets the display. LEDs 7–2 show initialization, streaming, CS, DC, panel reset, and PLL lock; LEDs 1–0 are off. This starter needs no image memory, image stretcher, or button debounce module.

**Load OLED (Advanced)** replaces the design with the complete `io/fpga_oled_fast` demo, including its image memory, color buttons, and aspect modes. Both starters use `btn[6:0]` and the same pinout, including `btn[5]` at D12 and `btn[6]` at C12. Loading either starter selects `top.v` and marks any previous build outdated. To refresh the shared driver files and advanced demo after changing the source project, run `npm run sync:oled-preset` from `web-ui` and commit the updated preset files. The simple starter's `top.v` is maintained separately in `src/lib/presets/oled-simple/`.

## Wokwi import

The **Wokwi Import** tab accepts a downloaded `diagram.json` or pasted JSON text. Its **Badge clock speed** field defaults to 10 Hz and overrides the Wokwi clock generator frequency for the generated FPGA clock (1 Hz to 100 kHz). Changing the field or pasted JSON clears the old preview; preview again before applying. The importer validates supported digital parts and wiring, previews structural Verilog, and can replace `top.v` or replace it and synthesize immediately. An invalid diagram leaves the editor untouched. Applying a valid diagram clears artifacts from the previous source. See [the example circuits](../wokwi/README.md) for supported parts and Wokwi usage.

For a Tiny Tapeout diagram, the importer recognizes the input and output blocks by type. Badge buttons `btn[0]`–`btn[4]` drive `IN0`–`IN4` high when pressed; the active-low Mecha buttons `btn[5]` at D12 and `btn[6]` at C12 drive `IN5` and `IN6` high when pressed. `OUT0`–`OUT7` drive LEDs 0–7. `IN7` is unavailable: a direct connection to an output becomes low, while a gate using it produces an import error. The Wokwi switches, step/reset buttons, seven-segment display, and other simulation controls stay outside the FPGA circuit. Logic using `CLK` runs from the divided on-chip oscillator at an approximate rate. Logic using `RST_N` reads PMOD J1 pin 0; drive that 2.5 V input high normally and low to reset. The default `pinout.lpf` constrains all seven buttons; an edited pinout must also constrain them. Importing preserves the current `pinout.lpf`.

## Badge programming

Synthesis, viewing, and bitstream download work in browsers without hardware access. Programming requires a secure context (HTTPS or localhost), Web Serial support, permission to connect to the badge, and the browser's directory access capability used by the existing programming workflow.
