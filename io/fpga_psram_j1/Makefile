SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
PROJ := fpga_psram_j1
RTL := src/spi_transaction.v src/spi_burst.v src/qpi_burst.v src/psram_spi.v src/host_spi.v src/psram_demo.v src/top.v
FREQ ?= 60
BUILD ?= build
QPI ?= 0
OSC_DIV ?= 3
HALF_PERIOD ?= 1
BURST_BYTES ?= 16
TRACE ?= 0
SPI_BURST ?= 1
SPI_FAST_READ ?= 1

all: $(BUILD)/$(PROJ).bit

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/$(PROJ).json: $(RTL) scripts/check_netlist.py | $(BUILD)
	yosys -p 'read_verilog $(RTL); chparam -set ENABLE_QPI $(QPI) -set OSC_DIV $(OSC_DIV) -set QPI_HALF_PERIOD $(HALF_PERIOD) -set BURST_BYTES $(BURST_BYTES) -set TRACE $(TRACE) -set SPI_BURST $(SPI_BURST) -set SPI_FAST_READ $(SPI_FAST_READ) top; synth_ecp5 -top top -json $@; check -assert' > $(BUILD)/yosys.log 2>&1
	python3 scripts/check_netlist.py $@ | tee $(BUILD)/netlist_check.log

$(BUILD)/$(PROJ).config: $(BUILD)/$(PROJ).json pinout.lpf
	nextpnr-ecp5 --25k --package CABGA256 --freq $(FREQ) --json $< --lpf pinout.lpf --textcfg $@ > $(BUILD)/nextpnr.log 2>&1

$(BUILD)/$(PROJ).bit: $(BUILD)/$(PROJ).config
	ecppack --compress --svf $(BUILD)/$(PROJ).svf $< $@ > $(BUILD)/ecppack.log 2>&1

test: | build
	iverilog -g2012 -Wall -s tb_psram_demo -o build/test.vvp $(filter-out src/top.v,$(RTL)) sim/aps6404_model.v sim/tb_psram_demo.v
	vvp build/test.vvp | tee build/simulation.log
	iverilog -g2005 -Wall -s tb_top_wiring -o build/top_test.vvp $(RTL) sim/aps6404_model.v sim/tb_top_wiring.v
	vvp build/top_test.vvp | tee build/top_simulation.log
	iverilog -g2012 -Wall -s tb_psram_demo -Ptb_psram_demo.QPI=1 -o build/qpi_test.vvp $(filter-out src/top.v,$(RTL)) sim/aps6404_model.v sim/tb_psram_demo.v
	vvp build/qpi_test.vvp | tee build/qpi_simulation.log
	iverilog -g2012 -Wall -s tb_psram_demo -Ptb_psram_demo.QPI=1 -Ptb_psram_demo.HALF_PERIOD=1 -Ptb_psram_demo.BURST_BYTES=128 -Ptb_psram_demo.CLK_HALF_NS=5 -o build/qpi_fast_test.vvp $(filter-out src/top.v,$(RTL)) sim/aps6404_model.v sim/tb_psram_demo.v
	vvp build/qpi_fast_test.vvp | tee build/qpi_fast_simulation.log
	iverilog -g2005 -Wall -s tb_top_wiring -Ptb_top_wiring.QPI=1 -Ptb_top_wiring.OSC_DIV=3 -Ptb_top_wiring.HALF_PERIOD=1 -Ptb_top_wiring.BURST_BYTES=128 -o build/qpi_top_test.vvp $(RTL) sim/aps6404_model.v sim/tb_top_wiring.v
	vvp build/qpi_top_test.vvp | tee build/qpi_top_simulation.log
	iverilog -g2012 -Wall -s tb_psram_demo -Ptb_psram_demo.SPI_BURST=1 -Ptb_psram_demo.BURST_BYTES=8 -o build/spi_burst_test.vvp $(filter-out src/top.v,$(RTL)) sim/aps6404_model.v sim/tb_psram_demo.v
	vvp build/spi_burst_test.vvp | tee build/spi_burst_simulation.log
	iverilog -g2012 -Wall -s tb_psram_demo -Ptb_psram_demo.SPI_BURST=1 -Ptb_psram_demo.FAST_READ=1 -Ptb_psram_demo.HALF_PERIOD=1 -Ptb_psram_demo.BURST_BYTES=16 -Ptb_psram_demo.CLK_HALF_NS=5 -o build/spi_fast_test.vvp $(filter-out src/top.v,$(RTL)) sim/aps6404_model.v sim/tb_psram_demo.v
	vvp build/spi_fast_test.vvp | tee build/spi_fast_simulation.log
	iverilog -g2005 -Wall -s tb_top_wiring -Ptb_top_wiring.SPI_BURST=1 -Ptb_top_wiring.FAST_READ=1 -Ptb_top_wiring.OSC_DIV=3 -Ptb_top_wiring.HALF_PERIOD=1 -Ptb_top_wiring.BURST_BYTES=16 -o build/spi_fast_top_test.vvp $(RTL) sim/aps6404_model.v sim/tb_top_wiring.v
	vvp build/spi_fast_top_test.vvp | tee build/spi_fast_top_simulation.log

lint:
	verilator --lint-only -Wall --top-module psram_demo $(filter-out src/top.v,$(RTL))
	verilator --lint-only -Wall --top-module psram_demo -GENABLE_QPI=1 -GQPI_HALF_PERIOD=1 -GBURST_BYTES=128 $(filter-out src/top.v,$(RTL))
	verilator --lint-only -Wall --top-module psram_demo -GSPI_BURST=1 -GBURST_BYTES=8 $(filter-out src/top.v,$(RTL))
	verilator --lint-only -Wall --top-module psram_demo -GSPI_BURST=1 -GSPI_FAST_READ=1 -GQPI_HALF_PERIOD=1 -GBURST_BYTES=16 $(filter-out src/top.v,$(RTL))

.PHONY: all test lint
