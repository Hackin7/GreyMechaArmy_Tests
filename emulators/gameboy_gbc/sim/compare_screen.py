#!/usr/bin/env python3
"""Compare an emulator framebuffer capture with the cgb-acid2 reference."""

from pathlib import Path
import sys
from PIL import Image, ImageChops


capture_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
    "build/sim/cgb-acid2.ppm"
)
reference_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(
    "sim/reference/cgb-acid2-reference.png"
)

capture = Image.open(capture_path).convert("RGB")
reference = Image.open(reference_path).convert("RGB")

if capture.size != reference.size:
    raise SystemExit(
        f"size mismatch: capture={capture.size}, reference={reference.size}"
    )

diff = ImageChops.difference(capture, reference)
pixels = list(diff.getdata())
differing = sum(pixel != (0, 0, 0) for pixel in pixels)
squared_error = sum(channel * channel for pixel in pixels for channel in pixel)
max_error = max(channel for pixel in pixels for channel in pixel)
mse = squared_error / (len(pixels) * 3)

capture.save(capture_path.with_suffix(".png"))
diff.save(capture_path.with_name(capture_path.stem + "-diff.png"))

print(f"capture_size={capture.size}")
print(f"reference_size={reference.size}")
print(f"differing_pixels={differing}/{len(pixels)}")
print(f"max_channel_error={max_error}")
print(f"mse={mse:.6f}")
print(f"difference_bbox={diff.getbbox()}")
