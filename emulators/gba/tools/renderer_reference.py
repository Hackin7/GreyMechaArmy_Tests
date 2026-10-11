#!/usr/bin/env python3
"""Produce the original parallel renderer with the same bus lowering."""
import sys
from pathlib import Path
from prepare_rtl import prepare

source, output = map(Path, sys.argv[1:])
prepare(source, output)
file = output / 'gba_gpu_drawer.vhd'
text = file.read_text().replace('entity gba_gpu_drawer is', 'entity gba_gpu_drawer_reference is')
text = text.replace('of gba_gpu_drawer is', 'of gba_gpu_drawer_reference is')
(output / 'gba_gpu_drawer_reference.vhd').write_text(text)
file = output / 'gba_savestates.vhd'
text = file.read_text().replace('entity gba_savestates is', 'entity gba_savestates_reference is')
text = text.replace('of gba_savestates is', 'of gba_savestates_reference is')
(output / 'gba_savestates_reference.vhd').write_text(text)
