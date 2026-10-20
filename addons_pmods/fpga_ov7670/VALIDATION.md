# OV7670 demo validation

## Current ISP qualification - 2026-10-20

The five selectable modes are implemented and loaded on GreyMecha. The user
confirmed Gamma, Contrast, Saturation and Sobel appearance, on-screen labels,
Left/Right adjustments, Grey bypass and a stable image without flicker,
tearing or label corruption during Sobel testing.

| Enabled mode | Seconds | Captured FPS | Displayed FPS | Result |
| --- | ---: | ---: | ---: | --- |
| Offset | 60.022 | 31.938 | 31.938 | PASS |
| Gamma | 60.021 | 31.939 | 31.939 | PASS |
| Contrast | 60.022 | 31.922 | 31.922 | PASS |
| Saturation | 60.022 | 31.955 | 31.955 | PASS |
| Sobel | 60.023 | 31.954 | 31.938 | PASS |
| Sobel endurance | 600.016 | 31.948 | 31.946 | PASS |

All completed intervals have zero malformed frames, capture drops, replaced
pending frames, pixel queue waits or recorded issues. The 600-second Sobel
run retains the same enabled mode, sensitivity and presets throughout.
Individual captured/displayed totals can differ by one transfer in flight
at an interval boundary; this is not a dropped frame.

24 RTL test variants and 15 Python tests pass. RTL includes all 256 gamma
inputs for all presets/channels, 83 independent image-reference cases, the
24-clock worker bound, asynchronous buffer ownership, and seven complete
SPI-decoded images with exact labels/windows. Timing passes at 53.527 MHz
system Fmax against 51.669 MHz and 126.342 MHz PCLK Fmax against 12.5 MHz.
The design uses exactly 56 block-RAM blocks. Camera capture/pins/sensor timing
are unchanged; external input setup/hold has not been newly measured.

Candidate: `build/fpga_ov7670.bit`, 712,177 bytes, SHA256
`f57324fde9f0dc3dd39e2c4a994d464eeb7d391ce1e807d1faea5576e3d7feb1`.
Verified FPGA SRAM load, SUM32 13737099. Left running in Sobel 1.000 ON.
The qualified binary is distributed with release `ov7670-v0.2.0`, together
with its SHA256 checksum. The source changes are committed to `main`.
Hardware qualification used FPGA SRAM; no persistent badge-file installation
or flash/NVM changes were made. The previous released bitstream is retained
locally as `build/fpga_ov7670-rollback.bit`.

Completed logs:
- `build/measure-isp-offset-60s.log`
- `build/measure-isp-gamma-60s.log`
- `build/measure-isp-contrast-60s.log`
- `build/measure-isp-saturation-60s.log`
- `build/measure-isp-sobel-60s.log`
- `build/measure-isp-sobel-600s.log`

The sections below retain the implementation and bring-up history.

## 30 FPS implementation — 2026-10-19

The new capture/display path is implemented, built, and now running on the
GreyMecha badge (UID 335CFEB138350510, CircuitPython 9.2.8). USB reconnected as
CIRCUITPY H: / COM3. Profiles 0, 1 and 2 were loaded in sequence using checked
RAM programming; every load returned `FPGA_PROGRAM_VERIFIED True` and the
sensor identified as PID 0x76 / VER 0x73. All reported 320-byte lines, 120-line
frames, zero malformed frames, zero capture drops and zero pending replacements.
Profiles 0/1 delivered roughly 4/8 fresh images per second in bring-up snapshots.

The profile-2 60-second measurement PASSED: over 60.014 seconds, 1,918 validated
camera frames and 1,917 completed display image transfers, or 31.959 / 31.943 FPS.
Malformed frames, no-free-bank drops and replaced pending frames all remained
zero. No stalls or geometry/initialization errors were observed. The one-frame
endpoint difference is a transfer in flight, not a dropped frame.
The first ten-minute measurement was interrupted by a closed USB serial port
after the 190.307-second sample; the last sample had 9,444 validated and displayed
frames and all error/drop counters zero. Reconnection showed counters continuing
at 11,856 frames, without an FPGA reset. This incomplete run is not counted as a
ten-minute pass. The retry was interrupted by the conversation at its last logged
540.870-second sample: 30,711 validated/displayed frames, zero errors/drops.
It also has no complete ten-minute result and is not counted as a pass.
The user confirms a stable live image and working Grey toggle/left/right controls,
but subsequently reports red appearing green. Color correctness is under diagnosis.
External input setup/hold has not been measured.

Device logs: `build/device-fps-profile0.log`, `build/device-fps-profile1.log`,
`build/device-fps-profile2.log`, `build/measure-profile2-60s.log`.
Loaded file: `/fpga/app_bitstreams/fpga_ov7670.bit`, SHA256 verified as
`9da5ed361cafd81bb77df36390035cb01a8ac4ef8b28d361a884f5a0b8d35b3e`.
Only the camera bitstream and helper scripts were replaced on the badge;
firmware, root code.py, NVM and configuration flash were not changed.

### Current automated results

All 16 RTL simulations pass, including all three decoded SCCB profiles,
768-bit atomic diagnostic snapshots, triple-buffer ownership/replacement,
malformed-frame rejection, a full consumer stall with no free buffers, and
reset while PCLK is stopped. The RAM test verifies all 57,600 stored words,
chunk boundaries and distributed tail using asynchronous clocks and three-cycle
reads. The window test decodes the actual panel SPI: all 57,600 initial black
pixels, bounds 40..199 / 60..179, two complete 19,200-pixel transfers, RGB
correction and endpoints. A testbench delta-cycle race at the final CS edge
was corrected by sampling the pin mux after combinational settling.

Four launcher tests and three diagnostic-decoder tests pass. The badge status
and measurement scripts compile with CPython; this is not a substitute for
running them on CircuitPython hardware. The PowerShell measurement wrapper
passes syntax parsing.

Logs: `build/fps-sim-final.log`, `build/window-final.log`, and
`build/fps-regression-complete.log`. The separate window log is the final
window-test result; the earlier interrupted simulation is not counted as a pass.

### Builds and resources

System constraint is 51.668907 MHz; camera PCLK constraint is 12.5 MHz.
All profiles pass synthesis, placement, routing, and the build resource/timing
checks. Seed remains 3. Constraints are internal timing checks, not an external
camera input timing model. The 12.5 MHz PCLK constraint must be checked against
measured clock frequency and signal setup/hold before accepting the faster
sensor profile.

| Profile | System Fmax MHz | PCLK Fmax MHz | Bitstream |
| --- | ---: | ---: | --- |
| 0, existing sensor divider | 81.900 | 133.958 | `build/fpga_ov7670-profile0.bit` |
| 1, divider removed | 80.141 | 124.116 | `build/fpga_ov7670-profile1.bit` |
| 2, divider removed + PLL x4 | 83.703 | 137.080 | `build/fpga_ov7670-profile2.bit` |

All profiles use exactly 56 DP16KD blocks plus 192 TRELLIS_DPR16X4 cells for
768 additional RGB565 pixels. Profile 2 uses 3,936 LUT4, 2,550 TRELLIS_FF,
474 CCU2C, one PLL, no DSP. The GC9A01 initialization sequence is explicitly
decoded in logic, releasing the two ROM RAM blocks needed by the third frame.
Window-only transfers have a modeled payload time of approximately 11.9 ms;
this is a calculation, not measured display performance.

`build/fpga_ov7670.bit` is the profile-2 candidate. The earlier hardware-verified
bitstream was preserved as `build/fpga_ov7670-working.bit` before any rebuild.

SHA256:

- Working rollback: `8971da96cfe8762f4dc6c004ba3a082729de1a73f2297450c19a4a35c075749e`.
- Profile 0: `1e30c143a8a33aa3a9034715df2d9dd83cbe9d8c3a141492dd2d3377ac1fec96`.
- Profile 1: `8e87bb74d8b42dc292dd1b2aacff12de0f7f622b8607668122ac30f340147406`.
- Profile 2: `9da5ed361cafd81bb77df36390035cb01a8ac4ef8b28d361a884f5a0b8d35b3e`.

### Hardware qualification procedure

Load profiles 0, 1, then 2 from the established badge path, checking ID,
sensor color bars, 320-byte lines and 120-line frames at every stage. Keep the
rollback bitstream available and restore it if any qualification fails.
Install the new `status.py`, then run `tools/measure_device.ps1` for 60 and
600 seconds. Acceptance is 28..33 validated captured AND completed displayed
images/s with no malformed frames, capture drops or replaced pending frames.
Check visual colors, tearing, button correction and dark-scene behavior.
The counter-based scripts cannot establish those visual observations.

Clock definitions were checked against the Linux OV7670 driver:
https://github.com/torvalds/linux/blob/master/drivers/media/i2c/ov7670.c
DBLV 0x0a bypass / 0x4a x4; CLKRC divider field; COM11 night-mode bit 0x80.
The local table now explicitly sets COM11=0x12 to avoid night-mode extension
and reapplies CLKRC after RGB configuration. Longer-exposure low-light frame
extension is disabled, so dim scenes can become darker or noisier.

## Historical bring-up results (before the 30 FPS implementation)

The following records refer to earlier builds. Their resource usage, fallback
bars and rate measurements do not describe the new candidate.

Run date: 2026-10-19. Default build: `HOLD_COLOR_BARS=0`, `PANEL_SWAP_RB=0`,
ECP5-25K CABGA256 speed grade 6, placement seed `PNR_SEED=3`.

This build uses the user's revised J1/J2 harness mapping. An additional
per-bank read register separates the RAM depth mux from bank selection;
the viewport and display simulation use the resulting three-cycle RAM read.
All functional simulations and routing checks pass after this change.
The hardware-debug build additionally uses a nominal 50 MHz system clock,
10 kHz SCCB with driven SIOC, stronger XCLK drive, visible fallback bars,
and a read-only USB-accessible SPI diagnostic snapshot.

## Tools

Portable OSS CAD Suite release `2026-10-18`, run under WSL:

- Yosys `0.70+157`, commit `af9f71e51`.
- nextpnr-ecp5 `0.11.1-65-ge677d5c3`.
- Icarus Verilog `14.0 (devel)`, `s20260301-596-gad0260be5-dirty`.
- Project Trellis `ecppack` from the same suite.

The tools were extracted into a temporary directory; no global system tool
installation or existing application source was changed.

## Automated results

| Check | Result |
| --- | --- |
| RGB565 bypass, all 65,536 inputs | PASS |
| All 65,536 inputs at each offset 0,4,...,64 | PASS |
| Button bounce, hold, bounds, simultaneous directions, frame commits, reset | PASS |
| Asynchronous capture/read clocks, byte order, buffer ownership and skipped frames | PASS |
| Odd/long lines, extra/missing rows, empty frames, recovery | PASS |
| Retention of last complete frame and reset with stopped PCLK | PASS |
| Three decoded full display frames: fallback bars, native image, corrected image | PASS |
| Real panel initialization/rearm, two full frames and R/B swap | PASS |
| SCCB transaction decoding, register reads, identity checks, NACK retries/recovery | PASS |
| Automatic bars-to-live and held-color-bars diagnostic mode | PASS |
| Diagnostic SPI snapshots and camera activity/geometry monitor | PASS |
| Four Python launcher ownership/failure tests, including actual overlay reset ownership | PASS |
| Yosys synthesis and structural checks | PASS |
| nextpnr placement/routing and build-check script | PASS |
| Bitstream generation | PASS |
| Published J1/J2 pads and FPGA bank supplies | PASS |

The panel test shortens precomputed initialization ROM pauses and freezes
the unused ROM address after initialization; initialization SPI commands,
stream sequencing and rearm logic are exercised.
Capture simulations use a smaller parameterized frame to exercise ownership
and malformed-frame cases; display simulations use the actual 240x240 panel
and 160x120 viewport.

Commands: `make -j2 sim`, targeted updated capture/panel regressions,
`make bit`, and `python3 tools/verify_board.py <downloaded-public-PCB>`.
Raw logs, simulation outputs, synthesis netlist and timing report are ignored
build artifacts under `build/`.

## Routed resources and timing

- Framebuffers: **40 / 56 DP16KD blocks** (71.4%); 76,800 image bytes.
- Synthesis: 1,940 LUT4 cells, 1,137 TRELLIS_FF cells, 311 CCU2C cells,
  one PLL and no multiplier blocks.
- System clock: **75.301 MHz achieved**, **51.669 MHz constrained**.
- Camera PCLK: **142.531 MHz achieved**, **12.500 MHz constrained**.

The system PLL now uses a nominal 50 MHz output for hardware bring-up;
nextpnr derives approximately 51.669 MHz from the internal oscillator model.
The build passes that derived constraint with margin.
PCLK is asynchronous and independently constrained. Its achieved Fmax is
internal timing headroom, not an instruction to run the camera at that rate.
External sensor data setup/hold and actual oscillator tolerance remain
hardware acceptance items.

Output: `build/fpga_ov7670.bit`, 675,089 bytes.

SHA-256:

```text
224c130a9a0b98e10681fafaff404236ea4b6e40212324a437f4200927a453dd
```

The public PCB was fetched from the main-branch URL linked in the README.
Downloaded PCB SHA-256:

```text
fc07282a34a26bc0a1bd4a4174c8da51c624d656f1bb8df3b9faf0cbf72c6ad8
```

## Hardware debugging results

Connected GreyMecha UID `335cfeb138350510`, CircuitPython 9.2.8, COM3.
The final image was flushed to
`/fpga/app_bitstreams/fpga_ov7670.bit` and loaded from a clean raw REPL.
The programmer returned `True`; independent JTAG readback showed
`0x00400100`, DONE set and FAIL clear.

Initially all five RP2350 LCD pins were still allocated. After clean-reset
loading they were available as inputs: SCLK 237/512 high samples, MOSI
126/512, DC 512/512, CS 0/512, RESET 512/512. This verifies pin handoff and
active FPGA SPI output, not the panel's visual appearance.

Three snapshots one second apart showed `display_frames` 55, 83, 111,
`display_ready=True`, and PLL locked. The camera did not respond:
`configured=False`, `error_code=1`, last register `0x12`, NACK bitmap `0x7`,
and zero PCLK edges, VSYNC frames and accepted camera frames. LED bitmap
was `0x88`. The same failure occurred before and after reducing SCCB from
100 kHz to 10 kHz, driving SIOC actively and strengthening XCLK.

These observations do not establish the cause of the missing camera
response. Module power, common ground, reset/power-down wiring, clock at
the module and sensor condition need physical verification.

## Hardware acceptance still required

Latest successful load: `build/device-window.log`, bitstream SHA256
`8971da96cfe8762f4dc6c004ba3a082729de1a73f2297450c19a4a35c075749e`.
Changing HSTART/HSTOP/HREF from 13/01/b6 to 16/04/24 aligns the
horizontal window with downsampling. Hardware now reports exactly 320 bytes
and 120 lines, frame_valid=True, active=True, malformed=False, error_code=0.
Accepted-frame counters increase 3,6,8 while display counters increase
55,84,112. The sensor transitions from color bars to live=True. Identity is
0x76/0x73. Programming verified True. This supersedes the 319-byte failure
below. Display appearance, color ordering and ten-minute stability still
require verification. System/PCLK timing achieved 77.58/159.80 MHz against
51.67/12.5 MHz constraints; framebuffer usage remains 40 DP16KD blocks.

The user subsequently corrected the harness mapping: RESET is B14 and
PWDN is B10; data pins are D0=B9, D1=B13, D2=B8, D3=B12, D4=A4,
D5=B11, D6=A3, D7=A11. With those constraints, programming verified and
the sensor identified as PID 0x76 / VER 0x73, with no SCCB errors. All
eight data inputs, PCLK, HREF and VSYNC show transitions. Initial measured
geometry is 120 lines, 319 bytes per line; capture correctly rejects these
incomplete frames. Log: `build/device-corrected-pins.log`. This supersedes
the no-response observations below, which used the earlier user pinout.

Diagnostic snapshots now extend to 64 bytes. Bytes 32..35 are `PIN1`,
36..37 are sampled input levels, 38..39 are sticky activity bits, and
40..63 are twelve big-endian 16-bit rising-edge counters, highest pin first.
Pin bit order 0..11: PCLK, VSYNC, HREF, D0..D7, SDA. Counters wrap modulo
65536 and sample at the system clock, so they are diagnostic activity
indicators, not a calibrated frequency measurement. Outputs remain driven
only on their assigned output pins. Pin monitor simulation and 512-bit SPI
snapshot simulation pass; all ten RTL tests and four launcher tests pass.

Additional address-scan diagnostic loaded successfully from
`/fpga/app_bitstreams/fpga_ov7670.bit`, SHA256
`6bd611124a3308cdcb404a3f18d0084f6a4a884743736cfb29015f19d1fcc67e`.
The write-address-only scan covered 7-bit addresses 0x08 through 0x77,
with STOP after every address and no register payload. All 112 addresses
NACKed. SDA sampled high; HREF, VSYNC and PCLK sampled low. Commanded
RESET=1 and PWDN=0; sampled internal XCLK changes between snapshots.
Output commands are not physical pad measurements. Display counters
continue at approximately 28 frames/s; camera edge/frame counters remain zero.
Log: `build/device-scan.log`. Scan simulation covers responding address 0x21,
all-NACK operation, enable gating and no automatic repeat after completion.
User confirms 3.3V supply connection and shared ground, without a measured
voltage. User cannot currently visually inspect the panel.

On configuration error, diagnostic bytes 28–31 contain scan-complete/first
ACK address, ACK count, pin levels, and current scan address instead of geometry.
Pin byte bits 7..0 are commanded reset, commanded power-down, internal XCLK,
commanded SCL, SDA input, HREF input, VSYNC input and PCLK input respectively.

Module power and logic compatibility, physical board revision, sensor identity,
visual panel output, color/byte order, camera setup/hold, camera frame rate, button
behavior on the screen and the ten-minute live streaming test are unverified.
Follow the README's hardware acceptance steps and append measurements here;
simulation rates must not be reported as measured camera/display performance.

## Color investigation

Diagnostic build `build/fpga_ov7670-color-diagnostic.bit` holds sensor color
bars and adds a bundled-data color probe with an acknowledged PCLK/system
transfer. The 116-byte SPI snapshot preserves bytes 0..95, then appends
`COL1` and eight big-endian RGB565 samples from x=10,30,..150 of row 0.
The probe and 928-bit snapshot simulations pass; all 17 RTL tests and eight
Python tests pass. Diagnostic routing passes with 56 DP16KD blocks,
system/PCLK Fmax 76.593/121.359 MHz against 51.669/12.5 MHz constraints.

Windows now reports the expected badge disk as read-only, while CircuitPython
also mounts its root read-only. Copying was refused. Runtime remounting is
also refused while USB-visible; no filesystem repair, disk-attribute change,
or badge-file write succeeded. Existing badge bitstream remains the earlier
profile-2 file. The diagnostic was instead loaded directly into FPGA SRAM
using `tools/program_ram.ps1` and the existing `ecp5p.prog_stream/prog_close`
path. It checks board identity/UID, byte count, SUM32, and FPGA configuration
status. Host source SHA256 is recorded separately (not claimed as a device
SHA256 calculation). Configuration verified True, 712177 bytes, SUM32 11229486,
host SHA256 `1fc160b9a685b36016a4e533542f3f62d7258ad22399a8b6b7441a4a701dd7b2`.

Raw color samples, unchanged over three snapshots:
`d69a c6e8 2739 1785 f91d e968 51da 4208`.
These decode as gray/white, yellow, cyan, green, magenta, red, blue, dark gray.
The red cell is RGB565 e968 (R=29,G=11,B=8); green is 1785 (R=2,G=60,B=5).
Log: `build/device-color-probe-raw.log`.

A passive RP2350 PIO sniffer samples actual screen-connector GP2/GP3 SCLK/MOSI,
using GP4/GP5 DC/CS only as inputs. Its RX DMA is armed before starting the
PIO capture; explicit wrap bounds exclude the start handshake. The physical
SPI words at all eight positions EXACTLY match the raw camera samples. All
sampled SCLK bits are high as expected. Log: `build/panel-wire-colors.log`.
This rules out byte/bit changes between capture and the screen connector for
the fixed bars. It does not establish live-camera color-matrix correctness or
the panel's visible interpretation. User was asked for visible bar order.

The bundled gc9a01 Python driver sets MADCTL=0x48, COLMOD=0x05 and INVON;
the copied FPGA initialization sets COLMOD=0x05 and INVON but omits MADCTL.
The sensor currently uses the generic 80/80/00/22/5e/80 matrix; Linux's RGB565
profile uses b3/b3/00/3d/a7/e4. No speculative channel swap, byte reversal,
color-matrix change or panel-inversion change has been applied yet.
## Confirmed panel red/blue mapping and live correction

The user reports the eight diagnostic bars as gray, cyan, yellow, green,
magenta, blue, red, dark gray. This is precisely a red/blue reversal, with
green unchanged. The existing final-transport R/B exchange is now enabled
by default (`PANEL_SWAP_RB=1` in Makefile/top); no sensor matrix, byte-order,
bit-order or inversion changes were applied. Raw RAM/ISP remain RGB565.

All 18 RTL tests and eight Python tests pass, including an added window test
that decodes every pixel with final R/B exchange enabled, in bypass and with
correction. Logs: `build/color-fixed-regression.log`.
The live profile-2 build (`HOLD_COLOR_BARS=0`) passes timing: system 80.684 MHz
and PCLK 139.179 MHz against 51.669/12.5 MHz constraints; still 56 DP16KD.
Log: `build/color-fixed-build.log`.

Loaded into FPGA SRAM using the checked direct programmer: 712177 bytes,
SUM32 11403790, configuration status True. Host source SHA256:
`1f07544921b016813ca9341fff7e971334c5a43ae4f21caa8f5b150683efed3d`.
Current local candidate: `build/fpga_ov7670.bit`.
An immediate passive PIO sample during its startup bars confirms actual
SPI words `d69a 46f8 cf24 2f82 e91f 417d d1ca 4208`, exactly the intended
R/B field exchange of the raw words. The panel's observed reversal therefore
restores the intended visible colors. The final live candidate passed its
60-second measurement: 1,917 valid captured and 1,917 displayed images over
60.016 seconds, or 31.942 FPS each, with zero malformed frames, capture drops,
pending replacements or recorded issues. Log: `build/measure-color-fixed-60s.log`.
The user subsequently reported that red objects still appear green. The
panel swap alone therefore does not fix live-camera color. Its ten-minute
measurement was interrupted for further debugging and is not a pass.

Persistent installation remains blocked by Windows's read-only badge-disk
attribute. The previous on-disk bitstream has not been replaced by the direct
RAM load. `tools/install_bitstream.ps1` is prepared for a guarded installation:
Windows administrator approval, exact badge serial/friendly-name checks,
copy and checksum verification of camera-owned files, then restoration of
the original disk attribute. It performs no formatting or filesystem repair.

## Live color-processing candidate

The attempted persistent installation returned `success: false`, with
"The media is write protected"; no files were installed. FPGA RAM remains
the available programming path.

Compared the sensor table against Linux `drivers/media/i2c/ov7670.c`,
`ov7670_default_regs` and `ov7670_fmt_rgb565`. Changed the six matrix
coefficients from the YUV defaults to b3/b3/00/3d/a7/e4, keeping signs 9e.
Completed AWB initialization (59-5e, 6c-6f), applied reference reserved
color-processing setting b0=84, and replaced zero initial blue/red gains
with 40/60. A zero gain initialization is a plausible source of green
dominance, but the cause is not proven until live hardware observation.
Sensor test bars alone cannot qualify this change.

Decoded SCCB tests pass for profiles 0/1/2 and held bars, checking the RGB
matrix, gain seeds, AWB setting and reserved color-processing write.
Log: `build/rgb-live-sccb.log`. Panel transport R/B exchange remains enabled
because the user's observed test-bar order independently established it.

The candidate passes all 18 RTL and eight Python tests
(`build/rgb-matrix-regression.log`). Build checks pass with 56 DP16KD,
system Fmax 76.359 MHz against 51.669 MHz and PCLK Fmax 135.428 MHz against
12.5 MHz. Artifacts promoted from `/tmp/greymecha-camera-rgb-live`.
Loaded 712,177 bytes directly into FPGA SRAM, configuration verified,
SUM32 11457525; SHA256
`608eeae3957d40500844e8352d4ec90ef0555663281d39d1dbb6f19a7e3ec6e2`.
Logs: `build/rgb-live-build.log`, `build/program-rgb-live.log`.
Current candidate is `build/fpga_ov7670.bit`, also retained separately as
`build/fpga_ov7670-rgb-live.bit`. Persistent badge files remain unchanged.
The user confirmed correct live colors. Startup-bar wire samples changed with
the sensor processing settings and are recorded in the programming log;
they must not be treated as proof of correct live colors.

Candidate 60-second measurement passed: 1,918 valid captured frames
(31.958 FPS), 1,917 displayed images (31.942 FPS), duration 60.016 seconds,
zero malformed frames, capture drops, pending replacements or issues.
Log: `build/measure-rgb-live-60s.log`. The user confirmed actual red, green
and blue objects now have correct live colors with this candidate.

Ten-minute qualification PASSED after that confirmation: 19,172 complete
captured frames and 19,172 displayed images in 600.016 seconds, 31.952 FPS
for both. All 60 samples had valid 320-byte/120-line geometry, active
capture and correct sensor identity. Zero malformed frames, capture drops,
pending replacements or reported issues. Log: `build/measure-rgb-live-600s.log`.
This completes the requested 28-33 FPS capture/display rate and endurance
qualification on the color-corrected candidate. Controls were confirmed
working by the user earlier; tearing was not separately confirmed.
The candidate remains running in FPGA SRAM. Persistent installation is
still blocked by the badge's write-protected filesystem.

## Selectable ISP implementation (camera-isp worktree)

Added mutually exclusive Offset, Gamma, Contrast, Saturation and grayscale
Sobel processing after capture. Up/down select modes; Grey toggles exact
bypass; left/right adjust remembered per-mode presets. Reset restores Offset
16, disabled. Independent 20 ms debounce filters and frame-start commits keep
settings and label consistent for a complete image. LED bits 5:3 now show mode.

The immutable display bank supplies eight tagged neighbor reads per interior
Sobel pixel, avoiding additional line/frame block RAM. A two-entry result queue
and ready/valid SPI shifter replace fixed prefetch timing. Starvation safely
waits with SCLK low between pixels and is counted. The 160x12 border label uses
columns 40..199, rows 40..51, with name, value and ON/OFF; only changed labels
are redrawn and the image address window is restored afterward.

The 116-byte diagnostic prefix is preserved; ISP1 adds 20 bytes for mode,
enable state, five remembered presets, Q8.8 selected value and pixel wait
cycles. Measurement now embeds the host decoder in RAM and can require a
selected/enabled mode; changed settings or unexpected queue waits fail it.

Software validation completed:
- 83 independent software-reference image cases passed: all point-effect
  presets, full-frame bypass/identity, flat fields, horizontal/vertical edges,
  ramps, isolated impulses, Sobel borders and gain/clipping limits.
- Every requested neighbor address was inside the frame; the worker stayed
  within 24 clocks and the two-entry queue handled consumer backpressure.
- All 256 gamma inputs passed for all nine presets and all three channels.
- Controls passed debounce/bounce/hold, atomic commit, opposing events,
  selection wraparound, remembered values, bounds and reset tests.
- SPI shifter passed deliberate startup/between-pixel starvation, exact data,
  final-bit and rearm checks.
- The final post-pipeline full-panel test decoded seven complete 19,200-pixel images,
  exact HUD glyphs/values and address windows, unchanged-label suppression,
  final R/B transport exchange, and zero queue waits.
- Triple-buffer asynchronous ownership/overload/malformed-frame regression,
  all 57,600 RAM words including chunk edges/tail, 1,088-bit atomic diagnostic
  snapshot and fast-profile SCCB initialization tests passed.
- 15 Python tests passed (launcher 4, diagnostics 5, measurement 6), including
  rejecting mode changes, wrong requested mode and queue starvation.

Gamma ROM first required logic-ROM mapping rather than forced distributed
RAM. The first routed build then found an overlong HUD formatting/glyph path;
HUD rendering was split into registered stages and arithmetic division was
removed. The next route isolated a saturation luma-to-gain path; luminance,
channel deltas and products were split into separate stages. The final 83-case
reference regression passes with the pipeline and 24-clock budget checks.

GreyMecha was reconnected on COM3. The candidate is loaded into FPGA SRAM;
hardware frame-rate/endurance and visual-effect qualification are in progress.
The verified release bitstream remains available for rollback. Hardware
acceptance requires 60 seconds per enabled mode and ten minutes in Sobel,
28..33 captured/displayed FPS, zero malformed/drop/wait counters, and visual
confirmation of effects, label, controls, colors and image stability.

Final timing/build: system 53.527 MHz against 51.669 MHz; PCLK 126.342 MHz
against 12.5 MHz, 56 DP16KD blocks. Gamma/font/queue add no block RAM.
Camera input capture, pins and sensor timing are unchanged; no new physical
setup/hold measurement at the receiving pins has been made.
Promoted artifacts from `/tmp/greymecha-camera-isp` to this worktree's build/.
Candidate: 712,177 bytes, SHA256
`f57324fde9f0dc3dd39e2c4a994d464eeb7d391ce1e807d1faea5576e3d7feb1`.
Direct programmer reports FPGA_PROGRAM_VERIFIED True and SUM32 13737099.
Logs: build/isp-build.log, build/program-isp.log.
Rollback copy: build/fpga_ov7670-rollback.bit, release SHA256
`608eeae3957d40500844e8352d4ec90ef0555663281d39d1dbb6f19a7e3ec6e2`.
At this bring-up checkpoint, no release, flash/NVM changes or persistent badge-file installation had been made.

All 24 RTL variants (18 retained, five ISP, expanded diagnostic snapshot) and
15 Python tests pass. Final pipeline logs: build/isp-final-pipeline-tests.log,
build/isp-panel.log, build/isp-extra-tests.log, build/isp-diagnostics-tests.log,
build/isp-legacy-regression.log. User confirmed live image and label work,
and enabled Offset with Grey. Initial diagnostic snapshots show ISP1 mode 0,
enabled True, value 4096, 320-byte/120-line geometry and zero error/drop/wait
counters. No hardware acceptance rate is claimed until a complete timed log.

Hardware qualification, candidate f57324fd:
- Offset enabled: 60.022 seconds, 1,917 valid captured and displayed images,
  31.938 FPS each; zero malformed/drop/replacement/pixel-wait counts or issues.
- Gamma 1.500 enabled: 60.021 seconds, 1,917 captured/displayed images,
  31.939 FPS each, zero errors/drops/waits/issues. User confirmed visible Gamma
  effect works. Logs: build/measure-isp-offset-60s.log and
  build/measure-isp-gamma-60s.log. The initial waiting Offset attempt was
  interrupted before the completed timed run; it is not a separate pass.
- Contrast qualification did not start: the 300-second physical-selection
  wait expired while the badge remained in Gamma ON, value 384. This is a
  waiting/selection timeout, not an algorithm or frame-rate failure. Log:
  build/measure-isp-contrast-60s.log; subsequent compact status is in
  build/status-isp-current.log and shows mode 1, enabled, zero malformed,
  capture-drop and pixel-wait counters.
- Remaining hardware acceptance: visual Contrast/Saturation/Sobel checks,
  Left/Right/bypass adjustment confirmation, 60 seconds each for the three
  remaining modes, and ten minutes continuously in enabled Sobel. These
  results must not be inferred from the completed Offset/Gamma runs.
- Left running in Gamma 1.500 ON. At that checkpoint, source edits remained isolated in branch
  camera-isp / .worktrees/camera-isp; no new commit, push or release was made.

User subsequently confirmed Gamma Left/Right adjustments, Grey bypass and
Contrast appearance all work. Diagnostic mode 2, enabled, Q8.8 value 320
(1.250) is confirmed; Contrast timing qualification resumed.

Contrast 1.250 enabled PASSED: 60.022 seconds, 1,916 captured and displayed
images, 31.922 FPS each, zero malformed frames, capture drops, pending
replacements, pixel waits or issues. User confirmed the Contrast effect and
Gamma Left/Right plus Grey bypass controls. Log:
build/measure-isp-contrast-60s.log (completed retry after the selection wait).

User confirmed Saturation appearance works at 1.250. Its initial physical
selection wait had expired; a fresh 60-second measurement started after
diagnostic mode 3 / enabled / value 320 was verified. No algorithm error
was indicated by that waiting timeout.

Saturation 1.250 enabled PASSED: 60.022 seconds, 1,918 captured/displayed
images, 31.955 FPS each; zero malformed frames, capture drops, pending
replacements, pixel waits or issues. Log: build/measure-isp-saturation-60s.log.
User confirmed Saturation effect works. Only Sobel visual/rate/endurance
qualification remains.

User confirmed Sobel grayscale outlines look correct. Its initial mode-selection
wait expired while awaiting physical input; a fresh measurement started after
mode 4 / enabled / Q8.8 value 256 was verified. At the start, cumulative valid
frames exceeded 1,022,000 with zero malformed/drop/replacement/pixel-wait
counters; this alone is not a timed Sobel qualification. Final 60-second and
ten-minute runs are in progress with the same candidate and settings.

Sobel 1.000 enabled, 60-second test PASSED: 60.023 seconds, 1,918 captured
frames (31.954 FPS) and 1,917 displayed images (31.938 FPS), with zero
malformed frames, drops, pending replacements, pixel waits or issues.
Log: build/measure-isp-sobel-60s.log. The one-image endpoint difference is
a transfer in flight, not a dropped frame. The 600-second run is active.
