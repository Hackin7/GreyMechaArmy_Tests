"""Share the shift-amount read with the multiply-accumulator/LR read port.

ALU/load/store shift setup never consumes the multiply accumulator. Multiply
and Thumb BL consume the accumulator/LR port and never use shiftbyreg.
This changes only asynchronous register address selection, not CPU stages.
"""
def share_shift_read(source):
    old='''   reg_acc_index <= to_unsigned(14,4) when execute_functions_detail=long_branch_with_link_low
      else unsigned(execute_muladd);'''
    assert source.count(old)==1
    source=source.replace(old,'''   reg_acc_index <= to_unsigned(14,4) when execute_functions_detail=long_branch_with_link_low
      else unsigned(execute_muladd) when execute_functions_detail=mulboth
      else unsigned(execute_shiftsettings(7 downto 4));
   reg_data_s <= reg_data_a(7 downto 0);''')
    assert source.count('data_s=>reg_data_s')==1
    source=source.replace('data_s=>reg_data_s','data_s=>open')
    source=source.replace('rs=>unsigned(execute_shiftsettings(7 downto 4))','rs=>to_unsigned(0,4)')
    return source
