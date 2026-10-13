`timescale 1ns/1ps
module tb_gba_psram_burst;
    parameter FAST=1, WRITE_HALF=1, READ_HALF=WRITE_HALF, READ_FALLING=0, INIT_HALF=1, RAM_GAP=4;
    parameter ASYNC_CLOCK=0, PHY_HALF_NS=10, PHY_PHASE_NS=7;
    reg clk=0,reset=1; always #25 clk=~clk; // Actual 20 MHz fabric clock.
    reg clk_ram=0;
    initial begin #(PHY_PHASE_NS);forever #(PHY_HALF_NS)clk_ram=~clk_ram;end
    reg request=0,reading=0;
    reg [22:0] address=0;
    reg [31:0] data=0;
    reg [3:0] enables=15;
    wire done,ready,idle,fault;
    wire [31:0] result;
    wire cs,sck; tri [3:0] dq; wire [3:0] dout,oe;
    genvar n;
    generate for(n=0;n<4;n=n+1) assign dq[n]=oe[n]?dout[n]:1'bz; endgenerate
    gba_psram #(.POWERUP_CYCLES(20),.ASYNC_CLOCK(ASYNC_CLOCK),.HALF_PERIOD(WRITE_HALF),
        .READ_HALF_PERIOD(READ_HALF),.READ_FALLING(READ_FALLING),.INIT_HALF_PERIOD(INIT_HALF),.CS_GAP(RAM_GAP)) dut(
        .clk(clk),.clk_ram(clk_ram),.reset(reset),.core_req(1'b0),.core_read(1'b0),.core_addr(26'd0),
        .core_wdata(32'd0),.core_rdata(),.core_done(),
        .host_req(request),.host_read(reading),.host_addr(address),
        .host_wdata(data),.host_be(enables),.host_rdata(result),.host_done(done),
        .video_req(1'b0),.video_read(1'b0),.video_addr(23'd0),
        .video_wdata(32'd0),.video_be(4'd0),.video_rdata(),.video_done(),
        .ready(ready),.device_id(),.fault(fault),.idle(idle),
        .cs_n(cs),.sck(sck),.dq_in(dq),.dq_out(dout),.dq_oe(oe));
    aps6404_model model(.cs_n(cs),.sck(sck),.dq(dq),.corrupt_reads(1'b0));
    integer transactions=0,edges=0,cycles=0,write_cycles,read_cycles;
    time selected_at;
    always @(negedge cs) if(ready) begin transactions=transactions+1;selected_at=$time;end
    always @(posedge sck) if(ready) edges=edges+1;
    always @(posedge cs) if(ready && FAST && $time-selected_at>8000)
        $fatal(1,"PSRAM CE# exceeds 8 us: %0t",$time-selected_at);
    task transfer(input bit rd,input [22:0] a,input [31:0] d,input [3:0] be);
        begin
            wait(idle); @(negedge clk);
            reading=rd;address=a;data=d;enables=be;request=1;
            transactions=0;edges=0;cycles=0;
            @(negedge clk);request=0;
            while(!done) begin
                @(negedge clk);cycles=cycles+1;
                if(cycles>10000)$fatal(1,"PSRAM transaction timeout");
            end
            if(fault)$fatal(1,"Unexpected PSRAM fault");
        end
    endtask
    reg [22:0] addresses[0:9];
    reg [31:0] expected;
    integer a,b,lane,bytes,abort_delay;
    initial begin
        addresses[0]=0;addresses[1]=23'h3fc;addresses[2]=23'h400;
        addresses[3]=23'h3fffc;addresses[4]=23'h40000;addresses[5]=23'h48000;
        addresses[6]=23'h100000;addresses[7]=23'h10fffc;
        addresses[8]=23'h400000;addresses[9]=23'h7ffffc;
        repeat(20)@(negedge clk);reset=0;wait(ready);
        transfer(0,0,32'h01234567,15);write_cycles=cycles;
        if(FAST && (transactions!=1 || edges!=64 || cycles>160))
            $fatal(1,"Full write must use one 64-clock burst: %0d transactions, %0d edges, %0d cycles",transactions,edges,cycles);
        transfer(1,0,0,15);read_cycles=cycles;
        if(result!==32'h01234567)$fatal(1,"Initial readback mismatch");
        if(FAST && (transactions!=1 || edges!=72 || cycles>180))
            $fatal(1,"Full read must use one 72-clock burst: %0d transactions, %0d edges, %0d cycles",transactions,edges,cycles);
        $display("PSRAM 20 MHz fabric, async=%0d, PHY half-period=%0d ns: write %0d cycles (%0d ns), read %0d cycles (%0d ns)",ASYNC_CLOCK,PHY_HALF_NS,write_cycles,write_cycles*50,read_cycles,read_cycles*50);
        for(a=0;a<10;a=a+1) for(b=0;b<16;b=b+1) begin
            transfer(0,addresses[a],32'h76543210,15);
            transfer(0,addresses[a],32'h89abcdef,b);
            bytes=0;
            for(lane=0;lane<4;lane=lane+1) bytes=bytes+((b>>lane)&1);
            if(FAST && transactions!=(b==15 ? 1 : bytes))$fatal(1,"Incorrect masked-write transaction count");
            expected=32'h76543210;
            for(lane=0;lane<4;lane=lane+1)
                if((b>>lane)&1)expected[lane*8+:8]=(32'h89abcdef>>(lane*8));
            transfer(1,addresses[a],0,15);
            if(result!==expected)$fatal(1,"Byte-enable %h at %h: %h expected %h",b,addresses[a],result,expected);
        end
        // Abort an in-flight read, reinitialize the chip, then verify new requests.
        wait(idle);@(negedge clk);request=1;reading=1;
        @(negedge clk);request=0;wait(!cs);repeat(12)@(negedge clk);
        reset=1;repeat(4)@(negedge clk);reset=0;wait(ready);
        if(done || fault)$fatal(1,"Reset leaked an aborted completion");
        transfer(0,23'h100000,32'hdeadbeef,15);
        transfer(1,23'h100000,0,15);
        if(result!==32'hdeadbeef)$fatal(1,"Post-reset readback mismatch");
        // Reset while request synchronization or acknowledgement is pending.
        for(abort_delay=1;abort_delay<=128;abort_delay=abort_delay*2)begin
            wait(idle);@(negedge clk);request=1;reading=1;
            @(negedge clk);request=0;repeat(abort_delay)@(negedge clk);
            reset=1;repeat(4)@(negedge clk);reset=0;wait(ready);
            repeat(12)begin @(negedge clk);if(done || fault)$fatal(1,"Reset leaked old acknowledgement");end
            transfer(1,23'h100000,0,15);
            if(result!==32'hdeadbeef)$fatal(1,"Reset epoch readback mismatch");
        end
        // Reject a misaligned host request without modifying RAM or signalling done.
        wait(idle);@(negedge clk);address=23'h100001;reading=0;request=1;
        @(negedge clk);request=0;repeat(10)@(negedge clk);
        if(!fault || done || !idle)$fatal(1,"Misaligned request was not rejected");
        $display("PASS PSRAM burst: all 16 byte masks at 10 boundaries, transaction lengths, bounded CE#, reset during transfer, alignment fault");
        $finish;
    end
    initial begin #100000000;$fatal(1,"PSRAM burst test timeout");end
endmodule
