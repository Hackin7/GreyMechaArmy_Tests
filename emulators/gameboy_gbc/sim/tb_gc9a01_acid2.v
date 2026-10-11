`timescale 1ns/1ps

// Panel-level visual test.  Acid2 runs in the Game Boy core, passes through
// gb_line_capture and gc9a01_native, and is reconstructed solely from the
// serial GC9A01 pins into both a 160x144 window and a 240x240 panel image.
module tb_gc9a01_acid2;
    reg core_clk = 0;
    reg panel_clk = 0;
    always #5 core_clk = ~core_clk;
    // Keep the panel consumer comfortably faster than the accelerated core
    // used by this functional simulation.
    always #1 panel_clk = ~panel_clk;

    reg reset = 1;
    reg panel_resetn = 0;
    reg core_run = 0;
    reg gbc_mode = 1;
    reg host_rom_we = 0;
    reg [22:0] host_rom_addr = 0;
    reg [7:0] host_rom_data = 0;

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
    wire cache_miss;
    wire [22:0] cache_miss_address;

    wire line_ready;
    wire line_bank;
    wire [7:0] line_number;
    wire line_done;
    wire [7:0] rd_addr;
    wire rd_bank;
    wire [15:0] rd_data;
    wire overflow;

    wire panel_sclk;
    wire panel_mosi;
    wire panel_dc;
    wire panel_cs_n;
    wire panel_rst_n;

    reg [7:0] rom [0:32767];
    reg [15:0] panel_window [0:23039];
    reg [7:0] serial_shift = 0;
    reg [2:0] serial_bit_count = 0;
    reg [7:0] pixel_high = 0;
    reg pixel_low_next = 0;
    reg ram_write_active = 0;
    reg transaction_started_postboot = 0;
    integer panel_pixel_count = 0;
    integer complete_panel_frames = 0;
    integer complete_postboot_frames = 0;
    integer incomplete_transactions = 0;

    reg [1023:0] rom_path;
    reg [1023:0] window_path;
    reg [1023:0] panel_path;
    integer fd;
    integer size;
    integer i;
    integer x;
    integer y;
    integer source_index;
    integer cycles;
    integer max_cycles;
    integer plusarg_seen;
    integer r5;
    integer g5;
    integer b5;
    integer r8;
    integer g8;
    integer b8;
    reg [15:0] output_pixel;
    reg [7:0] received_byte;

    gb_core_wrapper #(.BRAM_ROM(1)) core (
        .clk(core_clk), .reset(reset), .core_run(core_run),
        .gbc_mode(gbc_mode), .buttons(8'd0),
        .host_rom_we(host_rom_we), .host_rom_addr(host_rom_addr),
        .host_rom_data(host_rom_data), .fill_begin(1'b0),
        .fill_we(1'b0), .fill_offset(8'd0), .fill_data(8'd0),
        .fill_commit(1'b0), .fill_address(23'd0),
        .cache_miss(cache_miss), .cache_miss_address(cache_miss_address),
        .pixel_valid(pixel_valid), .pixel_rgb565(pixel_rgb565),
        .lcd_vsync(lcd_vsync), .audio_l(audio_l), .audio_r(audio_r),
        .running(running), .lcd_on_debug(lcd_on_debug),
        .lcd_clock_debug(lcd_clock_debug), .debug_pc(debug_pc),
        .debug_boot_rom(debug_boot_rom)
    );

    gb_line_capture lines (
        .core_clk(core_clk), .core_reset(reset),
        .pixel_valid(pixel_valid), .pixel_rgb565(pixel_rgb565),
        .frame_sync(lcd_vsync), .panel_clk(panel_clk),
        .panel_reset(!panel_resetn), .panel_rd_addr(rd_addr),
        .panel_rd_bank(rd_bank), .panel_rd_data(rd_data),
        .panel_line_ready(line_ready), .panel_line_bank(line_bank),
        .panel_line_number(line_number), .panel_line_done(line_done),
        .overflow(overflow)
    );

    gc9a01_native display (
        .clk(panel_clk), .resetn(panel_resetn), .line_ready(line_ready),
        .line_bank(line_bank), .line_number(line_number),
        .line_done(line_done), .rd_addr(rd_addr), .rd_bank(rd_bank),
        .rd_data(rd_data), .sclk(panel_sclk), .mosi(panel_mosi),
        .dc(panel_dc), .cs_n(panel_cs_n), .rst_n(panel_rst_n)
    );

    task host_write_rom_byte;
        input [22:0] address;
        input [7:0] value;
        begin
            @(negedge core_clk);
            host_rom_addr = address;
            host_rom_data = value;
            host_rom_we = 1;
            @(negedge core_clk);
            host_rom_we = 0;
        end
    endtask

    task write_rgb;
        input integer output_fd;
        input [15:0] value;
        begin
            r5 = value[15:11];
            g5 = value[10:6];
            b5 = value[4:0];
            r8 = (r5 << 3) | (r5 >> 2);
            g8 = (g5 << 3) | (g5 >> 2);
            b8 = (b5 << 3) | (b5 >> 2);
            $fwrite(output_fd, "%c%c%c", r8[7:0], g8[7:0], b8[7:0]);
        end
    endtask

    task write_panel_images;
        begin
            fd = $fopen(window_path, "wb");
            if (fd == 0) begin
                $display("FAIL: cannot create %0s", window_path);
                $finish(1);
            end
            $fwrite(fd, "P6\n160 144\n255\n");
            for (i = 0; i < 23040; i = i + 1)
                write_rgb(fd, panel_window[i]);
            $fclose(fd);

            fd = $fopen(panel_path, "wb");
            if (fd == 0) begin
                $display("FAIL: cannot create %0s", panel_path);
                $finish(1);
            end
            $fwrite(fd, "P6\n240 240\n255\n");
            for (y = 0; y < 240; y = y + 1) begin
                for (x = 0; x < 240; x = x + 1) begin
                    if (x >= 40 && x < 200 && y >= 48 && y < 192) begin
                        source_index = (y - 48) * 160 + (x - 40);
                        output_pixel = panel_window[source_index];
                    end else begin
                        output_pixel = 16'hffff;
                    end
                    write_rgb(fd, output_pixel);
                end
            end
            $fclose(fd);
            $display("PASS: decoded GC9A01 frame to %0s and %0s",
                     window_path, panel_path);
        end
    endtask

    // Decode only the physical serial outputs.  A command byte of 2C starts
    // a RAM write; subsequent DC=1 bytes are paired into RGB565 pixels.
    always @(posedge panel_sclk) begin
        if (!panel_cs_n) begin
            serial_shift = {serial_shift[6:0], panel_mosi};
            if (serial_bit_count == 3'd7) begin
                received_byte = serial_shift;
                serial_bit_count = 0;
                if (!panel_dc) begin
                    if (received_byte == 8'h2c) begin
                        if (ram_write_active && panel_pixel_count != 0 &&
                            panel_pixel_count != 23040) begin
                            incomplete_transactions = incomplete_transactions + 1;
                            $display("TRACE: incomplete RAMWR contained %0d pixels",
                                     panel_pixel_count);
                        end
                        ram_write_active = 1;
                        panel_pixel_count = 0;
                        pixel_low_next = 0;
                        transaction_started_postboot = !debug_boot_rom;
                    end else begin
                        ram_write_active = 0;
                        pixel_low_next = 0;
                    end
                end else if (ram_write_active) begin
                    if (!pixel_low_next) begin
                        pixel_high = received_byte;
                        pixel_low_next = 1;
                    end else begin
                        // Model the badge panel's BGR interpretation, not
                        // merely the raw wire word. This property is fixed
                        // independently of the serializer's SWAP_RB setting.
                        if (panel_pixel_count < 23040)
                            panel_window[panel_pixel_count] =
                                {received_byte[4:0], pixel_high[2:0],
                                 received_byte[7:5], pixel_high[7:3]};
                        panel_pixel_count = panel_pixel_count + 1;
                        pixel_low_next = 0;
                        if (panel_pixel_count == 23040) begin
                            complete_panel_frames = complete_panel_frames + 1;
                            if (transaction_started_postboot) begin
                                complete_postboot_frames =
                                    complete_postboot_frames + 1;
                                $display("TRACE: complete post-boot panel frame %0d",
                                         complete_postboot_frames);
                                if (complete_postboot_frames == 5) begin
                                    write_panel_images();
                                    $finish;
                                end
                            end
                        end
                    end
                end
            end else begin
                serial_bit_count = serial_bit_count + 1'b1;
            end
        end
    end

    always @(posedge panel_cs_n)
        serial_bit_count = 0;

    initial begin
        rom_path = "sim/roms/cgb-acid2.gbc";
        window_path = "build/sim/cgb-acid2-panel-window.ppm";
        panel_path = "build/sim/cgb-acid2-panel-240.ppm";
        max_cycles = 80000000;
        plusarg_seen = $value$plusargs("ROM=%s", rom_path);
        plusarg_seen = $value$plusargs("WINDOW=%s", window_path);
        plusarg_seen = $value$plusargs("PANEL=%s", panel_path);
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

        for (i = 0; i < 32768; i = i + 1)
            core.rom_bram[i] = rom[i];
        repeat (20) @(posedge core_clk);
        for (i = 16'h0100; i < 16'h0150; i = i + 1)
            host_write_rom_byte(i, rom[i]);
        host_write_rom_byte(23'd32767, rom[32767]);

        @(negedge core_clk);
        reset = 0;
        panel_resetn = 1;
        core_run = 1;
        $display("Running Acid2 through GC9A01 serial output");

        for (cycles = 0; cycles < max_cycles; cycles = cycles + 1) begin
            @(posedge core_clk);
            if ((cycles % 5000000) == 0)
                $display("TRACE: cycle=%0d pc=%04x boot=%b lcd=%b panel_frames=%0d incomplete=%0d overflow=%b",
                         cycles, debug_pc, debug_boot_rom, lcd_on_debug,
                         complete_panel_frames, incomplete_transactions,
                         overflow);
        end

        $display("FAIL: panel timeout pc=%04x boot=%b lcd=%b panel_frames=%0d postboot=%0d incomplete=%0d overflow=%b",
                 debug_pc, debug_boot_rom, lcd_on_debug,
                 complete_panel_frames, complete_postboot_frames,
                 incomplete_transactions, overflow);
        $finish(1);
    end
endmodule
