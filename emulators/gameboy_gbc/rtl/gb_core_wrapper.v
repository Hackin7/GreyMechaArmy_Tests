module gb_core_wrapper #(
    parameter BRAM_ROM = 1,
    parameter CACHE_SET_BITS = 5
) (
    input wire clk, input wire reset, input wire core_run, input wire gbc_mode,
    input wire [7:0] buttons,
    input wire host_rom_we, input wire [22:0] host_rom_addr,
    input wire [7:0] host_rom_data,
    input wire fill_begin, input wire fill_we, input wire [7:0] fill_offset,
    input wire [7:0] fill_data, input wire fill_commit,
    input wire [22:0] fill_address,
    output wire cache_miss, output wire [22:0] cache_miss_address,
    output wire pixel_valid, output wire [15:0] pixel_rgb565,
    output wire lcd_vsync, output wire [15:0] audio_l,
    output wire [15:0] audio_r, output wire running,
    output wire lcd_on_debug, output wire lcd_clock_debug,
    output wire [15:0] debug_pc, output wire debug_boot_rom
);
    wire core_reset = reset || !core_run;
    wire ce, ce_n, ce_2x;
    wire speed;
    wire [14:0] cart_addr;
    wire cart_a15, cart_rd, cart_wr, cart_oe, nCS;
    wire [7:0] cart_do, cart_di;
    wire [22:0] mbc_addr;
    wire [7:0] rom_di;
    wire rom_request = cart_rd && cart_oe;
    wire cache_ready;
    wire [7:0] cache_data;
    wire cache_stall = (BRAM_ROM == 0) && rom_request && !cache_ready;
    assign running = core_run && !cache_stall;

    gb_clock_enable clocks (
        .clk(clk), .reset(core_reset), .enable(core_run && !cache_stall),
        .ce(ce), .ce_n(ce_n), .ce_2x(ce_2x)
    );

    reg [7:0] rom_bram [0:32767];
    reg [7:0] rom_bram_q;
    reg [22:0] image_size;
    always @(posedge clk) begin
        rom_bram_q <= rom_bram[mbc_addr[14:0]];
        if (reset) image_size <= 0;
        else if (host_rom_we) begin
            if (host_rom_addr < 23'd32768) rom_bram[host_rom_addr[14:0]] <= host_rom_data;
            if (host_rom_addr >= image_size) image_size <= host_rom_addr + 1'b1;
        end
    end

    generate if (BRAM_ROM == 0) begin : cache_path
        gb_rom_cache #(.CACHE_SET_BITS(CACHE_SET_BITS)) cache (
            .clk(clk), .reset(reset), .request(rom_request), .address(mbc_addr),
            .data(cache_data), .ready(cache_ready), .miss_request(cache_miss),
            .miss_address(cache_miss_address), .fill_begin(fill_begin),
            .fill_address(fill_address), .fill_we(fill_we),
            .fill_offset(fill_offset), .fill_data(fill_data),
            .fill_commit(fill_commit)
        );
        assign rom_di = cache_data;
    end else begin : bram_path
        assign cache_ready = 1'b1;
        assign cache_miss = 1'b0;
        assign cache_miss_address = 23'd0;
        assign rom_di = rom_bram_q;
    end endgenerate

    reg [7:0] even_byte;
    reg ioctl_wr;
    reg [24:0] ioctl_addr;
    reg [15:0] ioctl_dout;
    always @(posedge clk) begin
        ioctl_wr <= 1'b0;
        if (host_rom_we) begin
            if (!host_rom_addr[0]) even_byte <= host_rom_data;
            else begin
                ioctl_addr <= {2'b00, host_rom_addr[22:1], 1'b0};
                ioctl_dout <= {host_rom_data, even_byte};
                ioctl_wr <= 1'b1;
            end
        end
    end

    wire [1:0] joy_p54;
    wire [3:0] joy_dpad = ~{buttons[3],buttons[2],buttons[1],buttons[0]};
    wire [3:0] joy_keys = ~{buttons[7],buttons[6],buttons[5],buttons[4]};
    wire [3:0] joy_din = (joy_p54[0] ? 4'hf : joy_dpad) &
                         (joy_p54[1] ? 4'hf : joy_keys);

    wire lcd_clkena;
    wire [14:0] lcd_data;
    wire [1:0] lcd_data_gb, lcd_mode;
    wire lcd_on;
    assign pixel_valid = ce && lcd_clkena && lcd_on;
    assign lcd_on_debug = lcd_on;
    assign lcd_clock_debug = lcd_clkena;
    wire [15:0] core_debug_pc;
    wire core_debug_boot_rom;
    assign debug_pc = core_debug_pc;
    assign debug_boot_rom = core_debug_boot_rom;
    assign pixel_rgb565 = {lcd_data[4:0], lcd_data[9:5], lcd_data[9], lcd_data[14:10]};

    wire [63:0] ss_din, ss_dout;
    wire [9:0] ss_adr;
    wire ss_wren, ss_rst, ss_load, ss_ovr;
    wire [19:0] ss_cram_addr;
    wire ss_cram_rd, ss_cram_wr;
    wire [15:0] ss_cram_write, ss_cram_q;
    wire [7:0] cart_ram_size;
    wire is_gbc_game, is_sgb_game;
    wire cram_rd, cram_wr, cram_bram_wr, is_cram_addr;
    wire [16:0] cram_addr;
    wire [15:0] bk_q;
    reg ce_32k;
    reg [24:0] rtc_phase = 0;
    always @(posedge clk) begin
        ce_32k <= 0;
        if (rtc_phase + 25'd32768 >= 25'd32000000) begin
            rtc_phase <= rtc_phase + 25'd32768 - 25'd32000000;
            ce_32k <= 1;
        end else rtc_phase <= rtc_phase + 25'd32768;
    end

    cart_top cart (
        .reset(core_reset), .clk_sys(clk), .ce_cpu(ce), .ce_cpu2x(ce_2x),
        .speed(speed), .megaduck(1'b0), .duck_md0_mode(1'b0), .mapper_sel(3'd0),
        .cart_addr(cart_addr), .cart_a15(cart_a15), .cart_rd(cart_rd),
        .cart_wr(cart_wr), .cart_do(cart_do), .cart_di(cart_di), .cart_oe(cart_oe),
        .nCS(nCS), .mbc_addr(mbc_addr), .dn_write(), .cart_ready(),
        .is_cram_addr(is_cram_addr), .cram_rd(cram_rd), .cram_wr(cram_wr),
        .cram_bram_wr(cram_bram_wr), .cram_addr(cram_addr),
        .cart_download(!core_run), .ram_mask_file(), .ram_size(cart_ram_size),
        .has_save(), .bram_save(), .isGBC_game(is_gbc_game), .isSGB_game(is_sgb_game),
        .ioctl_download(!core_run), .ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout), .ioctl_wait(), .bk_wr(1'b0), .bk_rtc_wr(1'b0),
        .bk_addr(17'd0), .bk_data(16'd0), .bk_q(bk_q), .img_size({41'd0,image_size}),
        .rom_di(rom_di), .joystick_analog_0(16'd0), .ce_32k(ce_32k),
        .RTC_time(33'd0), .RTC_timestampOut(), .RTC_savedtimeOut(), .RTC_inuse(),
        .SaveStateExt_Din(ss_din), .SaveStateExt_Adr(ss_adr),
        .SaveStateExt_wren(ss_wren), .SaveStateExt_rst(ss_rst),
        .SaveStateExt_Dout(ss_dout), .savestate_load(ss_load),
        .savestate_ovr(ss_ovr), .Savestate_CRAMAddr(ss_cram_addr),
        .Savestate_CRAMRWrEn(ss_cram_wr), .Savestate_CRAMWriteData(ss_cram_write),
        .Savestate_CRAM_Q(ss_cram_q), .rumbling()
    );

    gb core (
        .reset(core_reset), .clk_sys(clk), .ce(ce), .ce_n(ce_n), .ce_2x(ce_2x),
        .joystick(buttons), .isGBC(gbc_mode), .real_cgb_boot(1'b0),
        .isSGB(1'b0), .extra_spr_en(1'b0), .ext_bus_addr(cart_addr),
        .ext_bus_a15(cart_a15), .cart_rd(cart_rd), .cart_wr(cart_wr),
        .cart_do(cart_do), .cart_di(cart_di), .cart_oe(cart_oe), .nCS(nCS),
        .PHI(), .sdram_rd(), .cgb_boot_download(1'b0), .dmg_boot_download(1'b0),
        .sgb_boot_download(1'b0), .ioctl_wr(1'b0), .ioctl_addr(25'd0),
        .ioctl_dout(16'd0), .boot_gba_en(1'b0), .fast_boot_en(1'b1),
        .audio_l(audio_l), .audio_r(audio_r), .audio_no_pops(1'b1),
        .megaduck(1'b0), .lcd_clkena(lcd_clkena), .lcd_data(lcd_data),
        .lcd_data_gb(lcd_data_gb), .lcd_mode(lcd_mode), .lcd_on(lcd_on),
        .lcd_vsync(lcd_vsync), .joy_p54(joy_p54), .joy_din(joy_din),
        .speed(speed), .DMA_on(), .gg_reset(1'b0), .gg_en(1'b0),
        .gg_code(129'd0), .gg_available(), .sc_int_clock2(),
        .serial_clk_in(1'b1), .serial_clk_out(), .serial_data_in(1'b1),
        .serial_data_out(), .increaseSSHeaderCount(1'b0),
        .cart_ram_size(cart_ram_size), .save_state(1'b0), .load_state(1'b0),
        .savestate_number(2'd0), .sleep_savestate(), .savestate_ovr(ss_ovr),
        .SaveStateExt_Din(ss_din), .SaveStateExt_Adr(ss_adr),
        .SaveStateExt_wren(ss_wren), .SaveStateExt_rst(ss_rst),
        .SaveStateExt_Dout(ss_dout), .SaveStateExt_load(ss_load),
        .Savestate_CRAMAddr(ss_cram_addr), .Savestate_CRAMRdEn(ss_cram_rd),
        .Savestate_CRAMRWrEn(ss_cram_wr), .Savestate_CRAMWriteData(ss_cram_write),
        .Savestate_CRAMReadData(ss_cram_q), .SAVE_out_Din(), .SAVE_out_Dout(64'd0),
        .SAVE_out_Adr(), .SAVE_out_rnw(), .SAVE_out_ena(), .SAVE_out_be(),
        .SAVE_out_done(1'b0), .savestate_sdram_busy(1'b0),
        .rewind_on(1'b0), .rewind_active(1'b0),
        .debug_cpu_addr(core_debug_pc), .debug_boot_rom_enabled(core_debug_boot_rom)
    );
endmodule
