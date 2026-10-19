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
OV7670 -> PCLK capture -> two RGB565 block-RAM banks -> viewport
       -> RGB offset / bypass -> GC9A01 SPI
              Grey / left / right -> frame-latched settings
```

SCCB uses 7-bit device address 0x21 (wire bytes 0x42/0x43), STOP-separated
register reads and a final master NACK. Boot resets and identifies the sensor,
programs a 640x480 window downsampled by four in each dimension, and enables
RGB565 with the high byte first. It enables sensor color bars for two nominal
seconds, then clears COM17's test-pattern bit for live video.

D0..D7, HREF and VSYNC are sampled together on rising PCLK, using the sensor's
default polarity; they are not independently synchronized. Exact 320-byte
lines and 120-line frames are required. Odd/truncated/long lines and extra or
missing rows are rejected at VSYNC; capture resumes on a new frame boundary.

Two banks hold 76,800 image bytes. A completed bank stays immutable until
the display acknowledges its request between LCD frames. Capture then writes
the old display bank, starting at a later camera frame boundary. If the
display cannot accept a frame, incoming frames are skipped, never partially
overwritten. Cross-domain handshakes have two synchronization stages;
reset asserts asynchronously and releases synchronously in each clock domain.
Before the first complete frame, scanout shows red/green/blue/white test bars
inside the viewport. These are FPGA-generated diagnostic bars, not camera
video. A complete camera frame replaces them automatically.

The viewport uses counters with the streamer's sequential pixel requests.
Its counter, three-stage RAM read and correction stages fit within the streamer's
six-clock prefetch interval. The local streamer fixes a copied-demo endpoint
bug: completion tracks the transmitted last pixel rather than its look-ahead
address. It always transmits all 57,600 panel pixels, including black borders.

Correction expands each RGB565 channel through bit replication, subtracts
the shared 8-bit-domain offset with a floor of zero, and quantizes back to
RGB565. Bypass preserves every original bit. Offset 0 with correction enabled
also preserves every original pixel.

The bring-up build uses a nominal 50 MHz system clock (51.669 MHz in the
nextpnr oscillator model) and nominal 25 MHz panel SPI. Camera XCLK remains
nominally 12.5 MHz using a divide-by-four counter. Internal oscillator
tolerance affects real clocks and timers.
PCLK is constrained independently at a conservative 12.5 MHz, above the
configured divided camera clock rate. Hardware acceptance must also check
camera data setup/hold at the FPGA inputs, XCLK duty/voltage, actual PCLK and
wire signal integrity: internal place-and-route clock checks alone do not
prove the external camera timing. The default panel color swap is disabled;
if measured red/blue bars are reversed after checking sensor byte/data order,
rebuild with `PANEL_SWAP_RB=1`.

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
and the two-bank handoff all affect fresh-frame rate. Use a logic analyzer
on VSYNC/HREF/PCLK and panel CS/SCLK to distinguish camera and display rates.
See [VALIDATION.md](VALIDATION.md) for the checks actually run.

## USB diagnostics

The read-only diagnostic SPI port uses RP2350 GP8 as clock, GP10 as MISO,
and GP11 as CS. Each selection snapshots 32 bytes beginning with `CAM2`.
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
