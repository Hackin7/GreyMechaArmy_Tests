# Custom PicoRV32 Sandbox

This folder gives you a small firmware entry point that plugs into the existing
PicoRV32 testbench without relying on the top-level `picorv32/Makefile`.

## Files to edit

- `custom/main.c`: your program entry point.
- `custom/start.S`: minimal reset/exit shim used by the testbench.

## Build and run from WSL

From the `custom` directory:

```bash
make test TOOLCHAIN_PREFIX=riscv64-unknown-elf-
```

To generate waveforms and a trace:

```bash
make test_vcd TOOLCHAIN_PREFIX=riscv64-unknown-elf-
```

If your compiler uses another prefix, replace `riscv64-unknown-elf-` with the
prefix you already use in WSL, for example `riscv32-unknown-elf-` or
`riscv-none-elf-`.

## Run from Windows

From PowerShell in the `custom` directory:

```powershell
.\run-custom-wsl.ps1
```

That script auto-detects a common RISC-V GNU prefix inside WSL and runs
`make test` there. You can override both the target and prefix:

```powershell
.\custom\run-custom-wsl.ps1 -Target test_vcd -ToolchainPrefix riscv64-unknown-elf-
```

Extra Make arguments are passed through after the named parameters:

```powershell
.\custom\run-custom-wsl.ps1 -Target test COMPRESSED_ISA=
```

You can also launch it from the parent `picorv32` directory:

```powershell
.\custom\run-custom-wsl.ps1
```

## Pass and fail behavior

- Return `0` from `main()` to print `OK`, mark the test as passed, and trap.
- Return non-zero from `main()` to print `FAIL` and stop in the testbench.

The helper functions declared in `firmware/firmware.h` are available. In
particular, `print_str()`, `print_hex()`, and `print_dec()` write to the same
memory-mapped output used by the stock PicoRV32 tests.
