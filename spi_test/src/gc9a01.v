module gc9a01 (
    input wire clk,
    input wire rst_n,
    output wire sclk,
    output wire mosi,
    output wire ncs,
    output reg done
);

    // List of bytes to send
    // You can modify this list with the data you want to transmit.
    // In this example, we'll send the values: 8'hAA, 8'h55, 8'hF0
    localparam NUM_BYTES = 3;
    reg [7:0] data_list [0:NUM_BYTES-1];

    initial begin
        data_list[0] = 8'hAA;
        data_list[1] = 8'h55;
        data_list[2] = 8'hF0;
    end

    // FSM States for sequencing bytes
    localparam IDLE = 2'b00;
    localparam SEND_BYTE = 2'b01;
    localparam WAIT_TRANSFER = 2'b10;
    localparam FINISHED = 2'b11;

    // Internal Registers
    reg [1:0] state;
    reg [31:0] byte_count; // counter for bytes in the list
    reg start_transfer_reg;
    wire transfer_done_wire;

    // Instantiate the spi_master module
    spi_master spi_master_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_list[byte_count]),
        .start_transfer(start_transfer_reg),
        .transfer_done(transfer_done_wire),
        .sclk(sclk),
        .mosi(mosi),
        .ncs(ncs)
    );

    // Main FSM to control the byte sequence
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            byte_count <= 0;
            start_transfer_reg <= 0;
            done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (byte_count < NUM_BYTES) begin
                        state <= SEND_BYTE;
                        done <= 0;
                    end else begin
                        state <= FINISHED; // All bytes sent
                    end
                    start_transfer_reg <= 0;
                end
                
                SEND_BYTE: begin
                    start_transfer_reg <= 1; // Assert start signal for spi_master
                    state <= WAIT_TRANSFER;
                end
                
                WAIT_TRANSFER: begin
                    start_transfer_reg <= 0; // De-assert start
                    if (transfer_done_wire) begin
                        byte_count <= byte_count + 1;
                        state <= IDLE; // Move to the next byte
                    end
                end
                
                FINISHED: begin
                    // Remain in finished state until reset
                    done <= 1;
                    state <= FINISHED;
                end
            endcase
        end
    end
endmodule