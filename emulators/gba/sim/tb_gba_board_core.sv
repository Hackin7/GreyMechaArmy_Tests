`timescale 1ns/1ps
module tb_gba_board_core;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,pause=0;reg [9:0] keys=0;
    wire rr,er,rnw,pwe;wire [24:0] ra;wire [25:0] ea;wire [31:0] wd,pc;
    reg rd=0,ed=0;reg [31:0] rdata=0,second=0,edata=0;
    wire vr,vread;wire [13:0] va;wire [31:0] vw;wire [3:0] vbe;
    reg vd=0;reg [31:0] vdata=0,vram[0:16383];
    wire [7:0] px,py;wire [17:0] pd;
    gba_core_wrapper dut(.clk_100(clk),.reset_n(reset_n),.pause(pause),.video_ready(1'b1),
        .key_a(keys[0]),.key_b(keys[1]),.key_select(keys[2]),.key_start(keys[3]),
        .key_right(keys[4]),.key_left(keys[5]),.key_up(keys[6]),.key_down(keys[7]),.key_r(keys[8]),.key_l(keys[9]),
        .max_rom_addr(25'd4095),.flash_1m(1'b0),.rom_read(rr),.rom_addr(ra),.rom_done(rd),
        .rom_data(rdata),.rom_second_data(second),.ext_write_data(wd),.ext_read_data(edata),
        .ext_addr(ea),.ext_read_not_write(rnw),.ext_request(er),.ext_done(ed),
        .vram_request(vr),.vram_read(vread),.vram_addr(va),.vram_wdata(vw),.vram_be(vbe),
        .vram_rdata(vdata),.vram_done(vd),
        .bios_wraddr(12'd0),.bios_wrdata(32'd0),.bios_wr(1'b0),.pixel_x(px),.pixel_y(py),.pixel_addr(),
        .pixel_data(pd),.pixel_we(pwe),.audio_left(),.audio_right(),.debug_cpu_pc(pc));
    reg [31:0] ram[0:262143],rom[0:4095];
    integer i,rc=0,ec=0,cycles=0,frames=0;reg [24:0] rh;reg [25:0] eh;reg [31:0] wh;reg readh;
    integer vc=0,lane;reg [13:0] vh;reg [31:0] vwh;reg [3:0] vbh;reg vreadh;
    always @(posedge clk)begin
        rd<=0;ed<=0;vd<=0;cycles<=cycles+1;
        if(vr)begin
            if(vc!=0)$fatal(1,"Overlapping VRAM request");
            vc<=$test$plusargs("FASTMEM") ? 8+(va%7) : 1200;
            vh<=va;vwh<=vw;vbh<=vbe;vreadh<=vread;
        end
        if(vc>0)begin vc<=vc-1;if(vc==1)begin
            if(vreadh)vdata<=vram[vh];
            else for(lane=0;lane<4;lane=lane+1)if(vbh[lane])vram[vh][lane*8+:8]<=vwh[lane*8+:8];
            vd<=1;
        end end
        if(rr)begin if(rc!=0)$fatal(1,"Overlapping ROM request");rc<=12;rh<=ra;end
        if(rc>0)begin rc<=rc-1;if(rc==1)begin rdata<=rom[rh];second<=rom[rh^25'd1];rd<=1;end end
        if(er)begin if(ec!=0||ea>=262144)$fatal(1,"Bad external request %h",ea);ec<=$test$plusargs("FASTMEM") ? 8 : 1200;eh<=ea;wh<=wd;readh<=rnw;end
        if(ec>0)begin ec<=ec-1;if(ec==1)begin
            if(readh)edata<=ram[eh];else ram[eh]<=wh;ed<=1;
        end end
        if(pwe&&px==239&&py==159)frames<=frames+1;
        if(cycles%100000==0&&cycles!=0)begin
            $display("Core cycles=%d pc=%h frames=%d report=%h",cycles,pc,frames,ram[18'h20010]);$fflush();
        end
    end
    reg [31:0] frozen;
    initial begin
        for(i=0;i<262144;i=i+1)ram[i]=0;
        for(i=0;i<16384;i=i+1)vram[i]=0;
        for(i=0;i<4096;i=i+1)rom[i]=0;
        $readmemh("build/roms/open_bios.hex",ram,18'h12000,18'h12fff);
        $readmemh("build/roms/diagnostic.hex",rom);
        if($test$plusargs("SMOKEBOOT"))begin
            ram[18'h12000]=32'he3a000df; // MSR cpsr then branch to cartridge
            ram[18'h12001]=32'he121f000;
            ram[18'h12002]=32'he3a00008;ram[18'h12003]=32'he1a00c00;
            ram[18'h12004]=32'he12fff10;
        end
        repeat(100)@(negedge clk);reset_n=1;
        wait(ram[18'h20010][7:0]==8'h0d&&ram[18'h20013][7:0]==8'h60);
        if(ram[18'h2000c][7:0]!=255||ram[18'h2000d][7:0]!=3)
            $fatal(1,"Diagnostic checks failed flags=%h:%h arithmetic case=%h shifter case=%h",ram[18'h2000d],ram[18'h2000c],ram[18'h20024],ram[18'h20028]);
        wait(frames>=1);pause=1;repeat(1000)@(negedge clk);frozen=pc;repeat(1000)@(negedge clk);
        if(pc!==frozen)$fatal(1,"Pause changed PC");keys=10'h301;pause=0;
        wait(ram[18'h20014][7:0]==1&&ram[18'h20015][7:0]==3);
        $display("PASS board core: BIOS boot, ROM pair prefetch, EWRAM/IWRAM/VRAM subword writes/mirroring, ignored OBJ byte writes, ARM arithmetic/shift flags, SRAM report, PPU, pause, KEYINPUT");$finish;
    end
    initial begin #3000000000;$fatal(1,"Core timeout pc=%h frames=%d report=%h",pc,frames,ram[18'h20010]);end
endmodule
