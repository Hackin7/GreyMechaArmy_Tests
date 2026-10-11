"""Execute a local script through a CircuitPython raw REPL; save its output.

Requires pyserial. Does not copy files or alter the badge's root code.py.
"""
import argparse
import sys
import time
from pathlib import Path
import serial


def read_until(console, marker, timeout):
    result = bytearray()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        # Read one byte so the next raw-REPL delimiter stays in the UART buffer.
        part = console.read(1)
        if part:
            result.extend(part)
            if result.endswith(marker):
                return bytes(result)
    raise RuntimeError("REPL timeout; received: " + repr(bytes(result)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", required=True)
    parser.add_argument("--file", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--timeout", type=float, default=45)
    args = parser.parse_args()
    source = Path(args.file).read_bytes().replace(b"\r\n", b"\n")
    with serial.Serial(args.port, 115200, timeout=0.1) as console:
        console.write(b"\r\x03\x03")
        time.sleep(0.5)
        console.write(b"\x02\r\x03")
        time.sleep(0.5)
        console.reset_input_buffer()
        console.write(b"\x01")
        read_until(console, b"raw REPL; CTRL-B to exit\r\n>", 5)
        for offset in range(0, len(source), 128):
            console.write(source[offset:offset + 128])
            time.sleep(0.003)
        console.write(b"\x04")
        ack = read_until(console, b"OK", 5)
        if ack != b"OK":
            raise RuntimeError("Raw REPL refused script: " + repr(ack))
        try:
            stdout = read_until(console, b"\x04", args.timeout)[:-1]
            stderr = read_until(console, b"\x04", 5)[:-1]
            read_until(console, b">", 5)
        finally:
            console.write(b"\x02")
        result = stdout.decode("utf-8", "replace")
        if stderr:
            result += "\nDEVICE_EXCEPTION:\n" + stderr.decode("utf-8", "replace")
        # CircuitPython emits CR/CR/LF through this console; keep text logs clean.
        result = result.replace("\r\n", "\n").replace("\r", "")
        Path(args.log).write_text(result, encoding="utf-8")
        print(result)
        if stderr:
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
