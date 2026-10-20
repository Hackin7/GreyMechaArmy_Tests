`timescale 1ns/1ps
module tb_isp_pixels;
    reg clk=0;always #5 clk=~clk;
    reg resetn=0,start=0,stop=0,enabled=0,take=0;
    reg [2:0] mode=0;
    reg [39:0] presets=40'h030a0a0604;
    reg [15:0] value_q8=4096;
    wire [14:0] read_address;
    reg [15:0] read_data,q0,q1;
    wire valid;wire [15:0] pixel;wire [31:0] stalls;
    reg [15:0] source[0:19199],expected[0:19199];
    isp_pixels dut(.*);
    always @(posedge clk) begin q0<=source[read_address];q1<=q0;read_data<=q1;end
    integer fd,n,mi,en,idx,val,num,rc,p,cycles,age,frames=0;
    string dir,path;
    initial begin
        if(!$value$plusargs("VECTORS=%s",dir)) $fatal(1,"VECTORS required");
        fd=$fopen({dir,"/cases.txt"},"r");if(!fd) $fatal(1,"cases missing");
        repeat(4) @(negedge clk);resetn=1;
        while(!$feof(fd)) begin
            rc=$fscanf(fd,"%d %d %d %d %d %d\n",n,mi,en,idx,val,num);
            if(rc!=6) $fatal(1,"Malformed case");
            path=$sformatf("%s/source%0d.hex",dir,n);$readmemh(path,source);
            path=$sformatf("%s/expected%0d.hex",dir,n);$readmemh(path,expected);
            mode=mi;enabled=en;value_q8=val;presets=40'h030a0a0604;
            presets[15:8]=idx;
            start=1;@(negedge clk);start=0;p=0;cycles=0;age=0;
            while(p<num) begin
                // Delayed consumer fills the queue and exercises backpressure.
                take=valid && cycles%32==0 && (cycles%227<200);
                if(take) begin
                    if(pixel!==expected[p]) $fatal(1,"Case %0d mode %0d pixel %0d got %h expected %h",n,mi,p,pixel,expected[p]);
                    p=p+1;
                end
                @(negedge clk);cycles=cycles+1;
                if(cycles>num*70+100) $fatal(1,"ISP deadlock");
            end
            take=0;stop=1;@(negedge clk);stop=0;frames=frames+1;
        end
        $display("PASS ISP pixels: %0d software-reference cases, bypass, identity, borders, clipping, backpressure",frames);$finish;
    end
    integer work_cycles=0;
    always @(posedge clk) if(resetn && !start) begin
        if(dut.issue && read_address>=19200) $fatal(1,"Neighbor address out of frame");
        if(dut.count>2) $fatal(1,"FIFO overflow");
        if(dut.state==0 || dut.state==8) work_cycles=0;
        else begin
            work_cycles=work_cycles+1;
            if(work_cycles>24) $fatal(1,"Worker exceeds 24 clocks");
        end
    end
endmodule
