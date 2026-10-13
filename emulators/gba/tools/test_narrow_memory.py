"""Check width specialization, byte enables, bit masks and cache aliases."""
import subprocess
from pathlib import Path
w=Path('build/narrow-memory');w.mkdir(parents=True,exist_ok=True)
source=Path('sim/tb_gba_vram_hi_external.vhd').read_text()
for width,masked in [(32,False),(16,False),(3,False),(3,True),(1,True)]:
 name=f'tb_narrow_{width}_{int(masked)}'
 s=source.replace('tb_gba_vram_hi_external',name)
 s=s.replace(' signal checks:integer:=0;', " signal bits_mask:std_logic_vector(31 downto 0):=(others=>'1');\n signal checks:integer:=0;")
 s=s.replace('dut:entity work.gba_vram_hi_external port map(',f'dut:entity work.gba_vram_hi_external generic map(DATA_BITS=>{width},BIT_MASK_WRITE=>{str(masked).lower()}) port map(')
 s=s.replace('wd,mb,rd,done);','wd,mb,rd,done,bits_mask);')
 if masked:
  s=s.replace(" reset<='1';wait for 200 ns;reset<='0';set_ports",f''' for bits in 0 to {2**width-1} loop
 bits_mask<=(others=>'1');set_ports(8191,8191,'1',x"ffffffff","1111");
 bits_mask<=std_logic_vector(to_unsigned(bits,32));set_ports(8191,8191,'1',x"00000000","1111");
 set_ports(8191,8191,'0',(others=>'0'),"1111");
 assert unsigned(ram(8191))=to_unsigned({2**width-1}-bits,32)
   report "bit-masked write lost unrelated fields" severity failure;
 end loop;
 reset<='1';wait for 200 ns;reset<='0';set_ports''')
 s=s.replace('PASS upper VRAM:',f'PASS width {width}, bit-mask {masked}:')
 path=w/(name+'.vhd');path.write_text(s)
 subprocess.run(['ghdl','-a','--std=08','--workdir='+str(w),'rtl/bram_priority/gba_vram_hi_external.vhd',str(path)],check=True)
 subprocess.run(['ghdl','-r','--std=08','--workdir='+str(w),name,'--assert-level=error'],check=True)
