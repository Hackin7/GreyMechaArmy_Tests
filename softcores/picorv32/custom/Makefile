SHELL = bash
PYTHON = python3
VERILATOR = verilator
ICARUS_SUFFIX =
IVERILOG = iverilog$(ICARUS_SUFFIX)
VVP = vvp$(ICARUS_SUFFIX)

TOOLCHAIN_PREFIX ?= riscv-none-elf-
COMPRESSED_ISA ?= C
GCC_WARNS  = -Werror -Wall -Wextra -Wshadow -Wundef -Wpointer-arith -Wcast-qual -Wcast-align -Wwrite-strings
GCC_WARNS += -Wredundant-decls -Wstrict-prototypes -Wmissing-prototypes -pedantic # -Wconversion

FIRMWARE_ELF = firmware.elf
FIRMWARE_BIN = firmware.bin
FIRMWARE_HEX = firmware.hex
FIRMWARE_MAP = firmware.map

all: $(FIRMWARE_HEX)

test: testbench.vvp $(FIRMWARE_HEX)
	$(VVP) -N $< +firmware=$(FIRMWARE_HEX)

test_vcd: testbench.vvp $(FIRMWARE_HEX)
	$(VVP) -N $< +firmware=$(FIRMWARE_HEX) +vcd +trace +noerror

test_verilator: testbench_verilator $(FIRMWARE_HEX)
	./testbench_verilator +firmware=$(FIRMWARE_HEX)

testbench.vvp: ../picorv32/testbench.v ../picorv32/picorv32.v
	$(IVERILOG) -o $@ $(subst C,-DCOMPRESSED_ISA,$(COMPRESSED_ISA)) $^
	chmod -x $@

testbench_verilator: ../picorv32/testbench.v ../picorv32/picorv32.v ../picorv32/testbench.cc
	$(VERILATOR) --cc --exe -Wno-lint -trace --top-module picorv32_wrapper ../picorv32/testbench.v ../picorv32/picorv32.v ../picorv32/testbench.cc \
			$(subst C,-DCOMPRESSED_ISA,$(COMPRESSED_ISA)) --Mdir testbench_verilator_dir
	$(MAKE) -C testbench_verilator_dir -f Vpicorv32_wrapper.mk
	cp testbench_verilator_dir/Vpicorv32_wrapper testbench_verilator

$(FIRMWARE_HEX): $(FIRMWARE_BIN) ../picorv32/firmware/makehex.py
	$(PYTHON) ../picorv32/firmware/makehex.py $< 32768 > $@

$(FIRMWARE_BIN): $(FIRMWARE_ELF)
	$(TOOLCHAIN_PREFIX)objcopy -O binary $< $@
	chmod -x $@

$(FIRMWARE_ELF): start.o print.o main.o ../picorv32/firmware/sections.lds
	$(TOOLCHAIN_PREFIX)gcc -Os -mabi=ilp32 -march=rv32im$(subst C,c,$(COMPRESSED_ISA)) -ffreestanding -nostdlib -o $@ \
		-Wl,--build-id=none,-Bstatic,-T,../picorv32/firmware/sections.lds,-Map,$(FIRMWARE_MAP),--strip-debug \
		start.o print.o main.o -lgcc
	chmod -x $@

start.o: start.S
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32im$(subst C,c,$(COMPRESSED_ISA)) -o $@ $<

print.o: ../picorv32/firmware/print.c ../picorv32/firmware/firmware.h
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32i$(subst C,c,$(COMPRESSED_ISA)) -Os --std=c99 $(GCC_WARNS) -ffreestanding -nostdlib -o $@ $<

main.o: main.c ../picorv32/firmware/firmware.h
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32i$(subst C,c,$(COMPRESSED_ISA)) -Os --std=c99 $(GCC_WARNS) -ffreestanding -nostdlib -o $@ $<

clean:
	rm -rf start.o print.o main.o $(FIRMWARE_ELF) $(FIRMWARE_BIN) $(FIRMWARE_HEX) $(FIRMWARE_MAP) \
		testbench.vvp testbench.vcd testbench.trace testbench_verilator testbench_verilator_dir

.PHONY: all test test_vcd test_verilator clean
