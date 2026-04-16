// GC9A01 240x240 — reference-style pixel handshake + SPI (see references/oled_verilog_module_reference)
//
// SPI_CLK_DIV: lower => higher SCLK (f_SCLK ~= f_sys / (2*(clk_div+1))). GC9A01 typically
// supports tens of MHz SCLK; raise clk_div if the panel or wiring shows noise/glitches.
module gc9a01_display #(
	parameter integer CLK_HZ = 50000000,
	parameter [7:0] SPI_CLK_DIV = 8'd0
) (
	input  wire        clk,
	input  wire        resetn,
	output reg         frame_begin,
	output reg         sample_pixel,
	output reg  [15:0] pixel_index,
	input  wire [15:0] pixel_data,
	output reg         sending_pixels,
	output wire        cs,
	output wire        sdin,
	output wire        sclk,
	output wire        d_cn,
	output wire        resn
);
`include "gc9a01_init_rom.vh"

	localparam integer PIX_TOTAL = 240 * 240;
	localparam integer LAST_PIX  = PIX_TOTAL - 1;

	localparam integer RST_LO_CYCLES = CLK_HZ / 500; /* ~2 ms panel reset low */
	localparam integer WAIT10_CYCLES = (CLK_HZ / 1000) * 10;

	localparam [4:0] S_RST_LO       = 5'd0;
	localparam [4:0] S_RST_HI       = 5'd1;
	localparam [4:0] S_WAIT10       = 5'd2;
	localparam [4:0] S_INIT_ISSUE   = 5'd3;
	localparam [4:0] S_INIT_WAIT    = 5'd4;
	localparam [4:0] S_INIT_PAUSE   = 5'd5;
	localparam [4:0] S_WIN_ISSUE    = 5'd6;
	localparam [4:0] S_WIN_WAIT     = 5'd7;
	/* Merged S_FSTART + S_PSAMPLE: frame_begin + sample in one state */
	localparam [4:0] S_FRAME_HEAD   = 5'd8;
	localparam [4:0] S_PHI_ISS      = 5'd9;
	localparam [4:0] S_PHI_WAIT     = 5'd10;
	localparam [4:0] S_PLO_WAIT     = 5'd11;
	/* After each frame: only RAMWR cmd 0x2C (skip CASET/RASET repeat) */
	localparam [4:0] S_RAMWR_ISSUE  = 5'd12;
	localparam [4:0] S_RAMWR_WAIT   = 5'd13;

	reg  [ 4:0] st;
	reg  [31:0] timer;
	reg  [15:0] init_idx;
	reg  [23:0] pause_cnt;
	reg  [ 4:0] win_idx;
	reg  [15:0] pix;
	reg  [15:0] latched_rgb;

	reg  [ 7:0] spi_tx_data;
	reg         spi_dc_in;
	reg         spi_keep_cs;
	reg         spi_start;
	reg         spi_release_cs;
	reg         panel_rst_n;
	wire        spi_busy;
	wire        spi_done;
	wire        spi_rst_o;

	assign cs   = spi_cs_n;
	assign sdin = spi_mosi;
	assign sclk = spi_sclk;
	assign d_cn = spi_dc;
	assign resn = spi_rst_o;

	simple_spi_master spi0 (
		.clk        (clk),
		.resetn     (resetn),
		.clk_div    (SPI_CLK_DIV),
		.tx_data    (spi_tx_data),
		.start      (spi_start),
		.release_cs (spi_release_cs),
		.keep_cs    (spi_keep_cs),
		.idle_cs_n  (1'b1),
		.dc_in      (spi_dc_in),
		.rst_n_in   (panel_rst_n),
		.busy       (spi_busy),
		.done       (spi_done),
		.sclk       (spi_sclk),
		.mosi       (spi_mosi),
		.cs_n       (spi_cs_n),
		.dc         (spi_dc),
		.rst_n      (spi_rst_o)
	);

	function automatic [7:0] win_byte(input integer k);
		case (k)
			0:  win_byte = 8'h2A;
			1:  win_byte = 8'h00;
			2:  win_byte = 8'h00;
			3:  win_byte = 8'h00;
			4:  win_byte = 8'hEF;
			5:  win_byte = 8'h2B;
			6:  win_byte = 8'h00;
			7:  win_byte = 8'h00;
			8:  win_byte = 8'h00;
			9:  win_byte = 8'hEF;
			10: win_byte = 8'h2C;
			default: win_byte = 8'h00;
		endcase
	endfunction

	function automatic win_is_data(input integer k);
		case (k)
			0, 5, 10: win_is_data = 1'b0;
			default: win_is_data = 1'b1;
		endcase
	endfunction

	always @(posedge clk) begin
		frame_begin     <= 1'b0;
		sample_pixel    <= 1'b0;
		spi_start       <= 1'b0;
		spi_release_cs  <= 1'b0;

		if (!resetn) begin
			st             <= S_RST_LO;
			timer          <= 0;
			init_idx       <= 0;
			pause_cnt      <= 0;
			win_idx        <= 0;
			pix            <= 0;
			pixel_index    <= 0;
			panel_rst_n    <= 1'b0;
			sending_pixels <= 1'b0;
			spi_tx_data    <= 8'h00;
			spi_dc_in      <= 1'b0;
			spi_keep_cs    <= 1'b0;
		end else begin
			case (st)
				S_RST_LO: begin
					panel_rst_n <= 1'b0;
					sending_pixels <= 1'b0;
					if (timer < RST_LO_CYCLES)
						timer <= timer + 1;
					else begin
						timer <= 0;
						st    <= S_RST_HI;
					end
				end
				S_RST_HI: begin
					panel_rst_n <= 1'b1;
					st <= S_WAIT10;
				end
				S_WAIT10: begin
					if (timer < WAIT10_CYCLES)
						timer <= timer + 1;
					else begin
						timer    <= 0;
						init_idx <= 0;
						st       <= S_INIT_ISSUE;
					end
				end
				S_INIT_ISSUE: begin
					if (!spi_busy) begin
						spi_tx_data <= gc9a01_init_byte(init_idx);
						spi_dc_in   <= gc9a01_init_is_data(init_idx);
						spi_keep_cs <= 1'b0;
						spi_start   <= 1'b1;
						st          <= S_INIT_WAIT;
					end
				end
				S_INIT_WAIT: begin
					if (spi_done) begin
						if (gc9a01_init_pause(init_idx) != 0) begin
							pause_cnt <= gc9a01_init_pause(init_idx);
							st        <= S_INIT_PAUSE;
						end else begin
							if (init_idx + 1 == GC9A01_INIT_LEN) begin
								win_idx <= 0;
								st      <= S_WIN_ISSUE;
							end else begin
								init_idx <= init_idx + 1;
								st       <= S_INIT_ISSUE;
							end
						end
					end
				end
				S_INIT_PAUSE: begin
					if (pause_cnt != 0)
						pause_cnt <= pause_cnt - 1;
					else begin
						if (init_idx + 1 == GC9A01_INIT_LEN) begin
							win_idx <= 0;
							st      <= S_WIN_ISSUE;
						end else begin
							init_idx <= init_idx + 1;
							st       <= S_INIT_ISSUE;
						end
					end
				end
				S_WIN_ISSUE: begin
					if (!spi_busy) begin
						spi_tx_data <= win_byte(win_idx);
						spi_dc_in   <= win_is_data(win_idx);
						spi_keep_cs <= 1'b0;
						spi_start   <= 1'b1;
						st          <= S_WIN_WAIT;
					end
				end
				S_WIN_WAIT: begin
					if (spi_done) begin
						if (win_idx == 5'd10) begin
							pix <= 0;
							st  <= S_FRAME_HEAD;
						end else begin
							win_idx <= win_idx + 1;
							st      <= S_WIN_ISSUE;
						end
					end
				end
				/* Option 4: frame_begin + sample_pixel + latch in one state */
				S_FRAME_HEAD: begin
					frame_begin     <= 1'b1;
					sample_pixel    <= 1'b1;
					latched_rgb     <= pixel_data;
					pixel_index     <= pix;
					sending_pixels  <= 1'b1;
					st              <= S_PHI_ISS;
				end
				S_PHI_ISS: begin
					if (!spi_busy) begin
						spi_tx_data <= latched_rgb[15:8];
						spi_dc_in   <= 1'b1;
						spi_keep_cs <= 1'b1;
						spi_start   <= 1'b1;
						st          <= S_PHI_WAIT;
					end
				end
				/* Option 4: on HI done, issue LO immediately (drop separate PLO_ISS state) */
				S_PHI_WAIT: begin
					if (spi_done) begin
						spi_tx_data <= latched_rgb[7:0];
						spi_dc_in   <= 1'b1;
						spi_keep_cs <= (pix != LAST_PIX) ? 1'b1 : 1'b0;
						spi_start   <= 1'b1;
						st          <= S_PLO_WAIT;
					end
				end
				S_PLO_WAIT: begin
					if (spi_done) begin
						if (pix == LAST_PIX) begin
							sending_pixels <= 1'b0;
							st             <= S_RAMWR_ISSUE;
						end else begin
							pix <= pix + 1;
							st  <= S_FRAME_HEAD;
						end
					end
				end
				/* Option 3: only 0x2C before each subsequent frame (not full CASET/RASET) */
				S_RAMWR_ISSUE: begin
					if (!spi_busy) begin
						spi_tx_data <= 8'h2C;
						spi_dc_in   <= 1'b0;
						spi_keep_cs <= 1'b0;
						spi_start   <= 1'b1;
						st          <= S_RAMWR_WAIT;
					end
				end
				S_RAMWR_WAIT: begin
					if (spi_done) begin
						pix <= 0;
						st  <= S_FRAME_HEAD;
					end
				end
				default: st <= S_RST_LO;
			endcase
		end
	end
endmodule
