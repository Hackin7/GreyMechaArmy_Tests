`timescale 1ns/1ps

module openfpga_arduboy_1nvader_tb;
	reg clk = 1'b0;
	reg resetn = 1'b0;
	reg [5:0] buttons = 6'b111111;

	wire [15:0] pgm_addr;
	reg [15:0] pgm_data;
	reg [15:0] rom [0:16383];

	wire buzzer1;
	wire buzzer2;
	wire oled_dc;
	wire oled_cs;
	wire oled_rst;
	wire spi_scl;
	wire spi_mosi;
	wire [2:0] rgb;
	wire usd_cs;
	wire adc_cs;
	wire vs_rst;
	wire vs_xcs;
	wire vs_xdcs;
	wire uart_tx;
	wire [7:0] io_addr;
	wire [7:0] io_out;
	wire io_write;
	wire [7:0] io_in = 8'h00;
	wire io_read;
	wire io_sel;
	wire io_rst;
	wire nmi_rst;
	wire nmi_ack;
	wire sec_en;
	wire [7:0] ext_eep_data_o;

	wire twi_scl;
	wire twi_sda;
	wire usbp_io;
	wire usbn_io;

	wire [0:0] oled_pixel;

	integer i;
	integer cycles = 0;
	integer spi_edges = 0;
	integer oled_writes = 0;
	reg last_spi_scl = 1'b0;

	always #31 clk = ~clk; // about 16.1 MHz, close enough for core simulation.

	initial begin
		for (i = 0; i < 16384; i = i + 1)
			rom[i] = 16'hffff;
		$readmemh("real_titles/1nvader_words.mem", rom);

		#1000;
		resetn = 1'b1;
	end

	always @(posedge clk) begin
		pgm_data <= rom[pgm_addr[13:0]];

		if (spi_scl && !last_spi_scl)
			spi_edges = spi_edges + 1;
		last_spi_scl <= spi_scl;

		if (u_oled.mem_wr) begin
			oled_writes = oled_writes + 1;
			if (oled_writes <= 16)
				$display("OLED_WRITE cycle=%0d addr=0x%03x data=0x%02x dc=%b cs=%b",
					cycles, u_oled.write_addr, u_oled.write_data, oled_dc, oled_cs);
		end

		cycles = cycles + 1;
		if ((cycles % 200000) == 0)
			$display("PROGRESS cycles=%0d pgm_addr=0x%04x spi_edges=%0d oled_writes=%0d rst=%b cs=%b dc=%b",
				cycles, pgm_addr, spi_edges, oled_writes, oled_rst, oled_cs, oled_dc);

		if (oled_writes >= 32) begin
			$display("PASS: openfpga Arduboy core produced OLED framebuffer writes");
			$finish;
		end

		if (cycles == 2000000) begin
			$display("SUMMARY cycles=%0d pgm_addr=0x%04x spi_edges=%0d oled_writes=%0d rst=%b cs=%b dc=%b",
				cycles, pgm_addr, spi_edges, oled_writes, oled_rst, oled_cs, oled_dc);
			$finish;
		end
	end

	atmega32u4_arduboy #(
		.PLATFORM("XILINX"),
		.RAM_TYPE("BLOCK"),
		.ROM_ADDR_WIDTH(14),
		.BUS_ADDR_DATA_LEN(12),
		.RAM_ADDR_WIDTH(12),
		.USE_UART_1("FALSE"),
		.USE_EEPROM("FALSE"),
		.USE_TWI_1("FALSE")
	) u_core (
		.core_rst(!resetn),
		.dev_rst(!resetn),
		.clk(clk),
		.clk48m_i(clk),
		.clk_pll(clk),
		.nmi_sig(1'b0),
		.nmi_ack(nmi_ack),
		.sec_reg_rst(1'b0),
		.sec_en(sec_en),
		.buttons(buttons),
		.RGB(rgb),
		.Buzzer1(buzzer1),
		.Buzzer2(buzzer2),
		.OledDC(oled_dc),
		.OledCS(oled_cs),
		.OledRST(oled_rst),
		.spi_scl(spi_scl),
		.spi_mosi(spi_mosi),
		.uSD_CS(usd_cs),
		.ADC_CS(adc_cs),
		.VS_RST(vs_rst),
		.VS_xCS(vs_xcs),
		.VS_xDCS(vs_xdcs),
		.VS_DREQ(1'b1),
		.spi_miso(1'b0),
		.uSD_CD(1'b1),
		.uart_tx(uart_tx),
		.uart_rx(1'b1),
		.twi_scl(twi_scl),
		.twi_sda(twi_sda),
		.usbp_io(usbp_io),
		.usbn_io(usbn_io),
		.pgm_addr(pgm_addr),
		.pgm_data(pgm_data),
		.ext_eep_addr_i(17'd0),
		.ext_eep_data_i(8'hff),
		.ext_eep_data_wr_i(1'b0),
		.ext_eep_data_o(ext_eep_data_o),
		.ext_eep_data_rd_i(1'b0),
		.ext_eep_data_en_i(1'b0),
		.io_addr(io_addr),
		.io_out(io_out),
		.io_write(io_write),
		.io_in(io_in),
		.io_read(io_read),
		.io_sel(io_sel),
		.io_rst(io_rst),
		.nmi_rst(nmi_rst)
	);

	ssd1306 #(
		.X_PARENT_SIZE(128),
		.Y_PARENT_SIZE(64),
		.VRAM_BUFFERED_OUTPUT("FALSE"),
		.FULL_COLOR_OUTPUT("FALSE")
	) u_oled (
		.rst_i(!resetn || !oled_rst),
		.clk_i(clk),
		.edge_color_i(1'b0),
		.raster_x_i(13'd0),
		.raster_y_i(13'd0),
		.raster_clk_i(clk),
		.raster_d_o(oled_pixel),
		.ss_i(oled_cs),
		.scl_i(spi_scl),
		.mosi_i(spi_mosi),
		.dc_i(oled_dc)
	);

	wire unused = buzzer1 | buzzer2 | (|rgb) | usd_cs | adc_cs | vs_rst |
		vs_xcs | vs_xdcs | uart_tx | nmi_ack | sec_en |
		(|ext_eep_data_o) | (|io_addr) | (|io_out) | io_write |
		io_read | io_sel | io_rst | nmi_rst | twi_scl | twi_sda |
		usbp_io | usbn_io | oled_pixel;
endmodule
