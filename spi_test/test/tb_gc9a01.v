`timescale 1ns / 1ps

module tb_gc9a01;

    // Parameters for clock and data verification
    parameter CLK_PERIOD = 10;
    localparam NUM_BYTES = 20;

    // Testbench signals
    reg clk;
    reg rst_n;
    wire sclk;
    wire mosi;
    wire ncs;
    wire dc;
    wire done;


    // Data verification registers and arrays
    reg [7:0] received_data [0:NUM_BYTES-1];
    reg       received_dc [0:NUM_BYTES-1];
    reg [3:0] bit_count;
    reg [7:0] current_byte;
    reg [31:0] byte_index;

    // Instantiate the Unit Under Test (UUT)
    gc9a01 uut (
        .clk(clk),
        .rst_n(rst_n),
        .sclk(sclk),
        .mosi(mosi),
        .ncs(ncs),
        .dc(dc),
        .done(done)
    );

    initial begin
        // Specify the output file name
        $dumpfile("test.vcd");
        // Dump all signals in the current module (and its hierarchy)
        $dumpvars;
    end

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Test stimulus and verification
    integer i;
    initial begin
        // 1. Initialize
        rst_n = 1'b0;
        byte_index = 0;
        @(negedge clk);
        rst_n = 1'b1;

        // 2. Wait for the sequence to complete
        @(posedge done);

        #100;

        // 3. Final Verification
        $display("----------------------------------------");
        $display("SPI Sequence Sender Test Completed");
        $display("Expected Data: {8'hAA, 8'h55, 8'hF0}");
        $display("Received Data: {%h, %h, %h}", received_data[0], received_data[1], received_data[2]);
        for (i = 0; i < 20; i = i + 1) begin
			$display ("Current loop#%0d: %h %h", i, received_data[i], received_dc[i]);
		end

        if (received_data[0] == 8'hAA && received_data[1] == 8'h55 && received_data[2] == 8'hF0) begin
            $display("Test Passed! All data was verified correctly.");
        end else begin
            $display("Test Failed! Mismatch in received data.");
        end
        $display("----------------------------------------");
        $finish;
    end

    // SPI Slave model to capture data from the bus
    always @(posedge clk) begin
        // Start of a new byte transfer (ncs goes low)
        if (!ncs) begin
            if (sclk == 1'b0) begin
                if (byte_index < NUM_BYTES) begin
                    current_byte = {current_byte[6:0], mosi}; // Shift in the bit
                end
            end
        end

        // End of a byte transfer (ncs goes high again)
        if (ncs && !ncs_previous) begin
            if (byte_index < NUM_BYTES) begin
                received_data[byte_index] = current_byte;
                received_dc[byte_index] = dc;
                byte_index = byte_index + 1;
                current_byte = 8'b0; // Reset for the next byte
            end
        end
    end

    // To properly detect the rising edge of ncs, we need a register to store its previous state.
    reg ncs_previous;
    always @(posedge clk) begin
        ncs_previous <= ncs;
    end

endmodule
