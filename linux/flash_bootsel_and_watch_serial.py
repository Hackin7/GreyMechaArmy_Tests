import ctypes
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent
UF2 = ROOT / "flash-image.uf2"


def logical_drives():
    bitmask = ctypes.windll.kernel32.GetLogicalDrives()
    for i in range(26):
        if bitmask & (1 << i):
            yield Path(f"{chr(ord('A') + i)}:/")


def find_bootsel_drive():
    for drive in logical_drives():
        info = drive / "INFO_UF2.TXT"
        if not info.exists():
            continue
        try:
            text = info.read_text(errors="ignore")
        except OSError:
            continue
        if "RP2350" in text or "RPI-RP2" in text or "Pico" in text:
            return drive, text.strip()
    return None, None


def port_snapshot():
    try:
        output = subprocess.check_output(
            ["pnputil", "/enum-devices", "/class", "Ports"],
            universal_newlines=True,
            stderr=subprocess.STDOUT,
        )
    except (OSError, subprocess.CalledProcessError):
        return set(), ""

    ports = set()
    for line in output.splitlines():
        line = line.strip()
        if "Device Description:" in line and "(COM" in line:
            ports.add(line)
    return ports, output


def main():
    if not UF2.exists():
        print(f"Missing {UF2}", file=sys.stderr)
        return 1

    before, _ = port_snapshot()
    print("Waiting for RP2350 BOOTSEL drive...")
    print("Hold BOOTSEL while plugging/resetting the board.")

    drive = None
    info = None
    deadline = time.time() + 180
    while time.time() < deadline:
        drive, info = find_bootsel_drive()
        if drive:
            break
        time.sleep(0.5)

    if not drive:
        print("Timed out waiting for BOOTSEL drive.", file=sys.stderr)
        return 2

    print(f"Found BOOTSEL drive at {drive}")
    if info:
        print(info)

    target = drive / UF2.name
    print(f"Copying {UF2.name} to {target}...")
    shutil.copyfile(UF2, target)
    print("Copy complete. Waiting for the board to reboot and enumerate...")

    deadline = time.time() + 90
    while time.time() < deadline:
        now, raw = port_snapshot()
        new_ports = now - before
        if new_ports:
            print("New serial device(s):")
            for port in sorted(new_ports):
                print(port)
            return 0
        time.sleep(1)

    print("No new COM port appeared after flashing.", file=sys.stderr)
    return 3


if __name__ == "__main__":
    raise SystemExit(main())
