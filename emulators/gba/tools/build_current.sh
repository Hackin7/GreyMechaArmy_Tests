#!/usr/bin/env bash
# Rebuild the requested candidate without the BRAM-relocation experiment.
set -euo pipefail
cd "$(dirname "$0")/.."
make bit \
  BOARD_WORK="${GBA_BUILD_WORK:-/tmp/greymecha_gba_qspi67_psram50_colour}" \
  BUILD=build/qspi67-psram50-colour \
  FLASH_QSPI=1 FLASH_CYCLES=2 FLASH_RX_REGISTER=0 \
  PLL_CORE_DIV=26 PLL_FLASH_DIV=4 PSRAM_FAST_READ=1 "$@"
