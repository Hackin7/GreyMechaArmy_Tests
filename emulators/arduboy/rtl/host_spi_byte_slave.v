module host_spi_byte_slave (
	input  wire       clk,
	input  wire       resetn,
	input  wire       sck,
	input  wire       mosi,
	input  wire       cs_n,
	input  wire [7:0] tx_byte,
	output reg        miso,
	output reg  [7:0] rx_byte,
	output reg        rx_strobe,
	output wire       selected
);
	reg [2:0] sck_sync;
	reg [2:0] cs_sync;
	reg [1:0] mosi_sync;
	reg [2:0] bit_count;
	reg [7:0] rx_shift;
	reg [7:0] tx_shift;

	wire sck_rise = (sck_sync[2:1] == 2'b01);
	wire sck_fall = (sck_sync[2:1] == 2'b10);
	wire cs_fall  = (cs_sync[2:1] == 2'b10);
	wire cs_active = ~cs_sync[2];

	assign selected = cs_active;

	always @(posedge clk) begin
		sck_sync <= {sck_sync[1:0], sck};
		cs_sync <= {cs_sync[1:0], cs_n};
		mosi_sync <= {mosi_sync[0], mosi};
		rx_strobe <= 1'b0;

		if (!resetn) begin
			bit_count <= 0;
			rx_shift <= 0;
			tx_shift <= 0;
			rx_byte <= 0;
			miso <= 1'b0;
		end else if (!cs_active) begin
			bit_count <= 0;
			tx_shift <= tx_byte;
			miso <= tx_byte[7];
		end else begin
			if (cs_fall) begin
				bit_count <= 0;
				tx_shift <= tx_byte;
				miso <= tx_byte[7];
			end

			if (sck_rise) begin
				rx_shift <= {rx_shift[6:0], mosi_sync[1]};
				if (bit_count == 3'd7) begin
					rx_byte <= {rx_shift[6:0], mosi_sync[1]};
					rx_strobe <= 1'b1;
					bit_count <= 0;
				end else begin
					bit_count <= bit_count + 1'b1;
				end
			end

			if (sck_fall) begin
				tx_shift <= {tx_shift[6:0], 1'b0};
				miso <= tx_shift[6];
			end

			if (rx_strobe) begin
				tx_shift <= tx_byte;
				miso <= tx_byte[7];
			end
		end
	end
endmodule
