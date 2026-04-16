// Pure-Verilog GC9A01: btn[0]=image (stonks.mem), btn[1]=R, btn[2]=G, btn[3]=B, btn[4]=pink (priority hi index).
// D12=grey, C12=async reset (active low); onboard btn[0..4] unchanged.
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
	inout  wire [4:0] s
);
	/* OSCG DIV=6 ~50 MHz (vs DIV=5 ~62 MHz) — meets nextpnr timing with init-ROM FSM. */
	localparam integer CLK_HZ = 50000000;

	/* stonks.mem: 96×64 RGB565; panel is 240×240. Nearest-neighbor stretch to fill (no letterboxing). */
	localparam integer OLED_W = 240;
	localparam integer OLED_H = 240;
	localparam integer IMG_W  = 96;
	localparam integer IMG_H  = 64;

	/* Linear OLED index (0..57599) -> image RAM index (0..IMG_W*IMG_H-1).
	 * Stretch 96x64 -> 240x240: ix=(col*96)/240=(col*2)/5, iy=(row*64)/240=(row*4)/15.
	 * row/col from pix; col = pix - row*240 avoids mod-240. */
	function automatic [12:0] image_idx_from_oled_pix(input [15:0] pix);
		reg [15:0] row;
		reg [15:0] col;
		reg [9:0]  c2; /* col*2, max 478 */
		reg [10:0] r4; /* row*4, max 956 */
		reg [6:0]  ix;
		reg [5:0]  iy;
		begin
			row = pix / OLED_W;
			col = pix - row * 16'd240;
			c2  = col << 1;
			ix  = c2 / 5;
			r4  = row << 2;
			iy  = r4 / 15;
			image_idx_from_oled_pix = iy * IMG_W + ix;
		end
	endfunction

	wire clk_int;
	defparam OSCI1.DIV = "6";
	OSCG OSCI1 (.OSC(clk_int));

	wire clk = clk_int;
	wire unused_clk_ext = clk_ext;

	/* Dedicated reset button (C12): active low, same polarity as onboard buttons. */
	wire reset_button = ~btn_rst_n;
	reg  [1:0] reset_sync = 2'b11;
	reg  [7:0] reset_counter = 0;
	wire reset_request = reset_sync[1];
	wire resetn = &reset_counter;

	always @(posedge clk) begin
		reset_sync <= {reset_sync[0], reset_button};
		if (reset_request)
			reset_counter <= 0;
		else if (!resetn)
			reset_counter <= reset_counter + 1;
	end

	

	wire [4:0] btn_press;
	wire       grey_press;
	btn_debounce #(
		.WIDTH         (5),
		.STABLE_CYCLES (4096)
	) u_deb (
		.clk      (clk),
		.resetn   (resetn),
		.btn_n    (btn),
		.btn_press(btn_press)
	);
	btn_debounce #(
		.WIDTH         (1),
		.STABLE_CYCLES (4096)
	) u_grey (
		.clk      (clk),
		.resetn   (resetn),
		.btn_n    (btn_grey_n),
		.btn_press(grey_press)
	);

	reg [15:0] pixel_rgb;
	wire frame_begin;
	wire sending_pixels;
	wire sample_pixel;
	wire [15:0] pixel_index;

	/* SPI: see gc9a01_display SPI_CLK_DIV comment (raise toward 6–8 if unstable). */
	gc9a01_display #(
		.CLK_HZ      (CLK_HZ),
		.SPI_CLK_DIV (8'd4)
	) u_oled (
		.clk            (clk),
		.resetn         (resetn),
		.frame_begin    (frame_begin),
		.sending_pixels (sending_pixels),
		.sample_pixel   (sample_pixel),
		.pixel_index    (pixel_index),
		.pixel_data     (pixel_rgb),
		.cs             (oled_cs),
		.sdin           (oled_sda),
		.sclk           (oled_scl),
		.d_cn           (oled_dc),
		.resn           (oled_rst)
	);

	reg [15:0] image_memory [0:IMG_W * IMG_H - 1];
	initial begin
		$readmemh("stonks.mem", image_memory);
	end

	wire [12:0] image_ram_idx = image_idx_from_oled_pix(pixel_index);
	wire [15:0] image_pixel_data = image_memory[pixel_index]; //image_ram_idx];

	always @(*) begin
		if (grey_press)
			pixel_rgb = 16'hFFE0; /* RGB565 mid grey */
		else if (btn_press[4])
			pixel_rgb = 16'hFE19;
		else if (btn_press[3])
			pixel_rgb = 16'h001F;
		else if (btn_press[2])
			pixel_rgb = 16'h07E0;
		else if (btn_press[1])
			pixel_rgb = 16'hF800;
		else if (btn_press[0])
			pixel_rgb = image_pixel_data;
		else
			pixel_rgb = 16'hFFFF;
	end

	

	wire unused_fb = frame_begin;
	wire unused_sp = sending_pixels;
	wire unused_sa = sample_pixel;

	assign led = {2'b0, grey_press, btn_press};

	assign interconnect = 8'bz;
	assign pmod_j1 = 8'bz;
	assign pmod_j2 = 8'bz;
	assign s = 5'bz;
endmodule
