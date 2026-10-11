"""Invoke the on-badge flash ROM installer through CircuitPython's REPL."""

import argparse
import time

import serial


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="COM6")
    parser.add_argument(
        "--rom", default="/apps/gameboy_gbc/games/defcon.gbc")
    parser.add_argument("--timeout", type=int, default=1200)
    args = parser.parse_args()

    body = (
        "import microcontroller,supervisor\n"
        "p=%r\n"
        "n=microcontroller.nvm\n"
        "n[0]=0xAB\n"
        "n[1]=len(p)\n"
        "n[2:2+len(p)]=p.encode('utf-8')\n"
        "supervisor.reload()\n" % args.rom
    )
    command = ("exec(%r)\r\n" % body).encode("utf-8")

    deadline = time.monotonic() + args.timeout
    transcript = ""
    with serial.Serial(args.port, 115200, timeout=0.5) as console:
        console.dtr = True
        console.rts = True
        time.sleep(1)
        console.write(b"\x03\r\n")
        time.sleep(1)
        console.read(8192)
        console.write(b"\r\n" + command)

        while time.monotonic() < deadline:
            chunk = console.read(4096)
            if chunk:
                text = chunk.decode("utf-8", "replace")
                transcript += text
                print(text.encode("ascii", "backslashreplace").decode(
                    "ascii"), end="", flush=True)
                lines = transcript.replace("\r", "").splitlines()
                if any(line.startswith("GB_INSTALL_DONE ") for line in lines):
                    return
                if "Traceback (most recent call last)" in transcript:
                    raise RuntimeError("Badge installer raised an exception")
        raise TimeoutError("Timed out waiting for the badge installer")


if __name__ == "__main__":
    main()
