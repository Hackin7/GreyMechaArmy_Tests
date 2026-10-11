SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
PROJ := fpga_psram_j1
RTL := src/spi_transaction.v src/psram_spi.v src/host_spi.v src/psram_demo.v src/top.v
FREQ ?= 60

all: build/$(PROJ).bit

build:
	mkdir -p build

build/$(PROJ).json: $(RTL) scripts/check_netlist.py | build
	yosys -p 'read_verilog $(RTL); synth_ecp5 -top top -json $@; check -assert' > build/yosys.log 2>&1
	python3 scripts/check_netlist.py $@ | tee build/netlist_check.log

build/$(PROJ).config: build/$(PROJ).json pinout.lpf
	nextpnr-ecp5 --25k --package CABGA256 --freq $(FREQ) --json $< --lpf pinout.lpf --textcfg $@ > build/nextpnr.log 2>&1

build/$(PROJ).bit: build/$(PROJ).config
	ecppack --compress --svf build/$(PROJ).svf $< $@ > build/ecppack.log 2>&1

test: | build
	iverilog -g2012 -Wall -s tb_psram_demo -o build/test.vvp $(filter-out src/top.v,$(RTL)) sim/aps6404_model.v sim/tb_psram_demo.v
	vvp build/test.vvp | tee build/simulation.log
	iverilog -g2005 -Wall -s tb_top_wiring -o build/top_test.vvp $(RTL) sim/aps6404_model.v sim/tb_top_wiring.v
	vvp build/top_test.vvp | tee build/top_simulation.log

lint:
	verilator --lint-only -Wall --top-module psram_demo $(filter-out src/top.v,$(RTL))

.PHONY: all test lint
