`timescale 1ns/1ps

module tb_openfpga_arduboy_soc_real_game;
	reg clk = 1'b0;
	reg resetn = 1'b0;
	reg emulator_reset = 1'b1;
	reg [5:0] buttons = 6'b000000;

	wire fb_we;
	wire [9:0] fb_addr;
	wire [7:0] fb_wdata;
	wire [13:0] flash_addr;
	reg [15:0] flash_data;
	wire buzzer;

	reg [15:0] rom [0:16383];
	integer i;
	integer cycles = 0;
	integer writes = 0;
	integer nonzero_writes = 0;
	integer min_writes = 32;
	integer min_nonzero = 0;
	integer max_cycles = 2000000;
	integer press_b_at = -1;
	integer release_b_at = -1;
	integer check_linear = 0;
	integer expected_addr = 0;

	always #31 clk = ~clk;

	initial begin
		for (i = 0; i < 16384; i = i + 1)
			rom[i] = 16'hffff;
		$readmemh("real_titles/1nvader_words.mem", rom);
		if (!$value$plusargs("MIN_WRITES=%d", min_writes))
			min_writes = 32;
		if (!$value$plusargs("MIN_NONZERO=%d", min_nonzero))
			min_nonzero = 0;
		if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
			max_cycles = 2000000;
		if (!$value$plusargs("PRESS_B_AT=%d", press_b_at))
			press_b_at = -1;
		if (!$value$plusargs("RELEASE_B_AT=%d", release_b_at))
			release_b_at = -1;
		if (!$value$plusargs("CHECK_LINEAR=%d", check_linear))
			check_linear = 0;
		#1000;
		resetn = 1'b1;
		#1000;
		emulator_reset = 1'b0;
	end

	always @(posedge clk) begin
		flash_data <= rom[flash_addr];
		cycles = cycles + 1;

		if (cycles == press_b_at) begin
			buttons[5] <= 1'b1;
			$display("BUTTON: press B at cycle=%0d", cycles);
		end
		if (cycles == release_b_at) begin
			buttons[5] <= 1'b0;
			$display("BUTTON: release B at cycle=%0d", cycles);
		end

		if (fb_we) begin
			writes = writes + 1;
			if (check_linear != 0 && fb_addr != expected_addr[9:0]) begin
				$display("FAIL: non-linear framebuffer address write=%0d expected=0x%03x actual=0x%03x",
					writes, expected_addr[9:0], fb_addr);
				$finish;
			end
			expected_addr = (expected_addr + 1) & 1023;
			if (fb_wdata != 8'h00)
				nonzero_writes = nonzero_writes + 1;
			if (writes <= 16 || (fb_wdata != 8'h00 && nonzero_writes <= 16))
				$display("FB_WRITE cycle=%0d addr=0x%03x data=0x%02x writes=%0d nonzero=%0d",
					cycles, fb_addr, fb_wdata, writes, nonzero_writes);
		end

		if ((cycles % 200000) == 0)
			$display("PROGRESS cycles=%0d pc=0x%04x writes=%0d nonzero=%0d",
				cycles, u_soc.u_core.atmega32u4_inst.PC, writes, nonzero_writes);

		if ((min_writes == 0 || writes >= min_writes) &&
			(min_nonzero == 0 || nonzero_writes >= min_nonzero)) begin
			$display("PASS: production SoC decoded writes=%0d nonzero=%0d", writes, nonzero_writes);
			$finish;
		end

		if (cycles >= max_cycles) begin
			$display("FAIL: timeout cycles=%0d pc=0x%04x writes=%0d nonzero=%0d spi_scl=%b cs=%b dc=%b",
				cycles, u_soc.u_core.atmega32u4_inst.PC, writes, nonzero_writes,
				u_soc.spi_scl, u_soc.oled_cs, u_soc.oled_dc);
			$finish;
		end
	end

	openfpga_arduboy_soc u_soc (
		.clk(clk),
		.resetn(resetn),
		.emulator_reset(emulator_reset),
		.buttons(buttons),
		.fb_we(fb_we),
		.fb_addr(fb_addr),
		.fb_wdata(fb_wdata),
		.cpu_flash_word_addr(flash_addr),
		.cpu_flash_instr(flash_data),
		.buzzer(buzzer)
	);

	wire unused = buzzer;
endmodule
