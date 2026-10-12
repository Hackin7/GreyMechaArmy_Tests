# C demo profile: 2026-10-11

Measured on an AMD Ryzen 7 7840HS Windows host using MinGW GCC 13.2.0,
`-std=c11 -O3 -Wall -Wextra -Werror`. These are desktop measurements, not RP2350
measurements. The inference code was separately cross-compiled for Cortex-M33
using GNU Arm Embedded GCC 10.3.1, but no MCU runtime was measured and the full
Pico SDK application was not built or flashed.

The original EE2026 weights were exported without changing the source project:
SHA256 `7f32b2cb7387a670900e4ac6488f06e592603a2a9a45e513f7a6501ddc3002e1`.
Weights occupy 101,780 bytes in SRAM for the profile. The provided `00.coe`
fixture has 119 active pixels and predicts digit 0 in every implementation.

## Results

Median batch-average microseconds per inference, nine batches of 2,000 calls,
five warm-up calls per input/implementation. RAM copies, checking, and printing
are excluded; sparse index collection and the anti-elimination checksum are
included. Full results and batch minimum/maximum values are in the generated
`build/profile.csv`. Measurements remain subject to scheduling and CPU frequency
variation; implementations ran sequentially rather than simultaneously.

| Input | Active pixels | Reference, 64-bit | Conditional adds, 32-bit | Sparse indices, 32-bit |
|---|---:|---:|---:|---:|
| Provided `00.coe` | 119 | 15.606 us | 53.714 us | 6.407 us |
| Blank | 0 | 15.450 us | 50.974 us | 1.342 us |
| Full | 784 | 15.105 us | 38.822 us | 24.324 us |
| Sparse stroke | 55 | 16.216 us | 58.625 us | 3.683 us |
| Mixed | 287 | 14.998 us | 52.674 us | 11.005 us |

Sparse inference is about 2.44 times faster than the reference on the supplied
image, but slower on a full image. Avoiding multiplication with a conditional
branch is not by itself a speedup on this host. Do not extrapolate either these
absolute times or speedup ratios to Cortex-M33.
GCC's optimization report confirmed vectorized first-layer loops in the reference
and sparse implementations, which further limits comparisons with MCU execution.

## Validation

- All 74 neuron values and the digit matched independent Python integer oracles
  for all three implementations on the five fixture/synthetic inputs.
- Eleven additional cases (maximum/minimum constants, negative scores/ties and
  eight random full-range constant sets) passed for all three implementations.
- Strict-warning native GCC and CMake host builds passed.
- All three inference functions cross-compiled for Cortex-M33 with strict warnings.
  Total inference object text is 1,184 bytes. GCC reported stack frames of 56 bytes
  for reference, 296 bytes for conditional adds, and 1,864 bytes for sparse inference.
  These frames exclude their caller's stack; the Pico application reserves 8 KiB.

These checks validate integer inference, not the drawing pipeline or MNIST
test-set accuracy. For context, the isolated original RTL took 50,903 cycles,
about 2.036 ms at 25 MHz, in the earlier simulation.

## Reproduce

```powershell
.\run-demo.ps1 -Iterations 2000
```

Use the Pico SDK build instructions in `README.md` to obtain on-device elapsed
times. The program reports the actual system clock and uses one core. No
RP2350 latency claim can be made from this host profile.
