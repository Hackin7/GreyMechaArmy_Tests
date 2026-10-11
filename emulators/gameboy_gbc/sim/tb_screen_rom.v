`timescale 1ns/1ps

// Full-system visual ROM testbench. Loads a 32 KiB cartridge, executes the
// authentic CGB boot ROM, captures a settled 160x144 PPU frame, and writes a
// binary RGB PPM for comparison with the test ROM's reference image.
module tb_screen_rom;
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
    reg [15:0] framebuffer [0:23039];
    reg [1023:0] rom_path;
    reg [1023:0] frame_path;
    reg vsync_d;
    integer fd;
    integer size;
    integer i;
    integer pixel_count;
    integer settled_frames;
    integer max_cycles;
    integer cycles;
    integer plusarg_seen;
    integer r5;
    integer g5;
    integer b5;
    integer r8;
    integer g8;
    integer b8;

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

    task write_frame;
        begin
            fd = $fopen(frame_path, "wb");
            if (fd == 0) begin
                $display("FAIL: cannot create frame %0s", frame_path);
                $finish(1);
            end
            $fwrite(fd, "P6\n160 144\n255\n");
            for (i = 0; i < 23040; i = i + 1) begin
                // Recover the original RGB555 components. Green bit 5 in the
                // wrapper's RGB565 output is only a replicated MSB.
                r5 = framebuffer[i][15:11];
                g5 = framebuffer[i][10:6];
                b5 = framebuffer[i][4:0];
                r8 = (r5 << 3) | (r5 >> 2);
                g8 = (g5 << 3) | (g5 >> 2);
                b8 = (b5 << 3) | (b5 >> 2);
                $fwrite(fd, "%c%c%c", r8[7:0], g8[7:0], b8[7:0]);
            end
            $fclose(fd);
            $display("PASS: captured settled frame %0d to %0s",
                     settled_frames, frame_path);
        end
    endtask

    always @(posedge clk) begin
        vsync_d <= lcd_vsync;
        if (!reset && !debug_boot_rom) begin
            if (lcd_vsync && !vsync_d) begin
                if (pixel_count == 23040) begin
                    settled_frames = settled_frames + 1;
                    if (settled_frames == 5) begin
                        write_frame();
                        $finish;
                    end
                end else if (settled_frames != 0) begin
                    $display("FAIL: frame contained %0d pixels", pixel_count);
                    $finish(1);
                end
                pixel_count = 0;
            end
            if (pixel_valid) begin
                if (pixel_count < 23040)
                    framebuffer[pixel_count] <= pixel_rgb565;
                pixel_count = pixel_count + 1;
            end
        end
    end

    initial begin
        rom_path = "sim/roms/cgb-acid2.gbc";
        frame_path = "build/sim/cgb-acid2.ppm";
        max_cycles = 80000000;
        plusarg_seen = $value$plusargs("ROM=%s", rom_path);
        plusarg_seen = $value$plusargs("FRAME=%s", frame_path);
        plusarg_seen = $value$plusargs("MAX_CYCLES=%d", max_cycles);

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

        pixel_count = 0;
        settled_frames = 0;
        vsync_d = 0;
        for (i = 0; i < 32768; i = i + 1)
            dut.rom_bram[i] = rom[i];
        repeat (20) @(posedge clk);
        for (i = 16'h0100; i < 16'h0150; i = i + 1)
            host_write_rom_byte(i, rom[i]);
        host_write_rom_byte(23'd32767, rom[32767]);

        @(negedge clk);
        reset = 0;
        core_run = 1;
        $display("Running visual ROM %0s", rom_path);

        for (cycles = 0; cycles < max_cycles; cycles = cycles + 1) begin
            @(posedge clk);
            if ((cycles % 5000000) == 0)
                $display("TRACE: cycle=%0d pc=%04x boot=%b lcd=%b frame=%0d pixels=%0d",
                         cycles, debug_pc, debug_boot_rom, lcd_on_debug,
                         settled_frames, pixel_count);
        end

        $display("FAIL: timeout pc=%04x boot=%b lcd=%b frame=%0d pixels=%0d",
                 debug_pc, debug_boot_rom, lcd_on_debug,
                 settled_frames, pixel_count);
        $finish(1);
    end
endmodule
