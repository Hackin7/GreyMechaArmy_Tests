PROJ = custom_fpga

SHELL = bash
PYTHON = python3
VERILATOR = verilator
ICARUS_SUFFIX =
IVERILOG = iverilog$(ICARUS_SUFFIX)
VVP = vvp$(ICARUS_SUFFIX)

TOOLCHAIN_PREFIX ?= riscv-none-elf-
COMPRESSED_ISA ?= C
FIRMWARE_WORDS ?= 2048

GCC_WARNS  = -Werror -Wall -Wextra -Wshadow -Wundef -Wpointer-arith -Wcast-qual -Wcast-align -Wwrite-strings
GCC_WARNS += -Wredundant-decls -Wstrict-prototypes -Wmissing-prototypes -pedantic # -Wconversion

FIRMWARE_ELF = firmware/firmware.elf
FIRMWARE_BIN = firmware/firmware.bin
FIRMWARE_HEX = firmware/firmware.hex
FIRMWARE_MAP = firmware/firmware.map

FIRMWARE_SOURCES = firmware/start.S firmware/main.c firmware/board_io.c firmware/board_io.h firmware/sections.lds ../picorv32/firmware/print.c ../picorv32/firmware/firmware.h
RTL_SOURCES = ../picorv32/picorv32.v src/picorv32_custom_soc.v src/top.v
SIM_SOURCES = tb/testbench.v src/picorv32_custom_soc.v ../picorv32/picorv32.v

all: firmware

firmware: $(FIRMWARE_HEX)

test: testbench.vvp $(FIRMWARE_HEX)
	$(VVP) -N $< +firmware=$(FIRMWARE_HEX)

test_vcd: testbench.vvp $(FIRMWARE_HEX)
	$(VVP) -N $< +firmware=$(FIRMWARE_HEX) +vcd +trace +noerror

testbench.vvp: $(SIM_SOURCES)
	$(IVERILOG) -o $@ $(subst C,-DCOMPRESSED_ISA,$(COMPRESSED_ISA)) $^
	chmod -x $@

tmp.v: $(RTL_SOURCES)
	mkdir -p log
	cat ../picorv32/picorv32.v src/*.v > $@

$(PROJ).json: tmp.v $(FIRMWARE_HEX)
	bash -lc "set -o pipefail; yosys -p 'read_verilog $(subst C,-DCOMPRESSED_ISA,$(COMPRESSED_ISA)) $<; synth_ecp5 -top top -json $@' | tee log/yosys.log"

$(PROJ)_out.config: $(PROJ).json pinout.lpf
	bash -lc "set -o pipefail; nextpnr-ecp5 --json $< --textcfg $@ --25k --package CABGA256 --lpf pinout.lpf | tee log/nextpnr-ecp5.log"

$(PROJ).bit: $(PROJ)_out.config
	bash -lc "set -o pipefail; ecppack --svf $(PROJ).svf $< $@ | tee log/ecppack.log"

bit: $(PROJ).bit

$(FIRMWARE_HEX): $(FIRMWARE_BIN) ../picorv32/firmware/makehex.py
	$(PYTHON) ../picorv32/firmware/makehex.py $< $(FIRMWARE_WORDS) > $@

$(FIRMWARE_BIN): $(FIRMWARE_ELF)
	$(TOOLCHAIN_PREFIX)objcopy -O binary $< $@
	chmod -x $@

$(FIRMWARE_ELF): start.o print.o board_io.o main.o firmware/sections.lds
	$(TOOLCHAIN_PREFIX)gcc -Os -mabi=ilp32 -march=rv32im$(subst C,c,$(COMPRESSED_ISA)) -ffreestanding -nostdlib -o $@ \
		-Wl,--build-id=none,-Bstatic,-T,firmware/sections.lds,-Map,$(FIRMWARE_MAP),--strip-debug \
		start.o print.o board_io.o main.o -lgcc
	chmod -x $@

start.o: firmware/start.S
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32im$(subst C,c,$(COMPRESSED_ISA)) -o $@ $<

print.o: ../picorv32/firmware/print.c ../picorv32/firmware/firmware.h
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32i$(subst C,c,$(COMPRESSED_ISA)) -Os --std=c99 $(GCC_WARNS) -ffreestanding -nostdlib -o $@ $<

board_io.o: firmware/board_io.c firmware/board_io.h
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32i$(subst C,c,$(COMPRESSED_ISA)) -Os --std=c99 $(GCC_WARNS) -ffreestanding -nostdlib -o $@ $<

main.o: firmware/main.c ../picorv32/firmware/firmware.h
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32i$(subst C,c,$(COMPRESSED_ISA)) -Os --std=c99 $(GCC_WARNS) -ffreestanding -nostdlib -o $@ $<

clean:
	rm -rf log start.o print.o board_io.o main.o $(FIRMWARE_ELF) $(FIRMWARE_BIN) $(FIRMWARE_HEX) $(FIRMWARE_MAP) \
		testbench.vvp testbench.vcd testbench.trace tmp.v $(PROJ).json $(PROJ)_out.config $(PROJ).bit $(PROJ).svf

.PHONY: all firmware test test_vcd bit clean
