"""REPL-first GBA bring-up. ROM is preinstalled in FPGA flash at 0x100000."""
import os
import struct
import time
from gba_protocol import encode_frame, decode_status

APP_PATH = '/apps/gba/'
EWRAM = 0
IWRAM = 0x40000
BIOS = 0x48000
EEPROM = 0x60000
SAVE = 0x80000  # one logical save byte per PSRAM DWORD
VRAM_LOW = 0x100000


class BitBangSpi:
    def __init__(self):
        import board
        import digitalio
        self.sck = digitalio.DigitalInOut(board.GP8)
        self.mosi = digitalio.DigitalInOut(board.GP9)
        self.miso = digitalio.DigitalInOut(board.GP10)
        self.cs = digitalio.DigitalInOut(board.GP11)
        self.sck.switch_to_output(False)
        self.mosi.switch_to_output(False)
        self.miso.switch_to_input()
        self.cs.switch_to_output(True)

    def transfer(self, data):
        result = bytearray(len(data))
        self.cs.value = False
        try:
            for i, value in enumerate(data):
                received = 0
                for bit in range(7, -1, -1):
                    self.mosi.value = bool(value & (1 << bit))
                    self.sck.value = True
                    received = (received << 1) | int(self.miso.value)
                    self.sck.value = False
                result[i] = received
        finally:
            self.sck.value = False
            self.cs.value = True
        return result

    def deinit(self):
        for pin in (self.sck, self.mosi, self.miso, self.cs):
            pin.deinit()


class GBAHost:
    def __init__(self, spi):
        self.spi = spi
        self.sequence = 0

    def send(self, opcode, address=0, payload=b''):
        sequence = self.sequence
        self.sequence = (sequence + 1) & 255
        self.spi.transfer(encode_frame(opcode, sequence, address, payload))
        time.sleep(0.001)
        return sequence

    def status(self):
        self.send(0x20)
        return decode_status(self.spi.transfer(bytes(32)))

    def wait(self, sequence, timeout=30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            result = self.status()
            if result['error'] or result['ram_fault']:
                raise RuntimeError('GBA host operation failed: ' + repr(result))
            if result['sequence'] == sequence and not result['busy']:
                return result
            time.sleep(0.01)
        raise RuntimeError('GBA operation timed out: ' + repr(result))

    def command(self, opcode, address=0, payload=b'', timeout=30):
        return self.wait(self.send(opcode, address, payload), timeout)

    def wait_ready(self, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            result = self.status()
            if result['ram_ready'] and result['panel_ready']:
                if result['device_id'] in (0, 0xffffff) or result['ram_fault']:
                    raise RuntimeError('Invalid PSRAM initialization: ' + repr(result))
                return result
            time.sleep(0.01)
        raise RuntimeError('Board initialization timed out: ' + repr(result))

    def reset(self):
        self.command(1)
        time.sleep(0.01)
        return self.wait_ready()

    def pause(self):
        self.command(4)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            result = self.status()
            if result['ram_idle']:
                return result
        raise RuntimeError('RAM did not drain after pause')

    def resume(self):
        self.command(5)

    def keys(self, mask=None):
        self.command(6, payload=struct.pack('<BH', mask is not None, 0 if mask is None else mask))

    def fill(self, address, length, value=0):
        self.command(0x14, address, struct.pack('<IB', length, value), timeout=120)

    def write(self, address, data):
        if address & 3 or len(data) & 3:
            raise ValueError('Writes must be DWORD aligned')
        for offset in range(0, len(data), 256):
            self.command(0x10, address + offset, data[offset:offset + 256])

    def read(self, address, length, save=False):
        result = bytearray()
        if not save and (address & 3 or length & 3):
            raise ValueError('Reads must be DWORD aligned')
        for offset in range(0, length, 256):
            chunk = min(256, length - offset)
            self.command(0x15 if save else 0x12, address + offset, struct.pack('<H', chunk))
            self.send(0x21)
            result.extend(self.spi.transfer(bytes(chunk)))
        return bytes(result)

    def start(self, rom_size, bios_path=APP_PATH + 'open_bios.bin', flash_1m=False):
        if not 192 <= rom_size <= 8 * 1024 * 1024:
            raise ValueError('Installed ROM must be 192 bytes to 8 MiB')
        self.reset()
        self.fill(EWRAM, 0x48000)
        self.fill(VRAM_LOW, 0x10000)
        self.fill(EEPROM, 0x20000, 0xff)
        self.fill(SAVE, 0x80000, 0xff)
        with open(bios_path, 'rb') as source:
            bios = source.read()
        if len(bios) != 16384:
            raise ValueError('BIOS must be exactly 16384 bytes')
        self.write(BIOS, bios)
        if self.read(BIOS, 16384) != bios:
            raise RuntimeError('BIOS readback differs')
        self.command(2, payload=struct.pack('<IB', rom_size, flash_1m))
        self.command(3)
        return self.status()


def deferred_upload(path=APP_PATH + 'gba.bit'):
    """Use the existing root loader's NVM marker for a clean FPGA upload."""
    import microcontroller
    encoded = path.encode()
    microcontroller.nvm[0] = 0xaa
    microcontroller.nvm[1] = len(encoded)
    microcontroller.nvm[2:2 + len(encoded)] = encoded
    microcontroller.reset()


def install_rom(path, progress=None):
    """Sector-verify cartridge flash; retain the first MiB for FPGA config."""
    size = os.stat(path)[6]
    if size < 192 or size > 8 * 1024 * 1024:
        raise ValueError('ROM size outside supported range')
    from hardware.fpga import ecp5f
    if not hasattr(ecp5f, 'spi_jtag_on'):
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
                for i in range(len(data)):
                    value = 0
                    for _ in range(8):
                        jtag.tck.value = 0
                        jtag.tck.value = 1
                        value = (value << 1) | int(jtag.tdo.value)
                    data[i] = value

        def spi_jtag_on():
            jtag.bitbang_jtag_on()
            jtag.tms.value = 0
            jtag.tck.value = 0
            jtag.tck.value = 1
            jtag.hwspi = SoftJtagSpi()

        ecp5f.spi_jtag_on = spi_jtag_on
        ecp5f.spi_jtag_off = jtag.bitbang_jtag_off
    if progress is None:
        verified = ecp5f.flash(path, addr=0x100000)
    else:
        verified = ecp5f.flash(path, addr=0x100000, progress=progress)
    if not verified:
        raise RuntimeError('ROM flash verification failed')
    print('GBA_ROM_VERIFIED', path, size)
    return size


def app(rom_path=APP_PATH + 'diagnostic.gba'):
    from gba_launch import start_with_recovery
    spi = BitBangSpi()
    try:
        host = GBAHost(spi)
        start_with_recovery(host, os.stat(rom_path)[6])
        while True:
            status = host.status()
            if status['error'] or status['ram_fault'] or status['overflow']:
                raise RuntimeError('GBA hardware fault: ' + repr(status))
            time.sleep(1)
    finally:
        spi.deinit()
