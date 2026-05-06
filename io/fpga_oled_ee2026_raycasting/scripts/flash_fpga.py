#!/usr/bin/env python3
"""Flash fpga_oled_fast bitstream onto the GreyMecha Army badge.

Updates the existing bitstream slot at D:\\hackin7\\picorv32_test_spi\\fpga_oled.bit
and triggers `hardware.fpga.upload_bitstream(...)` over the CircuitPython REPL on COM17.
Calls `displayio.release_displays()` first so the RP2350 releases the OLED pins
before the FPGA bitstream takes over (avoids two bus masters fighting).

Pattern follows the on-board reference at D:\\hackin7\\picorv32_test_spi\\run.py.

Usage: python scripts/flash_fpga.py [COM_PORT]
"""
import os
import shutil
import sys
import time

import serial

DEFAULT_PORT = "COM17"
BAUD = 115200

# NEVER point this at fpga_oled.bit — that is the user's preserved
# original-speed bitstream. Use the _fast slot for our optimized streamer.
DEST_HOST = r"D:\hackin7\picorv32_test_spi\fpga_oled_fast.bit"
DEST_DEVICE = "/hackin7/picorv32_test_spi/fpga_oled_fast.bit"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
SRC_BIT = os.path.join(PROJECT_DIR, "fpga_oled.bit")

# REPL statements sent one-per-line. Each is a single Python statement
# so the friendly REPL processes them without indent-handling complications.
# Order matters:
# 1. release_displays + explicit hw_state display_bus deinit, in case the
#    Python references in hw_state are keeping busio.SPI alive.
# 2. gc.collect() so any released objects' destructors actually run and
#    free the underlying GP2/GP3 (SPI) and GP4/5/6 (DigitalInOut) pins.
# 3. Probe each OLED pin with a fresh DigitalInOut, then deinit — this
#    confirms the pin is free (errors silently if still held by busio.SPI).
# 4. Release prior upload_bitstream's GP20 (JTAG reset) if any.
# 5. Upload + deinit GP20.
REPL_LINES = [
    "import displayio",
    "displayio.release_displays()",
    r"exec('try:\n import hardware\n hardware.hw_state[\"display_bus\"].deinit()\nexcept: pass')",
    "import gc; gc.collect()",
    r"exec('import board, digitalio\nfor _p in (board.GP2, board.GP3, board.GP4, board.GP5, board.GP6):\n try:\n  _d=digitalio.DigitalInOut(_p); _d.deinit()\n except: pass')",
    "import hardware.fpga",
    r"exec('try: h.deinit()\nexcept: pass')",
    f"h = hardware.fpga.upload_bitstream({DEST_DEVICE!r})",
    "h.deinit()",
    "print('FPGA_UPLOAD_DONE')",
]


def safe_print(s):
    sys.stdout.write(s.encode("ascii", "replace").decode("ascii"))
    sys.stdout.flush()


def copy_bitstream():
    if not os.path.isfile(SRC_BIT):
        sys.exit(f"Bitstream not found: {SRC_BIT}")
    # Refuse to ever overwrite the preserved original-speed bitstream.
    if os.path.basename(DEST_HOST).lower() == "fpga_oled.bit":
        sys.exit(
            "DEST_HOST points to fpga_oled.bit. That file is the preserved "
            "original; refusing to overwrite. Edit DEST_HOST/DEST_DEVICE to "
            "use a different filename."
        )
    new_file = not os.path.isfile(DEST_HOST)
    shutil.copy2(SRC_BIT, DEST_HOST)
    verb = "Created" if new_file else "Updated"
    print(f"{verb} {DEST_HOST} ({os.path.getsize(DEST_HOST)} bytes)")


def drain(ser, secs):
    t0 = time.time()
    out = []
    while time.time() - t0 < secs:
        n = ser.in_waiting
        if n:
            out.append(ser.read(n).decode("utf-8", errors="replace"))
        else:
            time.sleep(0.02)
    return "".join(out)


def wait_for_prompt(ser, deadline_secs=3.0):
    """Read until we see a '>>> ' prompt at end of a flushed buffer."""
    buf = ""
    t0 = time.time()
    while time.time() - t0 < deadline_secs:
        n = ser.in_waiting
        if n:
            buf += ser.read(n).decode("utf-8", errors="replace")
            if buf.rstrip().endswith(">>>"):
                return buf
        else:
            time.sleep(0.02)
    return buf  # didn't see prompt — return what we got


def send_line(ser, line, deadline_secs=20.0, marker=None):
    """Send a single REPL line. Wait for either next prompt or marker."""
    ser.write((line + "\r\n").encode())
    buf = ""
    t0 = time.time()
    while time.time() - t0 < deadline_secs:
        n = ser.in_waiting
        if n:
            chunk = ser.read(n).decode("utf-8", errors="replace")
            buf += chunk
            safe_print(chunk)
            if marker and marker in buf:
                return buf, True
            if buf.rstrip().endswith(">>>"):
                return buf, True
            if "Traceback" in buf:
                # let traceback finish streaming
                time.sleep(0.4)
                extra = ser.read(ser.in_waiting).decode("utf-8", errors="replace")
                buf += extra
                safe_print(extra)
                return buf, False
        else:
            time.sleep(0.02)
    return buf, False


def flash(port):
    print(f"Opening {port} at {BAUD} baud...")
    with serial.Serial(port, BAUD, timeout=0.5) as ser:
        # Interrupt code.py and any nested loops/sleeps
        for _ in range(6):
            ser.write(b"\r\x03")
            time.sleep(0.15)
        # Press a key to leave the "Press any key to enter the REPL" state
        ser.write(b"\r")
        time.sleep(0.3)
        banner = drain(ser, 0.6)
        safe_print("--- after Ctrl-C / Enter ---\n")
        safe_print(banner[-500:] if len(banner) > 500 else banner)
        if not banner.rstrip().endswith(">>>"):
            # Hit Enter again to coax a prompt
            ser.write(b"\r")
            time.sleep(0.2)
            banner += drain(ser, 0.4)
            safe_print(banner[-200:])

        safe_print("\n--- sending REPL lines ---\n")
        success = False
        for line in REPL_LINES:
            safe_print(f">>> {line}\n")
            marker = "FPGA_UPLOAD_DONE" if line.startswith("print(") else None
            buf, ok = send_line(ser, line, deadline_secs=30.0, marker=marker)
            if not ok and "Traceback" in buf:
                return False
            if marker and marker in buf:
                success = True
                break

    return success


def main():
    args = sys.argv[1:]
    flash_original = "--original" in args
    args = [a for a in args if a != "--original"]
    port = args[0] if args else DEFAULT_PORT

    if flash_original:
        # Skip copy; use the known-good original bitstream already on the badge.
        # This is the diagnostic mode: program the FPGA with the proven-working
        # slow per-byte version so we can isolate "is our flow + OLED hardware
        # working?" from "is our streaming bitstream correct?".
        global REPL_LINES, DEST_DEVICE
        DEST_DEVICE = "/hackin7/picorv32_test_spi/fpga_oled.bit"
        REPL_LINES = [l for l in REPL_LINES if "fpga_oled_fast.bit" not in l]
        REPL_LINES.insert(-2,
            f"h = hardware.fpga.upload_bitstream({DEST_DEVICE!r})")
        print(f"DIAGNOSTIC MODE: flashing original {DEST_DEVICE} (no copy).")
    else:
        copy_bitstream()

    ok = flash(port)
    if ok:
        print("\nOK: bitstream programmed. Look at the OLED.")
        return 0
    print("\nFAIL: did not see success marker. Check output above.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
