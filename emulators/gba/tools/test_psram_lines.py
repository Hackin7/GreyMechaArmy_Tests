"""Exercise the actual LCD serializer with PSRAM-backed scanlines."""
import subprocess
from pathlib import Path
w=Path('build/psram-lines');w.mkdir(parents=True,exist_ok=True)
s=Path('sim/tb_gba_display.sv').read_text()
s=s.replace('module tb_gba_display #(', 'module tb_gba_psram_display #(')
s=s.replace('always #(CORE_HALF_NS) cc=~cc;', '''reg sys=0;always #(CORE_HALF_NS)sys=~sys;
    wire pixel_ready,panel_data_ready;reg tick=1,ptick=1;
    always @(negedge sys)tick<=reset||pixel_ready;
    always @(negedge psys)ptick<=reset||panel_data_ready;
    always @* cc=sys&&tick;
    reg psys=0;always #(PANEL_HALF_NS)psys=~psys;
    always @* pc=psys&&ptick;
    wire wr,rr;wire [22:0] wa,ra_mem;wire [31:0] wd;wire [3:0] wb;
    reg wdone=0,rdone=0;reg [31:0] rq=0,ram[0:511];
    integer wc=0,rc=0,wh,rh;reg [31:0] wheld;reg [3:0] wheld_be;
    initial for(integer n=0;n<512;n=n+1)ram[n]=0;
    always @(posedge sys)begin
      wdone<=0;rdone<=0;
      if(wr)begin wc<=11;wh<=(wa-23'h200000)>>2;wheld<=wd;wheld_be<=wb;end
      if(rr)begin rc<=9;rh<=(ra_mem-23'h200000)>>2;end
      if(wc>0)begin wc<=wc-1;if(wc==1)begin
        for(integer b=0;b<4;b=b+1)if(wheld_be[b])ram[wh][b*8+:8]<=wheld[b*8+:8];wdone<=1;
      end end
      if(rc>0)begin rc<=rc-1;if(rc==1)begin rq<=ram[rh];rdone<=1;end end
    end''')
s=s.replace('always #(PANEL_HALF_NS) pc=~pc;', '')
s=s.replace('gba_lines #(.SLOT_BITS(SLOT_BITS)) lines(.core_clk(cc)', '''gba_lines_psram #(.SLOT_BITS(SLOT_BITS)) lines(
        .memory_tick(tick),.pixel_ready(pixel_ready),.panel_data_ready(panel_data_ready),
        .write_req(wr),.write_addr(wa),.write_data(wd),.write_be(wb),.write_done(wdone),
        .read_req(rr),.read_addr(ra_mem),.read_done(rdone),.read_data(rq),.core_clk(sys)''')
s=s.replace('.pixel_we(we)', '.pixel_we(we&&tick)')
s=s.replace('#100000000;', '#300000000;')
# Stimulus keeps a transfer stable until a clock edge accepts it. The extra
# gated clock period separates coordinates across memory wait states.
(w/'tb.sv').write_text(s)
for partial in (0,1):
 exe=w/f'display{partial}.vvp'
 subprocess.run(['iverilog','-g2012','-Irtl','-I../arduboy/rtl/fast_oled','-s','tb_gba_psram_display','-Ptb_gba_psram_display.SLOT_BITS=1',f'-Ptb_gba_psram_display.PARTIAL_START={partial}','-o',str(exe),str(w/'tb.sv'),'rtl/bram_priority/gba_lines_psram.sv','rtl/gba_display.v','rtl/gba_oled_init.v','../arduboy/rtl/fast_oled/simple_spi_master.v'],check=True)
 subprocess.run(['vvp',str(exe)],check=True)
