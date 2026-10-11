`timescale 1ns/1ps

// End-to-end smoke-ROM gate: load the exact badge ROM through the wrapper's
// host interface, release the core, and require an LCD pixel pulse.
module tb_smoke_rom;
    reg clk = 0;
    always #5 clk = ~clk;

    reg reset = 1, core_run = 0, gbc_mode = 0;
    reg [7:0] buttons = 0;
    reg host_rom_we = 0;
    reg [22:0] host_rom_addr = 0;
    reg [7:0] host_rom_data = 0;
    wire cache_miss; wire [22:0] cache_miss_address;
    wire pixel_valid; wire [15:0] pixel_rgb565; wire lcd_vsync;
    wire [15:0] audio_l, audio_r; wire running, lcd_on_debug, lcd_clock_debug;
    reg fill_begin=0, fill_we=0, fill_commit=0;
    reg [7:0] fill_offset=0, fill_data=0;
    reg [22:0] fill_address=0;
    reg [7:0] rom [0:32767];
    integer fd, size, i, pixels;

    gb_core_wrapper #(.BRAM_ROM(1)) dut (
        .clk(clk), .reset(reset), .core_run(core_run), .gbc_mode(gbc_mode),
        .buttons(buttons), .host_rom_we(host_rom_we), .host_rom_addr(host_rom_addr),
        .host_rom_data(host_rom_data), .fill_begin(fill_begin), .fill_we(fill_we),
        .fill_offset(fill_offset), .fill_data(fill_data), .fill_commit(fill_commit),
        .fill_address(fill_address), .cache_miss(cache_miss),
        .cache_miss_address(cache_miss_address), .pixel_valid(pixel_valid),
        .pixel_rgb565(pixel_rgb565), .lcd_vsync(lcd_vsync), .audio_l(audio_l),
        .audio_r(audio_r), .running(running), .lcd_on_debug(lcd_on_debug),
        .lcd_clock_debug(lcd_clock_debug)
    );

    always @(posedge clk) if (pixel_valid) pixels = pixels + 1;

    initial begin
        fd = $fopen("games/game.gb", "rb");
        if (fd == 0) begin $display("FAIL: cannot open smoke ROM"); $finish(1); end
        size = $fread(rom, fd); $fclose(fd);
        if (size != 32768) begin $display("FAIL: smoke ROM size %0d", size); $finish(1); end
        repeat (20) @(posedge clk);
        // Match the badge uploader: ROM is written while the core is reset.
        for (i = 0; i < 32768; i = i + 1) begin
            @(negedge clk); host_rom_addr = i; host_rom_data = rom[i]; host_rom_we = 1;
            @(negedge clk); host_rom_we = 0;
        end
        @(negedge clk); reset = 0; core_run = 1;
        // Enough core-clock cycles for the internal DMG boot ROM and smoke
        // program to enable LCD.  Stop immediately once pixels appear.
        repeat (5000000) begin
            @(posedge clk);
            if (pixels != 0) begin
                $display("PASS: smoke ROM produced %0d LCD pixels", pixels);
                $finish;
            end
        end
        $display("FAIL: no LCD pixels (running=%b lcd_on=%b lcd_clock=%b)",
                 running, lcd_on_debug, lcd_clock_debug);
        $finish(1);
    end
endmodule
