SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
PYTHON ?= python3
RESOURCES ?= /mnt/d/Github/WORK/NUS/EE2026/EE2026_Project_B-MODs/integration_group_basic_tasks/integration_group_basic_tasks.srcs/sources_1/imports/res
OLED := ../../io/fpga_oled_fast/src
RTL := rtl/neural_net.v rtl/buttons.v rtl/inference.v rtl/paint_ui.v rtl/renderer.v rtl/app.v
PANEL := $(OLED)/simple_spi_master.v $(OLED)/oled_init.v $(OLED)/oled_stream.v $(OLED)/oled_gc9a01.v
INCLUDES := -Ibuild/generated -I$(OLED)

all: bit
build/generated/model.sha256: scripts/export_model.py ../mnist_c/export_model.py $(RESOURCES)/weights.coe $(RESOURCES)/00.coe
	$(PYTHON) scripts/export_model.py --resources "$(RESOURCES)"
build/generated/font.vh: scripts/gen_font.py
	$(PYTHON) $<
model: build/generated/model.sha256 build/generated/font.vh
sim-inference: model
	iverilog -g2012 -s tb_inference $(INCLUDES) -o build/inference.vvp sim/tb_inference.v rtl/neural_net.v rtl/inference.v
	vvp build/inference.vvp | tee build/inference.log
sim-controls: model
	iverilog -g2012 -s tb_controls $(INCLUDES) -o build/controls.vvp sim/tb_controls.v rtl/buttons.v rtl/paint_ui.v
	vvp build/controls.vvp | tee build/controls.log
sim-panel: model
	iverilog -g2012 -s tb_panel $(INCLUDES) -o build/panel.vvp sim/tb_panel.v rtl/renderer.v $(PANEL)
	vvp build/panel.vvp | tee build/panel.log
	$(PYTHON) scripts/render_preview.py
sim-system: model
	iverilog -g2012 -s tb_system $(INCLUDES) -o build/system.vvp sim/tb_system.v $(RTL)
	vvp build/system.vvp | tee build/system.log
sim: sim-inference sim-controls sim-panel sim-system
build/design.json: build/generated/model.sha256 build/generated/font.vh $(RTL) rtl/top.v rtl/paint_pll.v $(PANEL) $(OLED)/gc9a01_init_rom.vh
	yosys -Q -p 'read_verilog $(INCLUDES) $(RTL) rtl/top.v rtl/paint_pll.v $(PANEL); synth_ecp5 -top top -json $@' > build/yosys.log 2>&1 || { tail -60 build/yosys.log; exit 1; }
	tail -35 build/yosys.log
build/design.config: build/design.json pinout.lpf
	nextpnr-ecp5 --25k --package CABGA256 --freq 75 --json $< --lpf pinout.lpf --textcfg $@ --report build/timing.json > build/nextpnr.log 2>&1 || { tail -45 build/nextpnr.log; exit 1; }
	$(PYTHON) scripts/summarize_timing.py
paint_mnist.bit: build/design.config
	ecppack $< $@
bit: paint_mnist.bit
.PHONY: all model sim sim-inference sim-controls sim-panel sim-system bit
