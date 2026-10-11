library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- One right-shift network also implements left shifts by reversing bits.
-- Each stage carries the last discarded bit alongside the 32-bit result.
entity gba_alu_shifter is
  port(value : in unsigned(31 downto 0);
       amount : in unsigned(7 downto 0);
       mode : in std_logic_vector(1 downto 0);
       rrx, carry_in : in std_logic;
       result : out unsigned(31 downto 0);
       carry_out : out std_logic);
end;
architecture rtl of gba_alu_shifter is
  type stages_t is array(0 to 5) of unsigned(32 downto 0);
  signal stages : stages_t;
  signal reversed, shifted : unsigned(31 downto 0);
begin
  reverse_input : for bit_index in 0 to 31 generate
    reversed(bit_index) <= value(31-bit_index);
  end generate;
  stages(0)(32 downto 1) <= reversed when mode="00" else value;
  stages(0)(0) <= carry_in;
  barrel : for level in 0 to 4 generate
    constant distance : positive := 2**level;
    signal fill : unsigned(distance-1 downto 0);
  begin
    fill <= stages(level)(distance downto 1) when mode="11" else
            (others => stages(level)(32)) when mode="10" else
            (others => '0');
    stages(level+1) <= fill & stages(level)(32 downto distance)
                      when amount(level)='1' else stages(level);
  end generate;
  reverse_output : for bit_index in 0 to 31 generate
    shifted(bit_index) <= stages(5)(32-bit_index) when mode="00"
                          else stages(5)(bit_index+1);
  end generate;
  process(all)
  begin
    result <= shifted;
    carry_out <= stages(5)(0);
    if amount >= 32 and mode/="11" then
      case mode is
        when "00" =>
          result <= (others => '0');
          if amount=32 then carry_out<=value(0); else carry_out<='0'; end if;
        when "01" =>
          result <= (others => '0');
          if amount=32 then carry_out<=value(31); else carry_out<='0'; end if;
        when "10" => result <= (others => value(31)); carry_out <= value(31);
        when others => null;
      end case;
    end if;
    -- A nonzero multiple of 32 is an identity rotate with bit 31 in C.
    if mode="11" and amount/=0 and amount(4 downto 0)=0 then
      carry_out <= value(31);
    end if;
    if rrx='1' then
      result <= carry_in & value(31 downto 1);
      carry_out <= value(0);
    end if;
  end process;
end;
