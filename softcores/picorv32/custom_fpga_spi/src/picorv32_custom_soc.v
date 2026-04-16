module picorv32_custom_soc #(
	parameter [1023:0] FIRMWARE_HEX = "firmware/firmware.hex",
	parameter integer FIRMWARE_WORDS = 2048,
	parameter integer SRAM_WORDS = 2048
) (
	input clk,
	input resetn,
	output trap,
	output reg [7:0] leds,
	output reg out_strobe,
	output reg [7:0] out_byte,
	output reg passed,
	output trace_valid,
	output [35:0] trace_data,
	output spi_sclk,
	output spi_mosi,
	output spi_cs_n,
	output spi_dc,
	output spi_rst_n
);
	localparam [31:0] FIRMWARE_BYTES = FIRMWARE_WORDS * 4;
	localparam [31:0] SRAM_BASE = 32'h0000_2000;
	localparam [31:0] SRAM_BYTES = SRAM_WORDS * 4;
	localparam [31:0] OUTPORT_ADDR = 32'h1000_0000;
	localparam [31:0] LED_ADDR = 32'h1000_0004;
	localparam [31:0] SPI_TX_ADDR = 32'h1000_0010;
	localparam [31:0] SPI_CTRL_ADDR = 32'h1000_0014;
	localparam [31:0] SPI_STATUS_ADDR = 32'h1000_0018;
	localparam [31:0] PASS_ADDR = 32'h2000_0000;

`ifdef COMPRESSED_ISA
	localparam [0:0] CORE_COMPRESSED_ISA = 1;
`else
	localparam [0:0] CORE_COMPRESSED_ISA = 0;
`endif

	wire        mem_valid;
	wire        mem_instr;
	reg         mem_ready;
	wire [31:0] mem_addr;
	wire [31:0] mem_wdata;
	wire [ 3:0] mem_wstrb;
	reg  [31:0] mem_rdata;

	reg [31:0] firmware_rom [0:FIRMWARE_WORDS-1];
	reg [31:0] sram [0:SRAM_WORDS-1];
	reg [1023:0] firmware_file;

	wire rom_read = mem_valid && !mem_wstrb && mem_addr < FIRMWARE_BYTES;
	wire sram_read = mem_valid && !mem_wstrb &&
			mem_addr >= SRAM_BASE && mem_addr < SRAM_BASE + SRAM_BYTES;
	wire sram_write = mem_valid && |mem_wstrb &&
			mem_addr >= SRAM_BASE && mem_addr < SRAM_BASE + SRAM_BYTES;
	wire outport_write = mem_valid && |mem_wstrb && mem_addr == OUTPORT_ADDR;
	wire led_read = mem_valid && !mem_wstrb && mem_addr == LED_ADDR;
	wire led_write = mem_valid && |mem_wstrb && mem_addr == LED_ADDR;
	wire pass_read = mem_valid && !mem_wstrb && mem_addr == PASS_ADDR;
	wire pass_write = mem_valid && |mem_wstrb && mem_addr == PASS_ADDR;
	wire spi_tx_write = mem_valid && |mem_wstrb && mem_addr == SPI_TX_ADDR;
	wire spi_ctrl_read = mem_valid && !mem_wstrb && mem_addr == SPI_CTRL_ADDR;
	wire spi_ctrl_write = mem_valid && |mem_wstrb && mem_addr == SPI_CTRL_ADDR;
	wire spi_status_read = mem_valid && !mem_wstrb && mem_addr == SPI_STATUS_ADDR;

	wire [31:0] sram_word_addr = (mem_addr - SRAM_BASE) >> 2;

	reg  [ 7:0] spi_tx_latch;
	reg  [ 7:0] spi_clk_div;
	reg         spi_keep_cs;
	reg         spi_dc_reg;
	reg         spi_rst_n_reg;
	reg         spi_idle_cs_n;
	reg         spi_start;
	reg         spi_release_cs;
	wire        spi_busy;
	wire        spi_done;
	reg         spi_done_latch;

	initial begin
		leds = 0;
		out_strobe = 0;
		out_byte = 0;
		passed = 0;
		mem_ready = 0;
		mem_rdata = 0;
		spi_tx_latch = 0;
		spi_clk_div = 8'd3;
		spi_keep_cs = 0;
		spi_dc_reg = 0;
		spi_rst_n_reg = 1;
		spi_idle_cs_n = 1;
		spi_start = 0;
		spi_release_cs = 0;
		spi_done_latch = 0;
`ifdef SYNTHESIS
		$readmemh(FIRMWARE_HEX, firmware_rom);
`else
		firmware_file = FIRMWARE_HEX;
		$display("Loading firmware from %0s", firmware_file);
		if ($value$plusargs("firmware=%s", firmware_file))
			$display("Overriding firmware image with %0s", firmware_file);
		$readmemh(firmware_file, firmware_rom);
`endif
	end

	simple_spi_master spi0 (
		.clk        (clk),
		.resetn     (resetn),
		.clk_div    (spi_clk_div),
		.tx_data    (spi_tx_latch),
		.start      (spi_start),
		.release_cs (spi_release_cs),
		.keep_cs    (spi_keep_cs),
		.idle_cs_n  (spi_idle_cs_n),
		.dc_in      (spi_dc_reg),
		.rst_n_in   (spi_rst_n_reg),
		.busy       (spi_busy),
		.done       (spi_done),
		.sclk       (spi_sclk),
		.mosi       (spi_mosi),
		.cs_n       (spi_cs_n),
		.dc         (spi_dc),
		.rst_n      (spi_rst_n)
	);

	picorv32 #(
		.COMPRESSED_ISA(CORE_COMPRESSED_ISA),
		.ENABLE_MUL(1),
		.ENABLE_DIV(1),
		.ENABLE_TRACE(1),
		.LATCHED_MEM_RDATA(1)
	) cpu (
		.clk        (clk        ),
		.resetn     (resetn     ),
		.trap       (trap       ),
		.mem_valid  (mem_valid  ),
		.mem_instr  (mem_instr  ),
		.mem_ready  (mem_ready  ),
		.mem_addr   (mem_addr   ),
		.mem_wdata  (mem_wdata  ),
		.mem_wstrb  (mem_wstrb  ),
		.mem_rdata  (mem_rdata  ),
		.irq        (32'b0      ),
		.trace_valid(trace_valid),
		.trace_data (trace_data )
	);

	always @(posedge clk) begin
		mem_ready <= 0;
		out_strobe <= 0;
		spi_start <= 0;
		spi_release_cs <= 0;

		if (!resetn) begin
			leds <= 0;
			out_byte <= 0;
			passed <= 0;
			spi_tx_latch <= 0;
			spi_clk_div <= 8'd3;
			spi_keep_cs <= 0;
			spi_dc_reg <= 0;
			spi_rst_n_reg <= 1;
			spi_idle_cs_n <= 1;
			spi_done_latch <= 0;
		end else if (mem_valid && !mem_ready) begin
			if (rom_read) begin
				mem_rdata <= firmware_rom[mem_addr[12:2]];
				mem_ready <= 1;
			end else if (sram_read) begin
				mem_rdata <= sram[sram_word_addr];
				mem_ready <= 1;
			end else if (sram_write) begin
				if (mem_wstrb[0]) sram[sram_word_addr][ 7: 0] <= mem_wdata[ 7: 0];
				if (mem_wstrb[1]) sram[sram_word_addr][15: 8] <= mem_wdata[15: 8];
				if (mem_wstrb[2]) sram[sram_word_addr][23:16] <= mem_wdata[23:16];
				if (mem_wstrb[3]) sram[sram_word_addr][31:24] <= mem_wdata[31:24];
				mem_ready <= 1;
			end else if (outport_write) begin
				out_byte <= mem_wdata[7:0];
				out_strobe <= 1;
				mem_ready <= 1;
			end else if (led_read) begin
				mem_rdata <= {24'b0, leds};
				mem_ready <= 1;
			end else if (led_write) begin
				leds <= mem_wdata[7:0];
				mem_ready <= 1;
			end else if (pass_read) begin
				mem_rdata <= {31'b0, passed};
				mem_ready <= 1;
			end else if (pass_write) begin
				if (mem_wdata == 32'd123456789)
					passed <= 1;
				mem_ready <= 1;
			end else if (spi_tx_write) begin
				if (mem_wstrb[0]) spi_tx_latch <= mem_wdata[7:0];
				mem_ready <= 1;
			end else if (spi_ctrl_write) begin
				if (mem_wstrb[0]) spi_clk_div <= mem_wdata[7:0];
				if (mem_wstrb[1]) begin
					spi_keep_cs   <= mem_wdata[9];
					spi_dc_reg    <= mem_wdata[10];
					spi_rst_n_reg <= mem_wdata[11];
					spi_idle_cs_n <= mem_wdata[12];
					if (mem_wdata[13])
						spi_release_cs <= 1;
					if (mem_wdata[8] && !spi_busy)
						spi_start <= 1;
				end
				mem_ready <= 1;
			end else if (spi_ctrl_read) begin
				mem_rdata <= {19'b0,
					spi_idle_cs_n,
					spi_rst_n_reg,
					spi_dc_reg,
					spi_keep_cs,
					1'b0,
					spi_clk_div};
				mem_ready <= 1;
			end else if (spi_status_read) begin
				mem_rdata <= {30'b0, spi_done_latch | spi_done, spi_busy};
				spi_done_latch <= 0;
				mem_ready <= 1;
			end else begin
				mem_rdata <= 0;
				mem_ready <= 1;
			end
		end else begin
			if (spi_done)
				spi_done_latch <= 1;
		end
	end
endmodule
