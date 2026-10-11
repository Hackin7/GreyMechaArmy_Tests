`timescale 1ns/1ps

module tb_host_status;
    reg clk = 0;
    reg reset = 1;
    reg [7:0] rx_data = 0;
    reg rx_valid = 0;
    wire [7:0] tx_data;
    wire tx_valid;
    reg tx_ready = 1;

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
    wire irq;
    wire [7:0] last_sequence;
    wire [3:0] error_code;

    reg [7:0] response [0:3];
    integer response_count = 0;
    integer timeout;
    reg [15:0] crc;

    gb_host_bridge dut (
        .clk(clk), .reset(reset),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .cache_miss(1'b1), .cache_miss_address(23'h654321),
        .core_running(1'b1), .lcd_on(1'b1), .lcd_clock(1'b0),
        .pixel_count(16'hCAFE), .debug_pc(16'hBEEF),
        .rom_we(rom_we), .rom_addr(rom_addr), .rom_data(rom_data),
        .fill_begin(fill_begin), .fill_we(fill_we),
        .fill_offset(fill_offset), .fill_data(fill_data),
        .fill_commit(fill_commit), .fill_address(fill_address),
        .core_reset_pulse(core_reset_pulse), .core_run(core_run),
        .gbc_mode(gbc_mode), .irq(irq),
        .last_sequence(last_sequence), .error_code(error_code)
    );

    always #5 clk = ~clk;

    function automatic [15:0] crc_byte;
        input [15:0] old_crc;
        input [7:0] value;
        integer bit_index;
        reg [15:0] c;
        begin
            c = old_crc ^ {value, 8'h00};
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                c = c[15] ? {c[14:0], 1'b0} ^ 16'h1021
                          : {c[14:0], 1'b0};
            crc_byte = c;
        end
    endfunction

    task send_byte(input [7:0] value);
        begin
            @(negedge clk);
            rx_data = value;
            rx_valid = 1;
            @(negedge clk);
            rx_valid = 0;
        end
    endtask

    task send_crc_byte(input [7:0] value);
        begin
            send_byte(value);
            crc = crc_byte(crc, value);
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (tx_valid && response_count < 4) begin
            response[response_count] = tx_data;
            response_count = response_count + 1;
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        reset = 0;

        crc = 16'hFFFF;
        send_crc_byte(8'h47);
        send_crc_byte(8'h01);
        send_crc_byte(8'h20);
        send_crc_byte(8'h5A);
        send_crc_byte(8'h00);
        send_crc_byte(8'h00);
        send_crc_byte(8'h00);
        send_crc_byte(8'h00);
        send_crc_byte(8'h00);
        send_crc_byte(8'h00);
        send_byte(crc[7:0]);
        send_byte(crc[15:8]);

        begin : wait_response
            for (timeout = 0; timeout < 30; timeout = timeout + 1) begin
                @(posedge clk);
                #1;
                if (response_count == 4)
                    disable wait_response;
            end
            $fatal(1, "status response timeout");
        end

        if (response[0] !== 8'hE0)
            $fatal(1, "status flags %h, expected E0", response[0]);
        if (response[1] !== 8'h21 ||
            response[2] !== 8'h43 ||
            response[3] !== 8'h65)
            $fatal(1, "status address %h%h%h, expected 654321",
                   response[3], response[2], response[1]);

        $display("PASS gb_host_status flags=%h address=%h%h%h",
                 response[0], response[3], response[2], response[1]);
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "global timeout");
    end
endmodule
