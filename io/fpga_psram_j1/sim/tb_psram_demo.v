`timescale 1ns/1ps
module tb_psram_demo #(parameter QPI=0, parameter HALF_PERIOD=2, parameter BURST_BYTES=32,
                      parameter CLK_HALF_NS=10, parameter SPI_BURST=0, parameter FAST_READ=0);
    reg clk=0, reset=1, button=0;
    always #(CLK_HALF_NS) clk=~clk;
    reg host_sck=0, host_mosi=0, host_cs_n=1;
    wire host_miso, ram_cs_n, ram_sck;
    tri [3:0] dq;
    wire [3:0] dq_out, dq_oe;
    wire [7:0] leds;
    reg corrupt=0;
    genvar g;
    generate for (g=0;g<4;g=g+1) begin: io
        assign dq[g]=dq_oe[g] ? dq_out[g] : 1'bz;
    end endgenerate
    psram_demo #(.ENABLE_QPI(QPI),.QPI_HALF_PERIOD(HALF_PERIOD),.BURST_BYTES(BURST_BYTES),
                .SPI_BURST(SPI_BURST),.SPI_FAST_READ(FAST_READ)) dut(
        .clk(clk),.reset(reset),.test_button(button),
        .host_sck(host_sck),.host_mosi(host_mosi),.host_cs_n(host_cs_n),
        .host_miso(host_miso),.ram_cs_n(ram_cs_n),.ram_sck(ram_sck),
        .ram_cs_sense(ram_cs_n),.ram_sck_sense(ram_sck),
        .ram_dq_in(dq),.ram_dq_out(dq_out),.ram_dq_oe(dq_oe),.status_led(leds));
    aps6404_model model(.cs_n(ram_cs_n),.sck(ram_sck),.dq(dq),.corrupt_reads(corrupt));

    task byte_transfer;
        input [7:0] outgoing; output [7:0] incoming;
        integer bit_number;
        begin
            incoming=0;
            for(bit_number=7;bit_number>=0;bit_number=bit_number-1) begin
                host_mosi=outgoing[bit_number]; #500;
                host_sck=1; #200;
                incoming={incoming[6:0],host_miso}; #300;
                host_sck=0;
            end
        end
    endtask
    task command;
        input [7:0] opcode; input [23:0] address; input [7:0] data;
        reg [7:0] discard;
        begin
            host_cs_n=0; #500;
            byte_transfer(opcode,discard);
            byte_transfer(address[23:16],discard);
            byte_transfer(address[15:8],discard);
            byte_transfer(address[7:0],discard);
            byte_transfer(data,discard);
            #500; host_cs_n=1; #500;
        end
    endtask
    task reply;
        output [63:0] value;
        reg [7:0] b; integer n;
        begin
            value=0; host_cs_n=0; #500;
            for(n=0;n<8;n=n+1) begin byte_transfer(0,b); value={value[55:0],b}; end
            #500; host_cs_n=1; #500;
            if(value[63:56] !== 8'h50) $fatal(1,"Bad host response: %h",value);
        end
    endtask
    task wait_idle;
        output [63:0] value; integer n;
        begin
            n=0; reply(value);
            while(value[48] && n<100) begin #10000; reply(value); n=n+1; end
            if(value[48]) $fatal(1,"Operation timed out");
        end
    endtask
    task check_byte;
        input [23:0] address; input [7:0] value;
        reg [63:0] response;
        begin
            command(2,address,value); wait_idle(response);
            if(response[7:0] != 0) $fatal(1,"Write error");
            command(1,address,0); wait_idle(response);
            if(response[47:40] !== value || response[7:0] != 0)
                $fatal(1,"Read/write mismatch at %h: %h",address,response);
        end
    endtask
    reg [63:0] response;
    integer n;
    initial begin
        #200; @(negedge clk); reset=0;
        #450000; wait_idle(response);
        if(!response[52] || !response[49]) $fatal(1,"Startup ID failed: %h",response);
        command(5,0,0); wait_idle(response);
        if(response[31:8] !== 24'h0d5d26) $fatal(1,"Cached ID mismatch: %h",response);
        command(6,0,0); wait_idle(response);
        if(response[39:32] !== 8'hff || response[31:8] !== (QPI ? 24'd82 : 24'd74))
            $fatal(1,"Pad activity/clock counter mismatch: %h",response);
        check_byte(0,8'ha5); check_byte(1,8'h5a);
        check_byte(24'h0003ff,8'h80); check_byte(24'h000400,8'h01);
        check_byte(24'h400000,8'hc3); check_byte(24'h7fffff,8'h7e);
        // Distinct values remain at separate locations (including upper address bits).
        command(1,0,0); wait_idle(response);
        if(response[47:40] !== 8'ha5) $fatal(1,"Address alias");
        command(4,24'h0003f0,0); wait_idle(response);
        if(!response[50] || response[7:0] != 0) $fatal(1,"BIST failed: %h",response);
        command(4,24'h7fff00,0); wait_idle(response);
        if(!response[50]) $fatal(1,"Top-of-memory BIST failed");
        corrupt=1;
        command(4,24'h000800,0); wait_idle(response);
        if(response[7:0] !== 4 || response[31:8] !== 24'h000800 || response[50])
            $fatal(1,"Failure reporting incorrect: %h",response);
        corrupt=0;
        command(1,24'h800000,0); wait_idle(response);
        if(response[7:0] !== 3) $fatal(1,"Missing bounds check");
        command(4,24'h7fff01,0); wait_idle(response);
        if(response[7:0] !== 3) $fatal(1,"BIST range wraps");
        command(8'hff,0,0); wait_idle(response);
        if(response[7:0] !== 2) $fatal(1,"Missing opcode check");
        command(7,24'h7ffff0,16); wait_idle(response);
        if(response[7:0] !== 3) $fatal(1,"Benchmark range overflow");
        command(7,0,7); wait_idle(response);
        if(response[7:0] !== 3) $fatal(1,"Benchmark invalid size");
        command(7,24'h1000,10); wait_idle(response);
        if(!response[50]) $fatal(1,"1 KiB timed benchmark failed: %h",response);
        command(8,0,0); wait_idle(response);
        if(response[31:8] == 0) $fatal(1,"Missing write cycle metric");
        $display("BENCH_WRITE_CYCLES=%0d",response[31:8]);
        command(8,0,1); wait_idle(response);
        if(response[31:8] == 0) $fatal(1,"Missing read cycle metric");
        $display("BENCH_READ_CYCLES=%0d",response[31:8]);
        // An incomplete frame must not launch a write.
        host_cs_n=0; #500;
        begin: partial
            reg [7:0] discard;
            byte_transfer(2,discard); byte_transfer(0,discard);
        end
        host_cs_n=1; #500;
        check_byte(24'h123456,8'h96);
        // Recover a chip left in QPI mode by another design.
        model.qpi_mode=1;
        command(3,0,0); wait_idle(response);
        if(response[31:8] !== 24'h0d5d26 || !response[52]) $fatal(1,"QPI recovery failed");
        @(negedge clk); button=1; @(negedge clk); button=0;
        #10000; wait_idle(response);
        if(!response[50]) $fatal(1,"Button BIST failed");
        $display("PASS: ID, QPI recovery, read/write, boundaries, BIST, corruption, invalid/partial commands, button. %0d PSRAM transactions",model.transactions);
        $finish;
    end
    initial begin #20000000; $fatal(1,"Global timeout"); end
endmodule
