PROJ = fpga_oled
TARGET_FREQ_MHZ ?= 75

SHELL = bash
YOSYS_DEFS ?=

RTL_ORDER = src/simple_spi_master.v src/btn_debounce.v src/ecp5_oled_pll.v src/gc9a01_display.v src/top.v 

all: $(PROJ).bit

tmp.v: $(RTL_ORDER) src/gc9a01_init_rom.vh
	mkdir -p log
	cat $(RTL_ORDER) > $@

$(PROJ).json: tmp.v
	bash -lc "set -o pipefail; yosys -p 'read_verilog -Isrc $(YOSYS_DEFS) $<; synth_ecp5 -top top -json $@' | tee log/yosys.log"

$(PROJ)_out.config: $(PROJ).json pinout.lpf
	bash -lc "set -o pipefail; nextpnr-ecp5 --freq $(TARGET_FREQ_MHZ) --json $< --textcfg $@ --25k --package CABGA256 --lpf pinout.lpf | tee log/nextpnr-ecp5.log"

$(PROJ).bit: $(PROJ)_out.config
	bash -lc "set -o pipefail; ecppack --svf $(PROJ).svf $< $@ | tee log/ecppack.log"

bit: $(PROJ).bit

clean:
	rm -rf log tmp.v $(PROJ).json $(PROJ)_out.config $(PROJ).bit $(PROJ).svf

.PHONY: all bit clean
