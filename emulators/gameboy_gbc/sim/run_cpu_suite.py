#!/usr/bin/env python3
"""Run every vendored Blargg CPU instruction ROM and summarize by filename."""

import argparse
import concurrent.futures
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_EXE = ROOT / "build" / "sim" / "obj_dir" / "Vtb_cpu_instr"


def run_one(executable: Path, rom: Path, timeout: int):
    relative_rom = rom.relative_to(ROOT).as_posix()
    result = subprocess.run(
        [str(executable), f"+ROM={relative_rom}"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
    )
    passed = result.returncode == 0 and "PASS: instruction ROM reported Passed" in result.stdout
    return rom.name, passed, result.returncode, result.stdout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--jobs", type=int, default=min(11, os.cpu_count() or 1))
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()

    roms = sorted((ROOT / "sim" / "roms").glob("[0-9][0-9]-*.gb"))
    if len(roms) != 11:
        print(f"FAIL: expected 11 CPU instruction ROMs, found {len(roms)}", file=sys.stderr)
        return 2
    if not args.executable.is_file():
        print(f"FAIL: simulator executable not found: {args.executable}", file=sys.stderr)
        return 2

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(run_one, args.executable, rom, args.timeout) for rom in roms]
        for future in concurrent.futures.as_completed(futures):
            results.append(future.result())

    failures = 0
    for name, passed, returncode, output in sorted(results):
        if passed:
            print(f"PASS {name}")
        else:
            failures += 1
            print(f"FAIL {name} (exit {returncode})")
            print(output.rstrip())

    print(f"\n{len(results) - failures}/{len(results)} instruction ROMs passed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
