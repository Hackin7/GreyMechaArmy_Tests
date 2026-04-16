PROJ = greymecha_fpga_buzzer

SHELL = bash
RTL_SOURCES = src/top.v

all: $(PROJ).bit

tmp.v: $(RTL_SOURCES)
	mkdir -p log
	cat $^ > $@

$(PROJ).json: tmp.v
	bash -lc "set -o pipefail; yosys -p 'read_verilog $<; synth_ecp5 -top top -json $@' | tee log/yosys.log"

$(PROJ)_out.config: $(PROJ).json pinout.lpf
	bash -lc "set -o pipefail; nextpnr-ecp5 --json $< --textcfg $@ --25k --package CABGA256 --lpf pinout.lpf | tee log/nextpnr-ecp5.log"

$(PROJ).bit: $(PROJ)_out.config
	bash -lc "set -o pipefail; ecppack --svf $(PROJ).svf $< $@ | tee log/ecppack.log"

bit: $(PROJ).bit

clean:
	rm -rf log tmp.v $(PROJ).json $(PROJ)_out.config $(PROJ).bit $(PROJ).svf

.PHONY: all bit clean
