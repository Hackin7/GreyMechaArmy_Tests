module spi_master (
    input wire clk,
    input wire rst_n,
    input wire [7:0] data_in,
    input wire start_transfer,
    output wire transfer_done,

    output reg sclk,
    output reg mosi,
    output reg ncs
);

    // FSM States
    localparam IDLE = 2'b00;
    localparam START = 2'b01;
    localparam SHIFT = 2'b10;
    localparam DONE = 2'b11;

    // Internal Registers
    reg [1:0] state;
    reg [2:0] bit_count;
    reg [7:0] shift_reg;
    reg transfer_done_reg;

    // FSM and SPI Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            sclk <= 0;
            mosi <= 0;
            ncs <= 1;
            transfer_done_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start_transfer) begin
                        state <= START;
                        shift_reg <= data_in; // Load data to be transmitted
                        bit_count <= 8; // Prepare to send 8 bits
                        ncs <= 0; // Assert chip select
                        transfer_done_reg <= 0;
                    end
                    sclk <= 0;
                end

                START: begin
                    state <= SHIFT;
                    sclk <= 0; // Ensure clock starts low
                end

                SHIFT: begin
                    sclk <= ~sclk; // Toggle the clock
                    if (sclk == 0) begin // On the rising edge of the clock (to latch data on slave)
                        mosi <= shift_reg[7]; // Shift out the most significant bit
                        shift_reg <= shift_reg << 1;
                        bit_count <= bit_count - 1;

                        if (bit_count == 1) begin
                            state <= DONE;
                        end
                    end
                end

                DONE: begin
                    state <= IDLE;
                    ncs <= 1; // De-assert chip select
                    sclk <= 0;
                    transfer_done_reg <= 1; // Signal completion
                end
            endcase
        end
    end

    // Assign output
    assign transfer_done = transfer_done_reg;

endmodule