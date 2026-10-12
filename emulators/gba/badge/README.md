# GreyMecha Game Boy Advance app

The menu app and 25 MHz deployment bundle are installed on GreyMecha.
The default bundle uses the saved, hardware-tested 25 MHz SPI burst image.
Normal badge boot reaches the menu with the GBA entry installed. Picker
navigation and interactive launch still need hands-on verification. Cold BIOS startup
recovery is a workaround, not a fix for the RTL/BIOS startup problem.

Choose **Game Boy Advance**, browse ROMs with Left/Right, press Grey to
start, or Red to return to the menu. ROMs are discovered in `/apps/gba/`
and `/apps/gba/games/`; files outside the supported 192-byte to 8 MiB range
are skipped. The bundle includes the diagnostic and Tonc `bld_demo`.

The launch flow is:

1. The menu validates the ROM, BIOS and bitstream, records the ROM path in
   NVM, and performs a real MCU reset.
2. Before normal menu hardware initialization, marker `0xAE` programs and
   sector-verifies the ROM at flash address `0x100000`. The existing flash
   programmer skips unchanged contents. The display shows installation
   progress and failures. The first MiB of flash is retained.
3. A second reset with marker `0xAF` releases menu display/pin ownership,
   loads `/apps/gba/gba.bit`, initializes GBA memory and enables physical
   buttons. The launcher observes guest execution and advancing frames.
4. If the known BIOS stall persists for eight unchanged, idle status polls,
   it performs up to two warm guest restarts. Hardware faults abort without
   being treated as BIOS stalls. Launch failures use marker `0xB0` to reset
   into an error screen; either action button returns to the normal menu.
   Resetting the badge during normal play also returns to the menu.

No filesystem writes are required from CircuitPython. The path handoff
uses NVM because USB normally mounts CIRCUITPY read-only to the interpreter.
The app uses uniquely named GBA modules to avoid the existing Game Boy
app's `main`/`protocol` module cache collisions.

Prepare a local bundle from the repository's current Game Boy menu snapshot:

```powershell
C:/Python311/python.exe tools/build_badge_app.py
```

The output is `build/gba-menu-app/`, containing the GBA app, saved bitstream,
open BIOS and license, test ROMs and licenses, shared FPGA programmer, patched
root `code.py`, patched `apps/__init__.py`, and a SHA256 manifest. Generation
does not access or program the badge. The default menu files are snapshots;
before deploying, regenerate from the badge's actual current files to preserve
other apps and concurrent menu changes:

```powershell
C:/Python311/python.exe tools/build_badge_app.py --root-code E:/code.py --apps-init E:/apps/__init__.py
```

`--rom PATH` adds a user-supplied ROM under `apps/gba/games/`. `--bit PATH`
selects a different image, such as the preserved 10 MHz image. Menu patching is idempotent and fails on unknown
menu structure instead of silently replacing entries. Merge the bundle into
CIRCUITPY after checking storage capacity and retaining backups of overwritten
files. Do not replace unrelated directories or the badge's `hardware/main.py`.

Hardware verification: normal boot reaches the menu, and the clean-reset
install/launch flow starts `bld_demo` with one automatic BIOS restart and no
reported hardware faults. The boot hook restores the normal module search
path, and bundled Python files omit byte-order marks for CircuitPython.
Remaining checks: complete picker navigation/cancel, progress-screen appearance,
error return, and every physical control. Existing limitations remain: the saved 25 MHz image swaps
red/blue (the source correction requires a new image), no physical audio, and
save memory is initialized on every launch rather than persisted to disk.

Run the host-side menu/NVM/recovery tests with:

```powershell
C:/Python311/python.exe sim/test_badge_app.py
```
