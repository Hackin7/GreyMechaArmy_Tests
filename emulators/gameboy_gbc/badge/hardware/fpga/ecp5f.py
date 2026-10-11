# circuitpython RP2350
# ECP5 JTAG flash programmer
#
# AUTHOR=EMARD
# LICENSE=BSD
#
# Bulk TCK/TDI/TDO handling follows the PIO/full-duplex transport structure in
# pico-dirtyJtag (MIT license). TAP transitions and the final TMS-high bit stay
# under GPIO control.

from time import sleep
import board
from micropython import const

from hardware.fpga import jtag
from hardware.fpga.jtag import *
from hardware.fpga.flash_pio import FlashDrDriverPIO

PERSISTENT_FLASH_PIO = True

flash_read_size = const(2048)
flash_write_size = const(256)
flash_erase_size = const(4096)  # W25Q128 4 KiB sector
flash_erase_cmd = const(0x20)

_BURST_PIN_TCK = board.GP19
_BURST_PIN_TMS = board.GP17
_BURST_PIN_TDI = board.GP18
_BURST_PIN_TDO = board.GP16
# Validated on GreyMecha at 6/8/10/12 MHz with repeated nonblank reads and
# three complete program/verify/close cycles; 12 MHz was the highest tested.
_BURST_FREQ_HZ = 12_000_000

flash_req = bytearray(4)
flash_reqmv = memoryview(flash_req)
_read_discard = bytearray(4)
_dr_discard = bytearray(flash_read_size + 4)
_read_tx = bytearray(flash_read_size + 4)
_read_rx = bytearray(flash_read_size + 4)
_page_tx = bytearray(4 + flash_write_size)
_page_rx = bytearray(4 + flash_write_size)
_sector_file = bytearray(flash_erase_size)
_sector_flash = bytearray(flash_erase_size)
_sector_verify = bytearray(flash_erase_size)
_ff_sector = bytes([0xFF]) * flash_erase_size
_sector_file_mv = memoryview(_sector_file)
_sector_flash_mv = memoryview(_sector_flash)
_sector_verify_mv = memoryview(_sector_verify)
_file_pages = tuple(
    _sector_file_mv[i:i + flash_write_size]
    for i in range(0, flash_erase_size, flash_write_size)
)
_flash_read_chunks = tuple(
    _sector_flash_mv[i:i + flash_read_size]
    for i in range(0, flash_erase_size, flash_read_size)
)
_verify_read_chunks = tuple(
    _sector_verify_mv[i:i + flash_read_size]
    for i in range(0, flash_erase_size, flash_read_size)
)
_flash_driver = None


def _fill(buf, value):
  for i in range(len(buf)):
    buf[i] = value


def _set_request(command, addr):
  flash_req[0] = command
  flash_req[1] = (addr >> 16) & 0xFF
  flash_req[2] = (addr >> 8) & 0xFF
  flash_req[3] = addr & 0xFF


def _driver_open():
  global _flash_driver
  if _flash_driver is not None:
    return _flash_driver
  bitbang_jtag_off()
  bitbang_tms_off()
  _flash_driver = FlashDrDriverPIO(
      _BURST_PIN_TCK, _BURST_PIN_TMS, _BURST_PIN_TDI, _BURST_PIN_TDO,
      _BURST_FREQ_HZ, flash_read_size + 4
  )
  _flash_driver.open()
  return _flash_driver


def _driver_close():
  global _flash_driver
  if _flash_driver is None:
    return
  _flash_driver.close()
  _flash_driver = None
  bitbang_tms_on()
  bitbang_jtag_on()


def _dr_write(data):
  _driver_open().write(data, _dr_discard)


def _dr_response(data):
  _driver_open().write_readinto(data, data)


def flash_open():
  common_open()
  reset_tap()
  runtest_idle(1, 0)
  sir_idle(b"\xFF", 32, 0)  # BYPASS
  sir(b"\x3A")              # LSC_PROG_SPI
  flash_req[0] = 0xFE
  flash_req[1] = 0x68
  sdr_idle(flash_reqmv[0:2], 32, 0)


def flash_wait_status():
  retry = 50
  while retry > 0:
    # Persistent PIO is MSB-first: native W25Q READ STATUS command is 0x05.
    flash_req[0] = 0x05
    flash_req[1] = 0
    _dr_response(flash_reqmv[0:2])
    if (flash_req[1] & 0x03) == 0:
      return True
    sleep(0.001)
    retry -= 1
  print("error flash status 0x%02X & 0x03 != 0" % flash_req[1])
  return False


def flash_erase_block(addr=0):
  flash_req[0] = 0x06
  _dr_write(flash_reqmv[0:1])  # SPI WRITE ENABLE
  flash_req[0] = 0x05
  flash_req[1] = 0
  _dr_response(flash_reqmv[0:2])
  if (flash_req[1] & 0x03) != 0x02:
    print("WRITE ENABLE FAIL: 0x%02X" % flash_req[1])
    return False
  _set_request(flash_erase_cmd, addr)
  _dr_write(flash_req)
  return flash_wait_status()


def flash_write_block(block, addr=0):
  if len(block) != flash_write_size:
    raise ValueError("flash page must be 256 bytes")
  flash_req[0] = 0x06
  _dr_write(flash_reqmv[0:1])  # SPI WRITE ENABLE
  _page_tx[0] = 0x02
  _page_tx[1] = (addr >> 16) & 0xFF
  _page_tx[2] = (addr >> 8) & 0xFF
  _page_tx[3] = addr & 0xFF
  # Keep the final data byte as the final byte in this DR scan; the persistent
  # PIO engine asserts TMS on its last bit.
  memoryview(_page_tx)[4:] = block
  _driver_open().write_readinto(_page_tx, _page_rx)
  return flash_wait_status()


def flash_read_block(data, addr=0):
  size = len(data)
  if size > flash_read_size:
    raise ValueError("flash read exceeds 2 KiB transport buffer")
  _set_request(0x03, addr)
  for i in range(4):
    _read_tx[i] = flash_req[i]
  tx = memoryview(_read_tx)[:4 + size]
  rx = memoryview(_read_rx)[:4 + size]
  _driver_open().write_readinto(tx, rx)
  memoryview(data)[:] = memoryview(_read_rx)[4:4 + size]


def flash_close():
  _driver_close()
  sdr(b"\x20")              # SPI WRITE DISABLE
  sir_idle(b"\xFF", 100, 1)
  sir_idle(b"\x26", 2, 200) # ISC DISABLE
  sir_idle(b"\xFF", 2, 1)
  sir(b"\x79")              # LSC_REFRESH
  sdr_idle(b"\x00\x00\x00", 2, 100)
  reset_tap()
  bitbang_jtag_input()
  bitbang_jtag_off()
  bitbang_tms_off()


def flash_read(data, addr=0):
  flash_open()
  flash_read_block(data, addr)
  flash_close()


def _sector_needs_erase(current, requested):
  for i in range(flash_erase_size):
    if (current[i] & requested[i]) != requested[i]:
      return True
  return False


def _page_changed(current, requested, offset):
  changed = False
  non_ff = False
  end = offset + flash_write_size
  for i in range(offset, end):
    value = requested[i]
    if current[i] != value:
      changed = True
    if value != 0xFF:
      non_ff = True
  return changed and non_ff


def _read_sector(chunks, addr):
  for i in range(len(chunks)):
    flash_read_block(chunks[i], addr + i * flash_read_size)


def _buffers_equal(left, right):
  return left == right


def _notify(progress, phase, completed, total, detail=None):
  if progress is not None:
    progress(phase, completed, total, detail)


def _stream_sector_count(filedata):
  """Return the remaining number of sectors when the stream is seekable."""
  try:
    start = filedata.tell()
    filedata.seek(0, 2)
    remaining = filedata.tell() - start
    filedata.seek(start)
    return (remaining + flash_erase_size - 1) // flash_erase_size
  except (AttributeError, OSError, ValueError):
    return 0


def _program_sector(addr, progress=None, completed=0, total=0):
  _notify(progress, "read", completed, total, addr)
  _read_sector(_flash_read_chunks, addr)
  _notify(progress, "classify", completed, total, addr)
  if _buffers_equal(_sector_flash, _sector_file):
    _notify(progress, "verify", completed, total, addr)
    return True, False, 0

  must_erase = _sector_needs_erase(_sector_flash, _sector_file)
  if must_erase:
    _notify(progress, "erase", completed, total, addr)
    if not flash_erase_block(addr):
      return False, True, 0
    _sector_flash[:] = _ff_sector

  pages_written = 0
  _notify(progress, "program", completed, total, addr)
  for page_index in range(len(_file_pages)):
    offset = page_index * flash_write_size
    if _page_changed(_sector_flash, _sector_file, offset):
      if not flash_write_block(_file_pages[page_index], addr + offset):
        return False, must_erase, pages_written
      pages_written += 1

  _notify(progress, "verify", completed, total, addr)
  _read_sector(_verify_read_chunks, addr)
  return _buffers_equal(_sector_verify, _sector_file), must_erase, pages_written


def flash_stream(filedata, addr=0, progress=None):
  addr_mask = flash_erase_size - 1
  if addr & addr_mask:
    print("addr must be rounded to flash_erase_size = %d bytes (& 0x%06X)"
          % (flash_erase_size, 0xFFFFFF & ~addr_mask))
    _notify(progress, "failure", 0, 0, addr)
    return False
  addr = addr & 0xFFFFFF & ~addr_mask
  total_sectors = _stream_sector_count(filedata)
  _notify(progress, "read", 0, total_sectors, addr)
  flash_open()
  bytes_uploaded = 0
  sector_count = 0
  erase_count = 0
  page_count = 0
  stopwatch_start()

  while True:
    _sector_file[:] = _ff_sector
    count = filedata.readinto(_sector_file)
    if not count:
      break
    sector_addr = addr + bytes_uploaded
    success = False
    for _attempt in range(3):
      if _attempt:
        _notify(progress, "retry", sector_count, total_sectors, sector_addr)
      if progress is None:
        success, erased, pages = _program_sector(sector_addr)
      else:
        success, erased, pages = _program_sector(
            sector_addr, progress, sector_count, total_sectors)
      if erased:
        erase_count += 1
      page_count += pages
      if success:
        break
    if not success:
      print("flash verify failed at 0x%06X after 3 attempts" % sector_addr)
      _notify(progress, "failure", sector_count, total_sectors, sector_addr)
      stopwatch_stop(bytes_uploaded)
      return False
    bytes_uploaded += flash_erase_size
    sector_count += 1
    _notify(progress, "complete", sector_count, total_sectors, sector_addr)
    print(".", end="")
    if count < flash_erase_size:
      break

  print("\r", end="")
  stopwatch_stop(bytes_uploaded)
  print("%dK sectors: %d total, %d erased, %d pages written."
        % (flash_erase_size >> 10, sector_count, erase_count, page_count))
  _notify(progress, "complete", sector_count,
          total_sectors or sector_count, None)
  return True


def flash(filepath, addr=0, close=True, progress=None):
  filedata, gz = filedata_gz(filepath)
  if not filedata:
    return False
  status = flash_stream(filedata, addr, progress)
  if close:
    flash_close()
  return status


def flashrd(addr=0, length=1):
  data = bytearray(length)
  flash_read(data, addr)
  return data
