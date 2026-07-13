module arduboy_host_bridge (
	input  wire        clk,
	input  wire        resetn,
	input  wire [7:0]  rx_byte,
	input  wire        rx_strobe,
	output reg  [7:0]  status,

	output reg         emulator_reset,
	output reg         display_host_mode,

	output reg         fb_we,
	output reg  [9:0]  fb_addr,
	output reg  [7:0]  fb_wdata,

	output reg         flash_we,
	output reg  [14:0] flash_addr,
	output reg  [7:0]  flash_wdata,

	output reg         eeprom_we,
	output reg  [9:0]  eeprom_addr,
	output reg  [7:0]  eeprom_wdata,

	output reg         fx_we,
	output reg  [3:0]  fx_slot,
	output reg  [7:0]  fx_offset,
	output reg  [7:0]  fx_wdata,
	output reg         fx_tag_we,
	output reg  [23:0] fx_tag,

	input  wire        fx_req_pending
);
	localparam [3:0] S_CMD     = 4'd0;
	localparam [3:0] S_ADDR_H  = 4'd1;
	localparam [3:0] S_ADDR_L  = 4'd2;
	localparam [3:0] S_LEN_H   = 4'd3;
	localparam [3:0] S_LEN_L   = 4'd4;
	localparam [3:0] S_DATA    = 4'd5;
	localparam [3:0] S_TAG_S   = 4'd6;
	localparam [3:0] S_TAG_2   = 4'd7;
	localparam [3:0] S_TAG_1   = 4'd8;
	localparam [3:0] S_TAG_0   = 4'd9;

	localparam [7:0] CMD_RESET_ASSERT  = 8'h01;
	localparam [7:0] CMD_RESET_RELEASE = 8'h02;
	localparam [7:0] CMD_DISPLAY_HOST  = 8'h03;
	localparam [7:0] CMD_DISPLAY_SOC   = 8'h04;
	localparam [7:0] CMD_FB_WRITE      = 8'h10;
	localparam [7:0] CMD_FLASH_WRITE   = 8'h20;
	localparam [7:0] CMD_EEPROM_WRITE  = 8'h30;
	localparam [7:0] CMD_FX_WRITE      = 8'h40;
	localparam [7:0] CMD_FX_TAG        = 8'h41;

	reg [3:0] state;
	reg [7:0] command;
	reg [15:0] addr;
	reg [15:0] remaining;

	wire busy = (state != S_CMD);

	always @(posedge clk) begin
		fb_we <= 1'b0;
		flash_we <= 1'b0;
		eeprom_we <= 1'b0;
		fx_we <= 1'b0;
		fx_tag_we <= 1'b0;
		status <= {4'b0000, busy, fx_req_pending, display_host_mode, emulator_reset};

		if (!resetn) begin
			state <= S_CMD;
			command <= 0;
			addr <= 0;
			remaining <= 0;
			emulator_reset <= 1'b1;
			display_host_mode <= 1'b1;
			fb_addr <= 0;
			fb_wdata <= 0;
			flash_addr <= 0;
			flash_wdata <= 0;
			eeprom_addr <= 0;
			eeprom_wdata <= 0;
			fx_slot <= 0;
			fx_offset <= 0;
			fx_wdata <= 0;
			fx_tag <= 0;
		end else if (rx_strobe) begin
			case (state)
				S_CMD: begin
					command <= rx_byte;
					if (rx_byte == CMD_RESET_ASSERT)
						emulator_reset <= 1'b1;
					else if (rx_byte == CMD_RESET_RELEASE)
						emulator_reset <= 1'b0;
					else if (rx_byte == CMD_DISPLAY_HOST)
						display_host_mode <= 1'b1;
					else if (rx_byte == CMD_DISPLAY_SOC)
						display_host_mode <= 1'b0;
					else if (rx_byte == CMD_FB_WRITE || rx_byte == CMD_FLASH_WRITE ||
						rx_byte == CMD_EEPROM_WRITE || rx_byte == CMD_FX_WRITE)
						state <= S_ADDR_H;
					else if (rx_byte == CMD_FX_TAG)
						state <= S_TAG_S;
				end
				S_ADDR_H: begin
					addr[15:8] <= rx_byte;
					state <= S_ADDR_L;
				end
				S_ADDR_L: begin
					addr[7:0] <= rx_byte;
					state <= S_LEN_H;
				end
				S_LEN_H: begin
					remaining[15:8] <= rx_byte;
					state <= S_LEN_L;
				end
				S_LEN_L: begin
					remaining[7:0] <= rx_byte;
					state <= (rx_byte == 8'h00 && remaining[15:8] == 8'h00) ? S_CMD : S_DATA;
				end
				S_DATA: begin
					if (command == CMD_FB_WRITE) begin
						fb_addr <= addr[9:0];
						fb_wdata <= rx_byte;
						fb_we <= 1'b1;
					end else if (command == CMD_FLASH_WRITE) begin
						flash_addr <= addr[14:0];
						flash_wdata <= rx_byte;
						flash_we <= 1'b1;
					end else if (command == CMD_EEPROM_WRITE) begin
						eeprom_addr <= addr[9:0];
						eeprom_wdata <= rx_byte;
						eeprom_we <= 1'b1;
					end else if (command == CMD_FX_WRITE) begin
						fx_slot <= addr[11:8];
						fx_offset <= addr[7:0];
						fx_wdata <= rx_byte;
						fx_we <= 1'b1;
					end

					addr <= addr + 1'b1;
					if (remaining == 16'd1) begin
						remaining <= 0;
						state <= S_CMD;
					end else begin
						remaining <= remaining - 1'b1;
					end
				end
				S_TAG_S: begin
					fx_slot <= rx_byte[3:0];
					state <= S_TAG_2;
				end
				S_TAG_2: begin
					fx_tag[23:16] <= rx_byte;
					state <= S_TAG_1;
				end
				S_TAG_1: begin
					fx_tag[15:8] <= rx_byte;
					state <= S_TAG_0;
				end
				S_TAG_0: begin
					fx_tag[7:0] <= rx_byte;
					fx_tag_we <= 1'b1;
					state <= S_CMD;
				end
				default: state <= S_CMD;
			endcase
		end
	end
endmodule
