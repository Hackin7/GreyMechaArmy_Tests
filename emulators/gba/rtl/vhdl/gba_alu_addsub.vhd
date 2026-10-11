library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ARM ADD/ADC/SUB/SBC share a 33-bit sum. For subtraction, the high bit
-- reports absence of borrow, exactly as required by the ARM C flag.
entity gba_alu_addsub is
  port(a, b : in unsigned(31 downto 0);
       subtract, with_carry, carry_in : in std_logic;
       result : out unsigned(32 downto 0));
end;
architecture rtl of gba_alu_addsub is
  signal operand_b : unsigned(31 downto 0);
  signal carry : unsigned(0 downto 0);
begin
  operand_b <= not b when subtract='1' else b;
  carry(0) <= carry_in when with_carry='1' else subtract;
  result <= ('0' & a) + ('0' & operand_b) + resize(carry, 33);
end;
