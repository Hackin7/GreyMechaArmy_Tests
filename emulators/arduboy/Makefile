PROJ = arduboy_fx
TARGET_FREQ_MHZ ?= 75

SHELL = bash
YOSYS_DEFS ?=
AVR_DEFS = -DAVR_ARCH_SELECTED -DAVR_500
SYNTH_ECP5_FLAGS = -noabc9

FAST_OLED_SRC = rtl/fast_oled
OPENFPGA_AVR_SRC = vendor/openfpga-arduboy/src/fpga/core/rtl/avr
RTL_DIR = rtl

RTL_ORDER = \
	$(FAST_OLED_SRC)/btn_debounce.v \
	$(FAST_OLED_SRC)/simple_spi_master.v \
	$(FAST_OLED_SRC)/oled_init.v \
	$(FAST_OLED_SRC)/oled_stream.v \
	$(FAST_OLED_SRC)/oled_gc9a01.v \
	$(OPENFPGA_AVR_SRC)/mega-alu.v \
	$(OPENFPGA_AVR_SRC)/mega-core.v \
	$(OPENFPGA_AVR_SRC)/mega-ram.v \
	$(OPENFPGA_AVR_SRC)/mega-reg.v \
	$(OPENFPGA_AVR_SRC)/mega-rom.v \
	$(OPENFPGA_AVR_SRC)/io-dmux.v \
	$(OPENFPGA_AVR_SRC)/atmega-pio.v \
	$(OPENFPGA_AVR_SRC)/atmega-pll.v \
	$(OPENFPGA_AVR_SRC)/atmega-tim-8bit.v \
	$(OPENFPGA_AVR_SRC)/atmega-tim-10bit.v \
	$(OPENFPGA_AVR_SRC)/atmega-tim-16bit.v \
	$(OPENFPGA_AVR_SRC)/atmega-spi-m.v \
	$(OPENFPGA_AVR_SRC)/atmega-eep.v \
	$(OPENFPGA_AVR_SRC)/atmega-uart.v \
	$(OPENFPGA_AVR_SRC)/atmega_twi.v \
	$(OPENFPGA_AVR_SRC)/atmega_twi_s.v \
	$(OPENFPGA_AVR_SRC)/atmega-twi_s_h.v \
	$(OPENFPGA_AVR_SRC)/atmega-rtc.v \
	$(OPENFPGA_AVR_SRC)/atmega-rng-as-adc.v \
	$(OPENFPGA_AVR_SRC)/atmega32u4_arduboy.v \
	$(RTL_DIR)/openfpga_ecp5_stubs.v \
	$(RTL_DIR)/ecp5_arduboy_pll.v \
	$(RTL_DIR)/arduboy_oled_spi_decoder.v \
	$(RTL_DIR)/arduboy_framebuffer.v \
	$(RTL_DIR)/host_spi_byte_slave.v \
	$(RTL_DIR)/arduboy_host_bridge.v \
	$(RTL_DIR)/arduboy_memories.v \
	$(RTL_DIR)/openfpga_arduboy_soc.v \
	$(RTL_DIR)/top.v

YOSYS_INCLUDES = -I$(FAST_OLED_SRC) -I$(OPENFPGA_AVR_SRC)

all: $(PROJ).bit

tmp.v: $(RTL_ORDER) $(FAST_OLED_SRC)/gc9a01_init_rom.vh
	mkdir -p log
	cat $(RTL_ORDER) > $@

$(PROJ).json: tmp.v
	bash -lc "set -o pipefail; yosys -p 'read_verilog -sv $(YOSYS_INCLUDES) $(AVR_DEFS) $(YOSYS_DEFS) $<; synth_ecp5 $(SYNTH_ECP5_FLAGS) -top top -json $@' 2>&1 | tee log/yosys.log"

$(PROJ)_out.config: $(PROJ).json pinout.lpf
	bash -lc "set -o pipefail; nextpnr-ecp5 --freq $(TARGET_FREQ_MHZ) --json $< --textcfg $@ --25k --package CABGA256 --lpf pinout.lpf 2>&1 | tee log/nextpnr-ecp5.log"

$(PROJ).bit: $(PROJ)_out.config
	bash -lc "set -o pipefail; ecppack --svf $(PROJ).svf $< $@ 2>&1 | tee log/ecppack.log"

bit: $(PROJ).bit

clean:
	rm -rf log tmp.v $(PROJ).json $(PROJ)_out.config $(PROJ).bit $(PROJ).svf

.PHONY: all bit clean
