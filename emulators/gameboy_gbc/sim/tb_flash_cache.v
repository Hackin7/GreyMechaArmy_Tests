`timescale 1ns/1ps
module tb_flash_cache;
    reg clk = 0;
    reg reset = 1;
    always #31.25 clk = ~clk; // 16 MHz

    reg request = 0;
    reg [22:0] address = 0;
    wire [7:0] data;
    wire ready;
    wire miss_request;
    wire [22:0] miss_address;

    wire busy,fill_begin,fill_we,fill_commit;
    wire [22:0] fill_address;
    wire [7:0] fill_offset,fill_data;
    wire flash_clk,flash_cs_n,flash_mosi;
    reg flash_miso = 0;

    integer transactions = 0;
    integer flash_bits = 0;
    reg [7:0] flash_cmd = 0;
    reg [23:0] flash_addr = 0;

    function automatic [7:0] rom_byte(input [22:0] a);
        rom_byte = ((a * 23'd37) ^ 23'h0000a5) & 8'hff;
    endfunction

    gb_rom_cache cache (
        .clk(clk),.reset(reset),.request(request),.address(address),
        .data(data),.ready(ready),.miss_request(miss_request),
        .miss_address(miss_address),.fill_begin(fill_begin),
        .fill_address(fill_address),.fill_we(fill_we),
        .fill_offset(fill_offset),.fill_data(fill_data),
        .fill_commit(fill_commit));

    ecp5_flash_reader reader (
        .clk(clk),.reset(reset),.start(miss_request),
        .line_address(miss_address),.busy(busy),
        .fill_begin(fill_begin),.fill_address(fill_address),
        .fill_we(fill_we),.fill_offset(fill_offset),.fill_data(fill_data),
        .fill_commit(fill_commit),.flash_clk(flash_clk),
        .flash_cs_n(flash_cs_n),
        .flash_mosi(flash_mosi),.flash_miso(flash_miso));

    // Minimal W25Q128 0x0b fast-read model.  Input is sampled on rising
    // edges and output changes on falling edges (SPI mode 0).
    always @(negedge flash_cs_n) begin
        transactions = transactions + 1;
        flash_bits = 0;
        flash_cmd = 0;
        flash_addr = 0;
    end

    always @(posedge flash_clk) begin
        if (!flash_cs_n) begin
            if (flash_bits < 8)
                flash_cmd = {flash_cmd[6:0],flash_mosi};
            else if (flash_bits < 32)
                flash_addr = {flash_addr[22:0],flash_mosi};
            flash_bits = flash_bits + 1;
        end
    end

    integer read_bit;
    reg [22:0] cartridge_byte_address;
    reg [7:0] modeled_byte;
    always @(negedge flash_clk) begin
        if (!flash_cs_n && flash_bits >= 40) begin
            read_bit = flash_bits - 40;
            cartridge_byte_address =
                (flash_addr - 24'h100000) + (read_bit >> 3);
            modeled_byte = rom_byte(cartridge_byte_address);
            flash_miso = modeled_byte[7-(read_bit & 7)];
        end else begin
            flash_miso = 0;
        end
    end

    task automatic read_and_check(input [22:0] a);
        integer timeout;
        begin
            address = a;
            request = 1;
            timeout = 0;
            while (!ready && timeout < 10000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!ready) $fatal(1,"timeout reading %h",a);
            if (data !== rom_byte(a))
                $fatal(1,"data mismatch at %h: got %h expected %h",
                       a,data,rom_byte(a));
            request = 0;
            @(posedge clk);
            @(posedge clk);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset = 0;
        read_and_check(23'h012345);
        if (transactions != 1) $fatal(1,"expected one flash read");
        if (flash_cmd != 8'h0b) $fatal(1,"command was %h",flash_cmd);
        if (flash_addr != 24'h112300)
            $fatal(1,"physical address was %h",flash_addr);

        // A different byte in the same 256-byte line must be a cache hit.
        read_and_check(23'h0123fe);
        if (transactions != 1)
            $fatal(1,"cache hit started another flash transaction");

        // Crossing a line boundary must issue another aligned fast read.
        read_and_check(23'h012400);
        if (transactions != 2) $fatal(1,"expected second flash read");
        if (flash_addr != 24'h112400)
            $fatal(1,"second physical address was %h",flash_addr);
        $display("PASS: fast-read, dummy byte, 256-byte fill and cache hit");
        $finish;
    end
endmodule
