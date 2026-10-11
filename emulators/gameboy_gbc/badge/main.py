import os
import sys
import time
import board
import digitalio

try:
    import displayio
except ImportError:
    displayio = None
try:
    import hardware.fpga
except ImportError:
    hardware = None

APP_PATH = "/apps/gameboy_gbc/"
BRAM_BITSTREAM = APP_PATH + "gameboy_gbc_bram.bit"
CACHE_BITSTREAM = APP_PATH + "gameboy_gbc_cache.bit"
FLASH_BITSTREAM = APP_PATH + "gameboy_gbc_flash.bit"
DEFAULT_ROM = APP_PATH + "games/game.gb"
INSTALLED_HEADER = APP_PATH + "installed_rom_header.bin"
INSTALLED_METADATA = APP_PATH + "installed_rom.txt"
FLASH_ROM_BASE = 0x100000
FLASH_ROM_MAX = 8 * 1024 * 1024
CHUNK = 256
NVM_MAGIC = 0xAA
NVM_INSTALL_MAGIC = 0xAB

# CircuitPython's normal module path does not necessarily include an app's
# directory when Thonny executes the file directly.
if APP_PATH not in sys.path:
    sys.path.append(APP_PATH)

from protocol import (OP_CACHE_FILL, OP_CONFIG, OP_RESET, OP_ROM_WRITE,
                      OP_RUN, OP_STATUS, decode_status, encode_frame)


class BitBangSpi:
    """Army FPGA interconnect[0..3], matching the Arduboy port."""
    def __init__(self):
        self.sck = digitalio.DigitalInOut(board.GP8)
        self.mosi = digitalio.DigitalInOut(board.GP9)
        self.miso = digitalio.DigitalInOut(board.GP10)
        self.cs_n = digitalio.DigitalInOut(board.GP11)
        self.irq = digitalio.DigitalInOut(board.GP13)
        self.sck.direction = digitalio.Direction.OUTPUT
        self.mosi.direction = digitalio.Direction.OUTPUT
        self.miso.direction = digitalio.Direction.INPUT
        self.cs_n.direction = digitalio.Direction.OUTPUT
        self.irq.direction = digitalio.Direction.INPUT
        self.sck.value = False; self.mosi.value = False; self.cs_n.value = True

    def transfer(self, data):
        result = bytearray()
        self.cs_n.value = False
        for value in data:
            incoming = 0
            for bit in range(7, -1, -1):
                self.mosi.value = bool((value >> bit) & 1)
                self.sck.value = True
                incoming = (incoming << 1) | (1 if self.miso.value else 0)
                self.sck.value = False
            result.append(incoming)
        self.cs_n.value = True
        return result

    def deinit(self):
        self.sck.deinit(); self.mosi.deinit(); self.miso.deinit()
        self.cs_n.deinit(); self.irq.deinit()


class GameBoyHost:
    def __init__(self, spi):
        self.spi = spi
        self.sequence = 0

    def send(self, opcode, address=0, payload=b""):
        self.spi.transfer(encode_frame(opcode, self.sequence, address, payload))
        self.sequence = (self.sequence + 1) & 0xFF
        time.sleep(0.0005)

    def status(self):
        self.send(OP_STATUS)
        status = decode_status(self.spi.transfer(bytes(4)))
        return status["cache_miss"], status["address"]

    def load_header(self, source):
        source.seek(0)
        header = source.read(512)
        if len(header) < 512:
            header += bytes([0xFF] * (512 - len(header)))
        for offset in range(0, 512, CHUNK):
            self.send(OP_ROM_WRITE, offset, header[offset:offset + CHUNK])
        return header[0x143] in (0x80, 0xC0)

    def start(self, source, size, cache_mode=False, flash_mode=False):
        self.send(OP_RESET)
        gbc = self.load_header(source)
        self.send(OP_CONFIG, payload=bytes((1 if gbc else 0,)))
        if not cache_mode and not flash_mode:
            if size > 32768:
                raise ValueError("BRAM bitstream accepts ROMs up to 32 KiB")
            source.seek(512)
            address = 512
            while address < size:
                part = source.read(CHUNK)
                self.send(OP_ROM_WRITE, address, part)
                address += len(part)
        self.send(OP_RUN)

    def service_cache(self, source):
        if not self.spi.irq.value:
            return
        pending, address = self.status()
        if pending:
            source.seek(address)
            data = source.read(CHUNK)
            if len(data) < CHUNK:
                data += bytes([0xFF] * (CHUNK - len(data)))
            self.send(OP_CACHE_FILL, address, data)


def load_bitstream(cache_mode=False, flash_mode=False):
    if displayio is not None:
        displayio.release_displays()
    if hardware is None:
        raise RuntimeError("hardware.fpga is unavailable")
    if flash_mode:
        path = FLASH_BITSTREAM
    else:
        path = CACHE_BITSTREAM if cache_mode else BRAM_BITSTREAM
    handle = hardware.fpga.upload_bitstream(path)
    handle.deinit()
    time.sleep(0.25)


def defer_menu_launch(cache_mode=False, flash_mode=False):
    """Request a clean-reload FPGA upload from the badge menu.

    Uploading while the menu owns the display/PIO resources can leave the
    GC9A01 dark. The root code.py consumes this marker immediately after
    supervisor.reload() and then calls app(upload_bitstream=False).
    """
    import microcontroller
    import supervisor

    if flash_mode:
        path = FLASH_BITSTREAM
    else:
        path = CACHE_BITSTREAM if cache_mode else BRAM_BITSTREAM
    encoded = path.encode("utf-8")
    nvm = microcontroller.nvm
    if 2 + len(encoded) > len(nvm):
        raise ValueError("Bitstream path is too long for microcontroller.nvm")
    nvm[0:2] = bytes((NVM_MAGIC, len(encoded)))
    nvm[2:2 + len(encoded)] = encoded
    supervisor.reload()


def defer_rom_install(path):
    """Install after a clean reload, before the menu claims FPGA pins."""
    import microcontroller
    import supervisor

    encoded = path.encode("utf-8")
    nvm = microcontroller.nvm
    if 2 + len(encoded) > len(nvm):
        raise ValueError("ROM path is too long for microcontroller.nvm")
    nvm[0:2] = bytes((NVM_INSTALL_MAGIC, len(encoded)))
    nvm[2:2 + len(encoded)] = encoded
    supervisor.reload()


def installed_rom_source():
    """Return the retained full-ROM path used by menu-time reinstalls."""
    try:
        with open(INSTALLED_METADATA, "r") as metadata:
            for line in metadata:
                if line.startswith("source="):
                    path = line[7:].strip()
                    if path and os.stat(path)[6] >= 512:
                        return path
    except (OSError, ValueError):
        pass
    return DEFAULT_ROM


def program_rom_app(hw_state=None, rom_path=None):
    """Menu entry that installs the retained ROM, then launches Game Boy."""
    if rom_path is None:
        rom_path = installed_rom_source()
    defer_rom_install(rom_path)


def _declared_rom_size(code):
    if code <= 8:
        return 32768 << code
    if code == 0x52:
        return 72 * 16384
    if code == 0x53:
        return 80 * 16384
    if code == 0x54:
        return 96 * 16384
    raise ValueError("Unsupported ROM size code 0x%02x" % code)


def _validate_rom(path):
    size = os.stat(path)[6]
    if size < 512:
        raise ValueError("ROM is smaller than its 512-byte header area")
    if size > FLASH_ROM_MAX:
        raise ValueError("ROM exceeds the 8 MiB installed-ROM limit")
    with open(path, "rb") as source:
        header = source.read(512)

    checksum = 0
    for value in header[0x134:0x14d]:
        checksum = (checksum - value - 1) & 0xff
    if checksum != header[0x14d]:
        raise ValueError("Invalid Game Boy header checksum")

    declared = _declared_rom_size(header[0x148])
    if declared != size:
        raise ValueError(
            "ROM size is %d bytes but header declares %d" % (size, declared))

    supported = (
        0x00, 0x08, 0x09,
        0x01, 0x02, 0x03,
        0x05, 0x06,
        0x0f, 0x10, 0x11, 0x12, 0x13,
        0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e,
    )
    if header[0x147] not in supported:
        raise ValueError(
            "Unsupported cartridge type 0x%02x" % header[0x147])
    return size, header


def _save_installed_metadata(path, size, header):
    import storage
    remounted = False
    try:
        try:
            storage.remount(
                "/", readonly=False,
                disable_concurrent_write_protection=True)
            remounted = True
        except TypeError:
            try:
                storage.remount("/", readonly=False)
                remounted = True
            except TypeError:
                storage.remount("/", False)
                remounted = True

        with open(INSTALLED_HEADER, "wb") as output:
            output.write(header)
        title_bytes = header[0x134:0x144]
        title = "".join(chr(v) if 32 <= v < 127 else ""
                        for v in title_bytes).strip()
        with open(INSTALLED_METADATA, "w") as output:
            output.write("source=%s\n" % path)
            output.write("title=%s\n" % title)
            output.write("size=%d\n" % size)
            output.write("flash_address=0x%06x\n" % FLASH_ROM_BASE)
            output.write("cartridge_type=0x%02x\n" % header[0x147])
            output.write("cgb=%d\n" %
                         (1 if header[0x143] in (0x80, 0xc0) else 0))
    except (OSError, RuntimeError) as exc:
        # CIRCUITPY cannot be remounted writable while USB mass storage owns
        # it on some firmware builds. The flash operation is still valid, and
        # the clean-reload caller passes the current ROM path to app().
        print("GB_METADATA_SKIPPED", exc)
        return False
    finally:
        if remounted:
            try:
                storage.remount("/", readonly=True)
            except TypeError:
                storage.remount("/", True)
    return True


def install_rom(path, progress=None, load_after=True):
    """Install and sector-verify one ROM without touching flash below 1 MiB."""
    size, header = _validate_rom(path)
    try:
        from hardware.fpga import ecp5f
    except ImportError:
        raise RuntimeError("hardware.fpga.ecp5f is unavailable")

    # The GreyMecha 9.2.8 filesystem's ecp5f.py calls these acceleration
    # helpers, but its bundled jtag.py does not define them.  Supply the
    # bridge locally without altering hardware.fpga.  GP19/GP18/GP16 is not
    # a legal RP2350 hardware-SPI pin mapping, so use a reliable software
    # MSB-first transport for this installation-only path.
    if not hasattr(ecp5f, "spi_jtag_on"):
        from hardware.fpga import jtag

        class SoftJtagSpi:
            def write(self, data):
                jtag.tms.value = 0
                for value in data:
                    for bit in range(7, -1, -1):
                        jtag.tdi.value = (value >> bit) & 1
                        jtag.tck.value = 0
                        jtag.tck.value = 1

            def readinto(self, data):
                jtag.tms.value = 0
                jtag.tdi.value = 0
                for index in range(len(data)):
                    value = 0
                    for _ in range(8):
                        jtag.tck.value = 0
                        jtag.tck.value = 1
                        value = (value << 1) | int(jtag.tdo.value)
                    data[index] = value

        def spi_jtag_on():
            jtag.bitbang_jtag_on()
            # ecp5f leaves the TAP in Capture-DR and expects the original
            # hardware-SPI setup glitch to advance it into Shift-DR.  The
            # software transport is glitch-free, so provide that clock
            # explicitly before shifting the first command bit.
            jtag.tms.value = 0
            jtag.tck.value = 0
            jtag.tck.value = 1
            jtag.hwspi = SoftJtagSpi()

        def spi_jtag_off():
            jtag.bitbang_jtag_off()

        ecp5f.spi_jtag_on = spi_jtag_on
        ecp5f.spi_jtag_off = spi_jtag_off

    if progress is None:
        flashed = ecp5f.flash(path, addr=FLASH_ROM_BASE)
    else:
        flashed = ecp5f.flash(
            path, addr=FLASH_ROM_BASE, progress=progress)
    if not flashed:
        raise RuntimeError("FPGA flash programming or verification failed")
    _save_installed_metadata(path, size, header)
    if load_after:
        load_bitstream(flash_mode=True)
    return size


def app(hw_state=None, rom_path=None, cache_mode=False, flash_mode=True,
        upload_bitstream=None):
    if cache_mode:
        flash_mode = False
    if rom_path is None:
        rom_path = INSTALLED_HEADER if flash_mode else DEFAULT_ROM
    # Menu entry: defer the FPGA upload until after a clean soft reload.
    # Thonny/direct execution: upload immediately and run in this interpreter.
    if upload_bitstream is None:
        if hw_state is not None:
            defer_menu_launch(cache_mode, flash_mode)
            return
        upload_bitstream = True

    if upload_bitstream:
        load_bitstream(cache_mode, flash_mode)
    size = os.stat(rom_path)[6]
    spi = BitBangSpi()
    try:
        with open(rom_path, "rb") as source:
            host = GameBoyHost(spi)
            host.start(source, size, cache_mode, flash_mode)
            while True:
                if cache_mode:
                    host.service_cache(source)
                time.sleep(0.0005 if cache_mode else 0.1)
    finally:
        spi.deinit()


if __name__ == "__main__":
    app(flash_mode=True, upload_bitstream=True)
