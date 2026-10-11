"""Share the CPU arithmetic datapath without changing its execution stages."""
import re


def share_cpu_arithmetic(source):
    marker = '   signal alu_result_add    : unsigned(32 downto 0);'
    assert source.count(marker) == 1
    source = source.replace(marker, marker + '''
   signal alu_shared_result : unsigned(32 downto 0);
   signal alu_shared_subtract, alu_shared_withcarry : std_logic;
   signal alu_sub_carry : std_logic := '0';
''')
    a = source.index('                     when ALUCALC')
    start = source.index('                           when alu_add =>', a)
    end = source.index('                           when others =>', start)
    original = source[start:end]
    assert original.count("alu_result_add <= ('0' & alu_op1) + ('0' & alu_op2)") == 3
    assert original.count('alu_result <= alu_op1 - alu_op2') == 3
    source = source[:start] + '''                           when alu_add | alu_add_withcarry =>
                              alu_result_add <= alu_shared_result;
                           when alu_sub | alu_sub_withcarry =>
                              alu_result <= alu_shared_result(31 downto 0);
                              alu_sub_carry <= alu_shared_result(32);
''' + source[end:]
    # Keep overflow/N/Z equations and their original ALUSETFLAGS clock edge.
    a = source.index('                     when ALUSETFLAGS')
    start = source.index('                                 if (alu_op1 >= alu_op2)', a)
    end = source.index('                              when alu_sub_withcarry =>', start)
    source = source[:start] + "                                 Flag_Carry <= alu_sub_carry;\n\n" + source[end:]
    start = source.index("                                 if (Flag_Carry = '1') then", start)
    end = source.index('                              when others =>', start)
    original = source[start:end]
    assert 'elsif ((alu_op1 - 1) >= alu_op2)' in original
    source = source[:start] + "                                 Flag_Carry <= alu_sub_carry;\n\n" + source[end:]
    location = re.search(r'^begin\s*$', source, re.M).end()
    logic = '''
   alu_shared_subtract <= '1' when execute_functions_detail = alu_sub or
      execute_functions_detail = alu_sub_withcarry else '0';
   alu_shared_withcarry <= '1' when execute_functions_detail = alu_add_withcarry or
      execute_functions_detail = alu_sub_withcarry else '0';
   arithmetic : entity work.gba_alu_addsub port map(
      a => alu_op1, b => alu_op2, subtract => alu_shared_subtract,
      with_carry => alu_shared_withcarry, carry_in => Flag_Carry,
      result => alu_shared_result);
'''
    return source[:location] + logic + source[location:]
