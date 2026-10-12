# GreyMecha paint MNIST verification — 2026-10-12

The complete ECP5-25K/CABGA256 design was simulated, synthesized, placed, routed
and packed into `paint_mnist.bit`. No badge was flashed or physically tested.
Tools: Yosys 0.65 (`b85cad634782fafac275e5f540c056bfacb2b5d2`) and
nextpnr-ecp5 0.10-5+b1. The packed bitstream is 693,633 bytes; SHA256:
`02d7b00c714926a67f221ade4ddac630b45fdb2afe67e759edf90544a5eaf79c`.

## Routed timing and resources

Both clock domains pass nextpnr timing, with no timing-failure override. The tool
derives the frequencies from the internal oscillator and PLL ratios rather than
assuming the rounded 75/25 MHz values used for user-facing time estimates.

| Clock | Required | Routed maximum |
|---|---:|---:|
| Display, controls and canvas | 77.507 MHz | 79.014 MHz |
| Inference | 25.834 MHz | 61.076 MHz |

| Resource | Used | Available |
|---|---:|---:|
| Block RAM (`DP16KD`) | 48 | 56 |
| Multipliers (`MULT18X18D`) | 9 | 28 |
| Combinational cells (`TRELLIS_COMB`) | 7,952 | 24,288 |
| Flip-flops (`TRELLIS_FF`) | 1,704 | 24,288 |
| Distributed RAM write cells (`TRELLIS_RAMW`) | 178 | 3,036 |

The actual hardware clocks depend on the internal oscillator's tolerance. These
are static timing results, not measurements from a running badge. The source
renderer uses registered scene addresses, parallel caption lookups and a three-cycle
pixel pipeline. Paint commands register addresses before writing RAM; cell-coordinate
comparisons avoid coupling a multiplier and RAM read into the write-enable path.

Raw synthesis and route reports are in `build/yosys.log`, `build/nextpnr.log` and
`build/timing.json`. `scripts/summarize_timing.py` checks both constraints and resource
limits before bitstream packing.

## Functional checks

- Six images passed independent Python integer oracles: supplied `00.coe`, blank,
  full, sparse stroke, mixed pattern and one painted cell at the initial cursor.
  All 64 hidden values, ten scores and the digit matched on each image.
- The existing core asserted valid after exactly **50,903 cycles**. The request
  wrapper completed in 50,912 inference-clock cycles, including synchronization and
  warm-up. At nominal 25 MHz these are 2.03612 ms and 2.03648 ms respectively.
- The integrated 75/25 MHz simulation produced the first painted-cell result
  **2.047049 ms after the raw simulated A press**. Its debounce parameter was
  shortened to three cycles for testing; production adds the configured 5 ms
  debounce and subsequent updates can wait for the nominal 100 ms cooldown.
- Independent button debounce, bounce rejection, release detection, immediate and
  repeated diagonal movement, opposite-direction cancellation, boundary clamping,
  colour selection, held painting, snapshot isolation and update cooldown passed.
- Clear with A held leaves the canvas blank until A is released. Clear during
  inference rejects the stale result. Continued drawing while inference runs
  produces another snapshot without modifying the one currently being read.
- Booting with the loader's A button still held produces no accidental stroke;
  a debounced release is required before drawing.
- Three full panel frames each contained exactly **57,600 pixels**. Every decoded
  RGB565 pixel matched an independent reference scene, including the physical BGR
  swap, palette selection border, cursor, supplied image, blank indicator and
  prediction/update text. All visible content fits the circular screen.
- The generated round previews were visually inspected. See `build/previews.png`.

These checks verify the port and integer arithmetic. They do not establish MNIST
test-set accuracy or physical panel/button behavior on a badge.

## Shared OLED correction

The reused `io/fpga_oled_fast/src/oled_stream.v` previously ended each frame after
57,599 pixels: its prefetch index reached the last address while the previous pixel
was still being transmitted. A separate current-pixel counter now determines frame
completion. The first-pixel/prefetch behavior is unchanged. The existing short
stream regression passed, and the port's three complete SPI frames cover the final
pixel and frame restart behavior.

## Model provenance and reproduction

The copied `neural_net.v` is byte-identical to the supplied EE2026 original.
The unchanged model COE SHA256 is
`7f32b2cb7387a670900e4ac6488f06e592603a2a9a45e513f7a6501ddc3002e1`.
The original source project was not modified.

```powershell
.\demos\paint_mnist_fpga\build-wsl.ps1
```

This reruns the simulations and builds the bitstream using the original COE
resource directory. The installation procedure in `README.md` uses the existing
deferred-load bitstream menu and leaves MCU firmware unchanged.
