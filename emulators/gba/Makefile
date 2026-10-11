SHELL := /bin/bash
GHDL ?= ghdl
IVERILOG ?= iverilog
VVP ?= vvp
VVP_ARGS ?=
VENDOR := vendor/openfpga-GBA/src/fpga/gba
BUILD := build
MEM_WORK := $(BUILD)/ghdl-mem
GBA_WORK := $(BUILD)/ghdl-work
GEN := $(BUILD)/generated

MEM_VHDL := $(VENDOR)/SyncFifo.vhd $(VENDOR)/SyncRam.vhd $(VENDOR)/SyncRamDual.vhd $(VENDOR)/SyncRamDualNotPow2.vhd rtl/vhdl/SyncRamDualByteEnable.vhd
GBA_VHDL := $(VENDOR)/proc_bus_gba.vhd $(VENDOR)/reg_savestates.vhd $(VENDOR)/reggba_display.vhd $(VENDOR)/reggba_dma.vhd $(VENDOR)/reggba_keypad.vhd $(VENDOR)/reggba_serial.vhd $(VENDOR)/reggba_sound.vhd $(VENDOR)/reggba_system.vhd $(VENDOR)/reggba_timer.vhd $(VENDOR)/cache.vhd $(VENDOR)/gba_bios.vhd $(VENDOR)/gba_cpu.vhd $(VENDOR)/gba_dma_module.vhd $(VENDOR)/gba_dma.vhd $(VENDOR)/gba_drawer_mode0.vhd $(VENDOR)/gba_drawer_mode2.vhd $(VENDOR)/gba_drawer_mode345.vhd $(VENDOR)/gba_drawer_obj.vhd $(VENDOR)/gba_drawer_merge.vhd $(VENDOR)/gba_gpu_timing.vhd $(VENDOR)/gba_gpu_drawer.vhd $(VENDOR)/gba_gpu.vhd $(VENDOR)/gba_joypad.vhd $(VENDOR)/gba_reservedregs.vhd $(VENDOR)/gba_serial.vhd $(VENDOR)/gba_sound_ch1.vhd $(VENDOR)/gba_sound_ch3.vhd $(VENDOR)/gba_sound_ch4.vhd $(VENDOR)/gba_sound_dma.vhd $(VENDOR)/gba_sound.vhd $(VENDOR)/gba_timer_module.vhd $(VENDOR)/gba_timer.vhd $(VENDOR)/gba_savestates.vhd $(VENDOR)/gba_gpioRTCSolarGyro.vhd $(VENDOR)/gba_memorymux.vhd $(VENDOR)/gba_top.vhd

.PHONY: all sim verilog check-tools check-verilog-tools clean
all: sim
check-tools:
	@command -v $(GHDL) >/dev/null || { echo "missing: $(GHDL)"; exit 1; }

check-verilog-tools: check-tools
	@command -v $(IVERILOG) >/dev/null || { echo "missing: $(IVERILOG)"; exit 1; }
	@command -v $(VVP) >/dev/null || { echo "missing: $(VVP)"; exit 1; }
$(MEM_WORK)/mem-obj08.cf: $(MEM_VHDL)
	mkdir -p $(MEM_WORK)
	$(GHDL) -a --std=08 -fsynopsys -frelaxed --work=mem --workdir=$(MEM_WORK) $(MEM_VHDL)
$(GBA_WORK)/work-obj08.cf: $(GBA_VHDL) $(MEM_WORK)/mem-obj08.cf
	mkdir -p $(GBA_WORK)
	$(GHDL) -a --std=08 -fsynopsys -frelaxed -P$(MEM_WORK) --workdir=$(GBA_WORK) $(GBA_VHDL)
$(GBA_WORK)/tb.stamp: sim/tb_gba_smoke.vhd $(GBA_WORK)/work-obj08.cf
	$(GHDL) -a --std=08 -fsynopsys -frelaxed -P$(MEM_WORK) --workdir=$(GBA_WORK) sim/tb_gba_smoke.vhd
	touch $@
$(GEN)/gba_top.v: $(GBA_WORK)/work-obj08.cf
	mkdir -p $(GEN)
	$(GHDL) --synth --std=08 -fsynopsys -frelaxed -P$(MEM_WORK) --workdir=$(GBA_WORK) --out=verilog -gSoftmap_GBA_FLASH_ADDR=0 -gSoftmap_GBA_EEPROM_ADDR=0 -gSoftmap_GBA_WRam_ADDR=131072 -gSoftmap_GBA_Gamerom_ADDR=0 -gSoftmap_SaveState_ADDR=0 -gturbosound="'0'" gba_top > $@
$(BUILD)/gba_smoke.vvp: $(GEN)/gba_top.v rtl/gba_core_wrapper.sv sim/gba_sim_memory.sv sim/tb_gba_smoke.sv
	$(IVERILOG) -g2012 -Wall -s tb_gba_smoke -o $@ $^
sim: check-tools $(GBA_WORK)/tb.stamp
	$(GHDL) -r --std=08 -fsynopsys -frelaxed -P$(MEM_WORK) --workdir=$(GBA_WORK) tb_gba_smoke --assert-level=error --ieee-asserts=disable-at-0

# Experimental: GHDL 6 currently emits invalid Verilog for resolved record inouts.
verilog: check-verilog-tools $(BUILD)/gba_smoke.vvp
	cd $(BUILD) && $(VVP) gba_smoke.vvp $(VVP_ARGS)
clean:
	rm -rf $(BUILD)
