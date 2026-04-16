PROJ = custom_fpga_spi

SHELL = bash
PYTHON = python3
VERILATOR = verilator
ICARUS_SUFFIX =
IVERILOG = iverilog$(ICARUS_SUFFIX)
VVP = vvp$(ICARUS_SUFFIX)

TOOLCHAIN_PREFIX ?= riscv-none-elf-
COMPRESSED_ISA ?= C
FIRMWARE_WORDS ?= 2048

# Optional: -DUSE_SYS_PLL for ~100 MHz core from ecp5_sys_pll.v (tune PLL if OSCG != ~65 MHz).
YOSYS_DEFS ?=

# Firmware: e.g. EXTRA_CFLAGS='-DBOARD_CPU_HZ=62000000u -DGC9A01_MAIN_DEMO_MODE=2'
EXTRA_CFLAGS ?=

GCC_WARNS  = -Werror -Wall -Wextra -Wshadow -Wundef -Wpointer-arith -Wcast-qual -Wcast-align -Wwrite-strings
GCC_WARNS += -Wredundant-decls -Wstrict-prototypes -Wmissing-prototypes -pedantic # -Wconversion

FIRMWARE_ELF = firmware/firmware.elf
FIRMWARE_BIN = firmware/firmware.bin
FIRMWARE_HEX = firmware/firmware.hex
FIRMWARE_MAP = firmware/firmware.map

FIRMWARE_SOURCES = firmware/start.S firmware/main.c firmware/gc9a01.c firmware/gc9a01.h firmware/board_clock.h firmware/board_io.c firmware/board_io.h firmware/sections.lds ../picorv32/firmware/print.c ../picorv32/firmware/firmware.h
RTL_SOURCES = ../picorv32/picorv32.v src/simple_spi_master.v src/picorv32_custom_soc.v src/ecp5_sys_pll.v src/top.v
SIM_SOURCES = tb/testbench.v src/simple_spi_master.v src/picorv32_custom_soc.v ../picorv32/picorv32.v

all: firmware

firmware: $(FIRMWARE_HEX)

test: testbench.vvp $(FIRMWARE_HEX)
	$(VVP) -N $< +firmware=$(FIRMWARE_HEX)

test_vcd: testbench.vvp $(FIRMWARE_HEX)
	$(VVP) -N $< +firmware=$(FIRMWARE_HEX) +vcd +trace +noerror

testbench.vvp: $(SIM_SOURCES)
	$(IVERILOG) -Itb -o $@ $(subst C,-DCOMPRESSED_ISA,$(COMPRESSED_ISA)) $(SIM_SOURCES)
	chmod -x $@

tmp.v: $(RTL_SOURCES)
	mkdir -p log
	cat $(RTL_SOURCES) > $@

$(PROJ).json: tmp.v $(FIRMWARE_HEX)
	bash -lc "set -o pipefail; yosys -p 'read_verilog -DSYNTHESIS $(subst C,-DCOMPRESSED_ISA,$(COMPRESSED_ISA)) $(YOSYS_DEFS) $<; synth_ecp5 -top top -json $@' | tee log/yosys.log"

$(PROJ)_out.config: $(PROJ).json pinout.lpf
	bash -lc "set -o pipefail; nextpnr-ecp5 --json $< --textcfg $@ --25k --package CABGA256 --lpf pinout.lpf | tee log/nextpnr-ecp5.log"

$(PROJ).bit: $(PROJ)_out.config
	bash -lc "set -o pipefail; ecppack --svf $(PROJ).svf $< $@ | tee log/ecppack.log"

bit: $(PROJ).bit

# Core clock ~100 MHz via EHXPLLL (see src/ecp5_sys_pll.v); re-run ecppll if OSCG differs from ~65 MHz.
bit-pll:
	$(MAKE) bit YOSYS_DEFS=-DUSE_SYS_PLL

$(FIRMWARE_HEX): $(FIRMWARE_BIN) ../picorv32/firmware/makehex.py
	$(PYTHON) ../picorv32/firmware/makehex.py $< $(FIRMWARE_WORDS) > $@

$(FIRMWARE_BIN): $(FIRMWARE_ELF)
	$(TOOLCHAIN_PREFIX)objcopy -O binary $< $@
	chmod -x $@

$(FIRMWARE_ELF): start.o print.o board_io.o gc9a01.o main.o firmware/sections.lds
	$(TOOLCHAIN_PREFIX)gcc -Os -mabi=ilp32 -march=rv32im$(subst C,c,$(COMPRESSED_ISA)) -ffreestanding -nostdlib -o $@ \
		-Wl,--build-id=none,-Bstatic,-T,firmware/sections.lds,-Map,$(FIRMWARE_MAP),--strip-debug \
		start.o print.o board_io.o gc9a01.o main.o -lgcc
	chmod -x $@

start.o: firmware/start.S
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32im$(subst C,c,$(COMPRESSED_ISA)) -o $@ $<

print.o: ../picorv32/firmware/print.c ../picorv32/firmware/firmware.h
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32i$(subst C,c,$(COMPRESSED_ISA)) -Os --std=c99 $(GCC_WARNS) $(EXTRA_CFLAGS) -ffreestanding -nostdlib -o $@ $<

board_io.o: firmware/board_io.c firmware/board_io.h
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32i$(subst C,c,$(COMPRESSED_ISA)) -Os --std=c99 $(GCC_WARNS) $(EXTRA_CFLAGS) -ffreestanding -nostdlib -o $@ $<

gc9a01.o: firmware/gc9a01.c firmware/gc9a01.h firmware/board_clock.h firmware/board_io.h
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32i$(subst C,c,$(COMPRESSED_ISA)) -Os --std=c99 $(GCC_WARNS) $(EXTRA_CFLAGS) -ffreestanding -nostdlib -o $@ $<

main.o: firmware/main.c ../picorv32/firmware/firmware.h firmware/board_io.h firmware/gc9a01.h
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32i$(subst C,c,$(COMPRESSED_ISA)) -Os --std=c99 $(GCC_WARNS) $(EXTRA_CFLAGS) -ffreestanding -nostdlib -o $@ $<

clean:
	rm -rf log start.o print.o board_io.o gc9a01.o main.o $(FIRMWARE_ELF) $(FIRMWARE_BIN) $(FIRMWARE_HEX) $(FIRMWARE_MAP) \
		testbench.vvp testbench.vcd testbench.trace tmp.v $(PROJ).json $(PROJ)_out.config $(PROJ).bit $(PROJ).svf

.PHONY: all firmware test test_vcd bit bit-pll clean
