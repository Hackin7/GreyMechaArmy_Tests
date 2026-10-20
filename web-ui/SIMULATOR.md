# GreyMecha / Army FPGA simulator

Select **Simulator** in the sidebar to open its panel to the right of the editor. Choose an OLED mode and select **Compile & Run**. The editor's Verilog is compiled and simulated locally in a worker. No badge, server, bitstream, or place-and-route run is required. The compiler and artwork are served with the website; first use also loads its bundled Yosys frontend.

Drag the vertical divider to resize the right panel, or focus it and use **Left/Right** and **Home/End**. The terminal and other build views stay below the editor. Close the simulator with **×** to reclaim space; closing pauses execution and releases held inputs, while reopening preserves the compiled state. On very narrow windows it opens as a closable right drawer. The board and its controls adapt to the panel width independently of the window width.

Hold the on-screen buttons or focus the board and hold keys **1–7** for `btn[0]`–`btn[6]`. Buttons are active-low and support simultaneous presses. Leaving the board releases held inputs. Five-button designs disable the extra two controls. The separate PMOD J1[0] control supplies Tiny Tapeout `RST_N` where that port is present.

**Pause** preserves the current state. **Step Cycle** advances to the next rising edge of the primary clock, processing intervening clock edges. **Restart** recreates the model's initialized state; it does not change the source or add reset circuitry. **Stop** terminates the worker, including during compilation. Editing, uploading, importing, or loading a preset makes the simulation outdated. Compile again to use the new source. Hardware synthesis pauses simulation. Reopening the panel does not automatically resume it.

## OLED rendering

**Pixel Preview** is the default and fastest mode. In the simulation filesystem only, `oled_gc9a01.v` is replaced by a compatible module that scans `pixel_index` from 0 through 57599, holding each address for four rising clock edges before sampling RGB565 `pixel_data`. This supports the advanced preset's image stretcher, BRAM read, and registered color mux. The framebuffer clears during reset. `init_done` and `streaming` are virtual, and the SPI outputs are idle; their status LEDs do not test the hardware driver. Preview consumes logical RGB565 directly, without the physical driver's red/blue compensation. It requires one `oled_gc9a01` module in its own `oled_gc9a01.v` file. Incompatible projects receive an error and can use SPI mode instead. Designs without an OLED interface can still simulate their logic.

**SPI Simulation** runs the original wrapper and decodes its actual mode-0, MSB-first serial output. It models reset, sleep/display state, RGB565 writes, address windows, RAM-write restart/continue, MADCTL orientation and color order, and inversion. The badge glass's BGR order and normal INVON configuration are reflected in the model. Other vendor initialization commands are recorded, with their analog effects omitted. It never reads internal `pixel_data`. This mode takes longer because the original initialization delays and every transmitted bit are simulated.

Switching modes recompiles and restarts the simulation. Both render a 240×240 framebuffer through a circular display opening. The simple starter's exact `6'b11111` green component is 31/63 intensity, so its green preview is intentionally darker than `6'b111111`.

## Supported hardware and limits

- Synthesizable Verilog-2005 with a `top` module and the existing GreyMecha port names. Headers and memory files use the same flat filenames as the editor. Missing files and unsupported constructs produce errors.
- `btn[4:0]` or `btn[6:0]`, `led[7:0]`, scalar `clk_ext`, and the OLED pins. PMOD J1 bit 0 is an optional simulated input; other external peripherals and electrical contention are not modeled. LPF pin placement is not applied to the virtual board.
- One `OSCG` with DIV 2–128, based on a nominal 310 MHz oscillator. One PLL driven directly by that oscillator, using the OLED preset's fixed profile (CLKI_DIV=2, CLKFB_DIV=3, CLKOP_DIV=8, CPHASE=4, FPHASE=0, CLKOP feedback). Clock ratios are preserved; lock is modeled after 16 oscillator rising edges. The presets therefore run at a nominal 77.5 MHz with DIV=6. This is a functional approximation, not a PLL or oscillator tolerance model.
- `ODDRX1F` models both clock edges and asynchronous reset. Ordinary RTL clock dividers run as part of the model. `clk_ext` defaults to 10 MHz and is configurable from 1 Hz to 200 MHz.
- Two-state digital simulation with deterministic zero initialization plus explicit RTL initial values. It does not reproduce metastability, analog effects, physical routing delays, or full X/Z behavior. Only zero-based unpacked arrays are supported. Direct `$readmemh`/`$readmemb` calls support comments, whitespace-separated values, `@` addresses, and explicit ranges; unknown memory digits become zero. Macro-obscured memory calls that cannot be resolved from compiler locations are rejected.
- Speed depends on the design and computer. The UI reports actual cycles, simulated time, frames, and measured cycles/second. It does not claim real-time operation. OLED updates are limited to 30 per second; all underlying pin/pixel events are processed.

## Run and test the feature branch

Work is isolated on `feature/greymecha-fpga-simulator` in a separate worktree. `main`, its Pages deployment, and the `working-webui` tag are not changed by this branch.

From its `web-ui` directory:

```sh
npm ci
npx playwright install chromium
npm run dev
```

Native parity checks require `iverilog` and `vvp` (on Windows, installed in WSL). Browser tests use the real production build under a Pages-equivalent subpath:

```sh
npm run verify:simulator
npm run build -- --base=/GreyMechaArmy_Tests/
npm run test:simulator:browser
```

`verify:simulator` compares clocked logic, reset and ROM behavior with native Icarus, checks every Tiny Tapeout button combination, DDR edges, protocol decoding, every image pixel in all three aspect modes, color buttons, resets and error handling. Playwright checks the actual Chromium worker, controls, cancellation, stale source handling, both OLED modes, and screenshots. Existing `verify:toolchain`, `verify:wokwi`, `verify:tinytapeout`, and `verify:oled-preset` remain hardware-flow checks.

The feature branch/PR workflow runs these checks without deploying Pages. Its artifact includes `dist`, screenshots and the Playwright report. To serve a downloaded build, put `dist` contents inside a folder named `GreyMechaArmy_Tests`, serve its parent with a static HTTP server, and open `/GreyMechaArmy_Tests/`.

## Upstream source and artwork

See [vendor provenance](vendor/UPSTREAM.md) and [the pinned file manifest](vendor/simulator-manifest.json). The HDL runtime/parser are adapted from 8bitworkshop (GPL-3.0); the Verilator compiler retains its own license. Source Verilog projects retain their own licensing. The older Greybadge25 reference assets remain bundled for provenance; the simulator board now uses the Greybadge26 PCB export described below. Artwork is credited to Shuqing.

Refresh pinned assets and reapply the recorded compatibility patches with `npm run sync:simulator`. Normal builds need no upstream downloads. Do not change the pins or refresh assets without rerunning the native parity and browser acceptance tests.

## PCB-matched assembled front

The board uses Greybadge26's actual 75 × 99 mm outline, lanyard slot, front silkscreen artwork, exposed pads and footprint coordinates. Back-mounted electronics are hidden. Metallic switch bodies and red LED emitters sit over the corresponding front footprints. Hover or focus a switch for its `btn` bit, PCB reference and keyboard key; expand **Board controls and pin mapping** for the complete legend. Fit scales the outline, display, buttons and LEDs together to the available panel space.

| Signal bits, in order | PCB references |
|---|---|
| `btn[0]`–`btn[6]` | SW4, SW1, SW5, SW7, SW3, SW2, SW6 |
| `led[0]`–`led[7]` | D1, D3, D5, D8, D2, D4, D6, D7 |

The display footprint specifies the flex connector, not the panel's mounted face. The owner's assembled-badge photo is registered using all seven switch centers, with an approximately 0.8-pixel registration residual. At the owner's request, the virtual display is enlarged and centered on the circular face contour of the PCB artwork, using three stored vector contour landmarks; the photo supplies its rotation. The active opening is approximately 38 mm across. This is visual alignment, not a manufacturing measurement. Rotating the displayed canvas does not change its 240 × 240 pixel buffer, HDL coordinates, or either OLED simulation mode. The PCB artwork is taken from the current Greybadge26 design; small differences from the photographed manufactured revision, such as the upper-left UFO, are retained.

Refresh from a local hardware checkout with KiCad 10 installed:

```sh
npm run sync:simulator-board -- "/path/to/greybadge26/greymechaarmy_v2/hardware/greybadge_pcb/greybadge_pcb.kicad_pcb"
npm run verify:simulator-board
```

The optional second argument supplies `kicad-cli`; otherwise `KICAD_CLI`, the Windows KiCad 10 installation, or the executable on PATH is used. The script reads the PCB, plots F.SilkS into a temporary directory, and writes the bundled front SVG and `boardLayout.json`. It never saves the source PCB or project. It records the source commit/checksum, KiCad version, calibration checksum and SVG checksum. Display landmarks remain separate in `vendor/greybadge26-display-calibration.json`, so refreshing exports does not discard them. A changed board that no longer matches those landmarks fails registration and requires recalibration.

KiCad's plot converts text to vector paths; this export used Verdana when the PCB's HelveticaNeue font was unavailable. Existing polygon artwork is preserved. Ordinary website builds and CI use committed exports and require neither KiCad nor the external hardware checkout. The photo itself is not shipped; only its checksum and measured landmarks are retained.

The browser suite checks all seven button hit targets and all eight LED positions against the manifest through zoom, fit and a narrow viewport, including real simultaneous touch input. PCB geometry and export checks run as part of `verify:simulator`; the existing engine, synthesis and OLED acceptance tests remain in CI.
