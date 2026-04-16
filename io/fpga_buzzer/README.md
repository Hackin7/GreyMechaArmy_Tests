# GreyMecha FPGA Buzzer Template

This template drives a passive buzzer connected to pin `F16` with a square wave at the A4 note (`440 Hz`).

## Files

- `src/top.v`: Minimal top-level module that uses the internal oscillator and toggles the buzzer output.
- `pinout.lpf`: Constrains `buzzer` to `F16`.
- `Makefile`: Builds a `.bit` file with `yosys`, `nextpnr-ecp5`, and `ecppack`.

## Build

Run:

```sh
make
```

That produces `greymecha_fpga_buzzer.bit`.

## Customize

To change the note, edit `NOTE_HZ` in `src/top.v`.

This is meant for a passive buzzer. An active buzzer usually only needs a static enable level instead of a tone signal.
