# OV7670 camera on GreyMecha

Standalone ECP5-25K demo for a **parallel OV7670 breakout without FIFO** and
GreyMecha's GC9A01 round screen. The FPGA initializes the sensor, captures
160x120 RGB565, and shows it at native size, centered at `(40,60)` on the
240x240 panel. The entire image fits inside the visible circle.

Grey toggles a saturating RGB offset correction. This is a demonstration on
the camera's already processed RGB output, **not raw Bayer black-level
calibration**. The camera's exposure, gain, white balance and gamma remain
enabled. There is no recording, external RAM or Python pixel streaming.

## Wiring

**Power off before wiring.** Verify the module's actual pin labels, the badge
revision and pad-1 orientation. GreyMecha's headers are **not standard PMOD
power layouts**. Camera modules have different physical pin orders; the
table names sensor signals, not camera connector pin numbers.

The [published PCB](https://github.com/NUSGreyhats/greybadge25/blob/main/hardware/greybadge_pcb/greybadge_pcb.kicad_pcb)
connects J1/J2 pads 1 and 2 to +3V3, pads 3 and 4 to GND, and FPGA I/O-bank
supplies to +3V3. `tools/verify_board.py` checks the mapping against a downloaded
copy of that PCB. This does not establish the voltage of a different physical
board revision. This design uses `LVCMOS33`, rather than the older display
demos' `LVCMOS25` constraints.

Use a regulated breakout with compatible logic levels. A module accepting
3.3 V **power** does not necessarily accept 3.3 V on sensor **signal** pins.
Check its schematic/datasheet; add suitable level translation on FPGA outputs
and SCCB if required. Never connect a bare OV7670 sensor die directly to
3.3 V supplies or assume 5 V tolerance. Pull SIOD up externally
(typically 4.7 kOhm) to the module's permitted I/O rail; verify that its high
level meets the FPGA's LVCMOS33 input requirement. SIOD uses open drain;
the FPGA actively drives the single-master SIOC clock. Configuration runs
at nominal 10 kHz. Weak FPGA pull-ups alone are not the intended SIOD
termination. Use short wires and local module decoupling.

| OV7670 signal | GreyMecha connector pad | FPGA ball | RTL port |
| --- | --- | --- | --- |
| D0 (least significant bit) | J1 8 | B9 | cam_data[0] |
| D1 | J2 8 | B13 | cam_data[1] |
| D2 | J1 10 | B8 | cam_data[2] |
| D3 | J2 10 | B12 | cam_data[3] |
| D4 | J1 12 | A4 | cam_data[4] |
| D5 | J2 12 | B11 | cam_data[5] |
| D6 | J1 11 | A3 | cam_data[6] |
| D7 (most significant bit) | J2 11 | A11 | cam_data[7] |
| PCLK / PLK | J2 9 | A12 | cam_pclk |
| VSYNC | J2 7 | A13 | cam_vsync |
| HREF / HS | J1 7 | A9 | cam_href |
| XCLK / XLK | J1 9 | A8 | cam_xclk |
| SIOC / SCL | J2 5 | A14 | cam_sioc |
| SIOD / SDA | J1 5 | A10 | cam_siod |
| RESET# / RET | J2 6 | B14 | cam_reset_n |
| PWDN | J1 6 | B10 | cam_pwdn |
| Compatible module supply input | J1 or J2 1/2 | supply | +3V3 |
| GND | J1 or J2 3/4 | ground | GND |

This is the user's revised harness mapping. `RET` is interpreted as RESET#,
`PLK` as PCLK, `HS` as HREF, and `XLK` as XCLK. Earlier bitstreams use a
different mapping and must be replaced with the rebuilt bitstream.

PWDN is held low. RESET# is held low during startup, then released. XCLK is
nominally 12.5 MHz, 50% duty cycle. Both expansion connectors are dedicated
to this camera; disconnect other peripherals first.

## Build and run

Requires GNU Make, Python 3, Icarus Verilog, Yosys, nextpnr-ecp5 with its device
database, and Project Trellis `ecppack` (for example, OSS CAD Suite).

```sh
cd addons_pmods/fpga_ov7670
make sim
make bit
```

Output: `build/fpga_ov7670.bit`. Build logs and the timing report stay in
`build/`. The build fails if either checked clock misses timing or the frame
buffers no longer infer the expected block RAM. To keep sensor color bars
on screen for wiring checks, build `make bit HOLD_COLOR_BARS=1`. Rebuild with
`HOLD_COLOR_BARS=0` to return to automatic bars followed by live video.
The Makefile tracks these parameter changes without requiring `make clean`.
The revised harness uses validated placement seed `PNR_SEED=3`; seed changes
also trigger routing again, and failed builds discard incomplete targets.

Copy the bitstream and `badge/main.py` to:

```text
/fpga/app_bitstreams/fpga_ov7670.bit
/apps/ov7670/main.py
```

Stop the normal badge program with Ctrl-C and run from the CircuitPython REPL:

```python
exec(open('/apps/ov7670/main.py').read())
```

Only the bitstream is required for the existing **Load Bitstream** menu.
The optional launcher releases display, overlay/button and JTAG resources before RAM
configuration; it does not replace `code.py`, modify firmware or program
configuration flash. Ctrl-C stops the launcher loop but leaves FPGA capture
running. Restart normal badge firmware to restore its display/FPGA program.

The existing `mecha_fpga_loader` **Load Bitstream** picker uses that directory:
select `fpga_ov7670.bit`. Use that loader's
established deferred-load path if loading from the running menu. As documented
there, direct display takeover from an already-running menu may retain
supervisor-owned resources even after Python teardown; a fresh REPL or the
deferred loader avoids that condition. No changes to the loader are needed.

## Controls and LEDs

| Control | Action |
| --- | --- |
| Grey, D12 | Toggle correction (initially off) |
| Left, B4 | Offset -4, minimum 0 |
| Right, B6 | Offset +4, maximum 64 |
| Reset, C12 | Restart sensor/display and restore offset 16, correction off |

Buttons debounce independently for nominally 20 ms. Holds act once; opposing
simultaneous left/right presses cancel. Changes become visible between LCD
frames, so a frame never mixes correction settings.

| LED bit | Meaning |
| --- | --- |
| 0 | Sensor configuration and display initialization complete |
| 1 | A complete camera frame was accepted within the last nominal second |
| 2 | Correction enabled |
| 5:3 | Offset divided by 16 (coarse level 0..4; each button step is still 4) |
| 6 | Malformed camera frame seen since reset (sticky) |
| 7 | Sensor initialization failed, or configured camera has no recent frame |

LED 7 can light briefly during initial frame acquisition. A missing camera
produces an SCCB error; a configured camera with missing PCLK/HREF/VSYNC goes
stale. The last complete image stays visible when video stops. LED 6 clears
on reset. SCCB retries each failed transaction up to three attempts; bad IDs
stop initialization. Expected sensor registers are PID 0x76 and VER 0x73.
`ov7670_config.error_code` distinguishes NACK (1), PID (2), and version (3)
in simulation/debug; the board LED combines initialization failures.

## Pixel and clock behavior

```text
OV7670 -> PCLK capture -> three RGB565 buffers -> image-only GC9A01 SPI
              Grey / left / right -> frame-latched RGB offset correction
```

The default build targets approximately 30 distinct images/s; it is not a
hardware-qualified frame-rate guarantee. Select a timing profile explicitly:

| `TIMING_PROFILE` | CLKRC (0x11) | DBLV (0x6b) | Purpose |
| --- | --- | --- | --- |
| 0 | 0x01, divide by 2 | 0x0a, bypass | Previously working sensor timing |
| 1 | 0x00, divide by 1 | 0x0a, bypass | Intermediate clock qualification |
| 2 (default) | 0x00, divide by 1 | 0x4a, PLL x4 | Approximately 30 FPS candidate |

Example: `make bit TIMING_PROFILE=1 BUILD=build/profile1`. The Makefile tracks
profile changes. CLKRC is reapplied after RGB setup. COM11 is explicitly 0x12:
AEC and automatic banding remain enabled, but night-mode frame-length extension
is disabled. AEC, AGC, AWB and the normal internal RGB processing remain on.
Limited exposure time can make dim scenes darker or noisier. Register definitions
were checked against the [Linux OV7670 driver](https://github.com/torvalds/linux/blob/master/drivers/media/i2c/ov7670.c)
(DBLV_BYPASS/DBLV_X4, CLKRC and COM11_NIGHT).

System clock and panel SPI remain nominally 50 and 25 MHz. XCLK remains the
working divide-by-four output, approximately 12.9 MHz in the nextpnr oscillator
model. Internal oscillator tolerance affects all clocks and timers. PCLK has its
own conservative 12.5 MHz timing constraint. External camera data setup/hold,
clock duty cycle and wire signal integrity still need hardware verification;
internal Fmax checks alone do not establish input timing.

Boot resets the sensor, verifies PID 0x76 / VER 0x73 at SCCB address 0x21,
programs RGB565 QQVGA, displays sensor color bars for two nominal seconds,
then switches to live video. Exact 320-byte lines and 120-line frames are
required. Malformed frames are discarded without publishing partial images.

Live color processing uses the Linux OV7670 RGB565 matrix and reference AWB
setup, including nonzero initial red/blue gains. Sensor-generated bars bypass
parts of live processing: validate actual red, green and blue objects as well
as bars after changing this configuration. Final panel transport exchanges
red/blue fields to match this panel's observed bar order; RAM and ISP use RGB.

Three images contain 115,200 bytes. Buffers use 19 + 19 + 18 block-RAM blocks;
the third buffer's last 768 pixels (1,536 bytes) use distributed RAM. The
initialization ROM is decoded in logic, reserving all 56 block-RAM blocks for
images. Each bank has independent completion/release toggles, synchronized in
the receiving clock domain. Capture cannot reuse a bank until it is released.
The display keeps its bank until the final SPI pixel finishes. A newer complete
pending image replaces an older pending image; it never replaces the image
being transmitted. If all banks are occupied, complete incoming frames are
counted as dropped without writing occupied memory.

The display clears all 240x240 pixels to black once. It then programs columns
40..199 and rows 60..179, and sends 19,200 pixels only when a new image is ready.
Each image takes approximately 12 ms at the modeled SPI clock. Borders and the
last complete image remain in the panel's GRAM when capture stops. Before the
first image the panel stays black. Legacy full-screen/fallback-bar modules remain
for regression tests; the top-level uses the image-only path.

The badge panel's observed channel order requires `PANEL_SWAP_RB=1` (now the
default). Raw camera buffers and ISP arithmetic remain RGB565. Only the final
panel transport exchanges the five-bit red and blue fields; green stays intact.
With the correction disabled, sensor bars appeared gray/cyan/yellow/green/
magenta/blue/red/dark gray. A passive PIO capture confirmed the camera words
arrive unchanged at the panel connector, identifying a panel red/blue reversal.
Use `PANEL_SWAP_RB=0` only for a panel verified to accept the unswapped order.
RAM reads have three clock stages. A registered correction stage fits within
the streamer's six-clock prefetch. Correction settings commit at image-transfer
start, and remain constant through that image. RGB565 channels expand through
bit replication, subtract the shared offset with saturation at zero, then
quantize back to RGB565. Bypass preserves the original pixel exactly.

## Verification and hardware acceptance

`make sim` covers exhaustive RGB565 bypass and all 17 offset settings,
button bounce/holds/limits/frame commits, asynchronous capture and buffer
ownership, malformed-frame recovery, stale-image retention, SCCB writes and
reads, identity rejection, NACK retries, bars-to-live transition and diagnostic
bar hold. It decodes three complete SPI frames to check every panel pixel,
including native viewport boundaries, black borders and correction. A separate
panel test checks real initialization commands, two complete frames, safe
boundary/rearm behavior and R/B swapping. That test shortens ROM pauses and
freezes the unused ROM address after initialization to reduce simulation time.
Python
tests check launcher teardown, fresh-session behavior and upload errors.

Hardware checks still require the actual badge and module:

1. Verify rails, logic compatibility, connector orientation and pull-ups with
   power disconnected; then measure supplies and XCLK after power-up.
2. Use `HOLD_COLOR_BARS=1`. Confirm SCCB identity, complete 160x120 frames,
   stable bars, byte/bit order, and no malformed-frame LED. Measure setup/hold
   relative to rising PCLK at the receiving FPGA pins.
3. Restore the normal build. Confirm bars transition to live video, native
   image placement, and correction toggle/adjustment on a dark scene. Reset
   must restore defaults without reloading the FPGA.
4. Interrupt camera data while retaining safe power connections: the complete
   image should remain and LED 1 should clear/LED 7 assert after a second.
5. Run for ten minutes. Record board/module revision, build parameters,
   measured XCLK/PCLK/display SPI rates, fresh camera frames per second,
   display frames per second, malformed frames and visible tearing/artifacts.

No hardware frame rate is promised. Display scanout, sensor exposure timing,
and buffer availability all affect fresh-frame rate. Use a logic analyzer
on VSYNC/HREF/PCLK and panel CS/SCLK to distinguish camera and display rates.
See [VALIDATION.md](VALIDATION.md) for the checks actually run.

## USB diagnostics

The read-only diagnostic SPI port uses RP2350 GP8 as clock, GP10 as MISO,
and GP11 as CS. Each selection snapshots 116 bytes beginning with `CAM2`.
The original prefix and the `PIN1`/`FPS1` extensions are preserved. Bytes
96..115 add `COL1` and eight raw RGB565 words from row 0, x=10,30,..150.
`badge/status.py` decodes the flags, sensor ID, last register/result, NACK
bitmap, PCLK/VSYNC activity, accepted/displayed frames and line geometry.
NACK bitmap bits 0, 1 and 2 refer to device address, register address and
write data respectively; `0x7` means the sensor acknowledged none of them.

For host-driven diagnosis, put `badge/status.py` at `/apps/ov7670/status.py`
and use Windows PowerShell from this folder:

```powershell
.\tools\run_device.ps1 -Port COM3 -SoftReset -File .\badge\load_checked.py
```

`-SoftReset` resets the RP2350 in raw REPL before uploading, clearing display
owners without starting the normal menu. The checked loader requires the
programmer's configuration-status check to succeed, then prints three
diagnostic snapshots. It preserves root `code.py`, firmware and NVM.
`badge/probe_fpga.py` separately reads JTAG DONE/FAIL and shared LCD-pin
activity without reprogramming. Adjust the COM port for the connected badge.

### Rate qualification

The `FPS1` extension at bytes 64..95 contains eight big-endian words: magic,
timing profile, valid captured frames, malformed frames, no-free-bank drops,
replaced pending frames, image transfers started, image transfers completed.
Valid/malformed/drop counters originate in PCLK and cross through registered
Gray codes. The original VSYNC counter remains a sensor-activity indicator;
it is not the same as a complete validated image.

Copy `badge/measure.py` alongside `status.py` on the badge. From a clean raw REPL:

```python
duration_seconds=60  # then repeat with 600
exec(open('/apps/ov7670/measure.py').read())
```

Alternatively use PowerShell from the demo directory:

```powershell
.\tools\measure_device.ps1 -Port COM3 -DurationSeconds 60
.\tools\measure_device.ps1 -Port COM3 -DurationSeconds 600
```

These commands save serial output under `build/` without resetting the FPGA.
The script prints ten-second checkpoints and elapsed-time-based rates.
It excludes sensor startup, validates identity and geometry, checks for stalls,
and passes only with 28..33 valid and displayed images/s, no malformed frames,
and no capture drops or replaced pending images during the interval.

Qualify profiles 0, 1, then 2 using separate build directories. Check sensor ID,
color bars, geometry and errors at every step. Keep the earlier verified
bitstream before replacing `/fpga/app_bitstreams/fpga_ov7670.bit`. Restore that
bitstream if the faster candidate fails; preserve all measurement logs.
Screen color order, tearing and the correction controls still need a visual
hardware check even when counter-based qualification passes.

### Direct RAM loading and physical SPI sampling

If Windows mounts CIRCUITPY read-only, `tools/program_ram.ps1 -Source <bitstream>`
loads FPGA SRAM through the existing JTAG programmer, without disk writes. It
checks the expected badge UID, byte count, SUM32 and FPGA configuration status,
and records the host source SHA256 separately. This does not update the saved
bitstream file on CIRCUITPY. Optional `-ProbePanel` passively captures a SPI line
one second after programming, during the startup sensor bars.

`badge/sniff_panel.py` samples only inputs GP2/GP3/GP4/GP5 using PIO and RX DMA.
It prints the actual transmitted 16-bit words for comparison with the raw
`COL1` samples. Its PIO loop has explicit wrap bounds and a three-second timeout.

For a persistent install onto a Windows read-only badge disk,
`tools/install_bitstream.ps1 -Source <verified-bitstream>` requests Windows UAC
administrator approval. It matches the badge disk by serial number, temporarily
clears only that disk's read-only attribute, writes/verifies the camera bitstream
and helper scripts, then restores the original attribute. It performs no disk
repair or formatting. Inspect `build/badge-install-result.json` for the result.
