`timescale 1ns/1ps
module tb_gba_host;
    reg clk=0,reset=1;always #5 clk=~clk;
    reg sck=0,mosi=0,cs=1;wire miso;
    wire [7:0] rx,tx;wire rv,tv,tr;
    gb_spi_phy phy(.clk(clk),.reset(reset),.spi_sck(sck),.spi_mosi(mosi),.spi_csn(cs),
        .spi_miso(miso),.rx_data(rx),.rx_valid(rv),.tx_data(tx),.tx_valid(tv),.tx_ready(tr));
    wire req,rd,done,ready,idle,fault;wire [22:0] addr;wire [31:0] wd,qd;wire [3:0] be;
    wire [23:0] id;wire busy;wire [7:0] error,last;wire run,pause;
    gba_host host(.clk(clk),.reset(reset),.rx_data(rx),.rx_valid(rv),.tx_data(tx),.tx_valid(tv),.tx_ready(tr),
        .run(run),.pause(pause),.reset_pulse(),.max_rom_addr(),.flash_1m(),.inject_enable(),.injected(),
        .ram_ready(ready),.ram_idle(idle),.ram_fault(fault),.panel_ready(1'b1),.overflow(1'b0),
        .device_id(id),.pc(32'h08001234),.frames(32'd11),.flash_misses(32'd7),.physical(7'd0),.keys(10'd0),
        .mem_req(req),.mem_read(rd),.mem_addr(addr),.mem_wdata(wd),.mem_be(be),.mem_done(done),.mem_rdata(qd),
        .busy(busy),.error(error),.last_sequence(last));
    wire rcs,rsck;tri [3:0] dq;wire [3:0] dout,oe;
    genvar g;generate for(g=0;g<4;g=g+1)assign dq[g]=oe[g]?dout[g]:1'bz;endgenerate
    gba_psram #(.POWERUP_CYCLES(20)) ram(.clk(clk),.reset(reset),.core_req(1'b0),.core_read(1'b1),
        .core_addr(26'd0),.core_wdata(32'd0),.core_rdata(),.core_done(),
        .host_req(req),.host_read(rd),.host_addr(addr),.host_wdata(wd),.host_be(be),.host_rdata(qd),.host_done(done),
        .video_req(1'b0),.video_read(1'b1),.video_addr(23'd0),.video_wdata(32'd0),.video_be(4'd0),.video_rdata(),.video_done(),
        .ready(ready),.device_id(id),.fault(fault),.idle(idle),.cs_n(rcs),.sck(rsck),.dq_in(dq),.dq_out(dout),.dq_oe(oe));
    aps6404_model model(.cs_n(rcs),.sck(rsck),.dq(dq),.corrupt_reads(1'b0));
    reg [7:0] payload[0:255],reply[0:255];reg [15:0] crc;reg [7:0] discard;
    function [15:0] cb(input [15:0] old,input [7:0] value);
        reg [15:0] c;integer i;begin c=old^{value,8'd0};for(i=0;i<8;i=i+1)c=c[15]?(c<<1)^16'h1021:c<<1;cb=c;end
    endfunction
    task byte_x(input [7:0] b,output [7:0] q);
        integer i;begin q=0;for(i=7;i>=0;i=i-1)begin mosi=b[i];#100;sck=1;#100;q={q[6:0],miso};sck=0;#100;end end
    endtask
    task send_byte(input [7:0] b);begin byte_x(b,discard);crc=cb(crc,b);end endtask
    task packet(input [7:0] op,input [7:0] seq,input [31:0] a,input integer n,input corrupt);
        integer i;begin crc=16'hffff;cs=0;#100;
            send_byte(8'h47);send_byte(1);send_byte(op);send_byte(seq);
            for(i=0;i<4;i=i+1)send_byte(a>>(i*8));send_byte(n);send_byte(n>>8);
            for(i=0;i<n;i=i+1)send_byte(payload[i]);byte_x(crc[7:0]^corrupt,discard);byte_x(crc[15:8],discard);
            #100;cs=1;#1000;
        end
    endtask
    task response(input integer n);integer i;begin cs=0;#100;for(i=0;i<n;i=i+1)byte_x(0,reply[i]);#100;cs=1;#1000;end endtask
    task status;begin packet(8'h20,0,0,0,0);response(32);if(reply[0]!==8'h47||reply[1]!==1)$fatal(1,"Status framing");end endtask
    task wait_seq(input [7:0] seq);integer i;begin
        i=0;status;while((reply[2]!=seq||reply[3][0])&&i<100)begin i=i+1;status;end
        if(i==100||reply[11]!=0)$fatal(1,"Host completion seq=%d error=%d",reply[2],reply[11]);
    end endtask
    integer i;
    initial begin
        #200;@(negedge clk);reset=0;wait(ready);#1000;status;
        if(id!==24'h0d5d26||fault)$fatal(1,"PSRAM init");
        payload[0]=128;payload[1]=0;payload[2]=0;payload[3]=0;payload[4]=8'ha5;
        packet(8'h14,1,32'h3fff0,5,0);wait_seq(1);
        for(i=0;i<128;i=i+1)if(model.memory[32'h3fff0+i]!==8'ha5)$fatal(1,"Fill address changed during polling %d",i);
        for(i=0;i<64;i=i+1)payload[i]=i^8'h5a;
        packet(8'h10,2,32'h7fffc0,64,0);wait_seq(2);
        payload[0]=64;payload[1]=0;packet(8'h12,3,32'h7fffc0,2,0);wait_seq(3);
        packet(8'h21,0,0,0,0);response(64);
        for(i=0;i<64;i=i+1)if(reply[i] !== (i^8'h5a))$fatal(1,"Readback %d: %h",i,reply[i]);
        packet(8'h10,4,32'h7fffc0,64,1);status;if(reply[11]!==3)$fatal(1,"CRC rejection");
        packet(8'h12,5,32'hfffffffc,2,0);status;if(reply[11]!==5)$fatal(1,"Wrapped address accepted");
        for(i=0;i<64;i=i+1)model.memory[32'h80000+i*4]=i;
        payload[0]=64;payload[1]=0;packet(8'h15,6,0,2,0);wait_seq(6);
        packet(8'h21,0,0,0,0);response(64);
        for(i=0;i<64;i=i+1)if(reply[i]!==i[7:0])$fatal(1,"Save byte packing %d",i);
        if(fault)$fatal(1,"RAM arbitration fault");
        $display("PASS host: SPI framing, CRC, status during fill, upper-address PSRAM read/write, bounds");$finish;
    end
    initial begin #50000000;$fatal(1,"Host timeout");end
endmodule
