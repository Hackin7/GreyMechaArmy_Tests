library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_gba_vram_low_ext is end;
architecture sim of tb_gba_vram_low_ext is
  signal clk : std_logic := '0';
  signal reset, re, we, done, req, rd, mdone, hit : std_logic := '0';
  signal ca, a0, mux : integer range 0 to 16383 := 0;
  signal din, dout, data, wdata, rdata : std_logic_vector(31 downto 0) := (others=>'0');
  signal be, mbe : std_logic_vector(3 downto 0) := "1111";
  signal ma : std_logic_vector(13 downto 0);
begin
  clk <= not clk after 5 ns;
  dut: entity work.gba_vram_low_ext port map(
    clk=>clk,reset=>reset,cpu_addr=>ca,cpu_din=>din,cpu_re=>re,cpu_we=>we,cpu_be=>be,
    cpu_dout=>dout,cpu_done=>done,addr0=>a0,addr1=>1,addr2=>2,addr3=>3,mux_addr=>mux,
    ppu_data=>data,ppu_hit=>hit,mem_req=>req,mem_read=>rd,mem_addr=>ma,
    mem_wdata=>wdata,mem_be=>mbe,mem_rdata=>rdata,mem_done=>mdone);
  process(clk)
    type ram_t is array(0 to 16383) of std_logic_vector(31 downto 0);
    variable ram : ram_t := (others => x"5A000000");
    variable delay : natural := 0;
    variable address : natural := 0;
    variable read_value, write_value : std_logic_vector(31 downto 0);
    variable read_op : std_logic;
    variable lanes : std_logic_vector(3 downto 0);
  begin
    if rising_edge(clk) then
      mdone <= '0';
      if req = '1' then
        assert delay = 0 report "Overlapping VRAM memory operations" severity failure;
        address := to_integer(unsigned(ma)); read_op := rd;
        read_value := ram(address); write_value := wdata; lanes := mbe;
        delay := 10 + address mod 13;
      elsif delay > 0 then
        delay := delay - 1;
        if delay = 0 then
          if read_op='1' then rdata<=read_value;
          else
            for n in 0 to 3 loop
              if lanes(n)='1' then ram(address)(n*8+7 downto n*8):=write_value(n*8+7 downto n*8); end if;
            end loop;
          end if;
          mdone <= '1';
        end if;
      end if;
    end if;
  end process;
  process
    procedure step(n : positive := 1) is begin
      for j in 1 to n loop wait until falling_edge(clk); end loop;
    end;
    procedure access_word(address : natural; value : std_logic_vector(31 downto 0);
                          lanes : std_logic_vector(3 downto 0); reading : boolean := false) is
      variable timeout : natural := 0;
    begin
      ca<=address;din<=value;be<=lanes;
      if reading then re<='1';else we<='1';end if;
      step;re<='0';we<='0';
      while done/='1' loop step;timeout:=timeout+1;assert timeout<1000 severity failure;end loop;
      step;
    end;
  begin
    reset<='1';step(3);reset<='0';step(200);
    for j in 0 to 3 loop mux<=j;step(3);assert hit='1' and data=x"5A000000" severity failure;end loop;
    access_word(2,x"11223344","1111");step(100);mux<=2;step(3);
    assert hit='1' and data=x"11223344" report "CPU write did not invalidate PPU cache" severity failure;
    access_word(2,x"AABBCCDD","0101");access_word(2,x"00000000","0000",true);
    assert dout=x"11BB33DD" report "VRAM byte enables/readback" severity failure;
    step(100);assert hit='1' and data=x"11BB33DD" severity failure;
    a0<=16383;mux<=16383;
    wait until rising_edge(clk) and req='1' and ma=std_logic_vector(to_unsigned(16383,14));
    wait until falling_edge(clk);
    access_word(16383,x"DEADBEEF","1111");step(100);
    assert hit='1' and data=x"DEADBEEF" report "Old in-flight read survived queued CPU write" severity failure;
    access_word(16383,x"12345678","0000");step(100);
    assert hit='1' and data=x"DEADBEEF" report "Disabled byte lanes wrote VRAM" severity failure;
    report "PASS external VRAM: variable latency, four PPU caches, CPU byte enables, last address, write invalidation, queued-write coherence";
    finish;
  end process;
  process begin wait for 1 ms;assert false report "VRAM test timeout" severity failure;end process;
end;
