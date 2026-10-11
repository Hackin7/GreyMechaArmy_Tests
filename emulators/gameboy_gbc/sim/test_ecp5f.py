import importlib.util
import io
import pathlib
import sys
import types
import unittest


ROOT = pathlib.Path(__file__).parents[1]
ECP5F = ROOT / "badge/hardware/fpga/ecp5f.py"


class FakeDriver:
    instances = []

    def __init__(self, *args):
        self.events = []
        self.closed = False
        self.instances.append(self)

    def open(self):
        self.events.append("open")

    def write(self, data, discard):
        self.events.append(("write", bytes(data)))

    def write_readinto(self, tx, rx):
        self.events.append(("write_readinto", bytes(tx)))

    def readinto(self, rx):
        self.events.append(("readinto", len(rx)))
        for i in range(len(rx)):
            rx[i] = (i + 1) & 0xFF

    def close(self):
        self.closed = True
        self.events.append("close")


def load_module():
    events = []
    jtag = types.ModuleType("hardware.fpga.jtag")

    def record(name, result=None):
        def fn(*args, **kwargs):
            events.append((name, args))
            return result
        return fn

    for name in (
        "common_open", "reset_tap", "runtest_idle", "sir_idle", "sir",
        "sdr_idle", "sdr", "send_tms0111", "bitbang_jtag_input",
        "bitbang_tms_off", "stopwatch_start", "stopwatch_stop",
    ):
        setattr(jtag, name, record(name))
    jtag.send_tms = record("send_tms")
    jtag.bitbang_jtag_off = record("bitbang_jtag_off")
    jtag.bitbang_jtag_on = record("bitbang_jtag_on")
    jtag.send_int_msb1st = record("send_int_msb1st")
    jtag.send_read_buf_lsb1st = record("send_read_buf_lsb1st")
    jtag.filedata_gz = lambda path: (None, False)

    def sdr_response(data):
        events.append(("sdr_response", (data,)))
        data[1] = 0
    jtag.sdr_response = sdr_response

    hardware = types.ModuleType("hardware")
    fpga = types.ModuleType("hardware.fpga")
    fpga.jtag = jtag
    flash_pio = types.ModuleType("hardware.fpga.flash_pio")
    flash_pio.FlashDrDriverPIO = FakeDriver
    board = types.ModuleType("board")
    board.GP16, board.GP17, board.GP18, board.GP19 = (
        object(), object(), object(), object()
    )
    micropython = types.ModuleType("micropython")
    micropython.const = lambda value: value

    names = {
        "hardware": hardware,
        "hardware.fpga": fpga,
        "hardware.fpga.jtag": jtag,
        "hardware.fpga.flash_pio": flash_pio,
        "board": board,
        "micropython": micropython,
    }
    old = {name: sys.modules.get(name) for name in names}
    sys.modules.update(names)
    try:
        spec = importlib.util.spec_from_file_location("hardware.fpga.ecp5f", ECP5F)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        for name, value in old.items():
            if value is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = value
    module._test_events = events
    return module


class Ecp5FlashTests(unittest.TestCase):
    def setUp(self):
        FakeDriver.instances.clear()
        self.m = load_module()

    def test_read_uses_one_persistent_dr_transaction(self):
        data = bytearray(8)
        self.m.flash_read_block(data, 0x123456)
        driver = FakeDriver.instances[-1]
        self.assertEqual(driver.events[0], "open")
        self.assertEqual(
            driver.events[1],
            ("write_readinto", b"\x03\x12\x34\x56" + b"\x00" * 8),
        )
        self.assertFalse(driver.closed)
        names = [event[0] for event in self.m._test_events]
        self.assertEqual(
            names,
            ["bitbang_jtag_off", "bitbang_tms_off"],
        )

    def test_page_program_is_one_complete_pio_dr_scan(self):
        self.m.flash_wait_status = lambda: True
        page = bytes(range(256))
        self.assertTrue(self.m.flash_write_block(page, 0xABC000))
        events = FakeDriver.instances[-1].events
        self.assertEqual(events[1], ("write", b"\x06"))
        written = events[2][1]
        self.assertEqual(written[:4], b"\x02\xAB\xC0\x00")
        self.assertEqual(written[4:], page)

    def test_erase_classification_and_changed_non_ff_pages(self):
        current = bytearray(b"\xFF" * self.m.flash_erase_size)
        requested = bytearray(current)
        requested[0] = 0xF0
        self.assertFalse(self.m._sector_needs_erase(current, requested))
        self.assertTrue(self.m._page_changed(current, requested, 0))
        self.assertFalse(self.m._page_changed(current, requested, 256))
        current[0] = 0
        requested[0] = 1
        self.assertTrue(self.m._sector_needs_erase(current, requested))

    def test_partial_sector_is_padded_and_only_one_page_written(self):
        payload = b"\xAA" * 10
        reads = []
        writes = []

        def read_sector(chunks, addr):
            reads.append(addr)
            target = self.m._sector_flash
            if chunks is self.m._verify_read_chunks:
                target = self.m._sector_verify
            for i in range(len(target)):
                target[i] = 0xFF
            if chunks is self.m._verify_read_chunks:
                target[:10] = payload

        self.m.flash_open = lambda: None
        self.m._read_sector = read_sector
        self.m.flash_write_block = lambda page, addr=0: writes.append(
            (addr, bytes(page))
        ) or True
        self.m.stopwatch_start = lambda: None
        self.m.stopwatch_stop = lambda count: None
        self.assertTrue(self.m.flash_stream(io.BytesIO(payload), 0))
        self.assertEqual(len(writes), 1)
        self.assertEqual(writes[0][1][:10], payload)
        self.assertEqual(writes[0][1][10:], b"\xFF" * 246)
        self.assertEqual(self.m._sector_file[10:], b"\xFF" * (4096 - 10))

    def test_status_timeout_returns_false(self):
        self.m.sleep = lambda delay: None

        def busy(data):
            data[1] = 0x01
        self.m._dr_response = busy
        self.assertFalse(self.m.flash_wait_status())

    def test_retry_exhaustion_and_verify_failure_propagate(self):
        self.m.flash_open = lambda: None
        self.m.stopwatch_start = lambda: None
        self.m.stopwatch_stop = lambda count: None
        calls = []

        def fail(addr):
            calls.append(addr)
            return False, False, 0
        self.m._program_sector = fail
        self.assertFalse(self.m.flash_stream(io.BytesIO(b"\x01"), 0x4000))
        self.assertEqual(calls, [0x4000] * 3)

    def test_unaligned_address_fails_without_opening_tap(self):
        opened = []
        self.m.flash_open = lambda: opened.append(True)
        self.assertFalse(self.m.flash_stream(io.BytesIO(b"x"), 1))
        self.assertEqual(opened, [])

    def test_progress_reports_sector_phases_retry_and_completion(self):
        self.m.flash_open = lambda: None
        self.m.stopwatch_start = lambda: None
        self.m.stopwatch_stop = lambda count: None
        attempts = []
        events = []

        def program(addr, progress, completed, total):
            attempts.append(addr)
            progress("read", completed, total, addr)
            progress("classify", completed, total, addr)
            progress("verify", completed, total, addr)
            return len(attempts) > 1, False, 0

        self.m._program_sector = program
        callback = lambda phase, done, total, detail: events.append(
            (phase, done, total, detail))
        self.assertTrue(self.m.flash_stream(
            io.BytesIO(b"x" * 5000), progress=callback))
        phases = [event[0] for event in events]
        self.assertIn("retry", phases)
        self.assertEqual(events[-1][:3], ("complete", 2, 2))
        self.assertTrue(all(event[2] == 2 for event in events))


if __name__ == "__main__":
    unittest.main()
