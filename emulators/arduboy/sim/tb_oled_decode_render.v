`timescale 1ns/1ps

module tb_oled_decode_render;
        reg clk = 1'b0;
        reg resetn = 1'b0;
        reg cs = 1'b1;
        reg sclk = 1'b0;
        reg mosi = 1'b0;
        reg dc = 1'b0;

        wire fb_we;
        wire [9:0] fb_addr;
        wire [7:0] fb_wdata;

        reg [7:0] fb_shadow [0:1023];
        integer i;
        integer mismatches;
        integer out_fb;
        integer out_panel;

        reg rd_resetn = 1'b0;
        reg [15:0] panel_pixel_index = 16'd0;
        wire [15:0] panel_rgb;

        always #5 clk = ~clk;

        arduboy_oled_spi_decoder u_dec (
                .clk(clk),
                .resetn(resetn),
                .cs(cs),
                .sclk(sclk),
                .mosi(mosi),
                .dc(dc),
                .fb_we(fb_we),
                .fb_addr(fb_addr),
                .fb_wdata(fb_wdata)
        );

        arduboy_framebuffer u_fb (
                .wr_clk(clk),
                .rd_clk(clk),
                .rd_resetn(rd_resetn),
                .host_we(fb_we),
                .host_addr(fb_addr),
                .host_wdata(fb_wdata),
		.scale_mode(2'd0),
                .panel_pixel_index(panel_pixel_index),
                .panel_rgb(panel_rgb)
        );

        always @(posedge clk) begin
                if (fb_we)
                        fb_shadow[fb_addr] <= fb_wdata;
        end

        function [7:0] pattern_byte(input integer page, input integer col);
                integer y0;
                begin
                        y0 = page * 8;
                        pattern_byte = 8'h00;
                        if (col == 0 || col == 127)
                                pattern_byte = 8'hff;
                        else if (page == 0 || page == 7)
                                pattern_byte = 8'hff;
                        else begin
                                if (((col >> 3) ^ page) & 1)
                                        pattern_byte = 8'h3c;
                                else
                                        pattern_byte = 8'hc3;

                                if (col == y0 || col == (127 - y0))
                                        pattern_byte = pattern_byte ^ 8'hff;
                        end
                end
        endfunction

        task spi_byte(input bit is_data, input [7:0] value);
                integer b;
                begin
                        dc = is_data;
                        cs = 1'b0;
                        for (b = 7; b >= 0; b = b - 1) begin
                                mosi = value[b];
                                repeat (2) @(posedge clk);
                                sclk = 1'b1;
                                repeat (2) @(posedge clk);
                                sclk = 1'b0;
                        end
                        repeat (2) @(posedge clk);
                end
        endtask

        task cmd(input [7:0] value);
                begin
                        spi_byte(1'b0, value);
                end
        endtask

        task data(input [7:0] value);
                begin
                        spi_byte(1'b1, value);
                end
        endtask

        task clear_shadow;
                begin
                        for (i = 0; i < 1024; i = i + 1)
                                fb_shadow[i] = 8'h00;
                end
        endtask

        task send_horizontal_pattern;
                integer page;
                integer col;
                begin
                        cmd(8'h20); cmd(8'h00);       // horizontal addressing
                        cmd(8'h21); cmd(8'h00); cmd(8'h7f);
                        cmd(8'h22); cmd(8'h00); cmd(8'h07);
                        for (page = 0; page < 8; page = page + 1) begin
                                for (col = 0; col < 128; col = col + 1)
                                        data(pattern_byte(page, col));
                        end
                end
        endtask

        task send_page_pattern;
                integer page;
                integer col;
                begin
                        for (page = 0; page < 8; page = page + 1) begin
                                cmd(8'hb0 | page[7:0]);
                                cmd(8'h00);
                                cmd(8'h10);
                                for (col = 0; col < 128; col = col + 1)
                                        data(pattern_byte(page, col));
                        end
                end
        endtask

        task verify_pattern(input [8*32-1:0] label);
                integer page;
                integer col;
                integer addr;
                reg [7:0] exp;
                begin
                        mismatches = 0;
                        for (page = 0; page < 8; page = page + 1) begin
                                for (col = 0; col < 128; col = col + 1) begin
                                        addr = page * 128 + col;
                                        exp = pattern_byte(page, col);
                                        if (fb_shadow[addr] !== exp) begin
                                                if (mismatches < 16)
                                                        $display("MISMATCH %0s addr=%0d page=%0d col=%0d got=%02x exp=%02x",
                                                                label, addr, page, col, fb_shadow[addr], exp);
                                                mismatches = mismatches + 1;
                                        end
                                end
                        end
                        $display("VERIFY %0s mismatches=%0d", label, mismatches);
                end
        endtask

        task dump_fb_hex(input [8*128-1:0] path);
                begin
                        out_fb = $fopen(path, "w");
                        for (i = 0; i < 1024; i = i + 1)
                                $fwrite(out_fb, "%02x\n", fb_shadow[i]);
                        $fclose(out_fb);
                end
        endtask

        task dump_panel_hex(input [8*128-1:0] path);
                integer pix;
                begin
                        rd_resetn = 1'b0;
                        panel_pixel_index = 16'd0;
                        repeat (8) @(posedge clk);
                        rd_resetn = 1'b1;
                        repeat (8) @(posedge clk);

                        out_panel = $fopen(path, "w");
                        for (pix = 0; pix < 57600; pix = pix + 1) begin
                                panel_pixel_index = pix[15:0];
                                repeat (6) @(posedge clk);
                                $fwrite(out_panel, "%04x\n", panel_rgb);
                        end
                        $fclose(out_panel);
                end
        endtask

        initial begin
                clear_shadow();
                #100;
                resetn = 1'b1;
                repeat (10) @(posedge clk);

                send_horizontal_pattern();
                repeat (10) @(posedge clk);
                verify_pattern("horizontal");
                dump_fb_hex("sim/oled_decode_horizontal_fb.hex");
                dump_panel_hex("sim/oled_decode_horizontal_panel.hex");

                resetn = 1'b0;
                clear_shadow();
                repeat (10) @(posedge clk);
                resetn = 1'b1;
                repeat (10) @(posedge clk);

                send_page_pattern();
                repeat (10) @(posedge clk);
                verify_pattern("page");
                dump_fb_hex("sim/oled_decode_page_fb.hex");
                dump_panel_hex("sim/oled_decode_page_panel.hex");

                if (mismatches == 0)
                        $display("PASS: decoder patterns rendered");
                $finish;
        end
endmodule
