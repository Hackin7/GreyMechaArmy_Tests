`timescale 1ns/1ps

// Full-system CPU-ROM testbench.  The ROM is loaded through the same host
// interface used by the badge, and Blargg's serial writes are treated as the
// authoritative test result so this test does not depend on the LCD path.
module tb_cpu_instr;
    reg clk = 0;
    always #5 clk = ~clk;

    reg reset = 1;
    reg core_run = 0;
    reg gbc_mode = 1;
    reg [7:0] buttons = 0;
    reg host_rom_we = 0;
    reg [22:0] host_rom_addr = 0;
    reg [7:0] host_rom_data = 0;
    reg fill_begin = 0;
    reg fill_we = 0;
    reg fill_commit = 0;
    reg [7:0] fill_offset = 0;
    reg [7:0] fill_data = 0;
    reg [22:0] fill_address = 0;

    wire cache_miss;
    wire [22:0] cache_miss_address;
    wire pixel_valid;
    wire [15:0] pixel_rgb565;
    wire lcd_vsync;
    wire [15:0] audio_l;
    wire [15:0] audio_r;
    wire running;
    wire lcd_on_debug;
    wire lcd_clock_debug;
    wire [15:0] debug_pc;
    wire debug_boot_rom;

    reg [7:0] rom [0:32767];
    reg [1023:0] rom_path;
    integer fd;
    integer size;
    integer i;
    integer cycles;
    integer max_cycles;
    integer plusarg_seen;
    integer serial_chars;
    reg [2:0] pass_match;
    reg [2:0] fail_match;

    gb_core_wrapper #(.BRAM_ROM(1)) dut (
        .clk(clk), .reset(reset), .core_run(core_run), .gbc_mode(gbc_mode),
        .buttons(buttons), .host_rom_we(host_rom_we),
        .host_rom_addr(host_rom_addr), .host_rom_data(host_rom_data),
        .fill_begin(fill_begin), .fill_we(fill_we), .fill_offset(fill_offset),
        .fill_data(fill_data), .fill_commit(fill_commit),
        .fill_address(fill_address), .cache_miss(cache_miss),
        .cache_miss_address(cache_miss_address), .pixel_valid(pixel_valid),
        .pixel_rgb565(pixel_rgb565), .lcd_vsync(lcd_vsync),
        .audio_l(audio_l), .audio_r(audio_r), .running(running),
        .lcd_on_debug(lcd_on_debug), .lcd_clock_debug(lcd_clock_debug),
        .debug_pc(debug_pc), .debug_boot_rom(debug_boot_rom)
    );

    task consume_serial;
        input [7:0] value;
        begin
            serial_chars = serial_chars + 1;
            $write("%c", value);
            $fflush();

            case (pass_match)
                0: pass_match = (value == "P") ? 1 : 0;
                1: pass_match = (value == "a") ? 2 : 0;
                2: pass_match = (value == "s") ? 3 : 0;
                3: pass_match = (value == "s") ? 4 : 0;
                4: pass_match = (value == "e") ? 5 : 0;
                5: begin
                    if (value == "d") begin
                        $display("\nPASS: instruction ROM reported Passed (%0d serial bytes)",
                                 serial_chars);
                        $finish;
                    end
                    pass_match = 0;
                end
                default: pass_match = 0;
            endcase

            case (fail_match)
                0: fail_match = (value == "F") ? 1 : 0;
                1: fail_match = (value == "a") ? 2 : 0;
                2: fail_match = (value == "i") ? 3 : 0;
                3: fail_match = (value == "l") ? 4 : 0;
                4: fail_match = (value == "e") ? 5 : 0;
                5: begin
                    if (value == "d") begin
                        $display("\nFAIL: instruction ROM reported Failed (%0d serial bytes)",
                                 serial_chars);
                        $finish(1);
                    end
                    fail_match = 0;
                end
                default: fail_match = 0;
            endcase
        end
    endtask

    task host_write_rom_byte;
        input [22:0] address;
        input [7:0] value;
        begin
            @(negedge clk);
            host_rom_addr = address;
            host_rom_data = value;
            host_rom_we = 1;
            @(negedge clk);
            host_rom_we = 0;
        end
    endtask

    // Blargg writes the outgoing character to SB ($ff01), then starts the
    // transfer by writing bit 7 to SC ($ff02).  Sample SB at that SC write.
    always @(posedge clk) begin
        if (!reset && dut.core.ce_cpu && dut.core.sel_sc &&
            !dut.core.cpu_wr_n_edge && dut.core.cpu_do[7]) begin
            consume_serial(dut.core.sb_o);
        end
    end

    initial begin
        rom_path = "sim/roms/01-special.gb";
        if (!$value$plusargs("ROM=%s", rom_path)) begin end
        fd = $fopen(rom_path, "rb");
        if (fd == 0) begin
            $display("FAIL: cannot open ROM %0s", rom_path);
            $finish(1);
        end
        size = $fread(rom, fd);
        $fclose(fd);
        if (size != 32768) begin
            $display("FAIL: expected a 32768-byte ROM, got %0d", size);
            $finish(1);
        end

        serial_chars = 0;
        pass_match = 0;
        fail_match = 0;
        max_cycles = 200000000;
        plusarg_seen = $value$plusargs("MAX_CYCLES=%d", max_cycles);
        // Preload the simulation memory without spending 65,536 active-core
        // clock edges on transport.  Still clock the complete cartridge header
        // through the real host interface so mapper detection is exercised.
        for (i = 0; i < 32768; i = i + 1)
            dut.rom_bram[i] = rom[i];
        repeat (20) @(posedge clk);
        for (i = 16'h0100; i < 16'h0150; i = i + 1)
            host_write_rom_byte(i, rom[i]);
        host_write_rom_byte(23'd32767, rom[32767]);

        @(negedge clk);
        reset = 0;
        core_run = 1;
        $display("Running %0s", rom_path);

        for (cycles = 0; cycles < max_cycles; cycles = cycles + 1) begin
            @(posedge clk);
            if ((cycles % 5000000) == 0)
                $display("TRACE: cycle=%0d pc=%04x boot=%b lcd=%b serial=%0d",
                         cycles, debug_pc, debug_boot_rom, lcd_on_debug,
                         serial_chars);
        end

        $display("FAIL: timeout pc=%04x boot=%b lcd=%b serial=%0d",
                 debug_pc, debug_boot_rom, lcd_on_debug, serial_chars);
        $finish(1);
    end
endmodule
