`timescale 1ns/1ps
module tb_gba_psram_clients;
    parameter ASYNC_CLOCK=0;
    parameter STABLE_CLIENTS=0;
    parameter CHANGE_AFTER_REQUEST=0;
    reg clk=0,reset=1;always #25 clk=~clk;
    reg clk_ram=0;initial begin #7;forever #10 clk_ram=~clk_ram;end
    reg crq=0,hrq=0,vrq=0,read_op=0;
    reg [25:0] ca=26'h80;reg [22:0] ha=23'h100000,va=23'h100004;
    reg [31:0] cw=32'h11223344,hw=32'h55667788,vw=32'haabbccdd;
    reg [3:0] hb=4'hf,vb=4'b0101;
    wire cd,hd,vd,ready,idle,fault;wire [31:0] cq,hq,vq;
    wire cs,sck;tri [3:0] dq;wire [3:0] dout,oe;wire [23:0] id;
    genvar n;generate for(n=0;n<4;n=n+1)assign dq[n]=oe[n]?dout[n]:1'bz;endgenerate
    gba_psram #(.POWERUP_CYCLES(20),.ASYNC_CLOCK(ASYNC_CLOCK),.STABLE_CLIENTS(STABLE_CLIENTS)) dut(
        .clk(clk),.clk_ram(clk_ram),.reset(reset),.core_req(crq),.core_read(read_op),.core_addr(ca),
        .core_wdata(cw),.core_rdata(cq),.core_done(cd),
        .host_req(hrq),.host_read(read_op),.host_addr(ha),
        .host_wdata(hw),.host_be(hb),.host_rdata(hq),.host_done(hd),
        .video_req(vrq),.video_read(read_op),.video_addr(va),
        .video_wdata(vw),.video_be(vb),.video_rdata(vq),.video_done(vd),
        .ready(ready),.device_id(id),.fault(fault),.idle(idle),
        .cs_n(cs),.sck(sck),.dq_in(dq),.dq_out(dout),.dq_oe(oe));
    aps6404_model model(.cs_n(cs),.sck(sck),.dq(dq),.corrupt_reads(1'b0));
    reg [2:0] completed=0;integer completions=0,cycles=0;
    always @(posedge clk)begin
        if(cd)begin completed[0]<=1;completions<=completions+1;end
        if(hd)begin completed[1]<=1;completions<=completions+1;end
        if(vd)begin completed[2]<=1;completions<=completions+1;end
        if((cd&&hd)||(hd&&vd)||(cd&&vd))$fatal(1,"Two PSRAM owners completed together");
    end
    task batch;
        begin
            @(negedge clk);completed=0;completions=0;crq=1;hrq=1;vrq=1;
            ca=26'h80;ha=23'h100000;va=23'h100004;
            cw=32'h11223344;hw=32'h55667788;vw=32'haabbccdd;hb=4'hf;vb=4'b0101;
            @(negedge clk);crq=0;hrq=0;vrq=0;
            if(CHANGE_AFTER_REQUEST)begin
                ca=26'h100;ha=23'h110000;va=23'h110004;
                cw=0;hw=0;vw=0;hb=0;vb=0;
            end
            cycles=0;
            while(completed!=7)begin @(negedge clk);cycles=cycles+1;if(cycles>20000)$fatal(1,"Client starved %b",completed);end
            if(completions!=3||fault)$fatal(1,"PSRAM arbitration failure");
            wait(idle);@(negedge clk);
        end
    endtask
    initial begin
        model.memory[23'h100004]=8'h33;model.memory[23'h100005]=8'h22;
        model.memory[23'h100006]=8'h11;model.memory[23'h100007]=8'h00;
        repeat(20)@(negedge clk);reset=0;wait(ready);batch;
        read_op=1;batch;
        if(cq!==32'h11223344||hq!==32'h55667788||vq!==32'h00bb22dd)
            $fatal(1,"PSRAM clients/byte enables read %h %h %h",cq,hq,vq);
        $display("PASS PSRAM clients: simultaneous core/host/video requests, fair completion, external VRAM address, byte enables, readback");
        $finish;
    end
    initial begin #10000000;$fatal(1,"PSRAM client timeout");end
endmodule
