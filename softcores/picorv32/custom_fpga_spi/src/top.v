module top(
	input clk_ext,
	input [4:0] btn,
	output [7:0] led,
	inout [7:0] interconnect,
	inout [7:0] pmod_j1,
	inout [7:0] pmod_j2,
	output oled_scl,
	output oled_sda,
	output oled_dc,
	output oled_cs,
	output oled_rst,
	inout [4:0] s
);
	/*
	 * System clock f_sys (OSCG): Lattice TN-02200 + DS give oscillator + DIV;
	 * exact MHz is PVT-dependent. Practical ways to get a number:
	 * - Run nextpnr: it reports "Max frequency" / slack for the global clock net.
	 * - Scope SPI SCLK during a transfer: f_SCLK = f_sys / (2 * (clk_div + 1))
	 *   with clk_div from firmware spi_init() (see simple_spi_master.v).
	 * Rough same-board estimate: OSCG DIV="3" achieved ~103 MHz in another
	 * build; with DIV="5" here, scale ~103 * 3/5 ~ 62 MHz if comparable.
	 */
	wire clk_int;
	defparam OSCI1.DIV = "5";
	OSCG OSCI1 (.OSC(clk_int));

`ifdef USE_SYS_PLL
	wire clk_pll;
	wire pll_locked;
	ecp5_sys_pll pll_sys (
		.clki   (clk_int),
		.clko   (clk_pll),
		.locked (pll_locked)
	);
	wire clk = clk_pll;
	wire unused_pll_locked = pll_locked;
`else
	wire clk = clk_int;
`endif
	wire unused_clk_ext = clk_ext;
	wire reset_button = ~btn[0];

	reg [1:0] reset_sync = 2'b11;
	reg [7:0] reset_counter = 0;
	wire reset_request = reset_sync[1];
	wire resetn = &reset_counter;

	wire trap;
	wire passed;
	wire [7:0] led_value;
	wire out_strobe;
	wire [7:0] out_byte;
	wire trace_valid;
	wire [35:0] trace_data;
	wire unused_trap = trap;
	wire unused_passed = passed;
	wire unused_out_strobe = out_strobe;
	wire [7:0] unused_out_byte = out_byte;
	wire unused_trace_valid = trace_valid;
	wire [35:0] unused_trace_data = trace_data;

	wire spi_sclk;
	wire spi_mosi;
	wire spi_cs_n;
	wire spi_dc;
	wire spi_rst_n;

	always @(posedge clk) begin
		reset_sync <= {reset_sync[0], reset_button};
		if (reset_request)
			reset_counter <= 0;
		else if (!resetn)
			reset_counter <= reset_counter + 1;
	end

	picorv32_custom_soc soc (
		.clk         (clk         ),
		.resetn      (resetn      ),
		.trap        (trap        ),
		.leds        (led_value   ),
		.out_strobe  (out_strobe  ),
		.out_byte    (out_byte    ),
		.passed      (passed      ),
		.trace_valid (trace_valid ),
		.trace_data  (trace_data  ),
		.spi_sclk    (spi_sclk    ),
		.spi_mosi    (spi_mosi    ),
		.spi_cs_n    (spi_cs_n    ),
		.spi_dc      (spi_dc      ),
		.spi_rst_n   (spi_rst_n   )
	);

	assign led = led_value;

	assign interconnect = 8'bz;
	assign pmod_j1 = 8'bz;
	assign pmod_j2 = 8'bz;
	assign s = 5'bz;

	assign oled_scl = spi_sclk;
	assign oled_sda = spi_mosi;
	assign oled_dc  = spi_dc;
	assign oled_cs  = spi_cs_n;
	assign oled_rst = spi_rst_n;
endmodule
