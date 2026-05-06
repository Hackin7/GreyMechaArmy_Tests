# mecha_fpga_loader

On-badge "Load Bitstream" picker for the GreyMecha/Army CircuitPython
firmware. Drop a `.bit` into `/fpga/app_bitstreams/` over USB, scroll to it
on the OLED menu, press A — the badge runs `hardware.fpga.upload_bitstream(...)`
and the chosen bitstream takes over the FPGA.

This folder is the **source of truth**. The on-badge copies are deployed
snapshots; if the badge gets re-imaged, redeploy from here.

## Files modified on the badge

| Repo path                              | Badge path (`D:/...`)            | Kind   |
| -------------------------------------- | -------------------------------- | ------ |
| `apps/bitstream_loader.py`             | `/apps/bitstream_loader.py`      | new    |
| `apps/__init__.py`                     | `/apps/__init__.py`              | edit   |
| `code.py`                              | `/code.py`                       | edit   |
| —                                      | `/fpga/app_bitstreams/`          | new dir (badge-only, no source) |
| —                                      | `microcontroller.nvm`            | runtime marker (written + cleared by the loader; not a file) |

No changes to `hardware/` or any other app module.

## Why `code.py` had to change

We discovered empirically that `hardware.fpga.upload_bitstream(...)` works
when invoked from the REPL after a Ctrl-C halt (`run.py`,
`scripts/flash_fpga.py`) but does **not** correctly start an OLED-driving
bitstream when called from inside a running `code.py` — even with the full
`displayio.release_displays()` + `display_bus.deinit()` + pin-probe + GP6
reset-pulse + overlay-deinit teardown.

The reason is that CircuitPython's supervisor performs a hardware reset
on Ctrl-C / soft-reset that releases DMA channels, PIO state machines,
and `busio` objects — none of which user code can replicate. Without that
clean state, the JTAG re-program leaves the FPGA in a state where its
`oled_init` can't drive the panel cleanly.

The fix is a **deferred-load**: the loader writes the chosen `.bit` path
into `microcontroller.nvm` (a small flash-backed byte buffer that survives
soft-reset) and calls `supervisor.reload()`. On the next boot, `code.py`
checks the NVM marker *before* importing `hardware.main` (which would
re-init the display) and runs `upload_bitstream(...)` from the same fresh
post-supervisor state that `run.py` enjoys at the REPL.

NVM is used instead of a marker file because CircuitPython's filesystem is
read-only from the Python side while the badge is plugged in via USB —
attempting `open("/fpga/_pending", "w")` raises `OSError: Read-only
filesystem`. NVM bypasses this entirely.

## What changed in `apps/__init__.py`

Three edits, all surgical (the rest of the file is the upstream snapshot):

1. **New import**, alongside the other `apps.*` imports near the top:
   ```python
   import apps.bitstream_loader  # mecha_fpga_loader: on-badge bitstream picker
   ```

2. **New menu option** appended to the `options` list inside `menu()`:
   ```python
   options = [
       "Hi I'm Locked In", "Live Firing", "Animation", "Face", "Music",
       "Brick Game", "Brick Good", "Asteroids", "Spam Game", "Controller",
       "Advent of Code 25",
       "Load Bitstream",  # mecha_fpga_loader entry
   ]
   ```

3. **New select-handler branch**, paired with `Advent of Code 25` (both
   re-acquire `fpga_buttons` after the sub-app reprograms the FPGA):
   ```python
   if options[curr] == "Load Bitstream":
       apps.bitstream_loader.bitstream_loader(hw_state)
       fpga_buttons = hw_state["fpga_overlay"].set_mode_buttons()
   ```

## Bitstream directory layout

`/fpga/app_bitstreams/` is a flat folder of `.bit` files. The loader sorts
filenames alphabetically and shows them one at a time. No metadata, no
sub-folders, no manifest. Names are free-form — call them
`raycasting.bit`, `oled_demo_v2.bit`, whatever.

```
D:/fpga/app_bitstreams/
├── raycasting.bit
├── stonks.bit
└── ...
```

## Deploy

From `io/fpga_oled/` (or any working dir — adjust paths):

```bash
cp ../../mecha_fpga_loader/apps/bitstream_loader.py D:/apps/bitstream_loader.py
cp ../../mecha_fpga_loader/apps/__init__.py        D:/apps/__init__.py
cp ../../mecha_fpga_loader/code.py                  D:/code.py
mkdir -p "D:/fpga/app_bitstreams"
# then drop your .bit files into D:/fpga/app_bitstreams/
```

Soft-reset the badge (Ctrl-D in the REPL on COM17, or unplug/replug) so
`code.py` re-imports `apps`. The new `Load Bitstream` entry shows up at
the end of the main menu.

## Removing the loader

To restore the badge to upstream menu behaviour:

```bash
rm D:/apps/bitstream_loader.py
# revert D:/apps/__init__.py — restore from upstream image, or undo the
# three diff hunks above.
# revert D:/code.py — restore from upstream, or remove the deferred-load
# block at the top.
```

You can keep `/fpga/app_bitstreams/` around even after removal; it's just
a directory.

## Implementation notes

- Display rendering follows the same pattern as `apps/__init__.py:menu_layout()`
  — a `displayio.Group(scale=2)` anchored at `(120, 120)` on the 240×240 OLED.
- Pre-flash teardown matches `apps/aoc25/main.py:49-51`:
  `deinit_mode_buttons()` → `deinit()` → `jtag_rst.deinit()` → `gc.collect()`.
- After flashing, the parent `menu()` loop in `apps/__init__.py` already
  calls `set_mode_buttons()` to re-acquire the D-pad, so the loader does not
  re-init the display itself.
- Buttons used: `fpga_buttons[0]` (left) and `[4]` (right) for navigation,
  `hw_state["btn_action"][0]` (A) to select, `[1]` (B) to cancel. All
  active-low — compare with `.value is False`.
