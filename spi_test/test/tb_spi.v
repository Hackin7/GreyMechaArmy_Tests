`timescale 1ns / 1ps

module spi_master_tb;

    // Testbench signals
    reg clk;
    reg rst_n;
    reg [7:0] data_in;
    reg start_transfer;
    wire transfer_done;

    // SPI signals
    wire sclk;
    wire mosi;
    wire ncs;

    // DUT Instance
    spi_master dut (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .start_transfer(start_transfer),
        .transfer_done(transfer_done),
        .sclk(sclk),
        .mosi(mosi),
        .ncs(ncs)
    );

    // Testbench internal variables
    reg [7:0] received_data;
    integer bit_count;
    reg [7:0] test_data;

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Waveform file generation
    initial begin
        // Specify the output file name
        $dumpfile("test.vcd");
        // Dump all signals in the current module (and its hierarchy)
        $dumpvars;
    end

    // Test sequence
    initial begin
        // Initialize signals
        rst_n = 0;
        data_in = 8'h00;
        start_transfer = 0;

        // Apply reset
        #10 rst_n = 1;
        
        // Define the data to send
        test_data = 8'hA5; 
        $display("Sending data: 0x%h", test_data);

        // Wait for a few cycles before starting
        #20; 

        // 1. Load data and start transfer
        data_in = test_data;
        start_transfer = 1;
        #10 start_transfer = 0;

        // 2. Wait for the transfer to complete
        @(posedge transfer_done);
        $display("Transfer completed at time %0t", $time);

        // 3. Verify the received data
        $display("Verification complete. Original data: 0x%h, Received data: 0x%h", test_data, received_data);
        if (test_data == received_data) begin
            $display("Test Passed! Data was sent correctly. 🎉");
        end else begin
            $display("Test Failed! Data mismatch. 😢");
        end
        
        #10 $finish;
    end

    // SPI Slave Logic to receive data
    always @(negedge sclk) begin
        if (!ncs) begin // Only receive if chip select is active
            if (bit_count > 0) begin
                // Shift in the bit from MOSI on the falling edge of the clock
                received_data = {received_data[6:0], mosi};
                bit_count = bit_count - 1;
            end
        end
    end

    // Reset the bit counter when a new transfer starts
    always @(negedge ncs) begin
        if (!ncs) begin
            received_data = 8'h00;
            bit_count = 8;
        end
    end

endmodule