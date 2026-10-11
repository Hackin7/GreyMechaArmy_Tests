# Persistent rp2pio transport for ECP5 SPI-flash DR scans.
#
# LICENSE=BSD

from array import array
import rp2pio

from . import flash_jtag_pio


class FlashDrDriverPIO:
    def __init__(self, pin_tck, pin_tms, pin_tdi, pin_tdo,
                 freq_hz=12_000_000, max_bytes=2052):
        self._pin_tck = pin_tck
        self._pin_tms = pin_tms
        self._pin_tdi = pin_tdi
        self._pin_tdo = pin_tdo
        # Normal data bits use five SM cycles. TAP entry/exit overhead is
        # outside the data clock and does not alter TCK during shifting.
        self._sm_freq = freq_hz * 5
        self._max_bytes = max_bytes
        self._count = array("I", [0])
        self._rx_stage = bytearray(max_bytes + 1)
        self._sm = None

    def open(self):
        if self._sm is not None:
            return
        self._sm = rp2pio.StateMachine(
            flash_jtag_pio.PROGRAM.assembled,
            frequency=self._sm_freq,
            first_out_pin=self._pin_tdi,
            out_pin_count=1,
            first_in_pin=self._pin_tdo,
            in_pin_count=1,
            first_set_pin=self._pin_tms,
            set_pin_count=1,
            first_sideset_pin=self._pin_tck,
            sideset_pin_count=1,
            sideset_enable=True,
            initial_sideset_pin_state=0,
            auto_pull=True,
            # CircuitPython byte writes duplicate the byte across the FIFO
            # word. Pulling every eight bits consumes one source byte. The
            # explicit `pull; out x, 32` count header is still a uint32.
            pull_threshold=8,
            out_shift_right=False,
            auto_push=True,
            push_threshold=8,
            in_shift_right=False,
        )

    def write_readinto(self, tx, rx):
        if self._sm is None:
            raise RuntimeError("FlashDrDriverPIO not open")
        if len(tx) != len(rx):
            raise ValueError("tx and rx lengths must match")
        if not tx:
            return
        if len(tx) > self._max_bytes:
            raise ValueError("DR transfer exceeds configured maximum")
        self._count[0] = len(tx) * 8 - 1
        # The PIO consumes this uint32 header and stalls on the first data OUT.
        self._sm.write(self._count)
        # Source and destination remain byte buffers and transfer directly by
        # DMA; no Python repacking is required. The extra RX byte is a PIO
        # completion token emitted only after the TAP exit sequence finishes.
        self._sm.write_readinto(
            tx, self._rx_stage, in_end=len(tx) + 1
        )
        memoryview(rx)[:] = memoryview(self._rx_stage)[:len(tx)]

    def write(self, tx, discard):
        if len(discard) < len(tx):
            raise ValueError("discard buffer is too small")
        self.write_readinto(tx, memoryview(discard)[:len(tx)])

    def close(self):
        if self._sm is None:
            return
        self._sm.deinit()
        self._sm = None
