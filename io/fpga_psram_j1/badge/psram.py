"""CircuitPython REPL client. Only the FPGA accesses the external PSRAM.

Copy to /apps/psram_j1/psram.py, then import psram after adding that directory
to sys.path. The RP2350 sends commands through GP8..11; no RP2350 QMI setup.
"""
import time


class BitBangSpi:
    def __init__(self):
        import board
        import digitalio
        self.sck = digitalio.DigitalInOut(board.GP8)
        self.mosi = digitalio.DigitalInOut(board.GP9)
        self.miso = digitalio.DigitalInOut(board.GP10)
        self.cs = digitalio.DigitalInOut(board.GP11)
        self.sck.switch_to_output(value=False)
        self.mosi.switch_to_output(value=False)
        self.miso.switch_to_input()
        self.cs.switch_to_output(value=True)

    def transfer(self, payload):
        incoming = bytearray(len(payload))
        self.cs.value = False
        # Explicit margins for the FPGA's synchronizers, including first bit.
        time.sleep(0.00001)
        try:
            for index, value in enumerate(payload):
                received = 0
                for bit in range(7, -1, -1):
                    self.mosi.value = bool(value & (1 << bit))
                    time.sleep(0.000002)
                    self.sck.value = True
                    received = (received << 1) | int(self.miso.value)
                    time.sleep(0.000002)
                    self.sck.value = False
                incoming[index] = received
            time.sleep(0.00001)
        finally:
            self.sck.value = False
            self.cs.value = True
        time.sleep(0.00001)
        return incoming

    def deinit(self):
        self.cs.value = True
        for pin in (self.sck, self.mosi, self.miso, self.cs):
            pin.deinit()


def decode_response(data):
    if len(data) != 8 or data[0] != 0x50:
        raise RuntimeError("Invalid FPGA response: " + repr(data))
    return {
        "busy": bool(data[1] & 1), "ready": bool(data[1] & 2),
        "pass": bool(data[1] & 4), "error": bool(data[1] & 8),
        "id_good": bool(data[1] & 16), "data": data[2], "expected": data[3],
        "qpi": bool(data[1] & 32),
        "address": (data[4] << 16) | (data[5] << 8) | data[6],
        "error_code": data[7],
    }


class Psram:
    def __init__(self, spi=None):
        self.spi = spi if spi is not None else BitBangSpi()
        try:
            self.wait()
        except Exception:
            if spi is None:
                self.spi.deinit()
            raise

    def status(self):
        # Opcode zero is a no-op, so response reads never alter the result.
        return decode_response(self.spi.transfer(bytes(8)))

    def wait(self, timeout=2):
        deadline = time.monotonic() + timeout
        while True:
            result = self.status()
            if not result["busy"]:
                return result
            if time.monotonic() > deadline:
                raise RuntimeError("FPGA operation timed out")
            time.sleep(0.001)

    def _command(self, opcode, address=0, value=0):
        if not 0 <= address < 8 * 1024 * 1024:
            raise ValueError("Address must be 0..0x7fffff")
        self.wait()
        self.spi.transfer(bytes((opcode, address >> 16, (address >> 8) & 255,
                                 address & 255, value)))
        result = self.wait()
        if result["error_code"]:
            raise RuntimeError("FPGA error: " + repr(result))
        return result

    def id(self, reset=False):
        """Return vendor/KGD/density bytes. reset=True repeats initialization."""
        result = self._command(3 if reset else 5)
        value = result["address"]
        return bytes((value >> 16, (value >> 8) & 255, value & 255))

    def read(self, address, length=1):
        if length < 0 or address < 0 or address + length > 8 * 1024 * 1024:
            raise ValueError("Read range outside PSRAM")
        return bytes(self._command(1, address + n)["data"] for n in range(length))

    def pins(self):
        """Read pad levels and activity since FPGA reset; no memory access."""
        result = self._command(6)
        return {"levels": result["data"], "activity": result["expected"],
                "clock_edges": result["address"]}

    def write(self, address, payload):
        if address < 0 or address + len(payload) > 8 * 1024 * 1024:
            raise ValueError("Write range outside PSRAM")
        for n, value in enumerate(payload):
            self._command(2, address + n, value)

    def self_test(self, address=0):
        """Destructively write/read 256 bytes in the FPGA; return result."""
        if not 0 <= address <= 0x7fff00:
            raise ValueError("256-byte test range outside PSRAM")
        return self._command(4, address)

    def address_test(self):
        """Destructive data/address-line test: zero and every address bit."""
        addresses = [0] + [1 << bit for bit in range(23)] + [0x7fffff]
        for index, address in enumerate(addresses):
            self.write(address, bytes((index + 1,)))
        # Verify only after ALL writes, so aliased address lines are detected.
        for index, address in enumerate(addresses):
            actual = self.read(address)[0]
            if actual != index + 1:
                raise RuntimeError("Address alias at 0x%06x: %02x" % (address, actual))
        for value in (0, 255, 0x55, 0xaa, 1, 2, 4, 8, 16, 32, 64, 128):
            self.write(0, bytes((value,)))
            if self.read(0)[0] != value:
                raise RuntimeError("Data-line test failed")
        return True

    def measure_clock(self, periods=256, timeout=3):
        """Measure GP12 reference with native RP2350 pulse capture (microseconds)."""
        import board
        import pulseio
        pulses = pulseio.PulseIn(board.GP12, maxlen=periods * 2 + 2, idle_state=False)
        deadline = time.monotonic() + timeout
        try:
            while len(pulses) < periods * 2 + 2:
                if time.monotonic() > deadline:
                    raise RuntimeError('Clock reference did not toggle')
                time.sleep(0.001)
            pulses.pause()
            elapsed_us = sum(pulses[index] for index in range(1, periods * 2 + 1))
            return periods * 65536 * 1000000 / elapsed_us
        finally:
            pulses.deinit()

    def benchmark(self, address=0, size=65536, seed=0, clock_hz=None):
        """Destructive FPGA write/verify, timed in FPGA cycles (not USB time)."""
        if size < 256 or size > 65536 or size & (size - 1):
            raise ValueError('Size must be a power of two, 256..65536')
        if address < 0 or address + size > 8 * 1024 * 1024 or not 0 <= seed <= 7:
            raise ValueError('Invalid benchmark range/seed')
        exponent = 0
        remaining = size
        while remaining > 1:
            exponent += 1
            remaining >>= 1
        result = self._command(7, address, (seed << 5) | exponent)
        if not result['pass']:
            raise RuntimeError('Benchmark verify failed: ' + repr(result))
        metrics = [self._command(8, value=index)['address'] for index in range(6)]
        write_cycles, read_cycles, count, sys_khz, burst, spi_khz = metrics
        clock_hz = sys_khz * 1000 if clock_hz is None else clock_hz
        return {'bytes': count, 'write_cycles': write_cycles, 'read_cycles': read_cycles,
                'sys_khz': sys_khz, 'spi_khz': spi_khz, 'burst_bytes': burst,
                'qpi': result['qpi'], 'pass': True,
                'measured_sys_hz': clock_hz,
                'write_MB_s': count * clock_hz / (write_cycles * 1000000),
                'read_MB_s': count * clock_hz / (read_cycles * 1000000)}

    def deinit(self):
        self.spi.deinit()


def load(path="/apps/psram_j1/fpga_psram_j1.bit"):
    """Call from a stopped/fresh REPL, before creating Psram()."""
    import displayio
    import hardware.fpga
    displayio.release_displays()
    handle = hardware.fpga.upload_bitstream(path)
    handle.deinit()
    time.sleep(0.05)
