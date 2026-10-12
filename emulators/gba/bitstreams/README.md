# Saved GBA images

`gba_psram_burst_10mhz.bit` is the completed 565,379-byte GreyMecha GBA
image with four-byte PSRAM bursts at nominal 10 MHz SPI. All routed clocks
pass the speed-grade-6 timing model. Its checksum and resource/timing
details are in the adjacent `.sha256` and `.manifest.json` files.

This image is running on GreyMecha with J1 PSRAM connected. After a warm
guest restart, all eleven diagnostic checks pass (`0x7ff`) with zero
arithmetic, shifter or register-bank errors, and injected keys pass.
The unmodified Tonc `bld_demo` passes graphics-memory and blend-control
checks at about 1.99 captured frames/s. The user confirms the Metroid
images and fence are visible. Physical demo controls still need an explicit
check. Cold startup can stall in the BIOS and require a warm guest restart;
this image does not establish reliable cold boot or completion of the ROM suite.
Recorded evidence is in `../validation/gba-10mhz-hardware-2026-10-12.json`.

The matching pre-CDC PSRAM controller source is preserved as
`gba_psram_burst_10mhz.psram.v`. It was built with the `34f79bc` board sources,
the existing `spi_burst.v` added to the RTL list, and the cached generated
core from the shared-color build. The current main RTL uses the subsequent
25 MHz PHY and should not be described as the exact source of this image.

The saved `gba_psram_burst_25mhz.bit` has completed routing and passes all
clock timing checks using the speed-grade-6 model. It is 568,440 bytes;
its adjacent manifest and checksum identify the tested image.

On 2026-10-12 it was uploaded to GreyMecha with
`GbaRGB-Test-Keyboard-Control.gba`. ROM flash verification and PSRAM boundary
read/write checks passed. After one warm guest restart, the guest advanced
116 captured frames in ten seconds during startup. A later measurement was
68 frames in 10.016 seconds (6.79 FPS). No hardware faults were reported.
Physical controls are enabled. The saved image predates the red/blue fix;
cold-start reliability and full ROM-suite completion remain unresolved.
Evidence: `../validation/gba-25mhz-rgb-hardware-2026-10-12.json`.

The 10 MHz image and its earlier diagnostic/demo evidence remain available.

The cartridge is the unmodified Tonc `bld_demo` ROM built by `make bld-demo`.
To repeat deployment, run the diagnostic with the selected saved bitstream,
then use the `demo` action. The retry option allows up to two warm guest
restarts when the BIOS stalls:

```powershell
python tools/hardware_test.py --bit bitstreams/gba_psram_burst_10mhz.bit --retry-stalled-boot diagnostic --minutes 3
python tools/hardware_test.py --bit bitstreams/gba_psram_burst_10mhz.bit --retry-stalled-boot demo --minutes 3
```
