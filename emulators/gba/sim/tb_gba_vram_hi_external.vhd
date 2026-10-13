library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_gba_vram_hi_external is end;
architecture test of tb_gba_vram_hi_external is
 signal sys,clk,step,ready,reset,we,req,rnw,done:std_logic:='0';
 signal aa,ab:integer range 0 to 8191:=0;
 signal din,qa,qb,rd,wd:std_logic_vector(31 downto 0):=(others=>'0');
 signal be,mb:std_logic_vector(3 downto 0):="1111";
 signal ma:std_logic_vector(12 downto 0);
 type memory_t is array(0 to 8191) of std_logic_vector(31 downto 0);
 signal ram:memory_t:=(others=>(others=>'0'));
 signal checks:integer:=0;
begin
 sys<=not sys after 25 ns;
 process(sys)begin if falling_edge(sys)then step<=ready or reset;end if;end process;
 clk<=sys and step;
 dut:entity work.gba_vram_hi_external port map(clk,sys,step,reset,aa,ab,din(7 downto 0),din(15 downto 8),din(23 downto 16),din(31 downto 24),qa,qb,we,be,ready,req,rnw,ma,wd,mb,rd,done);
 process
 variable address:integer;variable delay:integer:=0;
 begin
 wait until rising_edge(sys);done<='0';
 if req='1' then
 address:=to_integer(unsigned(ma));
 assert address<8192 severity failure;
 delay:=(delay+3) mod 11;
 for i in 0 to delay loop wait until rising_edge(sys);assert req='0' report "duplicate upper request" severity failure;end loop;
 if rnw='1' then rd<=ram(address);
 else for i in 0 to 3 loop if mb(i)='1'then ram(address)(8*i+7 downto 8*i)<=wd(8*i+7 downto 8*i);end if;end loop;end if;
 done<='1';wait until rising_edge(sys);done<='0';
 end if;
 end process;
 process
 procedure set_ports(a,b:integer;w:std_logic;value:std_logic_vector(31 downto 0);mask:std_logic_vector(3 downto 0)) is
 begin
 wait until rising_edge(clk);wait for 1 ns;aa<=a;ab<=b;we<=w;din<=value;be<=mask;
 wait until rising_edge(clk);wait for 1 ns;
 if w='0'then assert qa=ram(a) and qb=ram(b) report "synchronous read mismatch" severity failure;checks<=checks+1;end if;
 end;
 variable expected:std_logic_vector(31 downto 0);
 begin
 reset<='1';wait for 200 ns;wait until falling_edge(sys);reset<='0';
 for i in 0 to 127 loop
 set_ports(i*61 mod 8192,(i*47+7)mod 8192,'1',std_logic_vector(to_unsigned(i*4567+5,32)),"1111");
 set_ports(i*61 mod 8192,(i*47+7)mod 8192,'0',(others=>'0'),"1111");
 end loop;
 for mask in 0 to 15 loop
 set_ports(8191,8191,'1',x"11223344","1111");
 set_ports(8191,8191,'1',x"aabbccdd",std_logic_vector(to_unsigned(mask,4)));
 set_ports(8191,8191,'0',(others=>'0'),"1111");
 end loop;
 reset<='1';wait for 200 ns;reset<='0';set_ports(8191,0,'0',(others=>'0'),"1111");
 report "PASS upper VRAM: delayed two-port reads, full/partial writes, cache aliases and reset";
 stop;wait;
 end process;
 process begin wait for 2 ms;assert false report "upper VRAM timeout" severity failure;end process;
end;
