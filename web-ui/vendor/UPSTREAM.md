# Simulator provenance

## 8bitworkshop HDL runtime and compiler distribution

- Upstream: https://github.com/sehugg/8bitworkshop
- Pinned commit: `09d99f2c3028e27b397df8471baec29975ec154b`
- Source subset: `src/common/hdl/{hdltypes,hdlruntime,vxmlparser}.ts`, `src/common/{util,workertypes}.ts`.
- Browser compiler: `src/worker/wasm/verilator_bin.{js,wasm}`. The executable reports `Verilator 4.205 devel rev UNKNOWN.REV (mod)`; do not describe it as current upstream Verilator.
- Original 8bitworkshop code is copyright Steven E. Hugg and contributors, GPL-3.0. Full license: [8bitworkshop/LICENSE](8bitworkshop/LICENSE), also served as `/simulator/COPYING`.
- Verilator is copyright Wilson Snyder and contributors, licensed LGPL-3.0 or Artistic-2.0. LGPL text is served as `/simulator/VERILATOR-LICENSE`. The upstream fork source is https://github.com/8bitworkshop/verilator; the 4.205 source reference used for licensing is `6c3efcd5d869ba772e4ed1365727e155fd9210da`.

The compiler bytes are pinned from 8bitworkshop, not rebuilt during website builds. Its embedded revision is `UNKNOWN.REV`; a bit-for-bit compiler rebuild is not asserted. The reproducible website build uses the recorded immutable download URLs and SHA-256 hashes. Upstream's legacy Emscripten instructions are retained in `verilator-build.txt` and `verilator-Makefile.local`, from compiler repository commit `b5c38a4ca090434e1ee2304e8b2b0dee0ffa9c2f`. To rebuild the compiler, use the upstream fork and those recipes with a compatible legacy Emscripten toolchain, verify the debug XML contract with the parser, then explicitly re-pin the resulting assets and run all acceptance tests. Modern upstream compiler/XML formats are not interchangeable with this runtime.

`npm run sync:simulator` restores the pinned files and applies two narrowly scoped patches:

1. `hdlruntime.ts`: descending unpacked arrays allocate `abs(high-low)+1` elements. Upstream allocated two fewer elements, corrupting the OLED preset's five-button synchronizer array.
2. `vxmlparser.ts`: pass readmem's radix and optional start/end to the runtime. The pinned compiler omits the radix from XML, so the GreyMecha adapter resolves `$readmemh` versus `$readmemb` from compiler source locations. The board adapter supplies a strict memory loader with whitespace, comments and address support.

`emu.ts` and `hdl/hdlhost.ts` are GreyMecha shims exposing only the error/host interfaces required by this subset. No 8bitworkshop IDE, emulators, unrelated toolchains, or frontend are bundled. The original UMD compiler loader is retained byte-for-byte, with a generated ESM copy that appends only `export default verilator_bin`.

The manifest records both upstream bytes and patched delivery hashes. `verify-simulator-assets.mjs` verifies delivery hashes and the generated loader. Source/assets have explicit Git attributes so checkout line-ending conversion does not invalidate those hashes.

## Official GreyMecha artwork

- Upstream: https://github.com/NUSGreyhats/greybadge25
- Pinned commit: `3ce9bfbf0061ee36e17dca1274c2f65ae9a5bb07`
- Files: `hardware/artwork/greymecha.png`, `hardware/fpga_placement.svg`.
- Credit: NUS Greyhats / GreyCTF 2025; artwork credited by upstream to Shuqing.

Artwork is unmodified. The simulator places labeled functional controls alongside it; it is not a mechanical replica of the PCB. Its framebuffer is clipped only for presentation: tests can inspect the full 240×240 image.
