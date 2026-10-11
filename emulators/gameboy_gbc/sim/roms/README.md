# Blargg CPU instruction ROM fixtures

These 32 KiB binaries are the eleven individual `cpu_instrs` fixtures from
Blargg's Game Boy test ROM collection, mirrored at:

https://github.com/retrio/gb-test-roms/tree/master/cpu_instrs/individual

They are test programs, not commercial game ROMs. The RTL testbench treats
their serial `Passed`/`Failed` output as the result and does not depend on the
display. File integrity is recorded in `SHA256SUMS`.
