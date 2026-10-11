// Read one 256-byte cartridge cache line from the ECP5 configuration flash.
//
// The physical W25Q128 address is ROM_BASE + cartridge_address.  USRMCLK is
// instantiated by top.v. flash_clk is explicitly phased from clk so MOSI is
// stable before every rising SPI edge and MISO is sampled while SCK is high.
module ecp5_flash_reader #(
    parameter [23:0] ROM_BASE = 24'h100000,
    parameter SPI_CYCLES = 3 // 3 at 16 MHz (fallback), 4 at 64 MHz (fast)
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [22:0] line_address,
    input  wire        fill_ready,
    output reg         busy,

    output reg         fill_begin,
    output reg  [22:0] fill_address,
    output reg         fill_we,
    output reg  [7:0]  fill_offset,
    output reg  [7:0]  fill_data,
    output reg         fill_commit,

    output reg         flash_clk,
    output reg         flash_cs_n,
    output reg         flash_mosi,
    input  wire        flash_miso
);
    localparam IDLE = 2'd0;
    localparam SEND = 2'd1;
    localparam READ = 2'd2;
    localparam DONE = 2'd3;

    reg [1:0] state;
    reg [1:0] phase;
    reg [39:0] tx_shift;
    reg [5:0] tx_bits_left;
    reg [2:0] rx_bit;
    reg [7:0] rx_shift;
    reg [7:0] read_offset;
    reg wait_release;

    wire [23:0] physical_address =
        ROM_BASE + {1'b0, line_address[22:8], 8'h00};
    wire [39:0] transaction = {8'h0b, physical_address, 8'h00};

    always @(posedge clk) begin
        fill_begin <= 1'b0;
        fill_we <= 1'b0;
        fill_commit <= 1'b0;

        if (reset) begin
            state <= IDLE;
            phase <= 2'd0;
            busy <= 1'b0;
            flash_clk <= 1'b0;
            flash_cs_n <= 1'b1;
            flash_mosi <= 1'b0;
            fill_address <= 23'd0;
            fill_offset <= 8'd0;
            fill_data <= 8'hff;
            fill_we <= 1'b0;
            tx_shift <= 40'd0;
            tx_bits_left <= 6'd0;
            rx_bit <= 3'd0;
            rx_shift <= 8'd0;
            read_offset <= 8'd0;
            wait_release <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    flash_clk <= 1'b0;
                    flash_cs_n <= 1'b1;
                    busy <= 1'b0;
                    if (!start)
                        wait_release <= 1'b0;
                    if (start && !wait_release) begin
                        wait_release <= 1'b1;
                        busy <= 1'b1;
                        fill_address <= {line_address[22:8], 8'h00};
                        fill_offset <= 8'd0;
                        read_offset <= 8'd0;
                        fill_begin <= 1'b1;
                        flash_cs_n <= 1'b0;
                        flash_mosi <= transaction[39];
                        tx_shift <= transaction;
                        tx_bits_left <= 6'd40;
                        phase <= 2'd0;
                        state <= SEND;
                    end
                end

                SEND: begin
                    case (phase)
                        2'd0: begin
                            flash_clk <= 1'b1;
                            phase <= 2'd1;
                        end
                        2'd1: phase <= 2'd2;
                        2'd2: begin
                            flash_clk <= 1'b0;
                            phase <= (SPI_CYCLES == 4) ? 2'd3 : 2'd0;
                            if (tx_bits_left == 6'd1) begin
                                flash_mosi <= 1'b0;
                                rx_bit <= 3'd0;
                                rx_shift <= 8'd0;
                                state <= READ;
                            end else begin
                                tx_shift <= {tx_shift[38:0], 1'b0};
                                flash_mosi <= tx_shift[38];
                                tx_bits_left <= tx_bits_left - 1'b1;
                            end
                        end
                        2'd3: phase <= 2'd0;
                    endcase
                end

                READ: begin
                    case (phase)
                        2'd0: begin
                            // Backpressure is allowed only between bytes,
                            // with SCK low; never truncate a high pulse.
                            if (rx_bit != 0 || fill_ready) begin
                                flash_clk <= 1'b1;
                                phase <= 2'd1;
                            end
                        end
                        2'd1: begin
                            rx_shift <= {rx_shift[6:0], flash_miso};
                            phase <= 2'd2;
                            if (rx_bit == 3'd7) begin
                                fill_data <= {rx_shift[6:0], flash_miso};
                                fill_offset <= read_offset;
                                fill_we <= 1'b1;
                                rx_bit <= 3'd0;
                                if (read_offset == 8'hff)
                                    state <= DONE;
                                else
                                    read_offset <= read_offset + 1'b1;
                            end else begin
                                rx_bit <= rx_bit + 1'b1;
                            end
                        end
                        2'd2: begin
                            flash_clk <= 1'b0;
                            phase <= (SPI_CYCLES == 4) ? 2'd3 : 2'd0;
                        end
                        2'd3: phase <= 2'd0;
                    endcase
                end

                DONE: begin
                    flash_clk <= 1'b0;
                    flash_cs_n <= 1'b1;
                    fill_commit <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
