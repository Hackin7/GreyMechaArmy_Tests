#!/usr/bin/env python3
"""Sample every 16th entry from sin.mem / cos.mem so the LUTs fit in ECP5 BRAM.

Original LUTs are 65536 entries x 16-bit = 1 Mib each — 2 Mib total exceeds
the ECP5-25K's ~1 Mib BRAM budget. Sampling 1-of-16 yields 4096 entries each
(64 Kib / 4 EBRs), comfortably affordable. Indexing in raycasting.v compensates
with `array[idx >> 4]`.
"""
import os

SRC_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "raycasting")
DST_DIR = os.path.dirname(__file__)
N_OUT = 4096
STRIDE = 16

def shrink(name):
    src = os.path.join(SRC_DIR, name)
    dst = os.path.join(DST_DIR, name)
    with open(src) as f:
        # Strip blank/comment lines, keep first 16-bit hex token per line.
        entries = []
        for line in f:
            tok = line.strip()
            if not tok or tok.startswith("//") or tok.startswith("@"):
                continue
            entries.append(tok.split()[0])
            if len(entries) >= N_OUT * STRIDE:
                break
    sampled = [entries[i] for i in range(0, len(entries), STRIDE)][:N_OUT]
    while len(sampled) < N_OUT:
        sampled.append("0000")
    with open(dst, "w") as f:
        f.write("\n".join(sampled) + "\n")
    print(f"{name}: {len(entries)} src -> {len(sampled)} out -> {dst}")

if __name__ == "__main__":
    shrink("sin.mem")
    shrink("cos.mem")
