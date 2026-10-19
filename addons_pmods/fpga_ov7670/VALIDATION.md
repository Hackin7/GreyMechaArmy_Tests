# OV7670 demo validation

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
