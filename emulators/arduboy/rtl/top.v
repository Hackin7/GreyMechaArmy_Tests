module top (
	input  wire       clk_ext,
	input  wire [4:0] btn,
	input  wire       btn_grey_n,
	input  wire       btn_rst_n,
	output wire [7:0] led,
	inout  wire [7:0] interconnect,
	inout  wire [7:0] pmod_j1,
	inout  wire [7:0] pmod_j2,
	output wire       oled_scl,
	output wire       oled_sda,
	output wire       oled_dc,
	output wire       oled_cs,
	output wire       oled_rst,
	inout  wire [4:0] s,
	output wire       buzzer
);
	localparam integer OLED_CLK_HZ = 75000000;
	// The 310 MHz internal oscillator divided by six and the PLL's /40 output
	// produce the CPU clock used by nextpnr's derived timing constraint.
	localparam integer CPU_CLK_HZ = 15500000;

	wire osc_clk;
	defparam OSCI1.DIV = "6";
	OSCG OSCI1 (.OSC(osc_clk));

	wire clk_oled;
	wire clk_cpu;
	wire pll_locked;
	ecp5_arduboy_pll u_pll (
		.clki(osc_clk),
		.clk_oled(clk_oled),
		.clk_cpu(clk_cpu),
		.locked(pll_locked)
	);

	wire clk = clk_cpu;
	wire unused_clk_ext = clk_ext;

	wire board_reset;
	wire display_mode_toggle;
	display_mode_reset_button #(
		.HOLD_CYCLES(2 * CPU_CLK_HZ),
		.DEBOUNCE_CYCLES(4096)
	) u_display_mode_button (
		.clk(clk),
		.resetn(pll_locked),
		.btn_n(btn[2]),
		.mode_cycle_toggle(display_mode_toggle),
		.board_reset(board_reset)
	);

	reg [7:0] reset_counter = 0;
	reg [7:0] loader_reset_counter = 0;
	wire resetn = (&reset_counter) & pll_locked;
	wire loader_resetn = (&loader_reset_counter) & pll_locked;
	reg [1:0] oled_reset_sync = 2'b00;
	wire resetn_oled = &oled_reset_sync;

	always @(posedge clk) begin
		if (board_reset || !pll_locked)
			reset_counter <= 0;
		else if (!resetn)
			reset_counter <= reset_counter + 1'b1;

		// The SPI loader and its control state are outside the emulated board.
		// Keep them alive across a button reset so retained flash can restart.
		if (!pll_locked)
			loader_reset_counter <= 0;
		else if (!loader_resetn)
			loader_reset_counter <= loader_reset_counter + 1'b1;
	end

	always @(posedge clk_oled) begin
		oled_reset_sync <= {oled_reset_sync[0], resetn};
	end

	reg [1:0] display_mode_toggle_sync = 2'b00;
	reg display_mode_toggle_seen = 1'b0;
	reg [1:0] display_scale_mode = 2'd0;
	always @(posedge clk_oled) begin
		if (!resetn_oled) begin
			display_mode_toggle_sync <= 2'b00;
			display_mode_toggle_seen <= 1'b0;
			display_scale_mode <= 2'd0;
		end else begin
			display_mode_toggle_sync <= {
				display_mode_toggle_sync[0], display_mode_toggle
			};
			if (display_mode_toggle_sync[1] != display_mode_toggle_seen) begin
				display_mode_toggle_seen <= display_mode_toggle_sync[1];
				if (display_scale_mode == 2'd2)
					display_scale_mode <= 2'd0;
				else
					display_scale_mode <= display_scale_mode + 1'b1;
			end
		end
	end

        wire [4:0] btn_press;
        wire grey_press;
        wire rst_press;
        btn_debounce #(.WIDTH(5), .STABLE_CYCLES(4096)) u_btn_deb (
                .clk(clk),
                .resetn(resetn),
                .btn_n(btn),
                .btn_press(btn_press)
	);
	btn_debounce #(.WIDTH(1), .STABLE_CYCLES(4096)) u_grey_deb (
		.clk(clk),
		.resetn(resetn),
                .btn_n(btn_grey_n),
                .btn_press(grey_press)
        );
        btn_debounce #(.WIDTH(1), .STABLE_CYCLES(4096)) u_rst_deb (
                .clk(clk),
                .resetn(resetn),
                .btn_n(btn_rst_n),
                .btn_press(rst_press)
        );

        wire [5:0] ard_buttons;
        assign ard_buttons[0] = btn_press[1];  // Up: btn[1]
        assign ard_buttons[1] = btn_press[3];  // Down: btn[3]
        assign ard_buttons[2] = btn_press[0];  // Left: btn[0]
        assign ard_buttons[3] = btn_press[4];  // Right: btn[4]
        assign ard_buttons[4] = grey_press;    // A: btn[5]
        assign ard_buttons[5] = rst_press;     // B: btn[6]

	wire host_sck = interconnect[0];
	wire host_mosi = interconnect[1];
	wire host_cs_n = interconnect[3];
	wire host_miso;
	wire [7:0] host_rx_byte;
	wire host_rx_strobe;
	wire [7:0] host_status;
	wire host_selected;

	assign interconnect[2] = host_selected ? host_miso : 1'bz;

	wire emulator_reset;
	wire display_host_mode;
	wire host_fb_we;
	wire [9:0] host_fb_addr;
	wire [7:0] host_fb_wdata;
	wire soc_fb_we;
	wire [9:0] soc_fb_addr;
	wire [7:0] soc_fb_wdata;
	wire fb_we = host_fb_we | soc_fb_we;
	wire [9:0] fb_addr = host_fb_we ? host_fb_addr : soc_fb_addr;
	wire [7:0] fb_wdata = host_fb_we ? host_fb_wdata : soc_fb_wdata;
	wire flash_we;
	wire [14:0] flash_addr;
	wire [7:0] flash_wdata;
	wire eeprom_host_we;
	wire [9:0] eeprom_host_addr;
	wire [7:0] eeprom_host_wdata;
	wire fx_we;
	wire [3:0] fx_slot;
	wire [7:0] fx_offset;
	wire [7:0] fx_wdata;
	wire fx_tag_we;
	wire [23:0] fx_tag;
	wire fx_req_pending = 1'b0;

	host_spi_byte_slave u_host_spi (
		.clk(clk),
		.resetn(loader_resetn),
		.sck(host_sck),
		.mosi(host_mosi),
		.cs_n(host_cs_n),
		.tx_byte(host_status),
		.miso(host_miso),
		.rx_byte(host_rx_byte),
		.rx_strobe(host_rx_strobe),
		.selected(host_selected)
	);

	arduboy_host_bridge u_host_bridge (
		.clk(clk),
		.resetn(loader_resetn),
		.rx_byte(host_rx_byte),
		.rx_strobe(host_rx_strobe),
		.status(host_status),
		.emulator_reset(emulator_reset),
		.display_host_mode(display_host_mode),
		.fb_we(host_fb_we),
		.fb_addr(host_fb_addr),
		.fb_wdata(host_fb_wdata),
		.flash_we(flash_we),
		.flash_addr(flash_addr),
		.flash_wdata(flash_wdata),
		.eeprom_we(eeprom_host_we),
		.eeprom_addr(eeprom_host_addr),
		.eeprom_wdata(eeprom_host_wdata),
		.fx_we(fx_we),
		.fx_slot(fx_slot),
		.fx_offset(fx_offset),
		.fx_wdata(fx_wdata),
		.fx_tag_we(fx_tag_we),
		.fx_tag(fx_tag),
		.fx_req_pending(fx_req_pending)
	);

	wire [15:0] pixel_index;
        wire [15:0] pixel_rgb;
        wire [15:0] oled_pixel_rgb;
        wire init_done;
        wire streaming;

        localparam OLED_CHECKERBOARD_TEST = 1'b0;
        reg [15:0] checker_last_pixel = 16'd0;
        reg [7:0] checker_x = 8'd0;
        reg [7:0] checker_y = 8'd0;
        reg [15:0] checker_rgb = 16'h0000;

        always @(posedge clk_oled) begin
                if (!resetn_oled) begin
                        checker_last_pixel <= 16'd0;
                        checker_x <= 8'd0;
                        checker_y <= 8'd0;
                        checker_rgb <= 16'h0000;
                end else if (pixel_index != checker_last_pixel) begin
                        checker_last_pixel <= pixel_index;
                        if (pixel_index == 16'd0 || pixel_index < checker_last_pixel) begin
                                checker_x <= 8'd0;
                                checker_y <= 8'd0;
                        end else if (checker_x == 8'd239) begin
                                checker_x <= 8'd0;
                                checker_y <= checker_y + 1'b1;
                        end else begin
                                checker_x <= checker_x + 1'b1;
                        end

                        checker_rgb <= checker_x[4] ^ checker_y[4] ? 16'hFFFF : 16'h0000;
                end
        end

        assign oled_pixel_rgb = OLED_CHECKERBOARD_TEST ? checker_rgb : pixel_rgb;

	oled_gc9a01 #(
		.CLK_HZ(OLED_CLK_HZ),
		.INIT_SPI_CLK_DIV(8'd4)
	) u_oled (
                .clk(clk_oled),
                .resetn(resetn_oled),
                .pixel_index(pixel_index),
                .pixel_data(oled_pixel_rgb),
		.oled_scl(oled_scl),
		.oled_sda(oled_sda),
		.oled_dc(oled_dc),
		.oled_cs(oled_cs),
		.oled_rst(oled_rst),
		.init_done(init_done),
		.streaming(streaming)
	);

	arduboy_framebuffer u_fb (
		.wr_clk(clk),
		.rd_clk(clk_oled),
		.rd_resetn(resetn_oled),
		.host_we(fb_we),
		.host_addr(fb_addr),
		.host_wdata(fb_wdata),
		.scale_mode(display_scale_mode),
		.panel_pixel_index(pixel_index),
		.panel_rgb(pixel_rgb)
	);

	wire [13:0] cpu_flash_word_addr;
	wire [15:0] cpu_flash_instr;
	arduboy_program_flash u_flash (
		.clk(clk),
		.host_we(flash_we),
		.host_addr(flash_addr),
		.host_wdata(flash_wdata),
		.cpu_word_addr(cpu_flash_word_addr),
		.cpu_instr(cpu_flash_instr)
	);

	wire unused_eeprom_loader = eeprom_host_we | |eeprom_host_addr | |eeprom_host_wdata;
	wire unused_fx_loader = fx_we | fx_tag_we | |fx_slot | |fx_offset | |fx_wdata | |fx_tag;

	openfpga_arduboy_soc u_soc (
		.clk(clk),
		.resetn(resetn),
		.emulator_reset(emulator_reset),
		.buttons(ard_buttons),
		.fb_we(soc_fb_we),
		.fb_addr(soc_fb_addr),
		.fb_wdata(soc_fb_wdata),
		.cpu_flash_word_addr(cpu_flash_word_addr),
		.cpu_flash_instr(cpu_flash_instr),
		.buzzer(buzzer)
	);

	assign interconnect[4] = emulator_reset;
	assign interconnect[5] = fx_req_pending;
	assign interconnect[6] = 1'bz;
	assign interconnect[7] = 1'bz;

        assign led = {init_done, pll_locked, ard_buttons};

	assign pmod_j1 = 8'bz;
	assign pmod_j2 = 8'bz;
	assign s = 5'bz;

	wire unused_display = display_host_mode | unused_clk_ext | unused_fx_loader |
		unused_eeprom_loader | host_selected | fx_req_pending;
endmodule
