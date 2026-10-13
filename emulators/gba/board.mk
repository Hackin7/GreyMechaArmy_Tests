# Keep expensive GHDL output on Linux's filesystem until complete.
BOARD_WORK ?= /tmp/greymecha_gba_board
PORTABLE ?= $(BOARD_WORK)/portable
SHARED_CPU_SHIFT_READ ?= 1
PORTABLE_FLAGS ?= --shared-backgrounds --no-savestates --shared-dma-arithmetic --shared-cpu-arithmetic --obj-metadata-ram --banked-register-ram --obj-window-ram --shared-color-arithmetic $(if $(filter 1,$(SHARED_CPU_SHIFT_READ)),--shared-cpu-shift-read)
# The CPU reductions save packed area with wider LUTs enabled. Keep carry
# chains disabled; MAPPING_FLAGS='-noccu2 -nowidelut' retains the old mapper.
MAPPING_FLAGS ?= -noccu2
# ECP5 tile flip-flops share reset controls. Put single-user synchronous
# resets in the data path instead of consuming a separate tile control set.
MIN_SRST_FANOUT ?= 2
BOARD_VHDL := $(patsubst $(VENDOR)/%,$(PORTABLE)/%,$(GBA_VHDL))
PYTHON ?= python3
YOSYS ?= yosys
NEXTPNR ?= nextpnr-ecp5
FPGA_SPEED ?= 6
BOARD_BIT ?= $(BUILD)/gba.bit
BOARD_LOG_TAG ?= board
NEXTPNR_FLAGS ?=
ECPPACK ?= ecppack
PSRAM_FAST_READ ?= 0
PSRAM_BENCH_ASYNC ?= 1
PSRAM_BENCH_TAG ?= baseline
PSRAM_BENCH_WORK ?= /tmp/greymecha_gba_psram_$(PSRAM_BENCH_TAG)
PSRAM_CORE_DIV ?= 20
PSRAM_CLK_DIV ?= 8
PSRAM_WRITE_HALF ?= 1
PSRAM_READ_HALF ?= $(PSRAM_WRITE_HALF)
PSRAM_READ_FALLING ?= 0
PSRAM_INIT_HALF ?= 1
PSRAM_GAP ?= 4
PSRAM_POWERUP ?= 20000
PSRAM_MHZ ?= 60
CORE_CONSTRAINT ?= $(if $(filter 1,$(PSRAM_FAST_READ)),24,21)
PANEL_CONSTRAINT ?= $(if $(filter 1,$(PSRAM_FAST_READ)),97,85)
RAM_CONSTRAINT ?= $(if $(filter 1,$(PSRAM_FAST_READ)),120,53)
CORE_SIM_ARGS ?= +FASTMEM
FLASH_QSPI ?= 1
FLASH_CYCLES ?= $(if $(filter 1,$(FLASH_QSPI)),2,4)
FLASH_RX_REGISTER ?= 0
# OSCG is 310 MHz +/-15%, divided by six. 26/4 gives ~67.17 MHz
# SCK at nominal silicon frequency and <=77.25 MHz at the upper bound.
PLL_CORE_DIV ?= $(if $(filter 1,$(FLASH_QSPI)),26,20)
PLL_FLASH_DIV ?= $(if $(filter 1,$(FLASH_QSPI)),4,8)
FLASH_MHZ ?= $(if $(filter 1,$(FLASH_QSPI)),155,53)
FLASH_TAG ?= $(FLASH_QSPI)
FLASH_TEST_PARAMS ?=
GB_RTL := ../gameboy_gbc/rtl
RAM_RTL := ../../io/fpga_psram_j1/src
OLED_RTL := ../arduboy/rtl/fast_oled
BOARD_RTL := rtl/top.v rtl/gba_pll.v rtl/gba_core_wrapper.sv rtl/gba_host.v rtl/gba_psram.v rtl/gba_flash.v rtl/gba_qspi_backend.v rtl/gba_qspi_reader.v rtl/gba_buttons.v rtl/gba_lines.v rtl/gba_display.v $(RAM_RTL)/psram_spi.v $(RAM_RTL)/spi_transaction.v $(RAM_RTL)/spi_burst.v $(GB_RTL)/gb_spi_phy.v $(GB_RTL)/ecp5_flash_backend.v $(GB_RTL)/ecp5_flash_reader.v $(GB_RTL)/gb_flash_fifo.v rtl/gba_oled_init.v $(OLED_RTL)/simple_spi_master.v

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

.PHONY: bit-existing-core
.PHONY: map-existing-core
map-existing-core:
	mkdir -p $(BOARD_WORK) $(BUILD)
	cp $(GEN)/gba_top_board.v $(BOARD_WORK)/gba_top.v
	cp tools/ecp5_area.abc $(BOARD_WORK)/area.abc
	$(YOSYS) -Q -T -p 'read_verilog -Irtl -I$(OLED_RTL) -sv $(BOARD_WORK)/gba_top.v $(BOARD_RTL); chparam -set PSRAM_FAST_READ $(PSRAM_FAST_READ) -set FLASH_QSPI $(FLASH_QSPI) -set FLASH_CYCLES $(FLASH_CYCLES) -set FLASH_RX_REGISTER $(FLASH_RX_REGISTER) -set PLL_CORE_DIV $(PLL_CORE_DIV) -set PLL_FLASH_DIV $(PLL_FLASH_DIV) top; scratchpad -set abc9.script $(BOARD_WORK)/area.abc; synth_ecp5 -top top $(MAPPING_FLAGS) -no-rw-check -run begin:map_ram; write_rtlil $(BOARD_WORK)/pre_ram.il; synth_ecp5 -top top $(MAPPING_FLAGS) -run map_ram:map_gates; write_rtlil $(BOARD_WORK)/pre_gates.il; synth_ecp5 -top top $(MAPPING_FLAGS) -run map_gates:map_ffs; dfflegalize -cell $$_DFF_?_ 01 -cell $$_DFF_?P?_ r -cell $$_SDFF_?P?_ r -cell $$_DFFE_??_ 01 -cell $$_DFFE_?P??_ r -cell $$_SDFFE_?P??_ r -cell $$_DLATCH_?_ x -minsrst $(MIN_SRST_FANOUT); synth_ecp5 -top top $(MAPPING_FLAGS) -run map_ffs:check; hierarchy -check; check -assert; stat; write_rtlil $(BOARD_WORK)/mapped.il; blackbox =A:whitebox; write_json $(BOARD_WORK)/top.json' > $(BUILD)/$(BOARD_LOG_TAG)-yosys.log

bit bit-existing-core:
	$(MAKE) map-existing-core
	$(MAKE) route-existing-map
	$(ECPPACK) --compress $(BOARD_WORK)/top.config $(BOARD_BIT)

.PHONY: route-existing-map test-clock-constraints
route-existing-map:
	mkdir -p $(BUILD)
	$(PYTHON) tools/bind_board_clocks.py $(BOARD_WORK)/top.json pinout.lpf --output-json $(BOARD_WORK)/clocked.json --output-lpf $(BOARD_WORK)/pins.lpf --manifest $(BUILD)/$(BOARD_LOG_TAG)-clocks.json --core $(CORE_CONSTRAINT) --panel $(PANEL_CONSTRAINT) --ram $(RAM_CONSTRAINT) --flash $(FLASH_MHZ)
	$(NEXTPNR) --25k --package CABGA256 --speed $(FPGA_SPEED) --json $(BOARD_WORK)/clocked.json --lpf $(BOARD_WORK)/pins.lpf --textcfg $(BOARD_WORK)/top.config --report $(BUILD)/$(BOARD_LOG_TAG)-timing.json --seed 1 $(NEXTPNR_FLAGS) > $(BUILD)/$(BOARD_LOG_TAG)-nextpnr.log 2>&1
	$(PYTHON) tools/check_board_timing.py $(BUILD)/$(BOARD_LOG_TAG)-clocks.json $(BUILD)/$(BOARD_LOG_TAG)-nextpnr.log --report $(BUILD)/$(BOARD_LOG_TAG)-timing.json

test-clock-constraints:
	$(PYTHON) sim/test_clock_constraints.py

test-board: test-flash test-qspi test-qspi-fast test-vram test-psram test-dma-arithmetic test-cpu-arithmetic test-cpu-shifter test-cpu-registers test-color-arithmetic test-host test-buttons test-display

.PHONY: psram-benchmark-bit
psram-benchmark-bit:
	mkdir -p $(PSRAM_BENCH_WORK) $(BUILD)/psram-benchmark
	$(YOSYS) -Q -T -p 'read_verilog -sv sim/psram_hardware_top.v rtl/gba_pll.v rtl/gba_host.v rtl/gba_psram.v $(GB_RTL)/gb_spi_phy.v $(RAM_RTL)/psram_spi.v $(RAM_RTL)/spi_transaction.v $(RAM_RTL)/spi_burst.v; chparam -set ASYNC_CLOCK $(PSRAM_BENCH_ASYNC) -set RAM_CORE_DIV $(PSRAM_CORE_DIV) -set RAM_CLK_DIV $(PSRAM_CLK_DIV) -set WRITE_HALF $(PSRAM_WRITE_HALF) -set READ_HALF $(PSRAM_READ_HALF) -set READ_FALLING $(PSRAM_READ_FALLING) -set INIT_HALF $(PSRAM_INIT_HALF) -set RAM_GAP $(PSRAM_GAP) -set POWERUP_CYCLES $(PSRAM_POWERUP) top; synth_ecp5 -top top -no-rw-check; check -assert; write_json $(PSRAM_BENCH_WORK)/top.json' > $(BUILD)/psram-benchmark/yosys-$(PSRAM_BENCH_TAG).log 2>&1
	sed -e '/^FREQUENCY/d' -e '/flash_io[23]/d' pinout.lpf > $(PSRAM_BENCH_WORK)/benchmark.lpf
	printf 'FREQUENCY NET "clk" 24.0 MHz;\nFREQUENCY NET "clk_ram" $(PSRAM_MHZ) MHz;\n' >> $(PSRAM_BENCH_WORK)/benchmark.lpf
	cat sim/psram_benchmark.lpf >> $(PSRAM_BENCH_WORK)/benchmark.lpf
	$(NEXTPNR) --25k --package CABGA256 --speed $(FPGA_SPEED) --json $(PSRAM_BENCH_WORK)/top.json --lpf $(PSRAM_BENCH_WORK)/benchmark.lpf --textcfg $(PSRAM_BENCH_WORK)/top.config --report $(BUILD)/psram-benchmark/timing-$(PSRAM_BENCH_TAG).json > $(BUILD)/psram-benchmark/nextpnr-$(PSRAM_BENCH_TAG).log 2>&1
	$(ECPPACK) --compress $(PSRAM_BENCH_WORK)/top.config $(BUILD)/psram-benchmark/gba-psram-$(PSRAM_BENCH_TAG).bit

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
	$(IVERILOG) -g2012 $(FLASH_TEST_PARAMS) -s tb_gba_flash -o $(BUILD)/flash.vvp sim/tb_gba_flash.sv rtl/gba_flash.v rtl/gba_qspi_backend.v rtl/gba_qspi_reader.v $(GB_RTL)/ecp5_flash_backend.v $(GB_RTL)/ecp5_flash_reader.v $(GB_RTL)/gb_flash_fifo.v
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
	$(GHDL) --elab-run --std=08 --workdir=$(BUILD)/regfile-test -o $(BUILD)/regfile-test/test tb_gba_cpu_regfile --assert-level=error

.PHONY: test-cpu-register-equivalence test-cpu-register-area
test-cpu-register-equivalence:
	mkdir -p $(BUILD)/regfile-equivalence
	$(GHDL) -a --std=08 --workdir=$(BUILD)/regfile-equivalence sim/gba_cpu_regfile_reference.vhd rtl/vhdl/gba_cpu_regfile.vhd sim/tb_gba_cpu_register_equivalence.vhd
	$(GHDL) --elab-run --std=08 --workdir=$(BUILD)/regfile-equivalence -o $(BUILD)/regfile-equivalence/test tb_gba_cpu_register_equivalence --assert-level=error

test-cpu-register-area:
	$(PYTHON) tools/measure_cpu_registers.py

diagnostic:
	mkdir -p $(BUILD)/roms
	arm-none-eabi-gcc $(DIAGNOSTIC_CFLAGS) -mcpu=arm7tdmi -marm -O2 -ffreestanding -nostdlib -fno-builtin -T roms/diagnostic.ld roms/diagnostic_start.S roms/diagnostic.c roms/banked_regs.S -o $(BUILD)/roms/diagnostic.elf
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

# All eleven diagnostics, BIOS, pause and keys; omit only the visual bar fill.
# The full test-board-core target retains its original framebuffer workload.
.PHONY: test-cpu-core
test-cpu-core:
	$(MAKE) test-board-core DIAGNOSTIC_CFLAGS=-DCPU_FOCUS_DIAGNOSTIC

test-renderer: board-core
	$(PYTHON) tools/renderer_reference.py $(VENDOR) $(BOARD_WORK)/reference
	$(GHDL) -a --std=08 -fsynopsys -frelaxed -P$(BOARD_WORK)/mem --workdir=$(BOARD_WORK)/work $(BOARD_WORK)/reference/gba_drawer_obj_reference.vhd $(BOARD_WORK)/reference/gba_drawer_merge_reference.vhd $(BOARD_WORK)/reference/gba_gpu_drawer_reference.vhd sim/tb_gba_renderer.vhd
	$(GHDL) -r --std=08 -fsynopsys -frelaxed -P$(BOARD_WORK)/mem --workdir=$(BOARD_WORK)/work tb_gba_renderer --assert-level=error --ieee-asserts=disable-at-0
	$(GHDL) -r --std=08 -fsynopsys -frelaxed -P$(BOARD_WORK)/mem --workdir=$(BOARD_WORK)/work tb_gba_renderer -gExternalMemory=true --assert-level=error --ieee-asserts=disable-at-0
	$(GHDL) -a --std=08 -fsynopsys -frelaxed -P$(BOARD_WORK)/mem --workdir=$(BOARD_WORK)/work $(BOARD_WORK)/reference/gba_savestates_reference.vhd sim/tb_gba_board_reset.vhd
	$(GHDL) -r --std=08 -fsynopsys -frelaxed -P$(BOARD_WORK)/mem --workdir=$(BOARD_WORK)/work tb_gba_board_reset --assert-level=error --ieee-asserts=disable-at-0

.PHONY: test-qspi flash-benchmark-bit
test-qspi:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -s tb_gba_qspi -o $(BUILD)/qspi.vvp sim/tb_gba_qspi.sv rtl/gba_flash.v rtl/gba_qspi_backend.v rtl/gba_qspi_reader.v $(GB_RTL)/ecp5_flash_backend.v $(GB_RTL)/ecp5_flash_reader.v $(GB_RTL)/gb_flash_fifo.v
	$(VVP) $(BUILD)/qspi.vvp
	$(IVERILOG) -g2012 -Ptb_gba_qspi.CORE_HALF_NS=500 -s tb_gba_qspi -o $(BUILD)/qspi-pressure.vvp sim/tb_gba_qspi.sv rtl/gba_flash.v rtl/gba_qspi_backend.v rtl/gba_qspi_reader.v $(GB_RTL)/ecp5_flash_backend.v $(GB_RTL)/ecp5_flash_reader.v $(GB_RTL)/gb_flash_fifo.v
	$(VVP) $(BUILD)/qspi-pressure.vvp
	$(IVERILOG) -g2012 -s tb_gba_qspi -Ptb_gba_qspi.QE_FAIL=1 -o $(BUILD)/qspi-qe-fail.vvp sim/tb_gba_qspi.sv rtl/gba_flash.v rtl/gba_qspi_backend.v rtl/gba_qspi_reader.v $(GB_RTL)/ecp5_flash_backend.v $(GB_RTL)/ecp5_flash_reader.v $(GB_RTL)/gb_flash_fifo.v
	$(VVP) $(BUILD)/qspi-qe-fail.vvp

# Two-cycle mode at a ~167 MHz controller clock, including FIFO pressure.
.PHONY: test-qspi-fast
test-qspi-fast:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -s tb_gba_qspi -Ptb_gba_qspi.CLOCK_CYCLES=2 -Ptb_gba_qspi.FLASH_HALF_NS=3.0 -Ptb_gba_qspi.OUTPUT_DELAY_NS=8 -o $(BUILD)/qspi-fast.vvp sim/tb_gba_qspi.sv rtl/gba_flash.v rtl/gba_qspi_backend.v rtl/gba_qspi_reader.v $(GB_RTL)/ecp5_flash_backend.v $(GB_RTL)/ecp5_flash_reader.v $(GB_RTL)/gb_flash_fifo.v
	$(VVP) $(BUILD)/qspi-fast.vvp
	$(IVERILOG) -g2012 -s tb_gba_qspi -Ptb_gba_qspi.CLOCK_CYCLES=2 -Ptb_gba_qspi.FLASH_HALF_NS=3.0 -Ptb_gba_qspi.OUTPUT_DELAY_NS=8 -Ptb_gba_qspi.CORE_HALF_NS=500 -o $(BUILD)/qspi-fast-pressure.vvp sim/tb_gba_qspi.sv rtl/gba_flash.v rtl/gba_qspi_backend.v rtl/gba_qspi_reader.v $(GB_RTL)/ecp5_flash_backend.v $(GB_RTL)/ecp5_flash_reader.v $(GB_RTL)/gb_flash_fifo.v
	$(VVP) $(BUILD)/qspi-fast-pressure.vvp

FLASH_BENCH_WORK ?= /tmp/greymecha_gba_flash_$(FLASH_TAG)
flash-benchmark-bit:
	mkdir -p $(FLASH_BENCH_WORK) $(BUILD)/flash-benchmark
	$(YOSYS) -Q -T -p 'read_verilog -sv sim/flash_hardware_top.v rtl/gba_pll.v rtl/gba_host.v rtl/gba_flash.v rtl/gba_qspi_backend.v rtl/gba_qspi_reader.v $(GB_RTL)/gb_spi_phy.v $(GB_RTL)/ecp5_flash_backend.v $(GB_RTL)/ecp5_flash_reader.v $(GB_RTL)/gb_flash_fifo.v; chparam -set FLASH_QSPI $(FLASH_QSPI) -set FLASH_CYCLES $(FLASH_CYCLES) -set FLASH_RX_REGISTER $(FLASH_RX_REGISTER) -set PLL_CORE_DIV $(PLL_CORE_DIV) -set PLL_FLASH_DIV $(PLL_FLASH_DIV) top; synth_ecp5 -top top -no-rw-check; check -assert; write_json $(FLASH_BENCH_WORK)/top.json' > $(BUILD)/flash-benchmark/yosys-$(FLASH_TAG).log 2>&1
	sed -n -e '/^FREQUENCY NET "clk_ram"/d' -e '/^FREQUENCY/p' -e '/^LOCATE COMP "host_/p' -e '/^IOBUF PORT "host_/p' -e '/^LOCATE COMP "flash_/p' -e '/^IOBUF PORT "flash_/p' -e '/^LOCATE COMP "led/p' -e '/^IOBUF PORT "led/p' pinout.lpf > $(FLASH_BENCH_WORK)/pins.lpf
	sed -e 's/clk_core/clk/g' -e 's/53.0 MHz/$(FLASH_MHZ) MHz/g' $(FLASH_BENCH_WORK)/pins.lpf > $(FLASH_BENCH_WORK)/benchmark.lpf
	cat sim/psram_benchmark.lpf >> $(FLASH_BENCH_WORK)/benchmark.lpf
	$(NEXTPNR) --25k --package CABGA256 --speed $(FPGA_SPEED) --json $(FLASH_BENCH_WORK)/top.json --lpf $(FLASH_BENCH_WORK)/benchmark.lpf --textcfg $(FLASH_BENCH_WORK)/top.config --report $(BUILD)/flash-benchmark/timing-$(FLASH_TAG).json > $(BUILD)/flash-benchmark/nextpnr-$(FLASH_TAG).log 2>&1
	$(ECPPACK) --compress $(FLASH_BENCH_WORK)/top.config $(BUILD)/flash-benchmark/gba-flash-$(FLASH_TAG).bit

.PHONY: check-qspi-top flash-qspi-bit
check-qspi-top:
	$(YOSYS) -Q -T -p 'read_verilog -lib +/ecp5/cells_sim.v +/ecp5/cells_bb.v; read_verilog -Irtl -I$(OLED_RTL) -sv $(GEN)/gba_top_board.v $(BOARD_RTL); chparam -set FLASH_QSPI 1 -set FLASH_CYCLES 2 -set PLL_CORE_DIV 26 -set PLL_FLASH_DIV 4 top; hierarchy -check -top top' > $(BUILD)/qspi-elaboration.log 2>&1

flash-qspi-bit:
	$(MAKE) flash-benchmark-bit FLASH_QSPI=1 FLASH_CYCLES=2 FLASH_RX_REGISTER=0 PLL_CORE_DIV=26 PLL_FLASH_DIV=4 FLASH_MHZ=155 FLASH_TAG=70mhz

# Full BIOS/IWRAM/lower-VRAM EBR allocation, with approximately 67 MHz QSPI.
# The 155 MHz PHY constraint covers +/-15% OSCG variation; SCK is PHY / 2.
.PHONY: bram-priority-core bram-priority-map
bram-priority-core:
	$(PYTHON) tools/prepare_bram_priority.py --work /tmp/greymecha_gba_bram_priority --core > $(BUILD)/bram-priority-core.log 2>&1
bram-priority-map: bram-priority-core
	$(PYTHON) tools/map_bram_priority.py --work /tmp/greymecha_gba_bram_priority

.PHONY: test-priority-memory
test-priority-memory:
	$(PYTHON) tools/test_bram_priority_memory.py

.PHONY: test-priority-psram
test-priority-psram:
	$(PYTHON) tools/test_narrow_memory.py
	$(PYTHON) tools/test_psram_host.py
	$(PYTHON) tools/test_psram_lines.py
	$(IVERILOG) -g2012 -s tb_gba_scratch_arbiter -o $(BUILD)/scratch-arbiter.vvp sim/tb_gba_scratch_arbiter.sv rtl/bram_priority/gba_scratch_arbiter.sv
	$(VVP) $(BUILD)/scratch-arbiter.vvp

.PHONY: test-psram-fast
test-psram-fast:
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -s tb_gba_psram_burst -Ptb_gba_psram_burst.ASYNC_CLOCK=1 -Ptb_gba_psram_burst.PHY_HALF_NS=5 -Ptb_gba_psram_burst.WRITE_HALF=2 -Ptb_gba_psram_burst.READ_HALF=1 -Ptb_gba_psram_burst.READ_FALLING=1 -Ptb_gba_psram_burst.INIT_HALF=2 -Ptb_gba_psram_burst.RAM_GAP=8 -o $(BUILD)/psram-fast.vvp sim/tb_gba_psram_burst.sv rtl/gba_psram.v $(RAM_RTL)/psram_spi.v $(RAM_RTL)/spi_transaction.v $(RAM_RTL)/spi_burst.v ../../io/fpga_psram_j1/sim/aps6404_model.v
	$(VVP) $(BUILD)/psram-fast.vvp

.PHONY: psram-fast-read-bit
psram-fast-read-bit:
	$(MAKE) psram-benchmark-bit PSRAM_BENCH_TAG=read51 PSRAM_CORE_DIV=20 PSRAM_CLK_DIV=4 PSRAM_WRITE_HALF=2 PSRAM_READ_HALF=1 PSRAM_READ_FALLING=1 PSRAM_INIT_HALF=2 PSRAM_GAP=8 PSRAM_POWERUP=40000 PSRAM_MHZ=120

.PHONY: check-psram-fast-top
check-psram-fast-top:
	$(YOSYS) -Q -T -p 'read_verilog -lib +/ecp5/cells_sim.v +/ecp5/cells_bb.v; read_verilog -Irtl -I$(OLED_RTL) -sv $(GEN)/gba_top_board.v $(BOARD_RTL); chparam -set PSRAM_FAST_READ 1 top; hierarchy -check -top top' > $(BUILD)/psram-fast-elaboration.log 2>&1
