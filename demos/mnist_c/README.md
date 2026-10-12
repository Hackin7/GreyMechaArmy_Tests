# Native C digit-recognition demo

This demo reproduces the supplied EE2026 `neural_net.v`: 784 binary pixels,
64 ReLU neurons, and 10 output scores. It preserves signed 16-bit constants,
first-layer bias scaling by four, second-layer bias scaling by one, and the
first winning digit on ties. It does not include drawing, display, or training.

`nn_reference` uses 64-bit accumulators as in the RTL. `nn_binary32` uses
conditional weight addition and a 32-bit first-layer accumulator; the bound
is `(784 + 4) * 32768 = 25,821,184`, so this is exact for binary inputs.
The second layer still accumulates in 64 bits. `nn_sparse32` first collects the
active pixel indices, then adds only those weights for each hidden neuron; this
preprocessing is included in the measured time. Its maximum extra index storage
is 1,568 bytes on the stack. All three implementations return all 74 values so
verification includes every neuron, not just the final digit.

## Run on Windows

From this directory, with Python and MinGW GCC on PATH:

```powershell
.\run-demo.ps1
# More samples per timed batch:
.\run-demo.ps1 -Iterations 1000
# Another copy of the original COE resource directory:
.\run-demo.ps1 -ResourcePath 'D:\path\to\res'
```

The script exports `weights.coe` and the provided `00.coe` image into ignored
`build/generated/` headers, compiles with `-O3`, and saves `build/profile.csv`.
The original source project is read only. Generated model data is not committed.

The exporter computes independent Python integer oracles for the provided image
and four synthetic inputs: blank, full, a sparse stroke, and a mixed pattern.
`00.coe` is a fixture name, not an asserted ground-truth digit label. These checks
establish arithmetic equivalence, not MNIST test-set accuracy.
The Windows script additionally checks all three C implementations against Python
on maximum/minimum 16-bit constants, negative scores/ties, and eight random
full-range constant sets with binary images.

## Timing methodology

Inputs and weights are copied to RAM before profiling. Each implementation and
image gets five warm-up calls and nine timed batches. The CSV reports the median,
minimum, and maximum **batch-average microseconds per inference**. A volatile
checksum prevents calls from being removed; it adds a small cost to each call.
Timers are Windows QueryPerformanceCounter, POSIX CLOCK_MONOTONIC, or the Pico
SDK's `time_us_64()`. Printing, model export, validation, and RAM copies are outside
the timed region. Interrupts are not disabled on the MCU.

GCC may vectorize the host reference loop, while conditional additions depend on
input density. Host speedups and absolute times do not predict Cortex-M33 speed.

## Run on RP2350 with the Pico SDK

Export the data first as above, then configure with an installed Pico SDK:

```powershell
cmake -S . -B build-pico -G Ninja -DMNIST_PICO=ON -DPICO_BOARD=pico2 -DPICO_SDK_PATH='C:/path/to/pico-sdk' -DCMAKE_BUILD_TYPE=Release
cmake --build build-pico
```

`pico2` is the default RP2350 development-board configuration. Use the appropriate
SDK board configuration for the GreyMecha badge. This program uses USB console
output and does not drive badge GPIO or the FPGA. Loading native firmware replaces
the current MCU firmware; the build and host scripts do not flash any device.

The native executable uses one core, reports the actual system clock, waits two
seconds for USB, verifies all three implementations, and measures 100 calls per batch.
Results print once to the USB serial console. Reset to repeat. The generated UF2
can be loaded using the board's normal firmware-loading procedure.

The RP2350 needs 101,780 bytes for the weights in SRAM, 784 bytes for the image,
plus result/stack space and SDK overhead. The Pico target reserves an 8 KiB stack
for the sparse index array and benchmark results. The initial model and test vectors also
occupy flash. Code runs from flash with its normal cache behavior.

Official references: [Pico examples board selection](https://github.com/raspberrypi/pico-examples)
and [Pico SDK timer/clock APIs](https://www.raspberrypi.com/documentation/pico-sdk/hardware.html).
