"""GreyMecha ROM picker and clean-reset handoff."""
import os
import time

APP_PATH = '/apps/gba/'
INSTALL_MAGIC = 0xae
LAUNCH_MAGIC = 0xaf
ERROR_MAGIC = 0xb0


def validate_rom(path):
    if not path.startswith(APP_PATH) or '..' in path.split('/'):
        raise ValueError('ROM must be inside /apps/gba')
    size = os.stat(path)[6]
    if not 192 <= size <= 8 * 1024 * 1024:
        raise ValueError('ROM must be 192 bytes to 8 MiB')
    return size


def list_roms():
    result = []
    for directory in (APP_PATH, APP_PATH + 'games/'):
        try:
            names = sorted(os.listdir(directory))
        except OSError:
            continue
        for name in names:
            if name.lower().endswith('.gba'):
                path = directory + name
                try:
                    validate_rom(path)
                    result.append(path)
                except (OSError, ValueError):
                    pass
    return result


def defer(magic, text):
    import microcontroller
    encoded = text.encode('utf-8')
    nvm = microcontroller.nvm
    if not encoded or len(encoded) > min(253, len(nvm) - 2):
        raise ValueError('Launch path is too long')
    # Publish the marker last so a partial payload cannot launch an old path.
    nvm[0] = 0
    nvm[2:2 + len(encoded)] = encoded
    nvm[1] = len(encoded)
    nvm[0] = magic
    microcontroller.reset()


def program_rom_app(hw_state=None, rom_path=None):
    if rom_path is None:
        choices = list_roms()
        if hw_state is None:
            if not choices:
                raise RuntimeError('No GBA ROMs found')
            rom_path = choices[0]
        else:
            from apps.bitstream_loader import _draw, _wrap
            buttons = hw_state['fpga_overlay'].set_mode_buttons()
            current = 0
            _draw(hw_state, 'Game Boy Advance',
                  _wrap(choices[0].rsplit('/', 1)[-1]) if choices else 'Add .gba files\nto apps/gba/games')
            # Require release of the button that opened this picker.
            while not hw_state['btn_action'][0].value:
                time.sleep(0.02)
            held = False
            next_move = 0
            while True:
                if not hw_state['btn_action'][1].value:
                    return
                if choices and not hw_state['btn_action'][0].value:
                    rom_path = choices[current]
                    break
                direction = -1 if not buttons[0].value else (1 if not buttons[4].value else 0)
                now = time.monotonic()
                if direction and (not held or now >= next_move):
                    if choices:
                        current = (current + direction) % len(choices)
                        _draw(hw_state, 'Game Boy Advance', _wrap(choices[current].rsplit('/', 1)[-1]))
                    next_move = now + (0.2 if held else 0.4)
                held = bool(direction)
                time.sleep(0.02)
    validate_rom(rom_path)
    if os.stat(APP_PATH + 'open_bios.bin')[6] != 16384:
        raise ValueError('GBA BIOS must be 16 KiB')
    os.stat(APP_PATH + 'gba.bit')
    defer(INSTALL_MAGIC, rom_path)
