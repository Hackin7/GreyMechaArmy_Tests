module openfpga_arduboy_soc (
	input  wire        clk,
	input  wire        resetn,
	input  wire        emulator_reset,
	input  wire [5:0]  buttons,

	output wire        fb_we,
	output wire [9:0]  fb_addr,
	output wire [7:0]  fb_wdata,

	output wire [13:0] cpu_flash_word_addr,
	input  wire [15:0] cpu_flash_instr,

	output wire        buzzer
);
	wire core_reset = !resetn || emulator_reset;

	wire [5:0] openfpga_buttons_pressed = {
		buttons[5], // B
		buttons[4], // A
		buttons[0], // Up
		buttons[1], // Down
		buttons[2], // Left
		buttons[3]  // Right
	};
	wire [5:0] openfpga_buttons = ~openfpga_buttons_pressed;

	wire [15:0] pgm_addr;
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

	assign cpu_flash_word_addr = pgm_addr[13:0];
	// Arduboy drives a piezo differentially on PC6/PC7. GreyMecha has a
	// single-ended passive buzzer, so emit the differential activity as one
	// square wave. OR would become a constant high for complementary outputs.
	assign buzzer = buzzer1 ^ buzzer2;

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
		.core_rst(core_reset),
		.dev_rst(core_reset),
		.clk(clk),
		.clk48m_i(clk),
		.clk_pll(clk),
		.nmi_sig(1'b0),
		.nmi_ack(nmi_ack),
		.sec_reg_rst(1'b0),
		.sec_en(sec_en),
		.buttons(openfpga_buttons),
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
		.pgm_data(cpu_flash_instr),
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

	arduboy_oled_spi_decoder u_oled_decode (
		.clk(clk),
		.resetn(resetn && oled_rst && !emulator_reset),
		.cs(oled_cs),
		.sclk(spi_scl),
		.mosi(spi_mosi),
		.dc(oled_dc),
		.fb_we(fb_we),
		.fb_addr(fb_addr),
		.fb_wdata(fb_wdata)
	);

	wire unused = (|rgb) | usd_cs | adc_cs | vs_rst | vs_xcs | vs_xdcs |
		uart_tx | nmi_ack | sec_en | (|ext_eep_data_o) | (|io_addr) |
		(|io_out) | io_write | io_read | io_sel | io_rst | nmi_rst |
		twi_scl | twi_sda | usbp_io | usbn_io;
endmodule
