`timescale 1ns/1ps

module tb_atmega_spi_spif;
	localparam [7:0] SPCR = 8'h4c;
	localparam [7:0] SPSR = 8'h4d;
	localparam [7:0] SPDR = 8'h4e;

	reg clk = 1'b0;
	reg rst = 1'b1;
	reg [7:0] addr = 8'h00;
	reg wr = 1'b0;
	reg rd = 1'b0;
	reg [7:0] bus_i = 8'h00;
	wire [7:0] bus_o;
	wire irq;
	wire sck;
	wire mosi;
	integer cycles;

	always #5 clk = ~clk;

	task write_reg;
		input [7:0] reg_addr;
		input [7:0] value;
		begin
			@(negedge clk);
			addr = reg_addr;
			bus_i = value;
			wr = 1'b1;
			@(negedge clk);
			wr = 1'b0;
		end
	endtask

	task read_reg;
		input [7:0] reg_addr;
		output [7:0] value;
		begin
			@(negedge clk);
			addr = reg_addr;
			rd = 1'b1;
			#1 value = bus_o;
			@(negedge clk);
			rd = 1'b0;
		end
	endtask

	reg [7:0] value;
	initial begin
		repeat (3) @(negedge clk);
		rst = 1'b0;

		// Enable SPI as master at the fastest normal rate.
		write_reg(SPCR, 8'h50);
		write_reg(SPDR, 8'ha5);

		cycles = 0;
		while (!dut.SPSR[7] && cycles < 100) begin
			@(negedge clk);
			cycles = cycles + 1;
		end
		if (!dut.SPSR[7]) begin
			$display("FAIL: SPIF was not set after transfer completion");
			$finish;
		end

		read_reg(SPSR, value);
		if (!value[7] || !dut.SPSR[7]) begin
			$display("FAIL: reading SPSR cleared SPIF prematurely");
			$finish;
		end

		// Re-reading SPSR must still leave SPIF set.
		read_reg(SPSR, value);
		if (!value[7] || !dut.SPSR[7]) begin
			$display("FAIL: repeated SPSR read cleared SPIF");
			$finish;
		end

		// The access to SPDR following the status read completes the clear.
		read_reg(SPDR, value);
		@(negedge clk);
		if (dut.SPSR[7]) begin
			$display("FAIL: SPSR-read/SPDR-access sequence did not clear SPIF");
			$finish;
		end

		// A new transfer must set SPIF again, and interrupt acknowledge clears it.
		write_reg(SPCR, 8'hd0);
		write_reg(SPDR, 8'h3c);
		cycles = 0;
		while (!irq && cycles < 100) begin
			@(negedge clk);
			cycles = cycles + 1;
		end
		if (!irq) begin
			$display("FAIL: SPI interrupt was not asserted");
			$finish;
		end
		@(negedge clk);
		int_ack = 1'b1;
		@(negedge clk);
		int_ack = 1'b0;
		if (dut.SPSR[7] || irq) begin
			$display("FAIL: interrupt acknowledge did not clear SPIF");
			$finish;
		end

		$display("PASS: AVR SPIF clear sequence");
		$finish;
	end

	reg int_ack = 1'b0;
	atmega_spi_m #(
		.SPCR_ADDR(SPCR),
		.SPSR_ADDR(SPSR),
		.SPDR_ADDR(SPDR)
	) dut (
		.rst_i(rst),
		.clk_i(clk),
		.addr_i(addr),
		.wr_i(wr),
		.rd_i(rd),
		.bus_i(bus_i),
		.bus_o(bus_o),
		.int_o(irq),
		.int_ack_i(int_ack),
		.io_connect_o(),
		.io_conn_slave_o(),
		.scl_o(sck),
		.miso_i(1'b0),
		.mosi_o(mosi)
	);

	wire unused = sck | mosi;
endmodule
