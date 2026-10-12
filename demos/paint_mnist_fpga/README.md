# GreyMecha paint MNIST

Standalone ECP5-25K/CABGA256 bitstream with D-pad drawing, the original four-colour
paint palette, and continuous digit recognition on the badge's 240x240 GC9A01.
No mouse, seven-segment display, MCU inference, or new TPU is required.

## Controls

| Control | Action |
|---|---|
| D-pad | Move cursor; diagonal movement works; opposite directions cancel |
| Hold A | Paint in the canvas; release to lift the pen |
| Press A over a swatch | Select red, blue, green or orange |
| Press B | Clear canvas and prediction; release A before drawing again |

Centre is unused. Buttons debounce independently for 5 ms. A new direction moves
immediately, repeats after 250 ms, then every 40 ms. The cursor stays within the
96x64 scene; it starts at `(28,28)` with red selected. A must first be released
after boot, avoiding accidental paint from the loader's held selection button.

The 28x28 colour canvas occupies a 56x56 logical area, rendered at 2x alongside
the palette. All four colours are binary ink for inference. Purple is a cursor
overlay and is never included in the image. The selected swatch has a white
border. `DIGIT: --` indicates an empty canvas; `*` indicates an update pending.
The latest prediction remains visible while new strokes are being processed.

## Build

Requires WSL/Linux with Python 3, Pillow, Icarus Verilog, Yosys with ECP5 support,
nextpnr-ecp5 and ecppack. From PowerShell:

```powershell
.\demos\paint_mnist_fpga\build-wsl.ps1
# Individual targets:
.\demos\paint_mnist_fpga\build-wsl.ps1 -Target sim
.\demos\paint_mnist_fpga\build-wsl.ps1 -Target bit
```

From this directory in WSL:

```bash
make sim bit
# Original resources elsewhere (use a Linux/WSL path without spaces):
make RESOURCES=/mnt/d/path/to/imports/res sim bit
```

The exporter reads `weights.coe` and `00.coe` from the supplied EE2026 project.
It generates the unchanged 50,890 signed 16-bit constants, six images and full
integer oracles under ignored `build/generated/`. It reuses the existing C demo's
COE parser and Python arithmetic reference. No original project files are changed.
The output bitstream is `paint_mnist.bit`; logs, timing reports and screen previews
are under `build/`.

## Architecture

Nominal 75 MHz handles controls and direct pixel rendering. A secondary PLL output
provides nominal 25 MHz to the original 784->64->10 inference core. Both clocks
track the FPGA internal oscillator; actual frequency depends on its tolerance.
Clock-domain resets release locally. No buttons are used as clocks.

Canvas changes trigger inference at most once every 100 ms. A sequential 784-cycle
snapshot pauses canvas edits and cursor movement for approximately 10.5 us; held
buttons and pending clicks resume afterward. The snapshot is stable until completion.
Request and completion toggles pass through two-register synchronizers; snapshot
and result buses remain stable while transferred. A clear-generation counter rejects
an older result after B is pressed. Empty snapshots are not classified.

Weight ROM uses block RAM. The canvas and intermediate values use distributed RAM;
the snapshot uses registers. No RGB framebuffer is allocated. All three inference
read interfaces retain the original two-cycle latency. The core keeps its exact
16-bit constants, 64-bit arithmetic, first-layer bias factor of four, ReLU and
first-digit tie behavior. Inference is 50,903 cycles from core reset release to valid,
approximately 2.036 ms at nominal 25 MHz; wrapper/capture overhead is measured separately.

The procedural renderer follows sequential pixel prefetch from the existing OLED
driver, and supplies settled RGB565 before the serial shifter reloads. Its stream
uses the established R/B swap for the badge's physical BGR panel order.

LEDs: `[7]` panel initialized, `[6]` snapshot/inference busy, `[5]` update pending,
`[4]` prediction valid, `[3:0]` last digit (interpret only with valid set).

## Verification and installation

`make sim` checks all 74 neuron values, cycle count, button behavior, image isolation
and clear during inference. Three full SPI frames are decoded and compared pixel by
pixel against an independent scene renderer. `build/previews.png` shows the supplied
image, blank canvas and palette/cursor/status examples, with a circular screen mask.
The tests establish arithmetic and display behavior, not MNIST test-set accuracy.

`make bit` requires successful placement/routing and timing for both clock domains;
it does not use `--timing-allow-fail`. See `VERIFICATION.md` for the measured build.

Copy only `paint_mnist.bit` to `/fpga/app_bitstreams/paint_mnist.bit` on the badge,
then select it in the existing **Load Bitstream** menu. That loader's deferred boot
path releases the RP2350 display hardware before the FPGA takes ownership. Reset
the badge to return to its normal menu. Do not replace MCU firmware. The build script
does not find drives, copy onto the badge, flash configuration storage or change
the existing loader. Physical badge loading and verification remain separate.

## Provenance

`rtl/neural_net.v` is copied from the user's supplied
`EE2026_Project_B-MODs/integration_group_basic_tasks/integration_group_basic_tasks.srcs/sources_1/new/group_task/given_paint/neural_net.v`.
It is retained verbatim. Constants come from that project's `sources_1/imports/res/weights.coe`.
The copied core and supplied model remain subject to their original authors' terms.
`00.coe` is an input fixture, not an asserted ground-truth label.

The pin assignments and PLL structure follow the existing GreyMecha projects.
The display driver is compiled directly from `io/fpga_oled_fast/src`. Its shared
streamer has a corrected final-pixel termination check: the prefetch address is
ahead of the pixel being transmitted, so termination uses a separate current-pixel
counter. The original canvas-transfer code is replaced to
remove its coordinate shift, 19x19 grid and unsafe inference-image updates.
