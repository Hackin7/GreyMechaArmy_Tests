"""Share ARM shifts while retaining the CPU's two registered shift stages."""
import re


def share_cpu_shifter(source):
    # ARM register ROR by a nonzero multiple of 32 sets C to bit 31.
    # Reducing it to zero would incorrectly keep the incoming carry.
    marker='                  shiftamount <= to_integer(unsigned(shiftbyreg(4 downto 0)));'
    assert source.count(marker)==1
    source=source.replace(marker,'''                  if shiftbyreg(4 downto 0)="00000" then
                     shiftamount <= 32;
                  else
                     shiftamount <= to_integer(unsigned(shiftbyreg(4 downto 0)));
                  end if;''')
    marker="   signal shiftwait         : integer range 0 to 2 := 0;"
    assert source.count(marker)==1
    source=source.replace(marker,'''   signal shared_shift_comb, shared_shift_stage : unsigned(31 downto 0) := (others => '0');
   signal shared_carry_comb, shared_carry_stage : std_logic := '0';
   -- synthesis translate_off
   signal shiftresult_reference : unsigned(31 downto 0) := (others => '0');
   signal shiftercarry_reference : std_logic := '0';
   -- synthesis translate_on
''' + marker)
    start=source.index('         -- LSL\n',source.index('-- ARM DOC:'))
    end=source.index('\n   \n      end if;',start)
    original=source[start:end]
    assert original.count('-- combine')==1
    reference=re.sub(r'\bshiftresult\b','shiftresult_reference',original)
    reference=re.sub(r'\bshiftercarry\b','shiftercarry_reference',reference)
    source=source[:start]+'''         shared_shift_stage <= shared_shift_comb;
         shared_carry_stage <= shared_carry_comb;
         shiftresult <= shared_shift_stage;
         shiftercarry <= shared_carry_stage;
         -- synthesis translate_off
''' + reference + '\n         -- synthesis translate_on' + source[end:]
    # Check timing as well as arithmetic wherever execution consumes a shift.
    check='''                           -- synthesis translate_off
                           assert shiftresult=shiftresult_reference and shiftercarry=shiftercarry_reference
                              report "Shared CPU shift pipeline differs from upstream" severity failure;
                           -- synthesis translate_on
'''
    for marker in ('                           alu_op2          <= shiftresult;',
                   "                           busaddmod     <= shiftresult(busaddmod'left downto 0);"):
        assert source.count(marker)==1
        source=source.replace(marker,check+marker)
    pos=re.search(r'^begin\s*$',source,re.M).end()
    logic='''
   shared_shifter : entity work.gba_alu_shifter port map(
      value => shiftervalue, amount => to_unsigned(shiftamount,8),
      mode => execute_shiftsettings(2 downto 1), rrx => shift_rrx,
      carry_in => Flag_Carry, result => shared_shift_comb, carry_out => shared_carry_comb);
'''
    return source[:pos]+logic+source[pos:]
