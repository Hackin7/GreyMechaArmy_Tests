# Software memory profiling

This headless mGBA 0.10.5 profiler records CPU instruction prefetch, scalar
loads/stores, LDM/STM transfers, DMA, and software-renderer graphics reads.
It changes neither the diagnostic ROMs nor the FPGA. Source is pinned to
`26b7884bc25a5933960f3cdcd98bac1ae14d42e2` from the official mGBA repository.

`instrument_mgba.py` produces a patch against that revision, and refuses
another version. Hooks include direct byte reads used by affine backgrounds
and indexed bitmaps, plus word reads used by tilemaps, tiles and sprites.
Renderer host pointers are mapped to actual VRAM/palette/OAM offsets.
Decoded palette lookups and cached OAM/tilemap consumption are not counted
as external reads. Whole unchanged-scanline reuse is disabled, because it
would hide repeated scanout traffic on static diagnostics.

Run inside WSL/Linux, from `emulators/gba`:

```sh
bash tools/memory_profile/build.sh
```

The default source/build directories are in `/tmp`; set
`MGBA_PROFILE_SOURCE` and `MGBA_PROFILE_BUILD` to override them. Building needs
Git, Python 3, CMake, Ninja and a C compiler. mGBA is fetched only if its source
directory is absent. Instrumentation is regenerated from clean Git blobs.

Build a separate control without access hooks, retaining the same rendering
and cartridge settings:

```sh
MGBA_PROFILE_SOURCE=/tmp/greymecha_gba_sources/mgba-profile-control \
MGBA_PROFILE_BUILD=/tmp/greymecha_gba_memory_profile_control \
MGBA_PROFILE_CONTROL_FLAG=--control bash tools/memory_profile/build.sh

python3 tools/memory_profile/run.py \
  --rgb-rom /mnt/c/Users/zunmun/Downloads/GbaRGB-Test-Keyboard-Control.gba \
  --control-binary /tmp/greymecha_gba_memory_profile_control/gba-memory-profile
```

The runner profiles the local diagnostic, Tonc `bld_demo`, and the supplied
RGB test cartridge. It requires the existing `build/roms` artifacts. Each
ROM runs for 180 emulated frames: 30 boot, 60 baseline, and 90 scripted input
frames. Both the board's open BIOS and mGBA's internal BIOS control are run.
The ROM is forced to cartridge memory: mGBA would otherwise classify the
minimal diagnostic header as multiboot and overwrite its executing code
with RAM tests. Logo-CRC-based BIOS skipping is disabled to match the FPGA.

Instrumented and unhooked controls must match final PC, frame counter,
framebuffer/VRAM/IWRAM/EWRAM checksums, and the diagnostic save report. Cache
self-tests cover LRU replacement, hit/miss accounting, invalidation, mirrored
addresses and filtering. All six measured ROM/BIOS combinations matched on
2026-10-13. The diagnostic returns `0x7bf` in mGBA: its upper-VRAM byte-write
check differs from the FPGA's `0x7ff`; arithmetic, shift and bank errors are zero.

Reports contain per-region/source counts, bytes, adjacent accesses, hot
64-byte blocks, VRAM heatmaps, per-frame read/write counts and hypothetical
cache results. CPU/DMA writes invalidate matching cached lines; writes do
not allocate. ROM models use 8-byte lines and a one-block 256-byte flash
backend. VRAM models cover **only the external lower 64 KiB**, with unified,
PPU-only and CPU-only alternatives. The 16-byte four-way LRU reference is
an approximation, not the actual four-requester FPGA cache. Wider line
misses represent a full-line burst; their fetched bytes are reported too.

Generate charts/report with Python plus matplotlib/numpy:

```sh
python3 tools/memory_profile/report.py build/memory-profile
```

The saved measurements and figures are in
`validation/memory-profile-2026-10-13/`. They predict locality and cache miss
rates, **not FPGA FPS**: mGBA schedules CPU/DMA/rendering differently, retains
some renderer caches and does not reproduce our serialized renderer or SPI
arbitration. No hardware access, synthesis, or board upload is involved.
