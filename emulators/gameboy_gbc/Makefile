PROJ := gameboy_gbc
BRAM_ROM ?= 1
FLASH_ROM ?= 0
CACHE_SET_BITS ?= 5
PANEL_SWAP_RB ?= 1
FLASH_DIAGNOSTIC ?= 0
PANEL_DIAGNOSTIC ?= 0
TARGET_FREQ_MHZ ?= 16

SHELL := bash
PYTHON ?= python3
GHDL ?= ghdl
YOSYS ?= yosys
NEXTPNR ?= nextpnr-ecp5
ECPPACK ?= ecppack
VERILATOR ?= verilator
IVERILOG ?= iverilog
VVP ?= vvp
DEFCON_ROM ?= games/defcon.gbc

VENDOR := vendor/Gameboy_MiSTer
VENDOR_RTL := $(VENDOR)/rtl
BUILD := build
GEN := $(BUILD)/generated
LOG := $(BUILD)/log
# GHDL writes its library index atomically.  Keep that disposable cache on
# the Linux filesystem when building from the Windows-mounted WSL workspace.
GHDL_WORK ?= /tmp/$(PROJ)_ghdl

VHDL_ORDER := \
	$(VENDOR_RTL)/bus_savestates.vhd \
	$(VENDOR_RTL)/reg_savestates.vhd \
	$(VENDOR_RTL)/T80/T80_Pack.vhd \
	$(VENDOR_RTL)/T80/T80_Reg.vhd \
	$(VENDOR_RTL)/T80/T80_MCode.vhd \
	$(VENDOR_RTL)/T80/T80_ALU.vhd \
	$(VENDOR_RTL)/T80/T80.vhd \
	$(VENDOR_RTL)/T80/GBse.vhd \
	$(VENDOR_RTL)/gbc_snd.vhd

MAPPER_RTL := $(wildcard $(VENDOR_RTL)/mappers/*.v) $(wildcard $(VENDOR_RTL)/mappers/*.sv)

UPSTREAM_RTL := \
	$(VENDOR_RTL)/megaswizzle.sv \
	$(VENDOR_RTL)/hdma.v \
	$(VENDOR_RTL)/link.v \
	$(VENDOR_RTL)/timer.v \
	$(VENDOR_RTL)/sprites.v \
	$(VENDOR_RTL)/sprites_extra.v \
	$(VENDOR_RTL)/sprites_extra_store.v \
	$(VENDOR_RTL)/video.v \
	$(MAPPER_RTL) \
	$(VENDOR_RTL)/cart.v \
	$(VENDOR_RTL)/gb.v

LOCAL_RTL := \
	rtl/cheatcodes_stub.v \
	rtl/gb_dpram.v \
	rtl/savestate_stubs.v \
	rtl/gb_clock_enable.v \
	rtl/ecp5_gb_pll.v \
	rtl/gb_spi_phy.v \
	rtl/gb_host_bridge.v \
	rtl/ecp5_flash_reader.v \
	rtl/gb_rom_cache.v \
	rtl/gb_save_cache.v \
	rtl/gb_line_capture.v \
	rtl/gc9a01_window_init.v \
	rtl/gc9a01_line_stream.v \
	rtl/gc9a01_native.v \
	rtl/gb_core_wrapper.v \
	rtl/top.v

PANEL_RTL := \
	rtl/panel_common/btn_debounce.v \
	rtl/panel_common/simple_spi_master.v \
	rtl/panel_common/oled_init.v \
	rtl/panel_common/oled_stream.v \
	rtl/panel_common/oled_gc9a01.v

GENERATED_VHDL := $(GEN)/GBse.v $(GEN)/gbc_snd.v
ALL_RTL := $(GENERATED_VHDL) $(UPSTREAM_RTL) $(PANEL_RTL) $(LOCAL_RTL)

SIM_BUILD := $(BUILD)/sim
SIM_CPU_GEN := $(SIM_BUILD)/GBse_sim.v
SIM_CPU_EXE := $(SIM_BUILD)/obj_dir/Vtb_cpu_instr
SIM_SPI_EXE := $(SIM_BUILD)/obj_spi/Vtb_spi_rom_transfer
SIM_PANEL_EXE := $(SIM_BUILD)/obj_panel/Vtb_gc9a01_acid2
SIM_MAPPER_EXE := $(SIM_BUILD)/tb_mapper_header.vvp
SIM_CACHE_EXE := $(SIM_BUILD)/obj_cache/Vtb_cache_defcon
SIM_FLASH_DEFCON_EXE := $(SIM_BUILD)/obj_flash_defcon/Vtb_cache_defcon
SIM_FLASH_EXE := $(SIM_BUILD)/tb_flash_cache.vvp
SIM_CPU_RTL := \
	$(SIM_CPU_GEN) \
	$(GEN)/gbc_snd.v \
	$(UPSTREAM_RTL) \
	rtl/cheatcodes_stub.v \
	rtl/gb_dpram.v \
	rtl/savestate_stubs.v \
	rtl/gb_clock_enable.v \
	rtl/gb_rom_cache.v \
	rtl/gb_save_cache.v \
	rtl/gb_core_wrapper.v

.PHONY: all bit test sim sim-cpu-build sim-cpu sim-cpu-suite sim-spi-build sim-spi sim-panel-build sim-panel sim-mapper sim-cache-defcon sim-flash sim-flash-defcon clean generated

all: bit

$(GEN)/cgb_boot.hex: $(VENDOR)/BootROMs/cgb_boot.mif tools/mif_to_hex.py
	mkdir -p $(GEN)
	$(PYTHON) tools/mif_to_hex.py $< $@

$(GHDL_WORK)/work-obj08.cf: $(VHDL_ORDER)
	mkdir -p $(GHDL_WORK) $(GEN) $(LOG)
	$(GHDL) -a --std=08 -fsynopsys --workdir=$(GHDL_WORK) $(VHDL_ORDER)

$(GEN)/GBse.v: $(GHDL_WORK)/work-obj08.cf
	mkdir -p $(GEN)
	$(GHDL) --synth --std=08 -fsynopsys --workdir=$(GHDL_WORK) --out=verilog GBse > $(GHDL_WORK)/GBse.v
	cp $(GHDL_WORK)/GBse.v $@

$(GEN)/gbc_snd.v: $(GHDL_WORK)/work-obj08.cf
	mkdir -p $(GEN)
	$(GHDL) --synth --std=08 -fsynopsys --workdir=$(GHDL_WORK) --out=verilog gbc_snd > $(GHDL_WORK)/gbc_snd.v
	cp $(GHDL_WORK)/gbc_snd.v $@

generated: $(GENERATED_VHDL) $(GEN)/cgb_boot.hex

$(BUILD)/$(PROJ).json: $(ALL_RTL) $(GEN)/cgb_boot.hex
	mkdir -p $(BUILD) $(LOG)
	bash -lc "set -o pipefail; $(YOSYS) -p 'read_verilog -sv -Irtl/panel_common $(ALL_RTL); chparam -set BRAM_ROM $(BRAM_ROM) -set FLASH_ROM $(FLASH_ROM) -set CACHE_SET_BITS $(CACHE_SET_BITS) -set PANEL_SWAP_RB $(PANEL_SWAP_RB) -set FLASH_DIAGNOSTIC $(FLASH_DIAGNOSTIC) -set PANEL_DIAGNOSTIC $(PANEL_DIAGNOSTIC) top; synth_ecp5 -noabc9 -top top -json $@' 2>&1 | tee $(LOG)/yosys.log"

$(BUILD)/$(PROJ)_out.config: $(BUILD)/$(PROJ).json pinout.lpf
	bash -lc "set -o pipefail; $(NEXTPNR) --freq $(TARGET_FREQ_MHZ) --json $< --textcfg $@ --25k --package CABGA256 --lpf pinout.lpf 2>&1 | tee $(LOG)/nextpnr-ecp5.log"

$(BUILD)/$(PROJ).bit: $(BUILD)/$(PROJ)_out.config
	bash -lc "set -o pipefail; $(ECPPACK) --svf $(BUILD)/$(PROJ).svf $< $@ 2>&1 | tee $(LOG)/ecppack.log"

bit: $(BUILD)/$(PROJ).bit

.PHONY: bit-flash
bit-flash:
	rm -f $(BUILD)/$(PROJ).json $(BUILD)/$(PROJ)_out.config \
		$(BUILD)/$(PROJ).bit $(BUILD)/$(PROJ).svf \
		$(BUILD)/$(PROJ)_flash.bit
	$(MAKE) bit BRAM_ROM=0 FLASH_ROM=1
	cp $(BUILD)/$(PROJ).bit $(BUILD)/$(PROJ)_flash.bit

.PHONY: bit-flash-diagnostic
bit-flash-diagnostic:
	rm -f $(BUILD)/$(PROJ).json $(BUILD)/$(PROJ)_out.config \
		$(BUILD)/$(PROJ).bit $(BUILD)/$(PROJ).svf \
		$(BUILD)/$(PROJ)_flash_diagnostic.bit
	$(MAKE) bit BRAM_ROM=0 FLASH_ROM=1 FLASH_DIAGNOSTIC=1 PANEL_DIAGNOSTIC=1
	cp $(BUILD)/$(PROJ).bit $(BUILD)/$(PROJ)_flash_diagnostic.bit

test: $(GEN)/cgb_boot.hex
	$(PYTHON) -m unittest discover -s sim -p 'test_*.py' -v

sim: test

$(SIM_CPU_GEN): $(GEN)/GBse.v tools/prepare_iverilog_cpu.py
	mkdir -p $(SIM_BUILD)
	$(PYTHON) tools/prepare_iverilog_cpu.py $< $@

$(SIM_CPU_EXE): $(SIM_CPU_RTL) $(GEN)/cgb_boot.hex sim/tb_cpu_instr.v
	$(VERILATOR) --binary --timing -j 0 \
		-Wno-fatal -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC \
		-Wno-WIDTHEXPAND -Wno-PINMISSING -Wno-CASEINCOMPLETE \
		-Wno-MULTIDRIVEN -Wno-ASCRANGE \
		--top-module tb_cpu_instr -Mdir $(SIM_BUILD)/obj_dir \
		-Irtl -I$(VENDOR_RTL) $(SIM_CPU_RTL) sim/tb_cpu_instr.v

sim-cpu-build: $(SIM_CPU_EXE)

sim-cpu: $(SIM_CPU_EXE)
	$(SIM_CPU_EXE) +ROM=sim/roms/01-special.gb +MAX_CYCLES=200000000

sim-cpu-suite: $(SIM_CPU_EXE)
	$(PYTHON) sim/run_cpu_suite.py

$(SIM_SPI_EXE): $(SIM_CPU_RTL) rtl/gb_spi_phy.v rtl/gb_host_bridge.v \
		$(GEN)/cgb_boot.hex sim/tb_spi_rom_transfer.v
	$(VERILATOR) --binary --timing -j 0 \
		-Wno-fatal -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC \
		-Wno-WIDTHEXPAND -Wno-PINMISSING -Wno-CASEINCOMPLETE \
		-Wno-MULTIDRIVEN -Wno-ASCRANGE \
		--top-module tb_spi_rom_transfer -Mdir $(SIM_BUILD)/obj_spi \
		-Irtl -I$(VENDOR_RTL) $(SIM_CPU_RTL) \
		rtl/gb_spi_phy.v rtl/gb_host_bridge.v sim/tb_spi_rom_transfer.v

sim-spi-build: $(SIM_SPI_EXE)

sim-spi: $(SIM_SPI_EXE)
	$(SIM_SPI_EXE) +ROM=sim/roms/cgb-acid2.gbc +MAX_CYCLES=80000000

$(SIM_PANEL_EXE): $(SIM_CPU_RTL) rtl/gb_line_capture.v \
		rtl/panel_common/simple_spi_master.v rtl/panel_common/oled_init.v \
		rtl/gc9a01_window_init.v rtl/gc9a01_line_stream.v \
		rtl/gc9a01_native.v rtl/panel_common/gc9a01_init_rom.vh \
		$(GEN)/cgb_boot.hex sim/tb_gc9a01_acid2.v
	$(VERILATOR) --binary --timing -j 0 \
		-Wno-fatal -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC \
		-Wno-WIDTHEXPAND -Wno-PINMISSING -Wno-CASEINCOMPLETE \
		-Wno-MULTIDRIVEN -Wno-ASCRANGE \
		--top-module tb_gc9a01_acid2 -Mdir $(SIM_BUILD)/obj_panel \
		-Irtl -Irtl/panel_common -I$(VENDOR_RTL) $(SIM_CPU_RTL) \
		rtl/gb_line_capture.v rtl/panel_common/simple_spi_master.v \
		rtl/panel_common/oled_init.v rtl/gc9a01_window_init.v \
		rtl/gc9a01_line_stream.v rtl/gc9a01_native.v \
		sim/tb_gc9a01_acid2.v

sim-panel-build: $(SIM_PANEL_EXE)

sim-panel: $(SIM_PANEL_EXE)
	$(SIM_PANEL_EXE) +ROM=sim/roms/cgb-acid2.gbc +MAX_CYCLES=80000000
	$(PYTHON) sim/compare_screen.py build/sim/cgb-acid2-panel-window.ppm

$(SIM_MAPPER_EXE): $(MAPPER_RTL) $(VENDOR_RTL)/cart.v \
		rtl/gb_dpram.v rtl/savestate_stubs.v sim/tb_mapper_header.v
	mkdir -p $(SIM_BUILD)
	$(IVERILOG) -g2012 -Irtl -I$(VENDOR_RTL) -o $@ \
		rtl/gb_dpram.v rtl/savestate_stubs.v $(MAPPER_RTL) \
		$(VENDOR_RTL)/cart.v sim/tb_mapper_header.v

sim-mapper: $(SIM_MAPPER_EXE)
	$(VVP) $(SIM_MAPPER_EXE)

$(SIM_CACHE_EXE): $(SIM_CPU_RTL) $(GEN)/cgb_boot.hex sim/tb_cache_defcon.v
	$(VERILATOR) --binary --timing -j 0 \
		-Wno-fatal -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC \
		-Wno-WIDTHEXPAND -Wno-PINMISSING -Wno-CASEINCOMPLETE \
		-Wno-MULTIDRIVEN -Wno-ASCRANGE \
		--top-module tb_cache_defcon -GCACHE_SET_BITS=$(CACHE_SET_BITS) -Mdir $(dir $@) \
		-Irtl -I$(VENDOR_RTL) $(SIM_CPU_RTL) sim/tb_cache_defcon.v

sim-cache-defcon: $(SIM_CACHE_EXE)
	$(SIM_CACHE_EXE) +ROM="$(DEFCON_ROM)" \
		+FRAME=build/sim/defcon-cache.ppm +MAX_CYCLES=200000000 \
		+TARGET_FRAMES=120

$(SIM_FLASH_DEFCON_EXE): $(SIM_CPU_RTL) rtl/ecp5_flash_reader.v \
		$(GEN)/cgb_boot.hex sim/tb_cache_defcon.v
	$(VERILATOR) --binary --timing -j 0 \
		-Wno-fatal -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC \
		-Wno-WIDTHEXPAND -Wno-PINMISSING -Wno-CASEINCOMPLETE \
		-Wno-MULTIDRIVEN -Wno-ASCRANGE \
		--top-module tb_cache_defcon -GFLASH_BACKEND=1 -GCACHE_SET_BITS=$(CACHE_SET_BITS) \
		-Mdir $(dir $@) \
		-Irtl -I$(VENDOR_RTL) $(SIM_CPU_RTL) rtl/ecp5_flash_reader.v \
		sim/tb_cache_defcon.v

sim-flash-defcon: $(SIM_FLASH_DEFCON_EXE)
	$(SIM_FLASH_DEFCON_EXE) +ROM="$(DEFCON_ROM)" \
		+FRAME=build/sim/defcon-flash-start.ppm \
		+MAX_CYCLES=350000000 +TARGET_FRAMES=480 \
		+START_PRESS_FRAME=360 +START_RELEASE_FRAME=370

$(SIM_FLASH_EXE): rtl/ecp5_flash_reader.v rtl/gb_rom_cache.v sim/tb_flash_cache.v
	mkdir -p $(SIM_BUILD)
	$(IVERILOG) -g2012 -o $@ $^

sim-flash: $(SIM_FLASH_EXE)
	$(VVP) $(SIM_FLASH_EXE)

.PHONY: sim-rom-cache
sim-rom-cache:
	mkdir -p $(SIM_BUILD)
	$(IVERILOG) -g2012 -Ptb_rom_cache.CACHE_SET_BITS=4 -o $(SIM_BUILD)/cache8.vvp rtl/gb_rom_cache.v sim/tb_rom_cache.v
	$(VVP) $(SIM_BUILD)/cache8.vvp
	$(IVERILOG) -g2012 -Ptb_rom_cache.CACHE_SET_BITS=5 -o $(SIM_BUILD)/cache16.vvp rtl/gb_rom_cache.v sim/tb_rom_cache.v
	$(VVP) $(SIM_BUILD)/cache16.vvp

.PHONY: sim-panel-colours
sim-panel-colours:
	mkdir -p $(SIM_BUILD)
	$(IVERILOG) -g2012 -Ptb_panel_colours.SWAP_RB=1 -o $(SIM_BUILD)/colours-bgr.vvp rtl/gc9a01_line_stream.v sim/tb_panel_colours.v
	$(VVP) $(SIM_BUILD)/colours-bgr.vvp
	$(IVERILOG) -g2012 -Ptb_panel_colours.SWAP_RB=0 -o $(SIM_BUILD)/colours-rgb.vvp rtl/gc9a01_line_stream.v sim/tb_panel_colours.v
	$(VVP) $(SIM_BUILD)/colours-rgb.vvp

clean:
	rm -rf $(BUILD)
