`timescale 1ns/1fs
module tb_flash_cache #(parameter FAST_SPI = 1, parameter CACHE_SET_BITS = 5,
    parameter real CORE_HALF_NS = 31.25);
    reg clk = 0;
    reg reset = 1;
    always #(CORE_HALF_NS) clk = ~clk; // normally 16 MHz
    reg fast_clk = 0;
    // Deliberately offset the domains: no test depends on coincident edges.
    initial begin #2.3; forever #7.8125 fast_clk = ~fast_clk; end

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
        rom_byte = ((a * 23'd37) ^ (a >> 8) ^ (a >> 16) ^ 23'h0000a5) & 8'hff;
    endfunction

    gb_rom_cache #(.CACHE_SET_BITS(CACHE_SET_BITS)) cache (
        .clk(clk),.reset(reset),.request(request),.address(address),
        .data(data),.ready(ready),.miss_request(miss_request),
        .miss_address(miss_address),.fill_begin(fill_begin),
        .fill_address(fill_address),.fill_we(fill_we),
        .fill_offset(fill_offset),.fill_data(fill_data),
        .fill_commit(fill_commit));

    ecp5_flash_backend #(.FAST_SPI(FAST_SPI)) reader (
        .clk_core(clk),.clk_fast(fast_clk),.reset(reset),.start(miss_request),
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
            // Model output propagation instead of zero-delay ideal MISO.
            flash_miso <= #12 modeled_byte[7-(read_bit & 7)];
        end else begin
            flash_miso = 0;
        end
    end

    task automatic read_and_check(input [22:0] a);
        integer timeout;
        begin
            @(negedge clk);
            address = a;
            request = 1;
            timeout = 0;
            while (!ready && timeout < 10000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!ready) $fatal(1,"timeout reading %h",a);
            if (data !== rom_byte(a))
                $fatal(1,"data mismatch at %h: got %h expected %h",
                       a,data,rom_byte(a));
            request = 0;
            repeat (3) @(negedge clk);
        end
    endtask

    realtime last_rise = 0, last_fall = 0, last_mosi = 0, fill_time = 0;
    integer filled = 0, completed = 0, stretched_bits = 0;
    always @(flash_mosi) last_mosi = $realtime;
    always @(negedge flash_cs_n) begin
        last_rise = 0; last_fall = 0;
    end
    always @(posedge flash_clk) begin
        if (!reset && !flash_cs_n && FAST_SPI) begin
            if (CORE_HALF_NS == 31.25 && last_rise != 0 &&
                ($realtime-last_rise < 62.499 || $realtime-last_rise > 62.501))
                $fatal(1,"SPI period %0.3f ns, expected 62.5",$realtime-last_rise);
            if (last_rise != 0 && $realtime-last_rise > 62.501)
                stretched_bits = stretched_bits + 1;
            if (last_fall != 0 && ($realtime-last_fall < 31.249 ||
                (CORE_HALF_NS == 31.25 && $realtime-last_fall > 31.251)))
                $fatal(1,"SPI low pulse not 31.25 ns");
            if ($realtime-last_mosi < 12)
                $fatal(1,"MOSI setup too short");
            last_rise = $realtime;
        end
    end
    always @(negedge flash_clk) begin
        if (!reset && FAST_SPI && last_rise != 0) begin
            if ($realtime-last_rise < 31.249 || $realtime-last_rise > 31.251)
                $fatal(1,"SPI high pulse not 31.25 ns");
            last_fall = $realtime;
        end
    end
    always @(posedge flash_cs_n) begin
        if (!reset && flash_bits != 0) begin
            if (flash_bits != 2088 || flash_cmd != 8'h0b)
                $fatal(1,"wrong fast-read transaction bits=%0d cmd=%h",flash_bits,flash_cmd);
        end
    end
    always @(posedge clk) begin
        if (reset) filled = 0;
        else begin
            if (fill_begin) begin filled = 0; fill_time = $realtime; end
            if (fill_we) begin
                if (fill_offset !== filled[7:0] ||
                    fill_data !== rom_byte(fill_address + filled))
                    $fatal(1,"fill mismatch offset=%h expected=%0d data=%h",
                           fill_offset,filled,fill_data);
                filled = filled + 1;
            end
            if (fill_commit) begin
                if (filled != 256) $fatal(1,"premature commit at byte %0d",filled);
                completed = completed + 1;
                $display("LINE FAST=%0d fill_us=%0.3f", FAST_SPI,
                         ($realtime-fill_time)/1000.0);
                if (FAST_SPI && CORE_HALF_NS == 31.25 && $realtime-fill_time > 133000)
                    $fatal(1,"fast fill exceeded 133 us");
            end
        end
    end

    initial begin
        repeat (4) @(negedge clk);
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
        // Verify every byte of the just-filled line, then mapper-style bank
        // boundaries and the highest supported cartridge line.
        begin : all_bytes
            integer b, before_hits;
            before_hits = transactions;
            for (b=0; b<256; b=b+1) read_and_check(23'h012400+b);
            if (transactions != before_hits) $fatal(1,"line hit caused refill");
        end
        read_and_check(23'h003fff);
        read_and_check(23'h004000);
        read_and_check(23'h1fc000);
        read_and_check(23'h7fffff);

        // Abort mid-transfer, reset both domains, and ensure no stale FIFO
        // records or old completion can enter the next cache line.
        @(negedge clk); address = 23'h005678; request = 1;
        wait(!flash_cs_n);
        repeat(20) @(negedge clk);
        reset = 1; request = 0;
        repeat(5) @(negedge clk);
        reset = 0;
        read_and_check(23'h005678);
        read_and_check(23'h0056ff);
        if (FAST_SPI && CORE_HALF_NS > 31.25 && stretched_bits == 0)
            $fatal(1,"reader backpressure not exercised");
        $display("PASS flash backend FAST=%0d CACHE_SET_BITS=%0d lines=%0d",
                 FAST_SPI,CACHE_SET_BITS,completed);
        $finish;
    end
    initial begin #20000000; $fatal(1,"flash test global timeout"); end
endmodule
