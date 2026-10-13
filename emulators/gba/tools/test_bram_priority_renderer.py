#!/usr/bin/env python3
"""Compare every tested graphics mode while upper VRAM stops the core clock."""
import argparse
import subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--work',type=Path,default=Path('/tmp/greymecha_gba_bram_priority'));a=p.parse_args();w=a.work
subprocess.run(['python3','tools/renderer_reference.py','vendor/openfpga-GBA/src/fpga/gba',str(w/'reference')],check=True)
s=Path('sim/tb_gba_renderer.vhd').read_text().replace('tb_gba_renderer','tb_gba_priority_renderer')
s=s.replace('architecture sim of tb_gba_priority_renderer is','architecture sim of tb_gba_priority_renderer is\n signal mem_reset:std_logic:=\'0\';')
s=s.replace('drawer_ready => ready(', 'external_reset=>mem_reset,drawer_ready => ready(')
s=s.replace("    bus_in.rst<='1'; step(2); bus_in.rst<='0'; step(2);", "    mem_reset<='1';bus_in.rst<='1'; step(4); mem_reset<='0';bus_in.rst<='0'; step(4);")
s=s.replace('    for scene in 0 to 23 loop', "    for scene in 0 to 23 loop\n      if scene=8 or scene=16 then\n        mem_reset<='1';step(4);mem_reset<='0';step(4);\n        while ready/=\"11\"loop step;end loop;\n      end if;")
s=s.replace("  signal clk : std_logic := '0';", '''  signal clk,sys,step,upper_ready,ureq,urnw,udone:std_logic:='0';
  signal uaddr:std_logic_vector(12 downto 0);
  signal uwdata,urdata:std_logic_vector(31 downto 0);
  signal ube:std_logic_vector(3 downto 0);
  type upper_t is array(0 to 8191)of std_logic_vector(31 downto 0);
  signal upper:upper_t:=(others=>(others=>'0'));''')
s=s.replace('  clk <= not clk after 5 ns;', '''  sys<=not sys after 5 ns;
  process(sys)begin if falling_edge(sys)then step<=upper_ready;end if;end process;
  clk<=sys and step;
  process
    variable address,latency:natural;
    variable rd:std_logic;variable wd:std_logic_vector(31 downto 0);variable mask:std_logic_vector(3 downto 0);
  begin
    wait until rising_edge(sys);udone<='0';
    if ureq='1'then
      address:=to_integer(unsigned(uaddr));rd:=urnw;wd:=uwdata;mask:=ube;
      latency:=3+address mod 17;
      for n in 0 to latency loop wait until rising_edge(sys);end loop;
      if rd='1'then urdata<=upper(address);
      else for n in 0 to 3 loop if mask(n)='1'then upper(address)(n*8+7 downto n*8)<=wd(n*8+7 downto n*8);end if;end loop;end if;
      udone<='1';wait until rising_edge(sys);udone<='0';
    end if;
  end process;''')
s=s.replace("  type upper_t", '''  signal scratch_ready,scratch_req,scratch_read,scratch_done:std_logic_vector(10 downto 0):=(others=>'0');
  signal scratch_addr:std_logic_vector(142 downto 0);
  signal scratch_wdata:std_logic_vector(351 downto 0);
  signal scratch_be:std_logic_vector(43 downto 0);
  signal scratch_rdata:std_logic_vector(31 downto 0):=(others=>'0');
  type scratch_t is array(0 to 2815)of std_logic_vector(31 downto 0);
  signal scratch:scratch_t:=(others=>(others=>'0'));
  type upper_t''')
s=s.replace('step<=upper_ready;', 'step<=upper_ready and (and scratch_ready);')
s=s.replace('  sys<=not sys after 5 ns;', '''  process(sys)
    variable pending:std_logic_vector(10 downto 0):=(others=>'0');
    variable owner,remaining,address:natural:=0;
    variable active:boolean:=false;
  begin
    if rising_edge(sys)then
      scratch_done<=(others=>'0');pending:=pending or scratch_req;
      if active then
        if remaining=0 then
          address:=owner*256+to_integer(unsigned(scratch_addr(owner*13+12 downto owner*13)));
          if scratch_read(owner)='1'then scratch_rdata<=scratch(address);
          else
            for b in 0 to 3 loop
              if scratch_be(owner*4+b)='1'then
                scratch(address)(b*8+7 downto b*8)<=scratch_wdata(owner*32+b*8+7 downto owner*32+b*8);
              end if;
            end loop;
          end if;
          scratch_done(owner)<='1';active:=false;
        else remaining:=remaining-1;end if;
      else
        for i in 0 to 10 loop
          if not active and pending(i)='1'then
            owner:=i;pending(i):='0';remaining:=3+i;active:=true;
          end if;
        end loop;
      end if;
    end if;
  end process;
  sys<=not sys after 5 ns;''')
s=s.replace("dut1: entity work.gba_gpu_drawer generic map (is_simu => '1', ExternalVRAMLow => ExternalMemory) port map (", "dut1: entity work.gba_gpu_drawer generic map (is_simu => '1', ExternalVRAMLow => ExternalMemory) port map (\nclk_memory=>sys,memory_tick=>step,upper_ready=>upper_ready,upper_req=>ureq,upper_read=>urnw,upper_addr=>uaddr,upper_wdata=>uwdata,upper_be=>ube,upper_rdata=>urdata,upper_done=>udone,")
s=s.replace('clk_memory=>sys,memory_tick=>step,', 'scratch_ready=>scratch_ready,scratch_req=>scratch_req,scratch_read=>scratch_read,scratch_addr=>scratch_addr,scratch_wdata=>scratch_wdata,scratch_be=>scratch_be,scratch_rdata=>scratch_rdata,scratch_done=>scratch_done,clk_memory=>sys,memory_tick=>step,')
(w/'tb_priority_renderer.vhd').write_text(s)
flags=['--std=08','-fsynopsys','-frelaxed','-P'+str(w/'mem'),'--workdir='+str(w/'work')]
sources=[str(w/'reference'/name)for name in ['gba_drawer_obj_reference.vhd','gba_drawer_merge_reference.vhd','gba_gpu_drawer_reference.vhd']]+[str(w/'tb_priority_renderer.vhd')]
subprocess.run(['ghdl','-a']+flags+sources,check=True)
subprocess.run(['ghdl','-r']+flags+['tb_gba_priority_renderer','--assert-level=error','--ieee-asserts=disable-at-0'],check=True)
