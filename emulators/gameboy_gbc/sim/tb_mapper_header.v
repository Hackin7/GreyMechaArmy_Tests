`timescale 1ns/1ps

// Cache mode uploads only the cartridge header through ioctl. Verify that the
// header alone initializes MBC banking and that a bank selection reaches the
// corresponding physical ROM address.
module tb_mapper_header;
    reg clk = 0;
    always #5 clk = ~clk;

    reg reset = 1;
    reg ce_cpu = 0;
    reg [14:0] cart_addr = 0;
    reg cart_a15 = 0;
    reg cart_rd = 0;
    reg cart_wr = 0;
    reg [7:0] cart_di = 0;
    reg nCS = 1;
    reg cart_download = 0;
    reg ioctl_wr = 0;
    reg [24:0] ioctl_addr = 0;
    reg [15:0] ioctl_dout = 0;

    wire [7:0] cart_do;
    wire cart_oe;
    wire [22:0] mbc_addr;
    wire [7:0] ram_size;

    cart_top dut (
        .reset(reset), .clk_sys(clk), .ce_cpu(ce_cpu), .ce_cpu2x(ce_cpu),
        .speed(1'b0), .megaduck(1'b0), .duck_md0_mode(1'b0),
        .mapper_sel(3'd0), .cart_addr(cart_addr), .cart_a15(cart_a15),
        .cart_rd(cart_rd), .cart_wr(cart_wr), .cart_do(cart_do),
        .cart_di(cart_di), .cart_oe(cart_oe), .nCS(nCS),
        .mbc_addr(mbc_addr), .dn_write(), .cart_ready(),
        .is_cram_addr(), .cram_rd(), .cram_wr(), .cram_bram_wr(),
        .cram_addr(), .cart_download(cart_download), .ram_mask_file(),
        .ram_size(ram_size), .has_save(), .bram_save(), .isGBC_game(),
        .isSGB_game(), .ioctl_download(cart_download), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout), .ioctl_wait(),
        .bk_wr(1'b0), .bk_rtc_wr(1'b0), .bk_addr(17'd0),
        .bk_data(16'd0), .bk_q(), .img_size(64'd2097152),
        .rom_di(8'hA5), .joystick_analog_0(16'd0), .ce_32k(1'b0),
        .RTC_time(33'd0), .RTC_timestampOut(), .RTC_savedtimeOut(),
        .RTC_inuse(), .SaveStateExt_Din(64'd0), .SaveStateExt_Adr(10'd0),
        .SaveStateExt_wren(1'b0), .SaveStateExt_rst(1'b0),
        .SaveStateExt_Dout(), .savestate_load(1'b0),
        .savestate_ovr(1'b0), .Savestate_CRAMAddr(20'd0),
        .Savestate_CRAMRWrEn(1'b0), .Savestate_CRAMWriteData(16'd0),
        .Savestate_CRAM_Q(), .rumbling()
    );

    task header_word(input [24:0] address, input [15:0] value);
        begin
            @(negedge clk);
            ioctl_addr = address;
            ioctl_dout = value;
            ioctl_wr = 1;
            @(negedge clk);
            ioctl_wr = 0;
        end
    endtask

    task cpu_write(input a15, input cs_n, input [14:0] address,
                   input [7:0] value);
        begin
            @(negedge clk);
            cart_a15 = a15;
            nCS = cs_n;
            cart_addr = address;
            cart_di = value;
            cart_wr = 1;
            ce_cpu = 1;
            @(negedge clk);
            cart_wr = 0;
            ce_cpu = 0;
        end
    endtask

    task expect_ram(input [7:0] expected);
        begin
            @(negedge clk);
            cart_a15 = 1;
            nCS = 0;
            cart_addr = 15'h2000;
            cart_rd = 1;
            repeat (2) @(posedge clk);
            #1;
            if (cart_do !== expected)
                $fatal(1, "cartridge RAM read %h, expected %h addr=%h q=%h enable=%b cram_wr=%b bram_wr=%b",
                       cart_do, expected, dut.cram_addr, dut.cram_q,
                       dut.mbc_ram_enable, dut.cram_wr, dut.cram_bram_wr);
            @(negedge clk);
            cart_rd = 0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        reset = 0;
        cart_download = 1;
        repeat (2) @(posedge clk);

        header_word(25'h00142, 16'hC000); // CGB flag at byte 0143
        header_word(25'h00146, 16'h1000); // MBC3+timer+RAM+battery
        header_word(25'h00148, 16'h0306); // 2 MiB ROM, 32 KiB RAM

        @(negedge clk);
        cart_download = 0;
        repeat (3) @(posedge clk);

        if (dut.rom_mask !== 9'h07f)
            $fatal(1, "MBC3 ROM mask %h, expected 07f", dut.rom_mask);
        if (dut.cart_mbc_type !== 8'h10)
            $fatal(1, "mapper type %h, expected 10", dut.cart_mbc_type);
        if (ram_size !== 8'h03)
            $fatal(1, "RAM size %h, expected 03", ram_size);

        // MBC3 ROM-bank register: write bank 2 to address range 2000-3fff.
        @(negedge clk);
        ce_cpu = 1;
        cart_wr = 1;
        cart_addr = 15'h2000;
        cart_di = 8'h02;
        @(negedge clk);
        cart_wr = 0;
        ce_cpu = 0;
        cart_addr = 15'h4000;
        #1;

        if (mbc_addr !== 23'h008000)
            $fatal(1, "bank 2 mapped to %h, expected 008000", mbc_addr);

        // Defcon declares four 8 KiB MBC3 RAM banks. Verify that local SRAM
        // reads do not come from rom_di and that adjacent banks do not alias.
        cpu_write(1'b0, 1'b1, 15'h0000, 8'h0A); // enable RAM
        cpu_write(1'b0, 1'b1, 15'h4000, 8'h00); // RAM bank 0
        cpu_write(1'b1, 1'b0, 15'h2000, 8'h12); // A000
        cpu_write(1'b0, 1'b1, 15'h4000, 8'h01); // RAM bank 1
        cpu_write(1'b1, 1'b0, 15'h2000, 8'h34); // A000
        expect_ram(8'h34);
        cpu_write(1'b0, 1'b1, 15'h4000, 8'h00);
        expect_ram(8'h12);

        $display("PASS cache-header MBC3 mask=%h bank2=%h SRAM banks distinct",
                 dut.rom_mask, mbc_addr);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "global timeout");
    end
endmodule
