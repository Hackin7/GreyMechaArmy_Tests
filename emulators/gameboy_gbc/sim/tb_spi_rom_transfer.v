`timescale 1ns/1ps

// Bit-level integration test for the badge cartridge path.  This drives the
// same SPI bytes and packet order as badge/main.py through gb_spi_phy and
// gb_host_bridge, verifies every cartridge BRAM byte, then boots the ROM.
module tb_spi_rom_transfer;
    localparam OP_RESET     = 8'h01;
    localparam OP_CONFIG    = 8'h02;
    localparam OP_RUN       = 8'h03;
    localparam OP_ROM_WRITE = 8'h10;

    reg clk = 0;
    always #5 clk = ~clk;

    reg reset = 1;
    reg spi_sck = 0;
    reg spi_mosi = 0;
    reg spi_csn = 1;
    wire spi_miso;

    wire [7:0] rx_data;
    wire rx_valid;
    wire [7:0] tx_data;
    wire tx_valid;
    wire tx_ready;
    wire rom_we;
    wire [22:0] rom_addr;
    wire [7:0] rom_data;
    wire fill_begin;
    wire fill_we;
    wire [7:0] fill_offset;
    wire [7:0] fill_data;
    wire fill_commit;
    wire [22:0] fill_address;
    wire core_reset_pulse;
    wire core_run;
    wire gbc_mode;
    wire host_irq;
    wire [7:0] last_sequence;
    wire [3:0] error_code;

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
    reg [15:0] pixel_count = 0;

    reg [7:0] rom [0:32767];
    reg [1023:0] rom_path;
    integer fd;
    integer size;
    integer i;
    integer offset;
    integer packet_sequence_number;
    integer mismatches;
    integer cycles;
    integer max_cycles;
    integer plusarg_seen;

    gb_spi_phy phy (
        .clk(clk), .reset(reset), .spi_sck(spi_sck),
        .spi_mosi(spi_mosi), .spi_csn(spi_csn), .spi_miso(spi_miso),
        .rx_data(rx_data), .rx_valid(rx_valid), .tx_data(tx_data),
        .tx_valid(tx_valid), .tx_ready(tx_ready)
    );

    gb_host_bridge host (
        .clk(clk), .reset(reset), .rx_data(rx_data), .rx_valid(rx_valid),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .cache_miss(cache_miss), .cache_miss_address(cache_miss_address),
        .core_running(running), .lcd_on(lcd_on_debug),
        .lcd_clock(lcd_clock_debug), .pixel_count(pixel_count),
        .debug_pc(debug_pc), .rom_we(rom_we), .rom_addr(rom_addr),
        .rom_data(rom_data), .fill_begin(fill_begin), .fill_we(fill_we),
        .fill_offset(fill_offset), .fill_data(fill_data),
        .fill_commit(fill_commit), .fill_address(fill_address),
        .core_reset_pulse(core_reset_pulse), .core_run(core_run),
        .gbc_mode(gbc_mode), .irq(host_irq),
        .last_sequence(last_sequence), .error_code(error_code)
    );

    gb_core_wrapper #(.BRAM_ROM(1)) core (
        .clk(clk), .reset(reset | core_reset_pulse), .core_run(core_run),
        .gbc_mode(gbc_mode), .buttons(8'd0), .host_rom_we(rom_we),
        .host_rom_addr(rom_addr), .host_rom_data(rom_data),
        .fill_begin(fill_begin), .fill_we(fill_we),
        .fill_offset(fill_offset), .fill_data(fill_data),
        .fill_commit(fill_commit), .fill_address(fill_address),
        .cache_miss(cache_miss), .cache_miss_address(cache_miss_address),
        .pixel_valid(pixel_valid), .pixel_rgb565(pixel_rgb565),
        .lcd_vsync(lcd_vsync), .audio_l(audio_l), .audio_r(audio_r),
        .running(running), .lcd_on_debug(lcd_on_debug),
        .lcd_clock_debug(lcd_clock_debug), .debug_pc(debug_pc),
        .debug_boot_rom(debug_boot_rom)
    );

    always @(posedge clk) begin
        if (reset)
            pixel_count <= 0;
        else if (pixel_valid)
            pixel_count <= pixel_count + 1'b1;
    end

    function automatic [15:0] crc_byte;
        input [15:0] old_crc;
        input [7:0] value;
        integer bit_index;
        reg [15:0] value_crc;
        begin
            value_crc = old_crc ^ {value, 8'h00};
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                value_crc = value_crc[15]
                    ? {value_crc[14:0], 1'b0} ^ 16'h1021
                    : {value_crc[14:0], 1'b0};
            crc_byte = value_crc;
        end
    endfunction

    task spi_byte;
        input [7:0] value;
        integer bit_index;
        begin
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                spi_mosi = value[bit_index];
                // Deliberately avoid an integer relationship with the 10 ns
                // FPGA clock.  Successive SCK edges therefore sweep through
                // core-clock phase instead of receiving ideal alignment.
                #37 spi_sck = 1;
                #43 spi_sck = 0;
            end
        end
    endtask

    task spi_body_byte;
        input [7:0] value;
        inout [15:0] packet_crc;
        begin
            spi_byte(value);
            packet_crc = crc_byte(packet_crc, value);
        end
    endtask

    task send_frame;
        input [7:0] opcode;
        input [7:0] packet_sequence;
        input [31:0] address;
        input integer payload_length;
        input integer rom_offset;
        input [7:0] config_value;
        integer payload_index;
        reg [15:0] packet_crc;
        reg [7:0] payload_value;
        begin
            packet_crc = 16'hffff;
            spi_sck = 0;
            spi_csn = 0;
            repeat (4) @(posedge clk);

            spi_body_byte(8'h47, packet_crc);
            spi_body_byte(8'h01, packet_crc);
            spi_body_byte(opcode, packet_crc);
            spi_body_byte(packet_sequence, packet_crc);
            spi_body_byte(address[7:0], packet_crc);
            spi_body_byte(address[15:8], packet_crc);
            spi_body_byte(address[23:16], packet_crc);
            spi_body_byte(address[31:24], packet_crc);
            spi_body_byte(payload_length[7:0], packet_crc);
            spi_body_byte(payload_length[15:8], packet_crc);

            for (payload_index = 0; payload_index < payload_length;
                 payload_index = payload_index + 1) begin
                payload_value = (opcode == OP_CONFIG)
                    ? config_value : rom[rom_offset + payload_index];
                spi_body_byte(payload_value, packet_crc);
            end

            spi_byte(packet_crc[7:0]);
            spi_byte(packet_crc[15:8]);
            repeat (4) @(posedge clk);
            spi_csn = 1;
            spi_mosi = 0;
            // The badge waits 0.5 ms between packets.  This shorter delay is
            // still longer than the bridge's worst-case 256-cycle commit.
            repeat (300) @(posedge clk);
        end
    endtask

    initial begin
        rom_path = "sim/roms/cgb-acid2.gbc";
        max_cycles = 80000000;
        plusarg_seen = $value$plusargs("ROM=%s", rom_path);
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

        repeat (20) @(posedge clk);
        reset = 0;
        repeat (20) @(posedge clk);

        $display("Transferring %0s through bit-level SPI", rom_path);
        packet_sequence_number = 0;
        send_frame(OP_RESET, packet_sequence_number[7:0], 0, 0, 0, 0);
        packet_sequence_number = packet_sequence_number + 1;
        send_frame(OP_ROM_WRITE, packet_sequence_number[7:0], 0, 256, 0, 0);
        packet_sequence_number = packet_sequence_number + 1;
        send_frame(OP_ROM_WRITE, packet_sequence_number[7:0], 256, 256, 256, 0);
        packet_sequence_number = packet_sequence_number + 1;
        send_frame(OP_CONFIG, packet_sequence_number[7:0], 0, 1, 0, 1);
        packet_sequence_number = packet_sequence_number + 1;

        for (offset = 512; offset < 32768; offset = offset + 256) begin
            send_frame(OP_ROM_WRITE, packet_sequence_number[7:0], offset, 256, offset, 0);
            packet_sequence_number = (packet_sequence_number + 1) & 8'hff;
            if ((offset & 4095) == 0)
                $display("TRACE: transferred %0d/32768 bytes", offset + 256);
        end

        mismatches = 0;
        for (i = 0; i < 32768; i = i + 1) begin
            if (core.rom_bram[i] !== rom[i]) begin
                if (mismatches < 8)
                    $display("MISMATCH: address=%04x expected=%02x actual=%02x",
                             i, rom[i], core.rom_bram[i]);
                mismatches = mismatches + 1;
            end
        end
        if (mismatches != 0) begin
            $display("FAIL: SPI transfer corrupted %0d/32768 cartridge bytes; error=%0d last_seq=%0d",
                     mismatches, error_code, last_sequence);
            $finish(1);
        end
        if (core.image_size != 23'd32768) begin
            $display("FAIL: image_size=%0d, expected 32768", core.image_size);
            $finish(1);
        end
        $display("PASS: all 32768 SPI-transferred cartridge bytes match");

        send_frame(OP_RUN, packet_sequence_number[7:0], 0, 0, 0, 0);
        if (error_code != 0 || last_sequence != packet_sequence_number[7:0] || !core_run) begin
            $display("FAIL: RUN commit error=%0d last_seq=%0d expected_seq=%0d core_run=%b",
                     error_code, last_sequence, packet_sequence_number[7:0], core_run);
            $finish(1);
        end

        for (cycles = 0; cycles < max_cycles; cycles = cycles + 1) begin
            @(posedge clk);
            if (pixel_count != 0) begin
                $display("PASS: SPI-loaded Acid2 produced LCD pixels at cycle %0d pc=%04x boot=%b lcd=%b",
                         cycles, debug_pc, debug_boot_rom, lcd_on_debug);
                $finish;
            end
            if ((cycles % 5000000) == 0)
                $display("TRACE: cycle=%0d pc=%04x boot=%b lcd=%b pixels=%0d",
                         cycles, debug_pc, debug_boot_rom,
                         lcd_on_debug, pixel_count);
        end

        $display("FAIL: SPI-loaded ROM timed out pc=%04x boot=%b lcd=%b pixels=%0d",
                 debug_pc, debug_boot_rom, lcd_on_debug, pixel_count);
        $finish(1);
    end
endmodule
