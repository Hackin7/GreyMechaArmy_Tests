library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- External 64 KiB VRAM bank. CPU requests retain the original byte enables;
-- four read caches serve the background engines through their existing mux.
-- A cache miss suppresses the mux's valid signal, so fetchers wait for data.
entity gba_vram_low_ext is
  port (
    clk, reset : in std_logic;
    cpu_addr : in integer range 0 to 16383;
    cpu_din : in std_logic_vector(31 downto 0);
    cpu_re, cpu_we : in std_logic;
    cpu_be : in std_logic_vector(3 downto 0);
    cpu_dout : out std_logic_vector(31 downto 0) := (others => '0');
    cpu_done : out std_logic := '0';
    addr0, addr1, addr2, addr3, mux_addr : in integer range 0 to 16383;
    ppu_data : out std_logic_vector(31 downto 0) := (others => '0');
    ppu_hit : out std_logic := '0';
    mem_req, mem_read : out std_logic := '0';
    mem_addr : out std_logic_vector(13 downto 0) := (others => '0');
    mem_wdata : out std_logic_vector(31 downto 0) := (others => '0');
    mem_be : out std_logic_vector(3 downto 0) := (others => '0');
    mem_rdata : in std_logic_vector(31 downto 0);
    mem_done : in std_logic
  );
end entity;

architecture rtl of gba_vram_low_ext is
  type addresses is array (0 to 3) of integer range 0 to 16383;
  type words is array (0 to 3) of std_logic_vector(31 downto 0);
  signal wanted, tags : addresses := (others => 0);
  signal cache : words := (others => (others => '0'));
  signal valid : std_logic_vector(0 to 3) := (others => '0');
  signal pending, busy, cpu_owner : std_logic := '0';
  signal held_addr : integer range 0 to 16383 := 0;
  signal held_data : std_logic_vector(31 downto 0) := (others => '0');
  signal held_be : std_logic_vector(3 downto 0) := (others => '0');
  signal held_read : std_logic := '1';
  signal turn, fill_slot : integer range 0 to 3 := 0;
  signal fill_addr : integer range 0 to 16383 := 0;
begin
  wanted <= (addr0, addr1, addr2, addr3);
  process(clk)
    variable write_conflict : boolean;
  begin
    if rising_edge(clk) then
      mem_req <= '0'; cpu_done <= '0'; ppu_hit <= '0';
      -- One synchronous read cycle, matching the replaced dual-port RAM.
      write_conflict := (cpu_we = '1' and cpu_addr = mux_addr) or
        (held_read = '0' and held_addr = mux_addr and
          (pending = '1' or (busy = '1' and cpu_owner = '1')));
      for n in 0 to 3 loop
        if valid(n) = '1' and tags(n) = mux_addr and not write_conflict then
          ppu_data <= cache(n); ppu_hit <= '1';
        end if;
      end loop;
      if reset = '1' then
        pending <= '0'; busy <= '0'; valid <= (others => '0');
        cpu_owner <= '0'; turn <= 0; ppu_hit <= '0';
        mem_req <= '0'; cpu_done <= '0';
      else
        if cpu_re = '1' or cpu_we = '1' then
          -- synthesis translate_off
          assert pending = '0' report "Overlapping CPU VRAM requests" severity failure;
          -- synthesis translate_on
          pending <= '1'; held_addr <= cpu_addr; held_data <= cpu_din;
          held_be <= cpu_be; held_read <= not cpu_we;
          if cpu_we = '1' then
            for n in 0 to 3 loop
              if tags(n) = cpu_addr then valid(n) <= '0'; end if;
            end loop;
          end if;
        end if;
        if busy = '0' then
          if pending = '1' then
            mem_addr <= std_logic_vector(to_unsigned(held_addr, 14));
            mem_read <= held_read; mem_wdata <= held_data; mem_be <= held_be;
            mem_req <= '1'; busy <= '1'; cpu_owner <= '1'; pending <= '0';
          elsif valid(turn) = '0' or tags(turn) /= wanted(turn) then
            mem_addr <= std_logic_vector(to_unsigned(wanted(turn), 14));
            mem_read <= '1'; mem_be <= "1111"; mem_req <= '1';
            fill_slot <= turn; fill_addr <= wanted(turn);
            busy <= '1'; cpu_owner <= '0';
          end if;
          turn <= (turn + 1) mod 4;
        elsif mem_done = '1' then
          busy <= '0';
          if cpu_owner = '1' then
            cpu_dout <= mem_rdata; cpu_done <= '1';
            if held_read = '0' then
              for n in 0 to 3 loop
                if tags(n) = held_addr then valid(n) <= '0'; end if;
              end loop;
            end if;
          else
            tags(fill_slot) <= fill_addr; cache(fill_slot) <= mem_rdata;
            valid(fill_slot) <= '1';
            -- A queued CPU write supersedes an older read response.
            if (pending = '1' and held_read = '0' and held_addr = fill_addr) or
               (cpu_we = '1' and cpu_addr = fill_addr) then
              valid(fill_slot) <= '0';
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
