`timescale 1ns/1ps

// Full cache-mode cartridge test. Only the 512-byte header is uploaded, then
// cache misses are serviced from a host-side ROM image exactly as on the badge.
module tb_cache_defcon #(parameter FLASH_BACKEND = 0);
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
    wire [15:0] audio_l, audio_r;
    wire running, lcd_on_debug, lcd_clock_debug;
    wire [15:0] debug_pc;
    wire debug_boot_rom;
    wire flash_busy,flash_fill_begin,flash_fill_we,flash_fill_commit;
    wire [22:0] flash_fill_address;
    wire [7:0] flash_fill_offset,flash_fill_data;
    wire flash_clk,flash_cs_n,flash_mosi;
    reg flash_miso = 0;

    reg [7:0] rom [0:2097151];
    reg [15:0] framebuffer [0:23039];
    reg [1023:0] rom_path;
    reg [1023:0] frame_path;
    reg [22:0] active_fill;
    reg [1:0] fill_state = 0;
    reg vsync_d = 0;
    integer fd, size, i, cycles, max_cycles, target_frames, plusarg_seen;
    integer start_press_frame, start_release_frame;
    integer pixel_count = 0;
    integer frame_count = 0;
    integer miss_count = 0;
    integer banked_miss_count = 0;
    integer nonblack_count = 0;
    integer nonwhite_count = 0;
    integer varying_count = 0;
    integer bus_changes = 0;
    integer data_mismatches = 0;
    reg [15:0] first_pixel = 0;
    reg [15:0] last_bus = 0;
    integer r5, g5, b5, r8, g8, b8;

    gb_core_wrapper #(.BRAM_ROM(0)) dut (
        .clk(clk), .reset(reset), .core_run(core_run), .gbc_mode(gbc_mode),
        .buttons(buttons), .host_rom_we(host_rom_we),
        .host_rom_addr(host_rom_addr), .host_rom_data(host_rom_data),
        .fill_begin(FLASH_BACKEND ? flash_fill_begin : fill_begin),
        .fill_we(FLASH_BACKEND ? flash_fill_we : fill_we),
        .fill_offset(FLASH_BACKEND ? flash_fill_offset : fill_offset),
        .fill_data(FLASH_BACKEND ? flash_fill_data : fill_data),
        .fill_commit(FLASH_BACKEND ? flash_fill_commit : fill_commit),
        .fill_address(FLASH_BACKEND ? flash_fill_address : fill_address),
        .cache_miss(cache_miss),
        .cache_miss_address(cache_miss_address), .pixel_valid(pixel_valid),
        .pixel_rgb565(pixel_rgb565), .lcd_vsync(lcd_vsync),
        .audio_l(audio_l), .audio_r(audio_r), .running(running),
        .lcd_on_debug(lcd_on_debug), .lcd_clock_debug(lcd_clock_debug),
        .debug_pc(debug_pc), .debug_boot_rom(debug_boot_rom)
    );

    ecp5_flash_reader flash_reader (
        .clk(clk),.reset(reset || !FLASH_BACKEND),.start(cache_miss),
        .line_address(cache_miss_address),.busy(flash_busy),
        .fill_begin(flash_fill_begin),.fill_address(flash_fill_address),
        .fill_we(flash_fill_we),.fill_offset(flash_fill_offset),
        .fill_data(flash_fill_data),.fill_commit(flash_fill_commit),
        .flash_clk(flash_clk),
        .flash_cs_n(flash_cs_n),.flash_mosi(flash_mosi),
        .flash_miso(flash_miso));

    // W25Q128 mode-0 model backed by the same Defcon image.  It verifies the
    // autonomous path without exposing the ROM array to the cache-fill port.
    integer flash_bits = 0;
    integer flash_read_bit;
    reg [7:0] flash_command = 0;
    reg [23:0] flash_address = 0;
    reg [22:0] flash_rom_address;
    reg [7:0] flash_byte;
    always @(negedge flash_cs_n) begin
        if (FLASH_BACKEND) begin
            flash_bits = 0;
            flash_command = 0;
            flash_address = 0;
            miss_count = miss_count + 1;
            if (cache_miss_address >= 23'h004000)
                banked_miss_count = banked_miss_count + 1;
        end
    end
    always @(posedge flash_clk) begin
        if (FLASH_BACKEND && !flash_cs_n) begin
            if (flash_bits < 8)
                flash_command = {flash_command[6:0],flash_mosi};
            else if (flash_bits < 32)
                flash_address = {flash_address[22:0],flash_mosi};
            flash_bits = flash_bits + 1;
        end
    end
    always @(negedge flash_clk) begin
        if (FLASH_BACKEND && !flash_cs_n && flash_bits >= 40) begin
            flash_read_bit = flash_bits - 40;
            flash_rom_address =
                (flash_address - 24'h100000) + (flash_read_bit >> 3);
            flash_byte = rom[flash_rom_address];
            flash_miso = flash_byte[7-(flash_read_bit & 7)];
        end else begin
            flash_miso = 0;
        end
    end

    task host_write_rom_byte(input [22:0] address, input [7:0] value);
        begin
            @(negedge clk);
            host_rom_addr = address;
            host_rom_data = value;
            host_rom_we = 1;
            @(negedge clk);
            host_rom_we = 0;
        end
    endtask

    // RP2350-equivalent 256-byte cache line service.
    always @(negedge clk) begin
        if (reset) begin
            fill_state = 0;
            fill_begin = 0;
            fill_we = 0;
            fill_commit = 0;
        end else if (FLASH_BACKEND) begin
            fill_begin = 0;
            fill_we = 0;
            fill_commit = 0;
        end else begin
            case (fill_state)
                0: if (cache_miss) begin
                    active_fill = cache_miss_address;
                    fill_address = cache_miss_address;
                    fill_begin = 1;
                    miss_count = miss_count + 1;
                    if (cache_miss_address >= 23'h004000)
                        banked_miss_count = banked_miss_count + 1;
                    fill_state = 1;
                end
                1: begin
                    fill_begin = 0;
                    fill_offset = 0;
                    fill_data = rom[active_fill];
                    fill_we = 1;
                    fill_state = 2;
                end
                2: begin
                    if (fill_offset == 8'hff) begin
                        fill_we = 0;
                        fill_commit = 1;
                        fill_state = 3;
                    end else begin
                        fill_offset = fill_offset + 1'b1;
                        fill_data = rom[active_fill + fill_offset];
                    end
                end
                3: begin
                    fill_commit = 0;
                    fill_state = 0;
                end
            endcase
        end
    end

    task write_frame;
        begin
            fd = $fopen(frame_path, "wb");
            if (fd == 0) $fatal(1, "cannot create frame %0s", frame_path);
            $fwrite(fd, "P6\n160 144\n255\n");
            for (i = 0; i < 23040; i = i + 1) begin
                r5 = framebuffer[i][15:11];
                g5 = framebuffer[i][10:6];
                b5 = framebuffer[i][4:0];
                r8 = (r5 << 3) | (r5 >> 2);
                g8 = (g5 << 3) | (g5 >> 2);
                b8 = (b5 << 3) | (b5 >> 2);
                $fwrite(fd, "%c%c%c", r8[7:0], g8[7:0], b8[7:0]);
            end
            $fclose(fd);
        end
    endtask

    always @(posedge clk) begin
        vsync_d <= lcd_vsync;
        if (!reset && !debug_boot_rom) begin
            if (lcd_vsync && !vsync_d) begin
                if (pixel_count == 23040) begin
                    frame_count = frame_count + 1;
                    $display("FRAME %0d bus=%04x changes=%0d mbc=%06x halt=%b ie=%02x if=%02x vbi=%b first=%04x varied=%0d mismatches=%0d nonblack=%0d nonwhite=%0d misses=%0d banked=%0d",
                             frame_count, debug_pc, bus_changes,
                             dut.mbc_addr, dut.core.cpu_halt_n,
                             dut.core.ie_r, dut.core.if_r,
                             dut.core.vblank_irq, first_pixel, varying_count,
                             data_mismatches, nonblack_count, nonwhite_count, miss_count,
                             banked_miss_count);
                    if (frame_count == start_press_frame) begin
                        buttons[7] = 1'b1;
                        $display("INPUT Start pressed at frame %0d", frame_count);
                    end
                    if (frame_count == start_release_frame) begin
                        buttons[7] = 1'b0;
                        $display("INPUT Start released at frame %0d", frame_count);
                    end
                    if (frame_count == target_frames) begin
                        write_frame();
                        if (nonblack_count == 0)
                            $fatal(1, "Defcon PPU frame is entirely black");
                        if (varying_count == 0)
                            $fatal(1, "Defcon PPU frame is a single flat color %04x", first_pixel);
                        if (data_mismatches != 0)
                            $fatal(1, "Defcon received %0d incorrect ROM bytes", data_mismatches);
                        if (banked_miss_count == 0)
                            $fatal(1, "Defcon never requested banked ROM");
                        $display("PASS Defcon cache frame contains visible pixels");
                        $finish;
                    end
                end
                pixel_count = 0;
                nonblack_count = 0;
                nonwhite_count = 0;
                varying_count = 0;
                bus_changes = 0;
            end
            if (debug_pc != last_bus) bus_changes = bus_changes + 1;
            last_bus = debug_pc;
            if (dut.ce && dut.rom_request && dut.cache_ready &&
                dut.rom_di !== rom[dut.mbc_addr]) begin
                if (data_mismatches < 8)
                    $display("ROM MISMATCH bus=%04x mbc=%06x got=%02x expected=%02x",
                             debug_pc, dut.mbc_addr, dut.rom_di,
                             rom[dut.mbc_addr]);
                data_mismatches = data_mismatches + 1;
            end
            if (pixel_valid) begin
                if (pixel_count < 23040)
                    framebuffer[pixel_count] <= pixel_rgb565;
                if (pixel_count == 0) first_pixel = pixel_rgb565;
                else if (pixel_rgb565 != first_pixel)
                    varying_count = varying_count + 1;
                if (pixel_rgb565 != 16'h0000) nonblack_count = nonblack_count + 1;
                if (pixel_rgb565 != 16'hffff) nonwhite_count = nonwhite_count + 1;
                pixel_count = pixel_count + 1;
            end
        end
    end

    initial begin
        rom_path = "C:/tmp/defcon.gbc";
        frame_path = "build/sim/defcon-cache.ppm";
        max_cycles = 200000000;
        target_frames = 120;
        start_press_frame = -1;
        start_release_frame = -1;
        plusarg_seen = $value$plusargs("ROM=%s", rom_path);
        plusarg_seen = $value$plusargs("FRAME=%s", frame_path);
        plusarg_seen = $value$plusargs("MAX_CYCLES=%d", max_cycles);
        plusarg_seen = $value$plusargs("TARGET_FRAMES=%d", target_frames);
        plusarg_seen = $value$plusargs("START_PRESS_FRAME=%d", start_press_frame);
        plusarg_seen = $value$plusargs("START_RELEASE_FRAME=%d", start_release_frame);
        fd = $fopen(rom_path, "rb");
        if (fd == 0) $fatal(1, "cannot open ROM %0s", rom_path);
        size = $fread(rom, fd);
        $fclose(fd);
        if (size != 2097152) $fatal(1, "expected 2 MiB ROM, got %0d", size);

        repeat (20) @(posedge clk);
        for (i = 0; i < 512; i = i + 1)
            host_write_rom_byte(i, rom[i]);
        @(negedge clk);
        reset = 0;
        core_run = 1;

        for (cycles = 0; cycles < max_cycles; cycles = cycles + 1) begin
            @(posedge clk);
            if ((cycles % 10000000) == 0)
                $display("TRACE cycle=%0d pc=%04x lcd=%b pixels=%0d misses=%0d banked=%0d",
                         cycles, debug_pc, lcd_on_debug, pixel_count,
                         miss_count, banked_miss_count);
        end
        $fatal(1, "timeout pc=%04x lcd=%b frames=%0d pixels=%0d misses=%0d banked=%0d",
               debug_pc, lcd_on_debug, frame_count, pixel_count,
               miss_count, banked_miss_count);
    end
endmodule
