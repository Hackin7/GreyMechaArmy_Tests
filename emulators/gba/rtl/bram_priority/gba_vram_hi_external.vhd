library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Preserve the upstream synchronous two-port RAM interface. A gated
-- emulator clock advances only once both read-port words are available.
-- This engine runs on the ungated memory clock and commits writes before
-- allowing another emulator clock edge. No sprite-engine timing rewrite.
entity gba_vram_hi_external is
  generic(READ_A : boolean := true; ADDRESS_MAX : natural := 8191;
          BIT_MASK_WRITE:boolean:=false; DATA_BITS:positive range 1 to 32:=32);
  port(clk, clk_memory, memory_tick, reset : in std_logic;
       addr_a, addr_b : in integer range 0 to ADDRESS_MAX;
       datain_a0,datain_a1,datain_a2,datain_a3 : in std_logic_vector(7 downto 0);
       dataout_a,dataout_b : out std_logic_vector(31 downto 0);
       we_a : in std_logic; be_a : in std_logic_vector(3 downto 0);
       ready : out std_logic;
       mem_req,mem_read : out std_logic := '0';
       mem_addr : out std_logic_vector(12 downto 0) := (others=>'0');
       mem_wdata : out std_logic_vector(31 downto 0) := (others=>'0');
       mem_be : out std_logic_vector(3 downto 0) := (others=>'0');
       mem_rdata : in std_logic_vector(31 downto 0); mem_done : in std_logic;
       bit_be:in std_logic_vector(31 downto 0):=(others=>'1'));
end;
architecture rtl of gba_vram_hi_external is
  type state_t is (IDLE, READ_WORD, WRITE_WORD);
  signal state : state_t := IDLE;
  type words_t is array(0 to 1)of std_logic_vector(DATA_BITS-1 downto 0);
  type tags_t is array(0 to 1)of integer range 0 to ADDRESS_MAX;
  signal ca : std_logic_vector(DATA_BITS-1 downto 0) := (others=>'0');
  signal cb:words_t:=(others=>(others=>'0'));
  signal ta,held_addr : integer range 0 to ADDRESS_MAX := 0;
  signal tb:tags_t:=(others=>0);
  signal va : std_logic := '0';signal vb:std_logic_vector(0 to 1):="00";
  signal replace_b,held_b:integer range 0 to 1:=0;
  signal hit_b0,hit_b1:std_logic;
  signal hit_a,hit_b,owner_b : std_logic;
  signal din : std_logic_vector(DATA_BITS-1 downto 0);
  signal raw_din : std_logic_vector(31 downto 0);
begin
  raw_din <= datain_a3 & datain_a2 & datain_a1 & datain_a0;
  din <= (raw_din(DATA_BITS-1 downto 0) and bit_be(DATA_BITS-1 downto 0)) or
         (ca and not bit_be(DATA_BITS-1 downto 0)) when BIT_MASK_WRITE else raw_din(DATA_BITS-1 downto 0);
  hit_a <= '1' when not READ_A or (va='1' and ta=addr_a) else '0';
  hit_b0 <= '1' when vb(0)='1' and tb(0)=addr_b else '0';
  hit_b1 <= '1' when vb(1)='1' and tb(1)=addr_b else '0';
  hit_b<=hit_b0 or hit_b1;
  ready <= '1' when reset='1' else
           '1' when state=IDLE and (hit_a='1' or (we_a='1' and not BIT_MASK_WRITE)) and hit_b='1' else '0';
  process(clk) begin
    if rising_edge(clk) then
      dataout_a<=std_logic_vector(resize(unsigned(ca),32));
      if hit_b0='1'then dataout_b<=std_logic_vector(resize(unsigned(cb(0)),32));
      else dataout_b<=std_logic_vector(resize(unsigned(cb(1)),32));end if;
    end if;
  end process;
  process(clk_memory) begin
    if rising_edge(clk_memory) then
      mem_req<='0';
      if reset='1' then
        state<=IDLE;va<='0';vb<="00";mem_req<='0';owner_b<='0';replace_b<=0;
      else
        case state is
          when IDLE =>
            if memory_tick='1' and we_a='1' then
              mem_req<='1';mem_read<='0';mem_addr<=std_logic_vector(to_unsigned(addr_a,13));
              mem_wdata<=std_logic_vector(resize(unsigned(din),32));mem_be<=be_a;state<=WRITE_WORD;
              if be_a="1111" then ca<=din;ta<=addr_a;va<='1';
              elsif va='1' and ta=addr_a then
                for n in 0 to DATA_BITS-1 loop if be_a(n/8)='1' then ca(n)<=din(n);end if;end loop;
              end if;
              for slot in 0 to 1 loop
                if vb(slot)='1' and tb(slot)=addr_a then
                  for n in 0 to DATA_BITS-1 loop if be_a(n/8)='1' then cb(slot)(n)<=din(n);end if;end loop;
                end if;
              end loop;
            elsif hit_a='0' then
              mem_req<='1';mem_read<='1';mem_be<="1111";
              mem_addr<=std_logic_vector(to_unsigned(addr_a,13));held_addr<=addr_a;owner_b<='0';state<=READ_WORD;
            elsif hit_b='0' then
              mem_req<='1';mem_read<='1';mem_be<="1111";
              mem_addr<=std_logic_vector(to_unsigned(addr_b,13));held_addr<=addr_b;owner_b<='1';held_b<=replace_b;replace_b<=1-replace_b;state<=READ_WORD;
            end if;
          when READ_WORD =>
            if mem_done='1' then
              if owner_b='1'then cb(held_b)<=mem_rdata(DATA_BITS-1 downto 0);tb(held_b)<=held_addr;vb(held_b)<='1';
              elsif held_addr=addr_b then cb(replace_b)<=mem_rdata(DATA_BITS-1 downto 0);tb(replace_b)<=held_addr;vb(replace_b)<='1';replace_b<=1-replace_b;end if;
              if owner_b='0' or held_addr=addr_a then ca<=mem_rdata(DATA_BITS-1 downto 0);ta<=held_addr;va<='1';end if;
              state<=IDLE;
            end if;
          when WRITE_WORD => if mem_done='1' then state<=IDLE;end if;
        end case;
      end if;
    end if;
  end process;
end;
