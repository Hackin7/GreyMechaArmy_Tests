# bitstream_loader.py — on-badge picker for FPGA bitstreams.
#
# Lists every .bit under /fpga/app_bitstreams/, lets the user scroll
# with the FPGA D-pad and press A to flash the chosen file via
# hardware.fpga.upload_bitstream(...). B returns to the parent menu
# without flashing.
#
# Source of truth lives in the mecha_fpga_loader/ repo folder; the
# on-badge copy at /apps/bitstream_loader.py is a deployed snapshot.
import os
import gc
import time

import board
import digitalio
import displayio
import microcontroller
import supervisor
import terminalio
from adafruit_display_text import label

import hardware.fpga

BITSTREAM_DIR = "/fpga/app_bitstreams"

# Pending-load marker lives in microcontroller.nvm (NOT on the filesystem
# — CircuitPython mounts the FS read-only from the Python side while USB
# is plugged in). Layout:
#   nvm[0]            = 0xAA when a load is pending, 0x00 otherwise
#   nvm[1]            = length L of the UTF-8 path (1..253)
#   nvm[2:2+L]        = path bytes
NVM_MAGIC = 0xAA


def _draw(hw_state, header, body):
    """Replace the current root_group child with a 2-line label group."""
    main = hw_state["display"].root_group
    try:
        main.pop()
    except Exception:
        pass

    header_label = label.Label(
        terminalio.FONT, text=header, color=0xFFFF00,
        anchor_point=(0.5, 0.5), anchored_position=(0, 0))
    header_label.y = -20

    body_label = label.Label(
        terminalio.FONT, text=body, color=0xFFFF00,
        anchor_point=(0.5, 0.5), anchored_position=(0, 0))
    body_label.y = 15

    direction = label.Label(
        terminalio.FONT, text="< >  A/B", color=0xFFFF00,
        anchor_point=(0.5, 0.5), anchored_position=(0, 0))
    direction.y = 50

    grp = displayio.Group(scale=2)
    grp.append(header_label)
    grp.append(body_label)
    grp.append(direction)
    main.append(grp)
    grp.x = 120
    grp.y = 120


def _list_bitstreams():
    try:
        names = [n for n in os.listdir(BITSTREAM_DIR) if n.endswith(".bit")]
    except OSError:
        return []
    names.sort()
    return names


def bitstream_loader(hw_state):
    # Brief splash before the picker. Just long enough to release the
    # action button after entering and to let the display settle.
    _draw(hw_state, "Bitstream", "Loader")
    time.sleep(0.5)

    files = _list_bitstreams()

    if not files:
        # Empty / missing dir — show a message and wait for any action button.
        _draw(hw_state, "No Bitstreams", BITSTREAM_DIR)
        while True:
            if hw_state["btn_action"][0].value is False:
                break
            if hw_state["btn_action"][1].value is False:
                break
            time.sleep(0.05)
        time.sleep(0.3)
        return

    curr = 0
    _draw(hw_state, "Load Bitstream", files[curr])

    fpga_buttons = hw_state["fpga_overlay"].set_mode_buttons()

    while True:
        moved = False
        if fpga_buttons[0].value is False:
            curr = (curr - 1) % len(files)
            moved = True
        elif fpga_buttons[4].value is False:
            curr = (curr + 1) % len(files)
            moved = True

        if moved:
            _draw(hw_state, "Load Bitstream", files[curr])
            time.sleep(0.3)
            continue

        # B = back, no flash.
        if hw_state["btn_action"][1].value is False:
            time.sleep(0.3)
            return

        # A = select + flash.
        if hw_state["btn_action"][0].value is False:
            chosen = BITSTREAM_DIR + "/" + files[curr]

            # Deferred-load: from inside a running code.py, the supervisor
            # has not cleaned up busio/DMA/PIO state, so calling
            # upload_bitstream here leaves the FPGA in a half-running state
            # that can't drive the OLED reliably. Empirically: even with
            # release_displays + the full overlay deinit chain, OLED
            # bitstreams stay dark — but the same upload via run.py at the
            # REPL works fine.
            #
            # Workaround: persist the chosen path in microcontroller.nvm,
            # then supervisor.reload() to trigger a clean soft-reset.
            # code.py picks up the marker on boot (before any display init)
            # and runs upload_bitstream from the post-supervisor-cleanup
            # state, exactly like run.py does.
            encoded = chosen.encode("utf-8")
            nvm = microcontroller.nvm
            if 2 + len(encoded) > len(nvm):
                # Path too long — bail loudly rather than silently fail.
                _draw(hw_state, "Path too long", "for nvm")
                time.sleep(2)
                return
            nvm[0:2] = bytes((NVM_MAGIC, len(encoded)))
            nvm[2:2 + len(encoded)] = encoded

            supervisor.reload()

        time.sleep(0.02)
