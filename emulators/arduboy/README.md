# Arduboy Emulator for GreyMecha

This directory contains an FPGA Arduboy emulator for the GreyMecha ECP5 badge.
It integrates the AVR core from `agg23/openfpga-arduboy`, loads standard 32 KiB
Arduboy Intel HEX files through the RP2350-to-FPGA SPI bridge, decodes the
emulated SSD1306 traffic, and displays the 128x64 image in the centre of the
badge's 240x240 GC9A01 panel.

## Implemented

- ATmega32U4-compatible OpenFPGA AVR core and 32 KiB host-loadable program RAM.
- SSD1306 SPI command/data decoder with horizontal and page addressing support.
- Button-selectable centered 1x, 1.5x, and 2x monochrome viewports on the
  circular GC9A01 display. The 2x mode is center-cropped horizontally to fit.
- Seven debounced physical controls mapped to Arduboy directions, A, B, and reset.
- Arduboy differential speaker output converted to the single-ended passive
  GreyMecha buzzer on FPGA pin `F16`.
- CircuitPython badge launcher that releases the display, configures the FPGA,
  loads a game, hands display ownership to the SoC, and releases AVR reset.

EEPROM and Arduboy FX external-flash persistence are not implemented yet.

## Controls

```text
btn[0]       Left
btn[1]       Up
btn[2]       Display scale (short press); board reset (hold for over 2 seconds)
btn[3]       Down
btn[4]       Right
btn_grey_n   A
btn_rst_n    B
```

Display scale changes on release, so a long hold does not also change scale.
The long-press reset restarts the emulated board from the already-loaded program
flash; the flash contents and host-loader state are retained.

## Host SPI Commands

Block writes use `command, address_hi, address_lo, length_hi, length_lo, data...`.

```text
0x01  Assert AVR reset
0x02  Release AVR reset
0x03  Give framebuffer ownership to the host
0x04  Give framebuffer ownership to the Arduboy SoC
0x10  Write SSD1306-layout framebuffer bytes
0x20  Write AVR program bytes
0x30  Reserved EEPROM write
0x40  Reserved FX-cache write
0x41  Reserved FX-cache tag
```

Status bit 0 is AVR reset, bit 1 is host display ownership, bit 2 is an FX
request, and bit 3 indicates a busy host bridge.

## Build

The build requires Yosys, nextpnr-ecp5, and ecppack:

```bash
make bit
```

This produces `arduboy_fx.bit`. Bitstreams, build logs, and synthesis
intermediates are ignored so committed source always remains the source of truth.

The OLED engine runs in its dedicated approximately 75 MHz clock domain. The AVR
core runs from the CPU PLL output.

## Badge Install

After building, copy these files to `/apps/arduboy_fx/` on the badge:

```text
/apps/arduboy_fx/main.py
/apps/arduboy_fx/arduboy_fx.bit   (the newly built arduboy_fx.bit)
/apps/arduboy_fx/games/1nvader.hex
```

Run `main.py` from the badge app loader or directly in Thonny. Change
`DEFAULT_HEX_PATH` in `badge/main.py` to select another firmware image.

## Display Simulation

`sim/tb_oled_decode_render.v` exercises horizontal and page-addressed SSD1306
writes. `tools/render_oled_sim.py` converts the captured framebuffer and circular
panel data into PNG previews for visual inspection.

## Upstream Core

The AVR implementation under `vendor/openfpga-arduboy` comes from
`agg23/openfpga-arduboy`. Its original licensing files are retained in the
vendored source tree.
