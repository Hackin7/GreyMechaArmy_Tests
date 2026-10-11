# rp2pio.StateMachine full-duplex JTAG burst driver.
#
# Public interface:
#     drv = BurstDriverPIO(pin_tck, pin_tdi, pin_tdo, freq_hz=6_000_000)
#     drv.open()
#     drv.write(buf)        # buf is bytes-like; clocks len(buf)*8 bits of TDI
#     drv.write_readinto(tx, rx)
#     drv.readinto(rx)      # clocks zeroes on TDI while receiving TDO
#     drv.close()
#
# The full-duplex write_readinto operation is implemented by CircuitPython with
# simultaneous TX/RX FIFO DMA.  The timing and transport split (PIO owns
# TCK/TDI/TDO for bulk clocks, GPIO owns TAP transitions) is materially
# informed by pico-dirtyJtag's MIT-licensed jtag.pio and pio_jtag.c.

import rp2pio

from . import jtag_burst_pio


class BurstDriverPIO:
    def __init__(self, pin_tck, pin_tdi, pin_tdo, freq_hz=6_000_000,
                 buffer_size=2048):
        self._pin_tck = pin_tck
        self._pin_tdi = pin_tdi
        self._pin_tdo = pin_tdo
        # 33 SM cycles clock eight JTAG bits, including the per-byte loop setup.
        self._sm_freq = freq_hz * 33 // 8
        self._sm = None
        self._zero_fill = bytearray(buffer_size)
        self._discard = bytearray(buffer_size)

    def open(self):
        if self._sm is not None:
            return
        self._sm = rp2pio.StateMachine(
            jtag_burst_pio.PROGRAM.assembled,
            frequency=self._sm_freq,
            first_out_pin=self._pin_tdi,
            out_pin_count=1,
            first_in_pin=self._pin_tdo,
            in_pin_count=1,
            first_sideset_pin=self._pin_tck,
            sideset_pin_count=1,
            sideset_enable=True,        # .side_set 1 opt
            auto_pull=True,
            pull_threshold=8,
            out_shift_right=False,      # MSB first within each byte (matches bitbangio.SPI default)
            auto_push=True,
            push_threshold=8,
            # TDO arrives MSB first. Shifting left places the first sampled bit
            # at bit 7 after eight clocks; CircuitPython reads the low byte.
            in_shift_right=False,
        )

    def _check_open(self):
        if self._sm is None:
            raise RuntimeError("BurstDriverPIO not open")

    def _ensure_scratch(self, size):
        if size > len(self._zero_fill):
            self._zero_fill = bytearray(size)
            self._discard = bytearray(size)

    def write_readinto(self, tx, rx):
        self._check_open()
        if len(tx) != len(rx):
            raise ValueError("tx and rx lengths must match")
        if len(tx) == 0:
            return
        self._sm.write_readinto(tx, rx)

    def readinto(self, rx):
        self._check_open()
        size = len(rx)
        if size == 0:
            return
        self._ensure_scratch(size)
        self._sm.write_readinto(
            self._zero_fill, rx, out_end=size, in_end=size
        )

    def write(self, buf):
        self._check_open()
        if len(buf) == 0:
            return
        size = len(buf)
        self._ensure_scratch(size)
        self._sm.write_readinto(
            buf, self._discard, out_end=size, in_end=size
        )

    def close(self):
        if self._sm is None:
            return
        self._sm.deinit()
        self._sm = None
