`timescale 1ns/1ps

module tb_rom_cache #(parameter CACHE_SET_BITS = 5);
    localparam SETS = 1 << CACHE_SET_BITS;
    localparam WAY_BYTES = SETS * 256;
    reg clk = 0;
    reg reset = 1;
    reg request = 0;
    reg [22:0] address = 0;
    wire [7:0] data;
    wire ready;
    wire miss_request;
    wire [22:0] miss_address;
    reg fill_begin = 0;
    reg [22:0] fill_address = 0;
    reg fill_we = 0;
    reg [7:0] fill_offset = 0;
    reg [7:0] fill_data = 0;
    reg fill_commit = 0;

    integer i;
    integer checks = 0;
    integer line;

    gb_rom_cache #(.CACHE_SET_BITS(CACHE_SET_BITS)) dut (
        .clk(clk), .reset(reset),
        .request(request), .address(address),
        .data(data), .ready(ready),
        .miss_request(miss_request), .miss_address(miss_address),
        .fill_begin(fill_begin), .fill_address(fill_address),
        .fill_we(fill_we), .fill_offset(fill_offset),
        .fill_data(fill_data), .fill_commit(fill_commit)
    );

    always #5 clk = ~clk;

    task start_request(input [22:0] requested_address);
        begin
            @(negedge clk);
            address = requested_address;
            request = 1;
        end
    endtask

    task release_request;
        begin
            @(negedge clk);
            request = 0;
            @(posedge clk);
            #1;
            if (ready)
                $fatal(1, "ready did not clear after request release");
        end
    endtask

    task expect_miss(input [22:0] expected_base);
        integer timeout;
        begin : wait_for_miss
            for (timeout = 0; timeout < 20; timeout = timeout + 1) begin
                @(posedge clk);
                #1;
                if (miss_request) begin
                    if (miss_address !== expected_base)
                        $fatal(1, "miss base %h, expected %h",
                               miss_address, expected_base);
                    checks = checks + 1;
                    disable wait_for_miss;
                end
            end
            $fatal(1, "cache miss timeout for %h", expected_base);
        end
    endtask

    task fill_line(input [22:0] base, input [7:0] salt);
        begin
            @(negedge clk);
            fill_address = base;
            fill_begin = 1;
            @(negedge clk);
            fill_begin = 0;
            fill_we = 1;
            for (i = 0; i < 256; i = i + 1) begin
                fill_offset = i[7:0];
                fill_data = i[7:0] ^ salt;
                @(negedge clk);
            end
            fill_we = 0;
            fill_commit = 1;
            @(negedge clk);
            fill_commit = 0;
        end
    endtask

    task expect_hit(input [7:0] expected_data);
        integer timeout;
        begin : wait_for_hit
            for (timeout = 0; timeout < 20; timeout = timeout + 1) begin
                @(posedge clk);
                #1;
                if (ready) begin
                    if (miss_request)
                        $fatal(1, "ready and miss_request asserted together");
                    if (data !== expected_data)
                        $fatal(1, "cache data %h, expected %h",
                               data, expected_data);
                    checks = checks + 1;
                    disable wait_for_hit;
                end
            end
            $fatal(1, "cache hit timeout");
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        reset = 0;

        // Cold miss, fill, and retry of the held request.
        start_request(23'h001234);
        expect_miss(23'h001200);
        fill_line(23'h001200, 8'hA0);
        expect_hit(8'h34 ^ 8'hA0);
        release_request();

        // The same line must now hit without another fill.
        start_request(23'h001234);
        expect_hit(8'h34 ^ 8'hA0);
        release_request();

        // Fill the second way in the same set.
        start_request(23'h001234 + WAY_BYTES);
        expect_miss(23'h001200 + WAY_BYTES);
        fill_line(23'h001200 + WAY_BYTES, 8'hB0);
        expect_hit(8'h34 ^ 8'hB0);
        release_request();

        // Touch way 0, making way 1 the LRU victim.
        start_request(23'h001234);
        expect_hit(8'h34 ^ 8'hA0);
        release_request();

        // A third conflicting tag must evict way 1 only.
        start_request(23'h001234 + 2*WAY_BYTES);
        expect_miss(23'h001200 + 2*WAY_BYTES);
        fill_line(23'h001200 + 2*WAY_BYTES, 8'hC0);
        expect_hit(8'h34 ^ 8'hC0);
        release_request();

        start_request(23'h001234);
        expect_hit(8'h34 ^ 8'hA0);
        release_request();

        start_request(23'h001234 + WAY_BYTES);
        expect_miss(23'h001200 + WAY_BYTES);

        // Reset must invalidate all sets, including the expanded upper half.
        @(negedge clk);
        request = 0;
        reset = 1;
        repeat (2) @(negedge clk);
        reset = 0;
        // Populate every line with a distinct signature. A wrong set/tag or
        // data index (especially bit 12) aliases the two halves and fails.
        for (line = 0; line < SETS*2; line = line + 1) begin
            start_request(line*256 + 255);
            expect_miss(line*256);
            fill_line(line*256, line[7:0]);
            expect_hit(8'hff ^ line[7:0]);
            release_request();
        end
        for (line = 0; line < SETS*2; line = line + 1) begin
            start_request(line*256);
            expect_hit(line[7:0]);
            release_request();
            start_request(line*256 + 255);
            expect_hit(8'hff ^ line[7:0]);
            release_request();
        end
        @(negedge clk);
        reset = 1;
        repeat (2) @(negedge clk);
        reset = 0;
        start_request((SETS*2-1)*256);
        expect_miss((SETS*2-1)*256);

        $display("PASS gb_rom_cache bytes=%0d checks=%0d", WAY_BYTES*2, checks);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "global timeout");
    end
endmodule
