-- Immutable register-file reference from origin/gba at 880cefb.
-- Keep the original bank mapping for architectural equivalence checks.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- All thirty physical ARM general registers, with asynchronous read ports.
-- A validity bit per word makes warm reset independent of RAM contents.
entity gba_cpu_regfile_reference is
  port(clk, reset, write_enable : in std_logic;
       read_mode, write_mode : in std_logic_vector(3 downto 0);
       write_index : in unsigned(3 downto 0);
       write_data, pc : in unsigned(31 downto 0);
       rn, rm, rd, ra, rs, rb : in unsigned(3 downto 0);
       block_user : in std_logic;
       dest_user : in std_logic := '0';
       data_n, data_m, data_d, data_a, data_b, data_lr : out unsigned(31 downto 0);
       data_s : out unsigned(7 downto 0));
end;
architecture rtl of gba_cpu_regfile_reference is
  type ram_t is array(0 to 31) of unsigned(31 downto 0);
  signal ram : ram_t;
  signal valid : std_logic_vector(31 downto 0) := (others => '0');
  signal addr_n, addr_m, addr_d, addr_a, addr_b, addr_s, addr_lr, addr_write : integer range 0 to 31;
  signal block_mode, dest_mode : std_logic_vector(3 downto 0);
  function physical(index : unsigned(3 downto 0); mode : std_logic_vector(3 downto 0)) return integer is
    variable bank : integer range 0 to 5;
    variable reg_index : integer range 0 to 15;
  begin
    reg_index := to_integer(index);
    case mode is
      when x"1" => bank:=1; -- FIQ
      when x"2" => bank:=2; -- IRQ
      when x"3" => bank:=3; -- supervisor
      when x"7" => bank:=4; -- abort
      when x"B" => bank:=5; -- undefined
      when others => bank:=0; -- user/system
    end case;
    if reg_index<8 then return reg_index;
    elsif reg_index<13 then
      if bank=1 then return reg_index+5; else return reg_index; end if;
    elsif reg_index<15 then return 18+bank*2+reg_index-13;
    else return 0; end if;
  end;
begin
  block_mode <= x"0" when block_user='1' else read_mode;
  dest_mode <= x"0" when dest_user='1' else read_mode;
  addr_n <= physical(rn,read_mode);
  addr_m <= physical(rm,read_mode);
  addr_d <= physical(rd,dest_mode);
  addr_a <= physical(ra,read_mode);
  addr_s <= physical(rs,read_mode);
  addr_b <= physical(rb,block_mode);
  addr_lr <= physical(to_unsigned(14,4),read_mode);
  addr_write <= physical(write_index,write_mode);
  data_n <= pc when rn=15 else ram(addr_n) when valid(addr_n)='1' else (others=>'0');
  data_m <= pc when rm=15 else ram(addr_m) when valid(addr_m)='1' else (others=>'0');
  data_d <= pc when rd=15 else ram(addr_d) when valid(addr_d)='1' else (others=>'0');
  data_a <= pc when ra=15 else ram(addr_a) when valid(addr_a)='1' else (others=>'0');
  data_s <= pc(7 downto 0) when rs=15 else ram(addr_s)(7 downto 0) when valid(addr_s)='1' else (others=>'0');
  data_b <= pc when rb=15 else ram(addr_b) when valid(addr_b)='1' else (others=>'0');
  data_lr <= ram(addr_lr) when valid(addr_lr)='1' else (others=>'0');
  process(clk)
  begin
    if rising_edge(clk) then
      if reset='1' then valid <= (others=>'0');
      elsif write_enable='1' and write_index<15 then
        ram(addr_write) <= write_data;
        valid(addr_write) <= '1';
      end if;
    end if;
  end process;
end;
