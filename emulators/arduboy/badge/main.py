import time
import os

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


APP_PATH = "/apps/arduboy_fx/"
BITSTREAM_PATH = APP_PATH + "arduboy_fx.bit"
DEFAULT_HEX_PATH = APP_PATH + "games/1nvader.hex"

CMD_RESET_ASSERT = 0x01
CMD_RESET_RELEASE = 0x02
CMD_DISPLAY_HOST = 0x03
CMD_DISPLAY_SOC = 0x04
CMD_FB_WRITE = 0x10
CMD_FLASH_WRITE = 0x20
CMD_EEPROM_WRITE = 0x30
CMD_FX_WRITE = 0x40
CMD_FX_TAG = 0x41


class BitBangSpi:
    """Mode-0-ish byte bridge for FPGA interconnect[0..3]."""

    def __init__(self):
        self.sck = digitalio.DigitalInOut(board.GP8)
        self.mosi = digitalio.DigitalInOut(board.GP9)
        self.miso = digitalio.DigitalInOut(board.GP10)
        self.cs_n = digitalio.DigitalInOut(board.GP11)

        self.sck.direction = digitalio.Direction.OUTPUT
        self.mosi.direction = digitalio.Direction.OUTPUT
        self.miso.direction = digitalio.Direction.INPUT
        self.cs_n.direction = digitalio.Direction.OUTPUT

        self.sck.value = False
        self.mosi.value = False
        self.cs_n.value = True

    def deinit(self):
        self.sck.deinit()
        self.mosi.deinit()
        self.miso.deinit()
        self.cs_n.deinit()

    def transfer(self, data):
        out = bytearray()
        self.cs_n.value = False
        for value in data:
            rx = 0
            for bit in range(7, -1, -1):
                self.mosi.value = bool((value >> bit) & 1)
                self.sck.value = True
                rx = (rx << 1) | (1 if self.miso.value else 0)
                self.sck.value = False
            out.append(rx)
        self.cs_n.value = True
        return out

    def command(self, command):
        return self.transfer(bytes([command]))[-1]

    def write_block(self, command, address, data, chunk=128):
        pos = 0
        total = len(data)
        while pos < total:
            part = data[pos : pos + chunk]
            header = bytes([
                command,
                ((address + pos) >> 8) & 0xFF,
                (address + pos) & 0xFF,
                (len(part) >> 8) & 0xFF,
                len(part) & 0xFF,
            ])
            self.transfer(header + part)
            pos += len(part)

    def set_fx_tag(self, slot, tag):
        self.transfer(bytes([
            CMD_FX_TAG,
            slot & 0x0F,
            (tag >> 16) & 0xFF,
            (tag >> 8) & 0xFF,
            tag & 0xFF,
        ]))


def parse_ihex(path, size=32768):
    image = bytearray([0xFF] * size)
    upper = 0
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line[0] != ":":
                raise ValueError("Bad Intel HEX line")
            count = int(line[1:3], 16)
            addr = int(line[3:7], 16)
            rectype = int(line[7:9], 16)
            payload = bytes(int(line[9 + i * 2 : 11 + i * 2], 16) for i in range(count))
            checksum = int(line[9 + count * 2 : 11 + count * 2], 16)
            total = count + (addr >> 8) + (addr & 0xFF) + rectype + sum(payload) + checksum
            if (total & 0xFF) != 0:
                raise ValueError("Bad Intel HEX checksum")
            if rectype == 0x00:
                base = upper + addr
                for i, value in enumerate(payload):
                    if 0 <= base + i < size:
                        image[base + i] = value
            elif rectype == 0x01:
                break
            elif rectype == 0x04:
                upper = int.from_bytes(payload, "big") << 16
    return image


def make_test_framebuffer():
    fb = bytearray(1024)
    for y in range(64):
        for x in range(128):
            border = x == 0 or x == 127 or y == 0 or y == 63
            grid = (x % 16 == 0) or (y % 16 == 0)
            diag = ((x + y) & 15) == 0
            if border or grid or diag:
                fb[(y // 8) * 128 + x] |= 1 << (y & 7)
    return fb


def load_eeprom(path):
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        data = b""
    data = data[:1024]
    return data + bytes([0xFF] * (1024 - len(data)))


def deinit_screen():
    """Release the badge GC9A01 pins before the FPGA takes ownership."""
    if displayio is not None:
        displayio.release_displays()


def load_bitstream():
    """Configure the ECP5 from the bitstream stored on the badge."""
    if hardware is None:
        raise RuntimeError("hardware.fpga is not available in this CircuitPython build")

    print("Loading FPGA bitstream:", BITSTREAM_PATH)
    handle = hardware.fpga.upload_bitstream(BITSTREAM_PATH)
    handle.deinit()
    time.sleep(0.25)
    print("FPGA bitstream loaded")


def setup_fpga(upload_bitstream=True):
    deinit_screen()
    if upload_bitstream:
        load_bitstream()
    return BitBangSpi()


def load_firmware(spi, hex_path, eeprom_path=None):
    """Load an Intel HEX image into AVR program RAM and start the core."""
    print("Loading Arduboy firmware:", hex_path)
    spi.command(CMD_RESET_ASSERT)
    spi.command(CMD_DISPLAY_HOST)
    spi.write_block(CMD_FLASH_WRITE, 0, parse_ihex(hex_path))
    if eeprom_path:
        spi.write_block(CMD_EEPROM_WRITE, 0, load_eeprom(eeprom_path))

    for _attempt in range(5):
        spi.command(CMD_DISPLAY_SOC)
        time.sleep(0.05)
        if (spi.command(0x00) & 0x02) == 0:
            break

    spi.command(CMD_RESET_RELEASE)
    spi.command(CMD_DISPLAY_SOC)
    print("Arduboy firmware running")


load_game = load_firmware


def app(hw_state=None, hex_path=None, eeprom_path=None, upload_bitstream=True):
    if hex_path is None:
        try:
            os.stat(DEFAULT_HEX_PATH)
            hex_path = DEFAULT_HEX_PATH
        except OSError:
            pass

    spi = setup_fpga(upload_bitstream=upload_bitstream)
    try:
        if not hex_path:
            raise OSError("Firmware not found: " + DEFAULT_HEX_PATH)
        load_firmware(spi, hex_path, eeprom_path=eeprom_path)
        while True:
            time.sleep(0.25)
    finally:
        spi.deinit()


if __name__ == "__main__":
    app(upload_bitstream=True)
