PROJ = fpga_oled
TARGET_FREQ_MHZ ?= 75

SHELL = bash
YOSYS_DEFS ?=

RTL_ORDER = src/simple_spi_master.v src/btn_debounce.v src/ecp5_oled_pll.v \
            src/oled_init.v src/oled_stream.v src/oled_gc9a01.v src/image_stretch.v \
            src/ee2026/custom/clk_counter.v \
            src/ee2026/task_a/animation_timer.v src/ee2026/task_a/middle_square_timer.v \
            src/ee2026/task_a/adaptor_task_a.v \
            src/ee2026/adaptor_task_b.v src/ee2026/adaptor_task_c.v src/ee2026/adaptor_task_d.v \
            src/ee2026/Top_Student.v \
            src/top.v

all: $(PROJ).bit

tmp.v: $(RTL_ORDER) src/gc9a01_init_rom.vh
	mkdir -p log
	cat $(RTL_ORDER) > $@

$(PROJ).json: tmp.v
	bash -lc "set -o pipefail; yosys -p 'read_verilog -sv -Isrc $(YOSYS_DEFS) $<; synth_ecp5 -top top -json $@' 2>&1 | tee log/yosys.log"

$(PROJ)_out.config: $(PROJ).json pinout.lpf
	bash -lc "set -o pipefail; nextpnr-ecp5 --freq $(TARGET_FREQ_MHZ) --json $< --textcfg $@ --25k --package CABGA256 --lpf pinout.lpf 2>&1 | tee log/nextpnr-ecp5.log"

$(PROJ).bit: $(PROJ)_out.config
	bash -lc "set -o pipefail; ecppack --svf $(PROJ).svf $< $@ 2>&1 | tee log/ecppack.log"

bit: $(PROJ).bit

clean:
	rm -rf log tmp.v $(PROJ).json $(PROJ)_out.config $(PROJ).bit $(PROJ).svf

SIM_DIR = tb/build

$(SIM_DIR):
	mkdir -p $@

sim_init: | $(SIM_DIR)
	iverilog -o $(SIM_DIR)/sim_init.vvp -I src tb/tb_oled_init.v src/oled_init.v
	cd tb && vvp build/sim_init.vvp

sim_stream: | $(SIM_DIR)
	iverilog -o $(SIM_DIR)/sim_stream.vvp -I src tb/tb_oled_stream.v src/oled_stream.v
	cd tb && vvp build/sim_stream.vvp

# sim_top runs vvp from project root so top.v's $readmemh("stonks.mem") resolves.
sim_top: | $(SIM_DIR)
	iverilog -o $(SIM_DIR)/sim_top.vvp -I src \
		tb/tb_top.v \
		src/top.v \
		src/oled_init.v \
		src/oled_stream.v \
		src/btn_debounce.v
	vvp $(SIM_DIR)/sim_top.vvp

sim: sim_init sim_stream sim_top

.PHONY: all bit clean sim sim_init sim_stream sim_top
