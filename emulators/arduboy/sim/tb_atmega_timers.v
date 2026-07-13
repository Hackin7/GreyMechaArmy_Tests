`timescale 1ns/1ps

module tb_atmega_timers;
	reg clk = 1'b0;
	reg rst = 1'b1;
	reg [9:0] divider = 10'h000;
	always #5 clk = ~clk;
	always @(posedge clk) begin
		if (rst)
			divider <= 10'h000;
		else
			divider <= divider + 1'b1;
	end

	wire clk8 = divider[2];
	wire clk64 = divider[5];
	wire clk256 = divider[7];
	wire clk1024 = divider[9];

	reg [7:0] addr0 = 8'h00;
	reg wr0 = 1'b0;
	reg rd0 = 1'b0;
	reg [7:0] data0 = 8'h00;
	wire [7:0] q0;
	wire tov0;
	reg tov0_ack = 1'b0;

	reg [7:0] addr3 = 8'h00;
	reg wr3 = 1'b0;
	reg rd3 = 1'b0;
	reg [7:0] data3 = 8'h00;
	wire [7:0] q3;
	wire compa3;
	reg compa3_ack = 1'b0;

	task write0;
		input [7:0] reg_addr;
		input [7:0] value;
		begin
			@(negedge clk);
			addr0 = reg_addr;
			data0 = value;
			wr0 = 1'b1;
			@(negedge clk);
			wr0 = 1'b0;
		end
	endtask

	task read0;
		input [7:0] reg_addr;
		output [7:0] value;
		begin
			@(negedge clk);
			addr0 = reg_addr;
			rd0 = 1'b1;
			#1 value = q0;
			@(negedge clk);
			rd0 = 1'b0;
		end
	endtask

	task write3;
		input [7:0] reg_addr;
		input [7:0] value;
		begin
			@(negedge clk);
			addr3 = reg_addr;
			data3 = value;
			wr3 = 1'b1;
			@(negedge clk);
			wr3 = 1'b0;
		end
	endtask

	task read3;
		input [7:0] reg_addr;
		output [7:0] value;
		begin
			@(negedge clk);
			addr3 = reg_addr;
			rd3 = 1'b1;
			#1 value = q3;
			@(negedge clk);
			rd3 = 1'b0;
		end
	endtask

	reg [7:0] first_count;
	reg [7:0] second_count;
	reg [7:0] timer3_low;
	integer timeout;
	initial begin
		repeat (4) @(negedge clk);
		rst = 1'b0;

		// Arduino Timer0 configuration: fast PWM, prescaler /64, overflow IRQ.
		write0(8'h44, 8'h03);
		write0(8'h45, 8'h03);
		write0(8'h6e, 8'h01);
		repeat (80) @(negedge clk);
		read0(8'h46, first_count);
		repeat (80) @(negedge clk);
		read0(8'h46, second_count);
		if (first_count == second_count || second_count == 0) begin
			$display("FAIL: TCNT0 did not expose the running /64 counter (%0d -> %0d)",
				first_count, second_count);
			$finish;
		end

		// A TCNT0 write must affect the running counter and quickly overflow.
		write0(8'h46, 8'hfa);
		timeout = 0;
		while (!tov0 && timeout < 600) begin
			@(negedge clk);
			timeout = timeout + 1;
		end
		if (!tov0) begin
			$display("FAIL: Timer0 overflow did not follow TCNT0 write");
			$finish;
		end
		tov0_ack = 1'b1;
		@(negedge clk);
		tov0_ack = 1'b0;
		@(negedge clk);
		if (tov0 || dut0.TIFR[0]) begin
			$display("FAIL: Timer0 interrupt acknowledge did not clear TOV0");
			$finish;
		end

		// ArduboyTones-style Timer3 CTC setup. OCR3A=3 means a four-tick period.
		write3(8'h99, 8'h00);
		write3(8'h98, 8'h03);
		write3(8'h90, 8'h00);
		write3(8'h91, 8'h09);
		write3(8'h71, 8'h02);
		timeout = 0;
		while (!compa3 && timeout < 20) begin
			@(negedge clk);
			timeout = timeout + 1;
		end
		if (!compa3) begin
			$display("FAIL: Timer3 CTC compare interrupt did not fire TCCR=%02x/%02x OCR=%02x%02x OCRA_int=%04x TCNT=%02x%02x TIMSK=%02x TIFR=%02x",
				dut3.TCCRA, dut3.TCCRB, dut3.OCRAH, dut3.OCRAL,
				dut3.OCRA_int, dut3.TCNTH, dut3.TCNTL, dut3.TIMSK, dut3.TIFR);
			$finish;
		end
		compa3_ack = 1'b1;
		@(negedge clk);
		compa3_ack = 1'b0;
		@(negedge clk);
		if (compa3 || dut3.TIFR[1]) begin
			$display("FAIL: Timer3 compare acknowledge did not clear OCF3A");
			$finish;
		end

		// TCNT3 writes must reset the same counter used by compare generation.
		write3(8'h95, 8'h00);
		write3(8'h94, 8'h00);
		read3(8'h94, timer3_low);
		if (timer3_low > 8'h02) begin
			$display("FAIL: TCNT3 write/read did not reset the running counter: %0d", timer3_low);
			$finish;
		end

		$display("PASS: Timer0 counting/overflow and Timer3 CTC behavior");
		$finish;
	end

	atmega_tim_8bit #(
		.USE_SIMPLE_COUNTER("FALSE"),
		.USE_OCRB("FALSE")
	) dut0 (
		.rst_i(rst), .clk_i(clk), .clk8_i(clk8), .clk64_i(clk64),
		.clk256_i(clk256), .clk1024_i(clk1024), .addr_i(addr0),
		.wr_i(wr0), .rd_i(rd0), .bus_i(data0), .bus_o(q0),
		.tov_int_o(tov0), .tov_int_ack_i(tov0_ack),
		.ocra_int_o(), .ocra_int_ack_i(1'b0),
		.ocrb_int_o(), .ocrb_int_ack_i(1'b0), .t_i(1'b0),
		.oca_o(), .ocb_o(), .oca_io_connect_o(), .ocb_io_connect_o()
	);

	atmega_tim_16bit #(
		.USE_SIMPLE_COUNTER("FALSE"),
		.USE_OCRB("FALSE"),
		.USE_OCRC("FALSE"),
		.USE_OCRD("FALSE"),
		.TCCRA_ADDR(8'h90), .TCCRB_ADDR(8'h91), .TCCRC_ADDR(8'h92),
		.TCNTL_ADDR(8'h94), .TCNTH_ADDR(8'h95),
		.ICRL_ADDR(8'h96), .ICRH_ADDR(8'h97),
		.OCRAL_ADDR(8'h98), .OCRAH_ADDR(8'h99),
		.OCRBL_ADDR(8'h9a), .OCRBH_ADDR(8'h9b),
		.OCRCL_ADDR(8'h9c), .OCRCH_ADDR(8'h9d),
		.TIMSK_ADDR(8'h71), .TIFR_ADDR(8'h38)
	) dut3 (
		.rst_i(rst), .clk_i(clk), .clk8_i(clk8), .clk64_i(clk64),
		.clk256_i(clk256), .clk1024_i(clk1024), .addr_i(addr3),
		.wr_i(wr3), .rd_i(rd3), .bus_i(data3), .bus_o(q3),
		.tov_int_o(), .tov_int_ack_i(1'b0),
		.ocra_int_o(compa3), .ocra_int_ack_i(compa3_ack),
		.ocrb_int_o(), .ocrb_int_ack_i(1'b0),
		.ocrc_int_o(), .ocrc_int_ack_i(1'b0),
		.ocrd_int_o(), .ocrd_int_ack_i(1'b0), .t_i(1'b0),
		.oca_o(), .ocb_o(), .occ_o(), .ocd_o(),
		.oca_io_connect_o(), .ocb_io_connect_o(),
		.occ_io_connect_o(), .ocd_io_connect_o()
	);
endmodule
