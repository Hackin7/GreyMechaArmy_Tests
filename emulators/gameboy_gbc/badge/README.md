# GreyMecha Game Boy app deployment

The same app supports both the GreyMecha menu and direct execution from
Thonny.

## Files on CIRCUITPY

Copy the files to these destinations:

| Repository file | CIRCUITPY destination |
| --- | --- |
| `badge/code.py` | `/code.py` |
| `badge/apps_init.py` | `/apps/__init__.py` |
| `badge/main.py` | `/apps/gameboy_gbc/main.py` |
| `badge/protocol.py` | `/apps/gameboy_gbc/protocol.py` |
| `badge/install_status.py` | `/apps/gameboy_gbc/install_status.py` |
| `badge/hardware/fpga/*.py` | `/hardware/fpga/` (merge into existing hardware package) |
| ROM to install | `/apps/gameboy_gbc/games/game.gb` |
| generated `build/gameboy_gbc_flash.bit` | `/apps/gameboy_gbc/gameboy_gbc_flash.bit` |

The bitstream remains a generated artifact and is not committed.

The supplied FPGA programming files use CircuitPython `rp2pio` and PIO
programs for accelerated bitstream and flash transfers. They include the
`progress=` callback required by the installation screen. Retain the badge's
existing `/hardware/__init__.py` and `/hardware/main.py`; only replace the
matching files inside `/hardware/fpga/`. The standard badge libraries and
`adafruit_pioasm` must be installed. No custom native C module is needed.

`apps_init.py` is a snapshot of the standard GreyMecha app registry with
three Game Boy changes: the import, the menu label, and the selection branch.
If the badge menu has changed since this snapshot, merge those three changes
instead of replacing the whole file.

## Launch from the menu

Choose **Game Boy** to recover the full ROM path recorded in
`installed_rom.txt`, program and verify it at `0x100000`, upload the Game Boy
bitstream, and start the game. The optimized programmer skips sectors and
pages that already contain the requested data.

The full ROM must remain on CIRCUITPY for **Game Boy**. If the recorded source
is missing, the programmer falls back to `games/game.gb`.

This clean-reload handoff is required for reliable FPGA ownership of the
GC9A01 display.

## Launch from Thonny

Open the badge file:

`/apps/gameboy_gbc/main.py`

and press **Run current script**. The `__main__` entry point releases the
CircuitPython display, uploads `gameboy_gbc_flash.bit`, transfers the saved
512-byte cartridge header, and starts the core.

Stop/restart the CircuitPython interpreter before switching back to the normal
menu.

## Install a ROM

From the Thonny REPL:

```python
import sys
sys.path.append("/apps/gameboy_gbc")
import main
main.install_rom("/apps/gameboy_gbc/games/game.gb")
main.app()
```

The installer validates the header and size, then erases, writes, and verifies
only ECP5 flash from `0x100000` upward. The normal configuration area below
`0x100000` is not changed. One ROM of at most 8 MiB is supported.

`installed_rom_header.bin` keeps the 512-byte startup header and
`installed_rom.txt` records the title, size, flash address, mapper, and CGB
mode. Keep the full ROM on CIRCUITPY for the menu's programming step.

During play, ROM cache misses are serviced by FPGA RTL. CircuitPython remains
idle and no cache-fill IRQ traffic is expected.

## Regression modes

The CircuitPython-backed cache remains available with:

```python
main.app(flash_mode=False, cache_mode=True,
         rom_path="/apps/gameboy_gbc/games/game.gb")
```

The BRAM bitstream remains available with `flash_mode=False,
cache_mode=False`.

The BRAM bitstream accepts a maximum 32 KiB ROM. A 32 KiB ROM-only Game Boy
or Game Boy Color image is recommended.
