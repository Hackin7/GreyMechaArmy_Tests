SHELL := /bin/bash
BUILD := build
YOSYS ?= yosys
NEXTPNR ?= nextpnr-ecp5
ECPPACK ?= ecppack
IVERILOG ?= iverilog
VVP ?= vvp
PYTHON ?= python3
HOLD_COLOR_BARS ?= 0
PANEL_SWAP_RB ?= 1
TIMING_PROFILE ?= 2
PNR_SEED ?= 3
RTL := $(wildcard src/*.v)
CORE := $(filter-out src/top.v src/ecp5_oled_pll.v,$(RTL))
TESTS := offset controls capture display panel sccb sccb_hold sccb_divider sccb_fast debug debug_wide scan pins triple ram3 window window_swap color_probe
TESTS += isp_controls isp_pixels isp_panel isp_spi isp_gamma
TESTS += debug_isp

.PHONY: all bit sim clean FORCE
.DELETE_ON_ERROR:
all: bit
bit: $(BUILD)/fpga_ov7670.bit
$(BUILD):
	mkdir -p $@

# Track parameter changes without forcing a rebuild for unchanged settings.
$(BUILD)/settings: FORCE | $(BUILD)
	@printf 'HOLD_COLOR_BARS=%s\nPANEL_SWAP_RB=%s\nTIMING_PROFILE=%s\n' $(HOLD_COLOR_BARS) $(PANEL_SWAP_RB) $(TIMING_PROFILE) > $@.new
	@cmp -s $@.new $@ && rm $@.new || mv $@.new $@

$(BUILD)/top.json: $(RTL) src/gc9a01_init_rom.vh $(BUILD)/settings
	$(YOSYS) -Q -T -p 'read_verilog -sv -Isrc $(RTL); chparam -set HOLD_COLOR_BARS $(HOLD_COLOR_BARS) -set PANEL_SWAP_RB $(PANEL_SWAP_RB) -set TIMING_PROFILE $(TIMING_PROFILE) top; synth_ecp5 -top top -json $@; check -assert; stat' > $(BUILD)/yosys.log 2>&1

$(BUILD)/route-settings: FORCE | $(BUILD)
	@printf 'PNR_SEED=%s\n' $(PNR_SEED) > $@.new
	@cmp -s $@.new $@ && rm $@.new || mv $@.new $@

$(BUILD)/top.config: $(BUILD)/top.json pinout.lpf tools/clocks.py $(BUILD)/route-settings
	$(NEXTPNR) --25k --package CABGA256 --speed 6 --freq 50 --seed $(PNR_SEED) --json $< --lpf pinout.lpf --pre-pack tools/clocks.py --textcfg $@ --report $(BUILD)/timing.json > $(BUILD)/nextpnr.log 2>&1
	$(PYTHON) tools/check_build.py $(BUILD)/top.json $(BUILD)/timing.json $(BUILD)/nextpnr.log

$(BUILD)/fpga_ov7670.bit: $(BUILD)/top.config
	$(ECPPACK) $< $@

sim: $(addprefix $(BUILD)/passed-,$(TESTS))
	$(PYTHON) tools/generate_gamma.py --check
	$(PYTHON) tools/test_launcher.py
	$(PYTHON) tools/test_status.py
	$(PYTHON) tools/test_measure.py
$(BUILD)/passed-%: sim/tb_%.sv $(CORE) src/gc9a01_init_rom.vh | $(BUILD)
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Isrc -s tb_$* -o $(BUILD)/tb_$*.vvp $< $(CORE)
	$(VVP) $(BUILD)/tb_$*.vvp
	touch $@

$(BUILD)/passed-sccb_hold: sim/tb_sccb.sv $(CORE) | $(BUILD)
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Isrc -s tb_sccb -Ptb_sccb.HOLD=1 -o $(BUILD)/tb_sccb_hold.vvp $< $(CORE)
	$(VVP) $(BUILD)/tb_sccb_hold.vvp
	touch $@

$(BUILD)/passed-sccb_divider: sim/tb_sccb.sv $(CORE) | $(BUILD)
	$(IVERILOG) -g2012 -Isrc -s tb_sccb -Ptb_sccb.PROFILE=1 -o $(BUILD)/tb_sccb_divider.vvp $< $(CORE)
	$(VVP) $(BUILD)/tb_sccb_divider.vvp
	touch $@

$(BUILD)/passed-sccb_fast: sim/tb_sccb.sv $(CORE) | $(BUILD)
	$(IVERILOG) -g2012 -Isrc -s tb_sccb -Ptb_sccb.PROFILE=2 -o $(BUILD)/tb_sccb_fast.vvp $< $(CORE)
	$(VVP) $(BUILD)/tb_sccb_fast.vvp
	touch $@

$(BUILD)/passed-debug_wide: sim/tb_debug.sv $(CORE) | $(BUILD)
	$(IVERILOG) -g2012 -Isrc -s tb_debug -Ptb_debug.WIDTH=928 -o $(BUILD)/tb_debug_wide.vvp $< $(CORE)
	$(VVP) $(BUILD)/tb_debug_wide.vvp
	touch $@

$(BUILD)/passed-window_swap: sim/tb_window.sv $(CORE) | $(BUILD)
	$(IVERILOG) -g2012 -Isrc -s tb_window -Ptb_window.SWAP=1 -o $(BUILD)/tb_window_swap.vvp $< $(CORE)
	$(VVP) $(BUILD)/tb_window_swap.vvp
	touch $@
$(BUILD)/passed-debug_isp: sim/tb_debug.sv $(CORE) | $(BUILD)
	$(IVERILOG) -g2012 -Isrc -s tb_debug -Ptb_debug.WIDTH=1088 -o $(BUILD)/tb_debug_isp.vvp $< $(CORE)
	$(VVP) $(BUILD)/tb_debug_isp.vvp
	touch $@

$(BUILD)/isp-vectors/stamp: tools/test_isp.py | $(BUILD)
	$(PYTHON) tools/test_isp.py $(BUILD)/isp-vectors
	touch $@
$(BUILD)/passed-isp_pixels: sim/tb_isp_pixels.sv $(CORE) $(BUILD)/isp-vectors/stamp
	$(IVERILOG) -g2012 -Isrc -s tb_isp_pixels -o $(BUILD)/tb_isp_pixels.vvp $< $(CORE)
	$(VVP) $(BUILD)/tb_isp_pixels.vvp +VECTORS=$(BUILD)/isp-vectors
	touch $@
$(BUILD)/passed-isp_panel: sim/tb_isp_panel.sv $(CORE) $(BUILD)/isp-vectors/stamp
	$(IVERILOG) -g2012 -Isrc -s tb_isp_panel -o $(BUILD)/tb_isp_panel.vvp $< $(CORE)
	$(VVP) $(BUILD)/tb_isp_panel.vvp +VECTORS=$(BUILD)/isp-vectors
	touch $@
$(BUILD)/passed-isp_gamma: sim/tb_isp_gamma.sv $(CORE) $(BUILD)/isp-vectors/stamp
	$(IVERILOG) -g2012 -Isrc -s tb_isp_gamma -o $(BUILD)/tb_isp_gamma.vvp $< $(CORE)
	$(VVP) $(BUILD)/tb_isp_gamma.vvp +VECTORS=$(BUILD)/isp-vectors
	touch $@

clean:
	rm -rf $(BUILD)
