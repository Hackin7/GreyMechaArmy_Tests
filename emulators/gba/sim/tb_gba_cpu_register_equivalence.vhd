library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_gba_cpu_register_equivalence is end;
architecture sim of tb_gba_cpu_register_equivalence is
  signal clk : std_logic := '0';
  signal reset,we,user_bank,dest_user : std_logic := '0';
  signal mode,wmode : std_logic_vector(3 downto 0) := x"0";
  signal rn,rm,rd,ra,rs,rb,wi : unsigned(3 downto 0) := (others=>'0');
  signal wd,pc : unsigned(31 downto 0) := (others=>'0');
  type words is array(0 to 5) of unsigned(31 downto 0);
  signal original,candidate : words;
  signal os,cs : unsigned(7 downto 0);
begin
  clk <= not clk after 5 ns;
  reference : entity work.gba_cpu_regfile_reference port map(
    clk,reset,we,mode,wmode,wi,wd,pc,rn,rm,rd,ra,rs,rb,user_bank,dest_user,
    original(0),original(1),original(2),original(3),original(4),original(5),os);
  dut : entity work.gba_cpu_regfile port map(
    clk,reset,we,mode,wmode,wi,wd,pc,rn,rm,rd,ra,rs,rb,user_bank,dest_user,
    candidate(0),candidate(1),candidate(2),candidate(3),candidate(4),candidate(5),cs);
  process
    variable seed : unsigned(31 downto 0) := x"12345678";
    procedure check is begin
      wait for 1 ns;
      assert original=candidate and os=cs report "Register file differs from 880cefb" severity failure;
    end;
    procedure randomize is begin
      seed:=seed xor shift_left(seed,13);
      seed:=seed xor shift_right(seed,17);
      seed:=seed xor shift_left(seed,5);
    end;
  begin
    reset<='1'; wait until falling_edge(clk); reset<='0'; check;
    -- Write every bank/word, then test independent read ports and user overrides.
    for bank in 0 to 15 loop
      for word in 0 to 15 loop
        wmode<=std_logic_vector(to_unsigned(bank,4)); wi<=to_unsigned(word,4);
        randomize; wd<=seed; we<='1'; wait until falling_edge(clk); check;
      end loop;
    end loop;
    we<='0';
    for flags in 0 to 3 loop
      user_bank<=to_unsigned(flags,2)(0); dest_user<=to_unsigned(flags,2)(1);
      for bank in 0 to 15 loop
        mode<=std_logic_vector(to_unsigned(bank,4));
        for word in 0 to 15 loop
          rn<=to_unsigned(word,4); rm<=to_unsigned((word+1) mod 16,4);
          rd<=to_unsigned((word+2) mod 16,4); ra<=to_unsigned((word+3) mod 16,4);
          rs<=to_unsigned((word+4) mod 16,4); rb<=to_unsigned((word+5) mod 16,4);
          pc<=seed; randomize; check;
        end loop;
      end loop;
    end loop;
    -- Include writes, read/write collisions, ignored PC writes and warm reset.
    for tick in 0 to 8191 loop
      randomize; wd<=seed; pc<=not seed;
      rn<=seed(3 downto 0); rm<=seed(7 downto 4); rd<=seed(11 downto 8);
      ra<=seed(15 downto 12); rs<=seed(19 downto 16); rb<=seed(23 downto 20);
      wi<=seed(3 downto 0); mode<=std_logic_vector(seed(27 downto 24));
      wmode<=std_logic_vector(seed(31 downto 28)); we<=seed(4);
      user_bank<=seed(5); dest_user<=seed(6);
      if tick mod 257=0 then reset<='1'; else reset<='0'; end if;
      check; wait until falling_edge(clk); check;
    end loop;
    report "PASS register equivalence: all modes/indices, independent ports, user overrides, collisions and warm reset";
    finish;
  end process;
end;
