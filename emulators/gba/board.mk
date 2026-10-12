# Keep expensive GHDL output on Linux's filesystem until complete.
BOARD_WORK ?= /tmp/greymecha_gba_board
PORTABLE ?= $(BOARD_WORK)/portable
PORTABLE_FLAGS ?= --shared-backgrounds --no-savestates --shared-dma-arithmetic --shared-cpu-arithmetic --obj-metadata-ram --banked-register-ram --obj-window-ram --shared-color-arithmetic
MAPPING_FLAGS ?= -noccu2 -nowidelut
# ECP5 tile flip-flops share reset controls. Put single-user synchronous
# resets in the data path instead of consuming a separate tile control set.
MIN_SRST_FANOUT ?= 2
BOARD_VHDL := $(patsubst $(VENDOR)/%,$(PORTABLE)/%,$(GBA_VHDL))
PYTHON ?= python3
YOSYS ?= yosys
NEXTPNR ?= nextpnr-ecp5
FPGA_SPEED ?= 6
NEXTPNR_FLAGS ?=
ECPPACK ?= ecppack
PSRAM_BENCH_ASYNC ?= 1
PSRAM_BENCH_WORK ?= /tmp/greymecha_gba_psram_bench
CORE_SIM_ARGS ?= +FASTMEM
FLASH_TEST_PARAMS ?=
GB_RTL := ../gameboy_gbc/rtl
RAM_RTL := ../../io/fpga_psram_j1/src
OLED_RTL := ../arduboy/rtl/fast_oled
BOARD_RTL := rtl/top.v rtl/gba_pll.v rtl/gba_core_wrapper.sv rtl/gba_host.v rtl/gba_psram.v rtl/gba_flash.v rtl/gba_buttons.v rtl/gba_lines.v rtl/gba_display.v $(RAM_RTL)/psram_spi.v $(RAM_RTL)/spi_transaction.v $(RAM_RTL)/spi_burst.v $(GB_RTL)/gb_spi_phy.v $(GB_RTL)/ecp5_flash_backend.v $(GB_RTL)/ecp5_flash_reader.v $(GB_RTL)/gb_flash_fifo.v rtl/gba_oled_init.v $(OLED_RTL)/simple_spi_master.v

.PHONY: portable board-core bit test-board test-host test-host-ranges test-buttons test-display test-flash test-renderer test-vram test-psram test-dma-arithmetic test-cpu-arithmetic test-cpu-shifter test-cpu-registers test-color-arithmetic test-board-core diagnostic bios suite
portable:
	$(PYTHON) tools/prepare_rtl.py $(VENDOR) $(PORTABLE) $(PORTABLE_FLAGS)

board-core: portable
	mkdir -p $(BOARD_WORK)/mem $(BOARD_WORK)/work $(GEN)
	$(GHDL) -a --std=08 -fsynopsys -frelaxed --work=mem --workdir=$(BOARD_WORK)/mem $(MEM_VHDL)
	$(GHDL) -a --std=08 -fsynopsys -frelaxed -P$(BOARD_WORK)/mem --workdir=$(BOARD_WORK)/work $(BOARD_VHDL)
	$(GHDL) --synth --std=08 -fsynopsys -frelaxed -P$(BOARD_WORK)/mem --workdir=$(BOARD_WORK)/work --out=verilog -gExternalFastMemory=true -gExternalVRAMLow=true -gROMCacheSize=64 -gSoftmap_GBA_FLASH_ADDR=131072 -gSoftmap_GBA_EEPROM_ADDR=98304 -gSoftmap_GBA_WRam_ADDR=0 -gSoftmap_GBA_Gamerom_ADDR=0 -gSoftmap_SaveState_ADDR=0 -gturbosound="'0'" gba_top > $(BOARD_WORK)/gba_top.v
	$(PYTHON) tools/compact_verilog.py $(BOARD_WORK)/gba_top.v --board-memory
	cp $(BOARD_WORK)/gba_top.v $(GEN)/gba_top_board.v

bit: board-core
	cp tools/ecp5_area.abc $(BOARD_WORK)/area.abc
	$(YOSYS) -Q -T -p 'read_verilog -Irtl -I$(OLED_RTL) -sv $(BOARD_WORK)/gba_top.v $(BOARD_RTL); scratchpad -set abc9.script $(BOARD_WORK)/area.abc; synth_ecp5 -top top $(MAPPING_FLAGS) -no-rw-check -run begin:map_ram; write_rtlil $(BOARD_WORK)/pre_ram.il; synth_ecp5 -top top $(MAPPING_FLAGS) -run map_ram:map_gates; write_rtlil $(BOARD_WORK)/pre_gates.il; synth_ecp5 -top top $(MAPPING_FLAGS) -run map_gates:map_ffs; dfflegalize -cell $$_DFF_?_ 01 -cell $$_DFF_?P?_ r -cell $$_SDFF_?P?_ r -cell $$_DFFE_??_ 01 -cell $$_DFFE_?P??_ r -cell $$_SDFFE_?P??_ r -cell $$_DLATCH_?_ x -minsrst $(MIN_SRST_FANOUT); synth_ecp5 -top top $(MAPPING_FLAGS) -run map_ffs:check; hierarchy -check; check -assert; stat; write_rtlil $(BOARD_WORK)/mapped.il; blackbox =A:whitebox; write_json $(BOARD_WORK)/top.json' > $(BUILD)/board-yosys.log
	$(NEXTPNR) --25k --package CABGA256 --speed $(FPGA_SPEED) --json $(BOARD_WORK)/top.json --lpf pinout.lpf --textcfg $(BOARD_WORK)/top.config --seed 1 $(NEXTPNR_FLAGS) > $(BUILD)/board-nextpnr.log 2>&1
	$(ECPPACK) --compress $(BOARD_WORK)/top.config $(BUILD)/gba.bit

test-board: test-flash test-vram test-psram test-dma-arithmetic test-cpu-arithmetic test-cpu-shifter test-cpu-registers test-color-arithmetic test-host test-buttons test-display

.PHONY: psram-benchmark-bit
psram-benchmark-bit:
	mkdir -p $(PSRAM_BENCH_WORK) $(BUILD)/psram-benchmark
	$(YOSYS) -Q -T -p 'read_verilog -sv sim/psram_hardware_top.v rtl/gba_pll.v rtl/gba_host.v rtl/gba_psram.v $(GB_RTL)/gb_spi_phy.v $(RAM_RTL)/psram_spi.v $(RAM_RTL)/spi_transaction.v $(RAM_RTL)/spi_burst.v; chparam -set ASYNC_CLOCK $(PSRAM_BENCH_ASYNC) top; synth_ecp5 -top top -no-rw-check; check -assert; write_json $(PSRAM_BENCH_WORK)/top.json' > $(BUILD)/psram-benchmark/yosys.log 2>&1
	sed -e 's/clk_core/clk/g' -e 's/clk_flash/clk_ram/g' pinout.lpf > $(PSRAM_BENCH_WORK)/benchmark.lpf
	cat sim/psram_benchmark.lpf >> $(PSRAM_BENCH_WORK)/benchmark.lpf
	$(NEXTPNR) --25k --package CABGA256 --speed $(FPGA_SPEED) --json $(PSRAM_BENCH_WORK)/top.json --lpf $(PSRAM_BENCH_WORK)/benchmark.lpf --textcfg $(PSRAM_BENCH_WORK)/top.config --report $(BUILD)/psram-benchmark/timing.json > $(BUILD)/psram-benchmark/nextpnr.log 2>&1
	$(ECPPACK) --compress $(PSRAM_BENCH_WORK)/top.config $(BUILD)/psram-benchmark/gba-psram-benchmark.bit

test-host-ranges:
	$(PYTHON) tools/prove_host_ranges.py

test-host: test-host-ranges
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -s tb_gba_host -o $(BUILD)/host.vvp sim/tb_gba_host.sv rtl/gba_host.v rtl/gba_psram.v $(GB_RTL)/gb_spi_phy.v $(RAM_RTL)/psram_spi.v $(RAM_RTL)/spi_transaction.v $(RAM_RTL)/spi_burst.v ../../io/fpga_psram_j1/sim/aps6404_model.v
	$(VVP) $(BUILD)/host.vvp
	$(IVERILOG) -g2012 -s tb_gba_host -Ptb_gba_host.ASYNC_CLOCK=1 -o $(BUILD)/host-cdc.vvp sim/tb_gba_host.sv rtl/gba_host.v rtl/gba_psram.v $(GB_RTL)/gb_spi_phy.v $(RAM_RTL)/psram_spi.v $(RAM_RTL)/spi_transaction.v $(RAM_RTL)/spi_burst.v ../../io/fpga_psram_j1/sim/aps6404_model.v
	$(VVP) $(BUILD)/host-cdc.vvp

test-buttons:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -s tb_gba_buttons -o $(BUILD)/buttons.vvp sim/tb_gba_buttons.sv rtl/gba_buttons.v
	$(VVP) $(BUILD)/buttons.vvp

test-display:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Irtl -I$(OLED_RTL) -s tb_gba_display -o $(BUILD)/display.vvp sim/tb_gba_display.sv rtl/gba_lines.v rtl/gba_display.v rtl/gba_oled_init.v $(OLED_RTL)/simple_spi_master.v
	$(VVP) $(BUILD)/display.vvp
	$(IVERILOG) -g2012 -Irtl -I$(OLED_RTL) -s tb_gba_display -Ptb_gba_display.PARTIAL_START=1 -o $(BUILD)/display-resync.vvp sim/tb_gba_display.sv rtl/gba_lines.v rtl/gba_display.v rtl/gba_oled_init.v $(OLED_RTL)/simple_spi_master.v
	$(VVP) $(BUILD)/display-resync.vvp

test-flash:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 $(FLASH_TEST_PARAMS) -s tb_gba_flash -o $(BUILD)/flash.vvp sim/tb_gba_flash.sv rtl/gba_flash.v $(GB_RTL)/ecp5_flash_backend.v $(GB_RTL)/ecp5_flash_reader.v $(GB_RTL)/gb_flash_fifo.v
	$(VVP) $(BUILD)/flash.vvp

test-vram:
	mkdir -p $(BUILD)/ghdl-vram
	$(GHDL) -a --std=08 --workdir=$(BUILD)/ghdl-vram rtl/vhdl/gba_vram_low_ext.vhd sim/tb_gba_vram_low_ext.vhd
	$(GHDL) -r --std=08 --workdir=$(BUILD)/ghdl-vram tb_gba_vram_low_ext --assert-level=error

test-psram:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -s tb_gba_psram_clients -o $(BUILD)/psram-clients.vvp sim/tb_gba_psram_clients.sv rtl/gba_psram.v $(RAM_RTL)/psram_spi.v $(RAM_RTL)/spi_transaction.v $(RAM_RTL)/spi_burst.v ../../io/fpga_psram_j1/sim/aps6404_model.v
	$(VVP) $(BUILD)/psram-clients.vvp
	$(IVERILOG) -g2012 -s tb_gba_psram_clients -Ptb_gba_psram_clients.ASYNC_CLOCK=1 -o $(BUILD)/psram-clients-cdc.vvp sim/tb_gba_psram_clients.sv rtl/gba_psram.v $(RAM_RTL)/psram_spi.v $(RAM_RTL)/spi_transaction.v $(RAM_RTL)/spi_burst.v ../../io/fpga_psram_j1/sim/aps6404_model.v
	$(VVP) $(BUILD)/psram-clients-cdc.vvp
	$(IVERILOG) -g2012 -s tb_gba_psram_burst -o $(BUILD)/psram-burst.vvp sim/tb_gba_psram_burst.sv rtl/gba_psram.v $(RAM_RTL)/psram_spi.v $(RAM_RTL)/spi_transaction.v $(RAM_RTL)/spi_burst.v ../../io/fpga_psram_j1/sim/aps6404_model.v
	$(VVP) $(BUILD)/psram-burst.vvp
	$(IVERILOG) -g2012 -s tb_gba_psram_burst -Ptb_gba_psram_burst.ASYNC_CLOCK=1 -o $(BUILD)/psram-burst-cdc.vvp sim/tb_gba_psram_burst.sv rtl/gba_psram.v $(RAM_RTL)/psram_spi.v $(RAM_RTL)/spi_transaction.v $(RAM_RTL)/spi_burst.v ../../io/fpga_psram_j1/sim/aps6404_model.v
	$(VVP) $(BUILD)/psram-burst-cdc.vvp
	$(IVERILOG) -g2012 -s tb_gba_psram_burst -Ptb_gba_psram_burst.ASYNC_CLOCK=1 -Ptb_gba_psram_burst.PHY_HALF_NS=20 -Ptb_gba_psram_burst.PHY_PHASE_NS=19 -o $(BUILD)/psram-burst-cdc-slow.vvp sim/tb_gba_psram_burst.sv rtl/gba_psram.v $(RAM_RTL)/psram_spi.v $(RAM_RTL)/spi_transaction.v $(RAM_RTL)/spi_burst.v ../../io/fpga_psram_j1/sim/aps6404_model.v
	$(VVP) $(BUILD)/psram-burst-cdc-slow.vvp
	$(IVERILOG) -g2012 -s tb_gba_psram_benchmark -o $(BUILD)/psram-benchmark.vvp sim/tb_gba_psram_benchmark.sv sim/psram_hardware_top.v rtl/gba_host.v rtl/gba_psram.v $(GB_RTL)/gb_spi_phy.v $(RAM_RTL)/psram_spi.v $(RAM_RTL)/spi_transaction.v $(RAM_RTL)/spi_burst.v ../../io/fpga_psram_j1/sim/aps6404_model.v
	$(VVP) $(BUILD)/psram-benchmark.vvp

test-dma-arithmetic:
	$(PYTHON) tools/prove_dma_arithmetic.py

test-cpu-arithmetic:
	$(PYTHON) tools/prove_cpu_arithmetic.py

test-cpu-shifter:
	$(PYTHON) tools/prove_cpu_shifter.py

test-color-arithmetic:
	$(PYTHON) tools/prove_color_arithmetic.py

test-cpu-registers:
	mkdir -p $(BUILD)/regfile-test
	$(GHDL) -a --std=08 --workdir=$(BUILD)/regfile-test rtl/vhdl/gba_cpu_regfile.vhd sim/tb_gba_cpu_regfile.vhd
	$(GHDL) -r --std=08 --workdir=$(BUILD)/regfile-test tb_gba_cpu_regfile --assert-level=error

diagnostic:
	mkdir -p $(BUILD)/roms
	arm-none-eabi-gcc -mcpu=arm7tdmi -marm -O2 -ffreestanding -nostdlib -fno-builtin -T roms/diagnostic.ld roms/diagnostic_start.S roms/diagnostic.c roms/banked_regs.S -o $(BUILD)/roms/diagnostic.elf
	arm-none-eabi-objcopy -O binary $(BUILD)/roms/diagnostic.elf $(BUILD)/roms/diagnostic.gba

bios:
	$(PYTHON) tools/build_bios.py

suite:
	$(PYTHON) tools/build_suite.py

.PHONY: bld-demo
bld-demo:
	$(PYTHON) tools/build_bld_demo.py

test-board-core: diagnostic
	$(PYTHON) tools/bin_to_hex.py $(BUILD)/roms/open_bios.bin $(BUILD)/roms/open_bios.hex
	$(PYTHON) tools/bin_to_hex.py $(BUILD)/roms/diagnostic.gba $(BUILD)/roms/diagnostic.hex
	verilator --binary --timing -Wno-fatal --top-module tb_gba_board_core --Mdir $(BOARD_WORK)/verilator -j 4 $(BOARD_WORK)/gba_top.v rtl/gba_core_wrapper.sv sim/tb_gba_board_core.sv > $(BUILD)/verilator-build.log 2>&1
	$(BOARD_WORK)/verilator/Vtb_gba_board_core $(CORE_SIM_ARGS)

test-renderer: board-core
	$(PYTHON) tools/renderer_reference.py $(VENDOR) $(BOARD_WORK)/reference
	$(GHDL) -a --std=08 -fsynopsys -frelaxed -P$(BOARD_WORK)/mem --workdir=$(BOARD_WORK)/work $(BOARD_WORK)/reference/gba_drawer_obj_reference.vhd $(BOARD_WORK)/reference/gba_drawer_merge_reference.vhd $(BOARD_WORK)/reference/gba_gpu_drawer_reference.vhd sim/tb_gba_renderer.vhd
	$(GHDL) -r --std=08 -fsynopsys -frelaxed -P$(BOARD_WORK)/mem --workdir=$(BOARD_WORK)/work tb_gba_renderer --assert-level=error --ieee-asserts=disable-at-0
	$(GHDL) -r --std=08 -fsynopsys -frelaxed -P$(BOARD_WORK)/mem --workdir=$(BOARD_WORK)/work tb_gba_renderer -gExternalMemory=true --assert-level=error --ieee-asserts=disable-at-0
	$(GHDL) -a --std=08 -fsynopsys -frelaxed -P$(BOARD_WORK)/mem --workdir=$(BOARD_WORK)/work $(BOARD_WORK)/reference/gba_savestates_reference.vhd sim/tb_gba_board_reset.vhd
	$(GHDL) -r --std=08 -fsynopsys -frelaxed -P$(BOARD_WORK)/mem --workdir=$(BOARD_WORK)/work tb_gba_board_reset --assert-level=error --ieee-asserts=disable-at-0
