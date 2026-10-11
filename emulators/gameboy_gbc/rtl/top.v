module top #(
    parameter BRAM_ROM = 1,
    parameter FLASH_ROM = 0,
    parameter FLASH_DIAGNOSTIC = 0,
    parameter PANEL_DIAGNOSTIC = 0
) (
    input wire clk_ext, input wire [4:0] btn,
    input wire btn_grey_n, input wire btn_rst_n,
    output wire [7:0] led, inout wire [7:0] interconnect,
    inout wire [7:0] pmod_j1, inout wire [7:0] pmod_j2,
    output wire oled_scl, output wire oled_sda, output wire oled_dc,
    output wire oled_cs, output wire oled_rst,
    inout wire [4:0] s, output wire buzzer
);
    wire osc_clk, clk_panel, clk_core, pll_locked;
    // The on-chip oscillator is used by the already-working Arduboy port.
    // Do not depend on clk_ext: it is not a reliable clock source here.
    defparam OSCI1.DIV = "6";
    OSCG OSCI1 (.OSC(osc_clk));
    wire unused_clk_ext = clk_ext;
    ecp5_gb_pll pll (.clk_50mhz(osc_clk), .reset(1'b0),
        .clk_75mhz(clk_panel), .clk_core(clk_core), .locked(pll_locked));
    reg [7:0] reset_count = 0;
    reg [1:0] panel_reset_sync = 0;
    wire resetn = &reset_count;
    wire reset = !resetn;
    wire panel_resetn = &panel_reset_sync;
    always @(posedge clk_core) begin
        if (!pll_locked) reset_count <= 0;
        else if (!resetn) reset_count <= reset_count + 1'b1;
    end
    always @(posedge clk_panel) panel_reset_sync <= {panel_reset_sync[0],resetn};

    wire [4:0] bp; wire grey, red;
    btn_debounce #(.WIDTH(5)) db0 (.clk(clk_core),.resetn(resetn),.btn_n(btn),.btn_press(bp));
    btn_debounce #(.WIDTH(1)) db1 (.clk(clk_core),.resetn(resetn),.btn_n(btn_grey_n),.btn_press(grey));
    btn_debounce #(.WIDTH(1)) db2 (.clk(clk_core),.resetn(resetn),.btn_n(btn_rst_n),.btn_press(red));
    wire select_pressed = grey && red;
    wire [7:0] gb_buttons = {bp[2],select_pressed,red && !select_pressed,
        grey && !select_pressed,bp[3],bp[1],bp[0],bp[4]};

    wire [7:0] rx_data, tx_data; wire rx_valid, tx_valid, tx_ready;
    gb_spi_phy phy (.clk(clk_core),.reset(reset),.spi_sck(interconnect[0]),
        .spi_mosi(interconnect[1]),.spi_csn(interconnect[3]),
        .spi_miso(interconnect[2]),.rx_data(rx_data),.rx_valid(rx_valid),
        .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready));

    wire rom_we; wire [22:0] rom_addr; wire [7:0] rom_data;
    wire host_fill_begin,host_fill_we,host_fill_commit;
    wire [7:0] host_fill_offset,host_fill_data;
    wire [22:0] host_fill_address;
    wire fill_begin,fill_we,fill_commit; wire [7:0] fill_offset,fill_data;
    wire [22:0] fill_address; wire core_reset_pulse,core_run,gbc_mode;
    wire host_irq; wire [7:0] last_sequence; wire [3:0] error_code;
    wire cache_miss; wire [22:0] cache_miss_address;
    reg flash_diag_start;
    reg flash_diag_started;
    reg flash_diag_done;
    reg flash_diag_failed;
    reg flash_diag_all_ff;
    reg flash_diag_all_zero;
    reg [8:0] flash_diag_count;
    reg [22:0] flash_diag_sample;
    reg [15:0] pixel_count;
    always @(posedge clk_core) begin
        if (reset) pixel_count <= 0;
        else if (pixel_valid) pixel_count <= pixel_count + 1'b1;
    end
    gb_host_bridge host (.clk(clk_core),.reset(reset),.rx_data(rx_data),.rx_valid(rx_valid),
        .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready),
        .cache_miss(FLASH_DIAGNOSTIC ? flash_diag_done : cache_miss),
        .cache_miss_address(FLASH_DIAGNOSTIC
            ? flash_diag_sample : cache_miss_address),
        .core_running(running),.lcd_on(lcd_on_debug),.lcd_clock(lcd_clock_debug),
        .pixel_count(pixel_count),.debug_pc(debug_pc),
        .rom_we(rom_we),.rom_addr(rom_addr),.rom_data(rom_data),
        .fill_begin(host_fill_begin),.fill_we(host_fill_we),
        .fill_offset(host_fill_offset),.fill_data(host_fill_data),
        .fill_commit(host_fill_commit),.fill_address(host_fill_address),
        .core_reset_pulse(core_reset_pulse),.core_run(core_run),.gbc_mode(gbc_mode),
        .irq(host_irq),.last_sequence(last_sequence),.error_code(error_code));

    wire flash_busy;
    wire flash_fill_begin,flash_fill_we,flash_fill_commit;
    wire [7:0] flash_fill_offset,flash_fill_data;
    wire [22:0] flash_fill_address;
    wire flash_clk,flash_cs_n,flash_mosi;
    wire flash_miso = s[2];

    always @(posedge clk_core) begin
        if (reset) begin
            flash_diag_start <= 1'b0;
            flash_diag_started <= 1'b0;
            flash_diag_done <= 1'b0;
            flash_diag_failed <= 1'b0;
            flash_diag_all_ff <= 1'b1;
            flash_diag_all_zero <= 1'b1;
            flash_diag_count <= 9'd0;
            flash_diag_sample <= 23'd0;
        end else begin
            flash_diag_start <= 1'b0;
            if (FLASH_DIAGNOSTIC && !flash_diag_started) begin
                flash_diag_start <= 1'b1;
                flash_diag_started <= 1'b1;
            end
            if (FLASH_DIAGNOSTIC && flash_fill_we) begin
                flash_diag_count <= flash_diag_count + 1'b1;
                if (flash_fill_data != 8'hff)
                    flash_diag_all_ff <= 1'b0;
                if (flash_fill_data != 8'h00)
                    flash_diag_all_zero <= 1'b0;
                if (flash_fill_offset == 8'h04)
                    flash_diag_sample[7:0] <= flash_fill_data;
                if (flash_fill_offset == 8'h05)
                    flash_diag_sample[15:8] <= flash_fill_data;
                if (flash_fill_offset == 8'h06)
                    flash_diag_sample[22:16] <= flash_fill_data[6:0];
                case (flash_fill_offset)
                    8'h04: if (flash_fill_data != 8'hce) flash_diag_failed <= 1'b1;
                    8'h05: if (flash_fill_data != 8'hed) flash_diag_failed <= 1'b1;
                    8'h06: if (flash_fill_data != 8'h66) flash_diag_failed <= 1'b1;
                    8'h07: if (flash_fill_data != 8'h66) flash_diag_failed <= 1'b1;
                    8'h08: if (flash_fill_data != 8'hcc) flash_diag_failed <= 1'b1;
                    8'h09: if (flash_fill_data != 8'h0d) flash_diag_failed <= 1'b1;
                    8'h0a: if (flash_fill_data != 8'h00) flash_diag_failed <= 1'b1;
                    8'h0b: if (flash_fill_data != 8'h0b) flash_diag_failed <= 1'b1;
                    8'h34: if (flash_fill_data != 8'h44) flash_diag_failed <= 1'b1;
                    8'h35: if (flash_fill_data != 8'h45) flash_diag_failed <= 1'b1;
                    8'h36: if (flash_fill_data != 8'h46) flash_diag_failed <= 1'b1;
                    8'h37: if (flash_fill_data != 8'h43) flash_diag_failed <= 1'b1;
                    8'h38: if (flash_fill_data != 8'h4f) flash_diag_failed <= 1'b1;
                    8'h39: if (flash_fill_data != 8'h4e) flash_diag_failed <= 1'b1;
                    8'h3a: if (flash_fill_data != 8'h42) flash_diag_failed <= 1'b1;
                    8'h3b: if (flash_fill_data != 8'h41) flash_diag_failed <= 1'b1;
                    default: begin end
                endcase
            end
            if (FLASH_DIAGNOSTIC && flash_fill_commit) begin
                flash_diag_done <= 1'b1;
                if (flash_diag_count != 9'd255)
                    flash_diag_failed <= 1'b1;
            end
        end
    end

    generate if (FLASH_ROM) begin : flash_backend
        ecp5_flash_reader reader (
            .clk(clk_core),.reset(reset),
            .start(FLASH_DIAGNOSTIC ? flash_diag_start : cache_miss),
            .line_address(FLASH_DIAGNOSTIC ? 23'h000100 : cache_miss_address),
            .busy(flash_busy),
            .fill_begin(flash_fill_begin),.fill_address(flash_fill_address),
            .fill_we(flash_fill_we),.fill_offset(flash_fill_offset),
            .fill_data(flash_fill_data),.fill_commit(flash_fill_commit),
            .flash_clk(flash_clk),
            .flash_cs_n(flash_cs_n),.flash_mosi(flash_mosi),
            .flash_miso(flash_miso));
        // USRMCLKTS is reset-controlled rather than tied to a constant as
        // required by the ECP5 user-mode sysCONFIG interface.
        USRMCLK flash_clock (
            .USRMCLKI(flash_clk),.USRMCLKTS(reset));
        assign s[0] = flash_cs_n;
        assign s[1] = flash_mosi;
        // s[2]/T7 is intentionally undriven: as a top-level inout this makes
        // it a real input from the flash DO pin.  An explicit `1'bz` here is
        // propagated as a constant by Yosys instead of inferring input mode.
    end else begin : no_flash_backend
        assign flash_busy = 1'b0;
        assign flash_fill_begin = 1'b0;
        assign flash_fill_we = 1'b0;
        assign flash_fill_commit = 1'b0;
        assign flash_fill_offset = 8'd0;
        assign flash_fill_data = 8'hff;
        assign flash_fill_address = 23'd0;
        assign flash_clk = 1'b0;
        assign flash_cs_n = 1'b1;
        assign flash_mosi = 1'b0;
        assign s[2:0] = 3'bzzz;
    end endgenerate

    assign fill_begin = FLASH_ROM ? flash_fill_begin : host_fill_begin;
    assign fill_we = FLASH_ROM ? flash_fill_we : host_fill_we;
    assign fill_commit = FLASH_ROM ? flash_fill_commit : host_fill_commit;
    assign fill_offset = FLASH_ROM ? flash_fill_offset : host_fill_offset;
    assign fill_data = FLASH_ROM ? flash_fill_data : host_fill_data;
    assign fill_address = FLASH_ROM ? flash_fill_address : host_fill_address;

    wire pixel_valid,frame_sync,lcd_on_debug,lcd_clock_debug; wire [15:0] pixel_rgb565,audio_l,audio_r,debug_pc;
    wire running;
    gb_core_wrapper #(.BRAM_ROM(BRAM_ROM)) gameboy (
        .clk(clk_core),.reset(reset | core_reset_pulse),.core_run(core_run),
        .gbc_mode(gbc_mode),.buttons(gb_buttons),.host_rom_we(rom_we),
        .host_rom_addr(rom_addr),.host_rom_data(rom_data),
        .fill_begin(fill_begin),.fill_we(fill_we),.fill_offset(fill_offset),
        .fill_data(fill_data),.fill_commit(fill_commit),.fill_address(fill_address),
        .cache_miss(cache_miss),.cache_miss_address(cache_miss_address),
        .pixel_valid(pixel_valid),.pixel_rgb565(pixel_rgb565),
        .lcd_vsync(frame_sync),.audio_l(audio_l),.audio_r(audio_r),.running(running),
        .lcd_on_debug(lcd_on_debug),.lcd_clock_debug(lcd_clock_debug),
        .debug_pc(debug_pc),.debug_boot_rom());

    wire line_ready,line_bank,line_done,rd_bank,overflow;
    wire [7:0] line_number,rd_addr; wire [15:0] rd_data;
    gb_line_capture lines (.core_clk(clk_core),.core_reset(reset),
        .pixel_valid(pixel_valid),.pixel_rgb565(pixel_rgb565),.frame_sync(frame_sync),
        .panel_clk(clk_panel),.panel_reset(!panel_resetn),.panel_rd_addr(rd_addr),
        .panel_rd_bank(rd_bank),.panel_rd_data(rd_data),.panel_line_ready(line_ready),
        .panel_line_bank(line_bank),.panel_line_number(line_number),
        .panel_line_done(line_done),.overflow(overflow));
    generate if (PANEL_DIAGNOSTIC) begin : panel_diagnostic
        wire [15:0] diag_pixel_index;
        wire [15:0] diag_pixel_rgb =
            FLASH_DIAGNOSTIC
                ? (!flash_diag_done ? 16'h0000 :
                    (!flash_diag_failed ? 16'h07e0 :
                     flash_diag_all_ff ? 16'hf81f :
                     flash_diag_all_zero ? 16'hffe0 : 16'hffff))
                : (diag_pixel_index[5] ? 16'hf800 : 16'h07e0);
        oled_gc9a01 #(.CLK_HZ(75000000), .INIT_SPI_CLK_DIV(8'd4), .SWAP_RB(1'b0)) diag (
            .clk(clk_panel), .resetn(panel_resetn), .pixel_index(diag_pixel_index),
            .pixel_data(diag_pixel_rgb), .oled_scl(oled_scl), .oled_sda(oled_sda),
            .oled_dc(oled_dc), .oled_cs(oled_cs), .oled_rst(oled_rst),
            .init_done(), .streaming()
        );
    end else begin : panel_gameboy
        gc9a01_native display (.clk(clk_panel),.resetn(panel_resetn),
            .line_ready(line_ready),.line_bank(line_bank),.line_number(line_number),
            .line_done(line_done),.rd_addr(rd_addr),.rd_bank(rd_bank),.rd_data(rd_data),
            .sclk(oled_scl),.mosi(oled_sda),.dc(oled_dc),.cs_n(oled_cs),.rst_n(oled_rst));
    end endgenerate

    reg [16:0] audio_acc = 0;
    wire [15:0] audio_mix = {1'b0,audio_l[15:1]} + {1'b0,audio_r[15:1]};
    always @(posedge clk_core) audio_acc <= audio_acc[15:0] + audio_mix;
    assign buzzer = audio_acc[16];
    assign interconnect[4] = 1'bz;
    assign interconnect[5] = host_irq | (cache_miss && !FLASH_ROM);
    assign interconnect[6] = 1'bz; assign interconnect[7] = 1'bz;
    assign pmod_j1 = 8'hzz; assign pmod_j2 = 8'hzz;
    assign s[4:3] = 2'bzz;
    assign led = FLASH_DIAGNOSTIC
        ? {flash_diag_failed,flash_diag_done,flash_diag_count[5:0]}
        : {last_sequence[3:0],overflow,cache_miss,running,pll_locked};
endmodule
