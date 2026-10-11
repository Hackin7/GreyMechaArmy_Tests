library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_gba_cpu_regfile is end;
architecture sim of tb_gba_cpu_regfile is
  signal clk : std_logic := '0';
  signal reset,we,user_bank : std_logic := '0';
  signal read_mode,write_mode : std_logic_vector(3 downto 0) := x"F";
  signal index,write_index : unsigned(3 downto 0) := (others=>'0');
  signal data,n,m,d,a,b,lr : unsigned(31 downto 0) := (others=>'0');
  signal s : unsigned(7 downto 0);
  constant pc : unsigned(31 downto 0) := x"12345678";
  type modes_t is array(0 to 6) of std_logic_vector(3 downto 0);
  constant modes : modes_t := (x"F",x"1",x"2",x"3",x"7",x"B",x"0");
begin
  clk <= not clk after 5 ns;
  dut : entity work.gba_cpu_regfile port map(clk=>clk,reset=>reset,write_enable=>we,
    read_mode=>read_mode,write_mode=>write_mode,write_index=>write_index,
    write_data=>data,pc=>pc,rn=>index,rm=>index,rd=>index,ra=>index,rs=>index,rb=>index,
    block_user=>user_bank,data_n=>n,data_m=>m,data_d=>d,data_a=>a,data_s=>s,data_b=>b,data_lr=>lr);
  process
    type common_t is array(0 to 12) of unsigned(31 downto 0);
    type fiq_t is array(8 to 12) of unsigned(31 downto 0);
    type stack_t is array(0 to 5,13 to 14) of unsigned(31 downto 0);
    variable common : common_t := (others=>(others=>'0'));
    variable fiq : fiq_t := (others=>(others=>'0'));
    variable stacks : stack_t := (others=>(others=>(others=>'0')));
    procedure step is begin wait until falling_edge(clk); end;
    procedure put(bank,regnum : natural; value : unsigned(31 downto 0)) is begin
      write_mode<=modes(bank); write_index<=to_unsigned(regnum,4); data<=value; we<='1'; step; we<='0';
      if regnum<8 then common(regnum):=value;
      elsif regnum<13 then
        if bank=1 then fiq(regnum):=value; else common(regnum):=value; end if;
      else stacks(bank,regnum):=value; end if;
    end;
    impure function expected(bank,regnum : natural) return unsigned is begin
      if regnum=15 then return pc;
      elsif regnum<8 then return common(regnum);
      elsif regnum<13 then
        if bank=1 then return fiq(regnum); else return common(regnum); end if;
      else
        if bank=6 then return stacks(0,regnum); else return stacks(bank,regnum); end if;
      end if;
    end;
    procedure check_all is
      variable wanted,block_wanted : unsigned(31 downto 0);
    begin
      for bank in modes'range loop
        read_mode<=modes(bank);
        for regnum in 0 to 15 loop
          index<=to_unsigned(regnum,4); step;
          wanted:=expected(bank,regnum);
          assert n=wanted and m=wanted and d=wanted and a=wanted and s=wanted(7 downto 0)
            report "Register data mismatch bank=" & integer'image(bank) & " reg=" & integer'image(regnum) severity failure;
          if user_bank='1' then block_wanted:=expected(0,regnum); else block_wanted:=wanted; end if;
          assert b=block_wanted report "STM user bank mismatch" severity failure;
          assert lr=expected(bank,14) report "Banked LR mismatch" severity failure;
        end loop;
      end loop;
    end;
  begin
    reset<='1'; step; reset<='0'; check_all;
    for regnum in 0 to 14 loop put(0,regnum,to_unsigned(16#1000#+regnum,32)); end loop;
    for regnum in 8 to 14 loop put(1,regnum,to_unsigned(16#2000#+regnum,32)); end loop;
    put(1,0,x"87654321"); -- R0 stays shared across FIQ and all other modes.
    for bank in 2 to 5 loop
      for regnum in 13 to 14 loop put(bank,regnum,to_unsigned(16#3000#+bank*256+regnum,32)); end loop;
    end loop;
    check_all; user_bank<='1'; check_all; user_bank<='0';
    reset<='1'; step; reset<='0';
    common:=(others=>(others=>'0')); fiq:=(others=>(others=>'0')); stacks:=(others=>(others=>(others=>'0')));
    check_all;
    put(0,5,x"FEDCBA98"); check_all;
    report "PASS banked register RAM: all read ports, six ARM banks, user/system alias, FIQ sharing, STM user selection, warm reset";
    finish;
  end process;
end;
