module arduboy_oled_spi_decoder (
	input  wire       clk,
	input  wire       resetn,
	input  wire       cs,
	input  wire       sclk,
	input  wire       mosi,
	input  wire       dc,
	output reg        fb_we,
	output reg [9:0]  fb_addr,
	output reg [7:0]  fb_wdata
);
        localparam [2:0] ARG_NONE  = 3'd0;
        localparam [2:0] ARG_MODE  = 3'd1;
        localparam [2:0] ARG_COL0  = 3'd2;
        localparam [2:0] ARG_COL1  = 3'd3;
        localparam [2:0] ARG_PAGE0 = 3'd4;
        localparam [2:0] ARG_PAGE1 = 3'd5;

	reg sclk_d;
	reg cs_d;
        reg [7:0] shreg;
        reg [2:0] bit_count;
        reg [6:0] col;
        reg [2:0] page;
        reg [6:0] col_start;
        reg [6:0] col_end;
        reg [2:0] page_start;
        reg [2:0] page_end;
        reg [1:0] addr_mode;
        reg [2:0] arg_state;
        reg [1:0] ignore_args;

        wire sclk_rise = !cs && !sclk_d && sclk;
        wire cs_fall = cs_d && !cs;
        wire [7:0] rx_byte = {shreg[6:0], mosi};

        task automatic advance_data_addr;
                begin
                        case (addr_mode)
                                2'd0: begin
                                        if (col == col_end) begin
                                                col <= col_start;
                                                page <= (page == page_end) ? page_start : page + 3'd1;
                                        end else begin
                                                col <= col + 7'd1;
                                        end
                                end
                                2'd1: begin
                                        if (page == page_end) begin
                                                page <= page_start;
                                                col <= (col == col_end) ? col_start : col + 7'd1;
                                        end else begin
                                                page <= page + 3'd1;
                                        end
                                end
                                default: begin
                                        col <= col + 7'd1;
                                end
                        endcase
                end
        endtask

        always @(posedge clk) begin
		sclk_d <= sclk;
		cs_d <= cs;
		fb_we <= 1'b0;

		if (!resetn) begin
			sclk_d <= 1'b0;
			cs_d <= 1'b1;
                        shreg <= 8'h00;
                        bit_count <= 3'd0;
                        col <= 7'd0;
                        page <= 3'd0;
                        col_start <= 7'd0;
                        col_end <= 7'd127;
                        page_start <= 3'd0;
                        page_end <= 3'd7;
                        addr_mode <= 2'd0;
                        arg_state <= ARG_NONE;
                        ignore_args <= 2'd0;
                        fb_addr <= 10'd0;
                        fb_wdata <= 8'h00;
		end else begin
			if (cs_fall)
				bit_count <= 3'd0;

			if (sclk_rise) begin
				shreg <= {shreg[6:0], mosi};
				bit_count <= bit_count + 3'd1;

				if (bit_count == 3'd7) begin
                                        if (dc) begin
                                                fb_we <= 1'b1;
                                                fb_addr <= {page, col};
                                                fb_wdata <= rx_byte;
                                                advance_data_addr();
                                                arg_state <= ARG_NONE;
                                        end else if (ignore_args != 2'd0) begin
                                                ignore_args <= ignore_args - 2'd1;
                                        end else begin
                                                case (arg_state)
                                                        ARG_MODE: begin
                                                                addr_mode <= rx_byte[1:0];
                                                                arg_state <= ARG_NONE;
                                                        end
                                                        ARG_COL0: begin
                                                                col <= rx_byte[6:0];
                                                                col_start <= rx_byte[6:0];
                                                                arg_state <= ARG_COL1;
                                                        end
                                                        ARG_COL1: begin
                                                                col_end <= rx_byte[6:0];
                                                                arg_state <= ARG_NONE;
                                                        end
                                                        ARG_PAGE0: begin
                                                                page <= rx_byte[2:0];
                                                                page_start <= rx_byte[2:0];
                                                                arg_state <= ARG_PAGE1;
                                                        end
                                                        ARG_PAGE1: begin
                                                                page_end <= rx_byte[2:0];
                                                                arg_state <= ARG_NONE;
                                                        end
                                                        default: begin
                                                                case (rx_byte)
                                                                        8'h20: arg_state <= ARG_MODE;
                                                                        8'h21: arg_state <= ARG_COL0;
                                                                        8'h22: arg_state <= ARG_PAGE0;
                                                                        8'h81,
                                                                        8'h8D,
                                                                        8'hA8,
									8'hD3,
									8'hD5,
									8'hD9,
									8'hDA,
									8'hDB: ignore_args <= 2'd1;
                                                                        default: begin
                                                                                arg_state <= ARG_NONE;
                                                                                if (shreg[6:3] == 4'hB)
                                                                                        page <= rx_byte[2:0];
                                                                                else if (shreg[6:3] == 4'h0)
                                                                                        col[3:0] <= rx_byte[3:0];
                                                                                else if (shreg[6:3] == 4'h1)
                                                                                        col[6:4] <= rx_byte[2:0];
                                                                        end
                                                                endcase
                                                        end
						endcase
					end
				end
			end
		end
	end
endmodule
