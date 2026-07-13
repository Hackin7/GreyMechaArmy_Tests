`timescale 1ns/1ps

module tb_1nvader_trace;
	reg clk = 1'b0;
	reg resetn = 1'b0;
	reg emulator_reset = 1'b1;
	reg [5:0] buttons = 6'b000000;

	wire fb_we;
	wire [9:0] fb_addr;
	wire [7:0] fb_wdata;
	wire cpu_eeprom_we;
	wire [9:0] cpu_eeprom_addr;
	wire [7:0] cpu_eeprom_wdata;
	wire [13:0] cpu_flash_word_addr;
	reg [15:0] cpu_flash_instr;
	wire [23:0] fx_cpu_page;
	wire [7:0] fx_cpu_offset;
	wire fx_cpu_req;
	wire buzzer;

	reg [15:0] rom [0:16383];
	reg [31:0] io_read_count [0:63];
	reg [31:0] io_write_count [0:63];
	reg [7:0] io_last_write [0:63];
	integer cycles = 0;
	integer fb_writes = 0;
	integer i;
	localparam integer MAX_CYCLES = 2000000;

	always #5 clk = ~clk;

	initial begin
		for (i = 0; i < 16384; i = i + 1)
			rom[i] = 16'hffff;
		for (i = 0; i < 64; i = i + 1) begin
			io_read_count[i] = 0;
			io_write_count[i] = 0;
			io_last_write[i] = 0;
		end
		$readmemh("real_titles/1nvader_words.mem", rom);
		#100;
		resetn = 1'b1;
		#100;
		emulator_reset = 1'b0;
	end

	always @(posedge clk) begin
		cpu_flash_instr <= rom[cpu_flash_word_addr];

		if (uut.io_re) begin
			io_read_count[uut.io_a] = io_read_count[uut.io_a] + 1;
	if (io_read_count[uut.io_a] <= 4)
				$display("IO_READ cycle=%0d pc=%0d a=0x%02x di=0x%02x instr=0x%04x",
					cycles, uut.u_avr.PC, uut.io_a, uut.io_di, uut.u_avr.INSTR);
		end

		if (uut.io_we) begin
			io_write_count[uut.io_a] = io_write_count[uut.io_a] + 1;
			io_last_write[uut.io_a] = uut.io_do;
	if (io_write_count[uut.io_a] <= 6)
				$display("IO_WRITE cycle=%0d pc=%0d a=0x%02x do=0x%02x instr=0x%04x",
					cycles, uut.u_avr.PC, uut.io_a, uut.io_do, uut.u_avr.INSTR);
		end

		if (fb_we) begin
			fb_writes = fb_writes + 1;
			if (fb_writes <= 8)
				$display("FB_WRITE cycle=%0d addr=0x%03x data=0x%02x", cycles, fb_addr, fb_wdata);
		end

		cycles = cycles + 1;
		if ((cycles % 500000) == 0 && cycles != 0)
			$display("PROGRESS cycles=%0d fb_writes=%0d pc=%0d instr=0x%04x",
				cycles, fb_writes, uut.u_avr.PC, uut.u_avr.INSTR);

		if (cycles == MAX_CYCLES) begin
			$display("SUMMARY cycles=%0d fb_writes=%0d pc=%0d instr=0x%04x",
				cycles, fb_writes, uut.u_avr.PC, uut.u_avr.INSTR);
			for (i = 0; i < 64; i = i + 1)
				if (io_read_count[i] || io_write_count[i])
					$display("SUMMARY_IO a=0x%02x reads=%0d writes=%0d last_write=0x%02x",
						i, io_read_count[i], io_write_count[i], io_last_write[i]);
			$finish;
		end
	end

	arduboy_soc_shell uut (
		.clk(clk),
		.resetn(resetn),
		.emulator_reset(emulator_reset),
		.buttons(buttons),
		.fb_we(fb_we),
		.fb_addr(fb_addr),
		.fb_wdata(fb_wdata),
		.cpu_eeprom_we(cpu_eeprom_we),
		.cpu_eeprom_addr(cpu_eeprom_addr),
		.cpu_eeprom_wdata(cpu_eeprom_wdata),
		.cpu_eeprom_rdata(8'h00),
		.cpu_flash_word_addr(cpu_flash_word_addr),
		.cpu_flash_instr(cpu_flash_instr),
		.fx_cpu_page(fx_cpu_page),
		.fx_cpu_offset(fx_cpu_offset),
		.fx_cpu_req(fx_cpu_req),
		.fx_cpu_rdata(8'h00),
		.fx_cpu_hit(1'b0),
		.buzzer(buzzer)
	);

	wire unused = cpu_eeprom_we | |cpu_eeprom_addr | |cpu_eeprom_wdata |
		|fx_cpu_page | |fx_cpu_offset | fx_cpu_req | buzzer;
endmodule
