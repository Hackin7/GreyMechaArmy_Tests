"""Small displayio status view used by clean-boot flash installers."""

import time
import displayio
import terminalio
from adafruit_display_text import label


class InstallStatus:
    def __init__(self, display, application, hw_state=None):
        self.display = display
        self.hw_state = hw_state
        self.last_update = 0
        self.last_phase = None
        self.last_percent = -1
        self.group = displayio.Group()
        self.background = displayio.Bitmap(display.width, display.height, 1)
        palette = displayio.Palette(1)
        palette[0] = 0x000000
        self.group.append(displayio.TileGrid(self.background,
                                              pixel_shader=palette))
        self.title = label.Label(
            terminalio.FONT, text=application, color=0xFFFFFF,
            anchor_point=(0.5, 0.0),
            anchored_position=(display.width // 2, 18), scale=2)
        self.phase = label.Label(
            terminalio.FONT, text="Preparing", color=0x80D8FF,
            anchor_point=(0.5, 0.0),
            anchored_position=(display.width // 2, 62))
        self.percent = label.Label(
            terminalio.FONT, text="0%", color=0xFFFFFF,
            anchor_point=(0.5, 0.0),
            anchored_position=(display.width // 2, 91), scale=2)
        self.sectors = label.Label(
            terminalio.FONT, text="0 / 0 sectors", color=0xB0B0B0,
            anchor_point=(0.5, 0.0),
            anchored_position=(display.width // 2, 125))
        self.group.append(self.title)
        self.group.append(self.phase)
        self.group.append(self.percent)
        self.group.append(self.sectors)
        self.bar_width = display.width - 40
        self.bar = displayio.Bitmap(self.bar_width, 14, 2)
        bar_palette = displayio.Palette(2)
        bar_palette[0] = 0x202020
        bar_palette[1] = 0x00C878
        self.group.append(displayio.TileGrid(
            self.bar, pixel_shader=bar_palette, x=20, y=158))
        display.root_group = self.group

    def callback(self, phase, completed, total, detail=None):
        now = time.monotonic()
        # Retry/failure/endpoints are immediate. Routine sector phases are
        # throttled so display refresh does not dominate flash programming.
        urgent = phase in ("retry", "failure") or completed in (0, total)
        if not urgent and now - self.last_update < 0.12:
            return
        self.last_phase = phase
        self.last_update = now
        names = {
            "read": "Checking flash",
            "classify": "Comparing sector",
            "erase": "Erasing",
            "program": "Programming",
            "verify": "Verifying",
            "retry": "Retrying sector",
            "complete": "Programming complete",
            "failure": "Programming failed",
        }
        self.phase.text = names.get(phase, phase)
        percent = (completed * 100 // total) if total else 0
        if phase == "complete" and completed == total:
            percent = 100
        self.percent.text = "%d%%" % percent
        self.sectors.text = "%d / %d sectors" % (completed, total)
        if percent != self.last_percent:
            self.last_percent = percent
            filled = self.bar_width * percent // 100
            for x in range(self.bar_width):
                value = 1 if x < filled else 0
                for y in range(14):
                    self.bar[x, y] = value

    def message(self, text, error=False):
        self.phase.color = 0xFF6060 if error else 0x80D8FF
        self.phase.text = text

    def release(self):
        blank = displayio.Group()
        background = displayio.Bitmap(self.display.width, self.display.height, 1)
        palette = displayio.Palette(1)
        palette[0] = 0x000000
        blank.append(displayio.TileGrid(background, pixel_shader=palette))
        self.display.root_group = blank
        try:
            self.display.refresh(minimum_frames_per_second=0)
        except AttributeError:
            time.sleep(0.05)
        except RuntimeError:
            # A refresh can be rejected when the previous auto-refresh was
            # too recent. Wait one frame and force the black frame again.
            time.sleep(0.05)
            try:
                self.display.refresh(minimum_frames_per_second=0)
            except (AttributeError, RuntimeError):
                time.sleep(0.05)
        displayio.release_displays()
        # hardware.main constructs the menu overlay even though clean-install
        # handlers never call overlay.init(). Its constructor owns GP13-GP15,
        # which the launched Game Boy/Flipper links need immediately.
        if self.hw_state is not None:
            self.hw_state["fpga_overlay"].deinit()


def create(application):
    import hardware.main as hardware
    return InstallStatus(
        hardware.hw_state["display"], application, hardware.hw_state)


def wait_for_menu(status):
    """Keep an error visible until action is pressed or the board resets."""
    import microcontroller
    import supervisor
    import hardware.main as hardware
    buttons = hardware.hw_state["btn_action"]
    while True:
        for button in buttons:
            if not button.value:
                microcontroller.nvm[0:2] = b"\x00\x00"
                supervisor.reload()
        time.sleep(0.05)
