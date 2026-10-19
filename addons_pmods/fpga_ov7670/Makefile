SHELL := /bin/bash
BUILD := build
YOSYS ?= yosys
NEXTPNR ?= nextpnr-ecp5
ECPPACK ?= ecppack
IVERILOG ?= iverilog
VVP ?= vvp
PYTHON ?= python3
HOLD_COLOR_BARS ?= 0
PANEL_SWAP_RB ?= 0
PNR_SEED ?= 3
RTL := $(wildcard src/*.v)
CORE := $(filter-out src/top.v src/ecp5_oled_pll.v,$(RTL))
TESTS := offset controls capture display panel sccb sccb_hold debug scan pins

.PHONY: all bit sim clean FORCE
.DELETE_ON_ERROR:
all: bit
bit: $(BUILD)/fpga_ov7670.bit
$(BUILD):
	mkdir -p $@

# Track parameter changes without forcing a rebuild for unchanged settings.
$(BUILD)/settings: FORCE | $(BUILD)
	@printf 'HOLD_COLOR_BARS=%s\nPANEL_SWAP_RB=%s\n' $(HOLD_COLOR_BARS) $(PANEL_SWAP_RB) > $@.new
	@cmp -s $@.new $@ && rm $@.new || mv $@.new $@

$(BUILD)/top.json: $(RTL) src/gc9a01_init_rom.vh $(BUILD)/settings
	$(YOSYS) -Q -T -p 'read_verilog -sv -Isrc $(RTL); chparam -set HOLD_COLOR_BARS $(HOLD_COLOR_BARS) -set PANEL_SWAP_RB $(PANEL_SWAP_RB) top; synth_ecp5 -top top -json $@; check -assert; stat' > $(BUILD)/yosys.log 2>&1

$(BUILD)/route-settings: FORCE | $(BUILD)
	@printf 'PNR_SEED=%s\n' $(PNR_SEED) > $@.new
	@cmp -s $@.new $@ && rm $@.new || mv $@.new $@

$(BUILD)/top.config: $(BUILD)/top.json pinout.lpf tools/clocks.py $(BUILD)/route-settings
	$(NEXTPNR) --25k --package CABGA256 --speed 6 --freq 50 --seed $(PNR_SEED) --json $< --lpf pinout.lpf --pre-pack tools/clocks.py --textcfg $@ --report $(BUILD)/timing.json > $(BUILD)/nextpnr.log 2>&1
	$(PYTHON) tools/check_build.py $(BUILD)/top.json $(BUILD)/timing.json $(BUILD)/nextpnr.log

$(BUILD)/fpga_ov7670.bit: $(BUILD)/top.config
	$(ECPPACK) $< $@

sim: $(addprefix $(BUILD)/passed-,$(TESTS))
	$(PYTHON) tools/test_launcher.py
$(BUILD)/passed-%: sim/tb_%.sv $(CORE) src/gc9a01_init_rom.vh | $(BUILD)
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Isrc -s tb_$* -o $(BUILD)/tb_$*.vvp $< $(CORE)
	$(VVP) $(BUILD)/tb_$*.vvp
	touch $@

$(BUILD)/passed-sccb_hold: sim/tb_sccb.sv $(CORE) | $(BUILD)
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Isrc -s tb_sccb -Ptb_sccb.HOLD=1 -o $(BUILD)/tb_sccb_hold.vvp $< $(CORE)
	$(VVP) $(BUILD)/tb_sccb_hold.vvp
	touch $@

clean:
	rm -rf $(BUILD)
