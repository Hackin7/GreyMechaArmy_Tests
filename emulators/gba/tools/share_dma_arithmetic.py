"""Use one address adder per DMA endpoint for +/-2 and +/-4 updates."""
import re

DECLARATIONS = '''
   function advance_dma(address : unsigned(27 downto 0);
                        wide : std_logic; decrement : boolean) return unsigned is
      variable delta : unsigned(27 downto 0);
   begin
      delta := (others => '0');
      if decrement then delta(27 downto 2) := (others => '1'); end if;
      if wide = '1' then delta(2) := '1'; else delta(1) := '1'; end if;
      return address + delta;
   end function;
   signal next_source, next_target : unsigned(27 downto 0);
'''

COMBINATIONAL = '''
   next_source <= advance_dma(addr_source, Transfer_Type_DW,
      source_Adr_Control = 1 and not (addr_source >= 16#8000000# and addr_source < 16#E000000#));
   next_target <= advance_dma(addr_target, Transfer_Type_DW, dest_Addr_Control = 1);
'''

SOURCE_ENABLE = 'source_Adr_Control = 0 or source_Adr_Control = 1 or source_Adr_Control = 3 or (addr_source >= 16#8000000# and addr_source < 16#E000000#)'
TARGET_ENABLE = 'dest_Addr_Control = 0 or dest_Addr_Control = 1 or (dest_Addr_Control = 3 and Start_Timing /= 3)'


def share_dma_arithmetic(source):
    start = source.index("                           if (Transfer_Type_DW = '1') then", source.index('addr_source <= addr_source + 4') - 300)
    end = source.index('\n                           -- timing', start)
    original = source[start:end]
    # The template deliberately preserves the endpoint update predicates;
    # only selection between four constant adders moves to the adder input.
    for endpoint in ('source', 'target'):
        for operator in ('+', '-'):
            for size in (2, 4):
                assert original.count(f'addr_{endpoint} <= addr_{endpoint} {operator} {size};') == 1
    replacement = f'''                           if ({SOURCE_ENABLE}) then
                              addr_source <= next_source;
                           end if;
                           if ({TARGET_ENABLE}) then
                              addr_target <= next_target;
                           end if;
'''
    source = source[:start] + replacement + source[end:]
    location = re.search(r'^begin\s*$', source, re.M).start()
    return source[:location] + DECLARATIONS + source[location:location+5] + COMBINATIONAL + source[location+5:]
