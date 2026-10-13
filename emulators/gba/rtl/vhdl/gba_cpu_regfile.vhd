library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- All thirty physical ARM general registers, with asynchronous read ports.
-- A validity bit per word makes warm reset independent of RAM contents.
-- Private RAM layout: shared R0-R12 at 0-12, user SP/LR at 14-15,
-- FIQ R8-R12 at 16-20, and exception SP/LR pairs at 22-31.
-- Aligning banks makes FIQ address selection wiring rather than addition.
entity gba_cpu_regfile is
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
architecture rtl of gba_cpu_regfile is
  type ram_t is array(0 to 31) of unsigned(31 downto 0);
  signal ram : ram_t;
  signal valid : std_logic_vector(31 downto 0) := (others => '0');
  signal addr_n, addr_m, addr_d, addr_a, addr_b, addr_s, addr_lr, addr_write : integer range 0 to 31;
  signal read_base, write_base, block_base, dest_base : unsigned(4 downto 0);
  signal read_fiq, write_fiq, block_fiq, dest_fiq : boolean;
  function stack_base(mode : std_logic_vector(3 downto 0)) return unsigned is
  begin
    case mode is
      when x"1" => return to_unsigned(22,5); -- FIQ
      when x"2" => return to_unsigned(24,5); -- IRQ
      when x"3" => return to_unsigned(26,5); -- supervisor
      when x"7" => return to_unsigned(28,5); -- abort
      when x"B" => return to_unsigned(30,5); -- undefined
      when others => return to_unsigned(14,5); -- user/system
    end case;
  end;
  function physical(index : unsigned(3 downto 0); fiq : boolean;
                    base : unsigned(4 downto 0)) return integer is
  begin
    if index<8 then return to_integer(index);
    elsif index<13 then
      if fiq then return to_integer(to_unsigned(2,2) & index(2 downto 0));
      else return to_integer(index); end if;
    elsif index<15 then return to_integer(base(4 downto 1) & not index(0));
    else return 0; end if;
  end;
begin
  read_base <= stack_base(read_mode);
  write_base <= stack_base(write_mode);
  block_base <= to_unsigned(14,5) when block_user='1' else read_base;
  dest_base <= to_unsigned(14,5) when dest_user='1' else read_base;
  read_fiq <= read_mode=x"1";
  write_fiq <= write_mode=x"1";
  block_fiq <= read_fiq and block_user/='1';
  dest_fiq <= read_fiq and dest_user/='1';
  addr_n <= physical(rn,read_fiq,read_base);
  addr_m <= physical(rm,read_fiq,read_base);
  addr_d <= physical(rd,dest_fiq,dest_base);
  addr_a <= physical(ra,read_fiq,read_base);
  addr_s <= physical(rs,read_fiq,read_base);
  addr_b <= physical(rb,block_fiq,block_base);
  addr_lr <= physical(to_unsigned(14,4),read_fiq,read_base);
  addr_write <= physical(write_index,write_fiq,write_base);
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
