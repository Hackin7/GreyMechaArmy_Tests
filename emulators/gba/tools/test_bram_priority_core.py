#!/usr/bin/env python3
"""Run the existing BIOS/diagnostic acceptance test with clock-stop upper VRAM."""
import argparse
import subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--work',type=Path,default=Path('/tmp/greymecha_gba_bram_priority'));a=p.parse_args();w=a.work
s=Path('sim/tb_gba_board_core.sv').read_text()
s=s.replace('module tb_gba_board_core;','module tb_gba_bram_priority_core;')
s=s.replace('    gba_core_wrapper dut(.clk_100(clk)', '''
    wire emu_clk,upper_ready,ur,uread,ud;
    wire [12:0] ua;wire [31:0] uw;wire [3:0] ub;
    wire [10:0] sr_ready,sr_req,sr_read;reg [10:0] sr_done=0,sr_pending=0;
    wire [142:0] sr_addr;wire [351:0] sr_data;wire [43:0] sr_be;
    reg [31:0] sr_q=0,scratch[0:2815];
    integer sc=0,so=0,sa=0,selected;reg sr_active=0;reg [10:0] sp;
    initial for(integer n=0;n<2816;n=n+1)scratch[n]=0;
    always @(posedge clk)begin
      sr_done<=0;sp=sr_pending|sr_req;
      if(sr_active)begin
        if(sc==0)begin
          sa=so*256+sr_addr[so*13+:13];
          if(sr_read[so])sr_q<=scratch[sa];
          else for(integer b=0;b<4;b=b+1)if(sr_be[so*4+b])scratch[sa][b*8+:8]<=sr_data[so*32+b*8+:8];
          sr_done[so]<=1;sr_active<=0;
        end else sc<=sc-1;
      end else begin
        selected=-1;
        for(integer n=0;n<11;n=n+1)if(sp[n]&&selected<0)selected=n;
        if(selected>=0)begin
          so<=selected;sc<=3+selected;sr_active<=1;sp[selected]=0;
        end
      end
      sr_pending<=sp;
    end
    reg [31:0] uq=0,upper[0:8191];integer uc=0;reg [12:0] uh;
    reg ureadh;reg [31:0] uwh;reg [3:0] ubh;reg ud_raw=0;
    reg tick=1;always @(negedge clk)tick<=!reset_n||(upper_ready&&(&sr_ready));
    assign emu_clk=clk&&tick;
    wire rd_hold,ed_hold,vd_hold;wire [31:0] r_hold,s_hold,e_hold,v_hold;
    gba_step_response rresp(clk,!reset_n,tick,rd,rdata,rd_hold,r_hold);
    gba_step_response sresp(clk,!reset_n,tick,rd,second,,s_hold);
    gba_step_response eresp(clk,!reset_n,tick,ed,edata,ed_hold,e_hold);
    gba_step_response vresp(clk,!reset_n,tick,vd,vdata,vd_hold,v_hold);
    assign ud=ud_raw;
    always @(posedge clk)begin
      ud_raw<=0;
      if(ur)begin if(uc!=0)$fatal(1,"upper overlapping request");uc<=7+(ua%13);uh<=ua;uwh<=uw;ubh<=ub;ureadh<=uread;end
      if(uc>0)begin uc<=uc-1;if(uc==1)begin
        if(ureadh)uq<=upper[uh];else for(integer b=0;b<4;b=b+1)if(ubh[b])upper[uh][8*b+:8]<=uwh[8*b+:8];
        ud_raw<=1;
      end end
    end
    gba_core_wrapper_priority dut(.clk_memory(clk),.memory_tick(tick),
        .scratch_ready(sr_ready),.scratch_req(sr_req),.scratch_read(sr_read),
        .scratch_addr(sr_addr),.scratch_wdata(sr_data),.scratch_be(sr_be),
        .scratch_rdata(sr_q),.scratch_done(sr_done),
        .upper_ready(upper_ready),.upper_req(ur),.upper_read(uread),.upper_addr(ua),
        .upper_wdata(uw),.upper_be(ub),.upper_rdata(uq),.upper_done(ud),.clk_100(emu_clk)''')
for original,replacement in [('.rom_done(rd)','.rom_done(rd_hold)'),('.rom_data(rdata)','.rom_data(r_hold)'),('.rom_second_data(second)','.rom_second_data(s_hold)'),('.ext_read_data(edata)','.ext_read_data(e_hold)'),('.ext_done(ed)','.ext_done(ed_hold)'),('.vram_rdata(vdata)','.vram_rdata(v_hold)'),('.vram_done(vd)','.vram_done(vd_hold)'),('if(vr)','if(vr&&tick)'),('if(rr)','if(rr&&tick)'),('if(er)','if(er&&tick)'),('if(pwe&&','if(pwe&&tick&&')]:s=s.replace(original,replacement)
s=s.replace('for(i=0;i<16384;i=i+1)vram[i]=0;', 'for(i=0;i<16384;i=i+1)vram[i]=0;for(i=0;i<8192;i=i+1)upper[i]=0;')
s=s.replace('cycles%100000==0','cycles%1000000==0')
s=s.replace('$fflush();', '$display("r2=%h r4=%h tick=%b",{dut.core.igba_cpu.registers.ram_n2[2],dut.core.igba_cpu.registers.ram_n1[2]},{dut.core.igba_cpu.registers.ram_n2[4],dut.core.igba_cpu.registers.ram_n1[4]},tick);$fflush();')
(w/'tb_priority.sv').write_text(s)
subprocess.run(['verilator','--binary','--timing','-Wno-fatal','--top-module','tb_gba_bram_priority_core','--Mdir',str(w/'verilator'),'-j','4',str(w/'gba_top.v'),str(w/'gba_core_wrapper_priority.sv'),'rtl/bram_priority/gba_local_mem.sv',str(w/'tb_priority.sv')],check=True)
subprocess.run([str(w/'verilator/Vtb_gba_bram_priority_core'),'+FASTMEM'],check=True)
