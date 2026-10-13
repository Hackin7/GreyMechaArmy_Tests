"""Share the shift-amount read with the multiply-accumulator/LR read port.

ALU/load/store shift setup never consumes the multiply accumulator. Multiply
and Thumb BL consume the accumulator/LR port and never use shiftbyreg.
This changes only asynchronous register address selection, not CPU stages.
"""
import re


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError('CPU shift-read sharing: expected exactly one ' + repr(old))
    return source.replace(old, new)


def share_shift_read(source):
    # Declaration, LR alias, register-file output, and multiply consumer.
    # Shift reads have a declaration, register-file output and two consumers.
    for name in ('reg_data_a', 'reg_data_s'):
        if len(re.findall(r'\b'+name+r'\b',source)) != 4:
            raise ValueError('CPU shift-read sharing: unexpected consumers of '+name)
    old='''   reg_acc_index <= to_unsigned(14,4) when execute_functions_detail=long_branch_with_link_low
      else unsigned(execute_muladd);'''
    source=replace_once(source,old,'''   reg_acc_index <= to_unsigned(14,4) when execute_functions_detail=long_branch_with_link_low
      else unsigned(execute_muladd) when execute_functions_detail=mulboth
      else unsigned(execute_shiftsettings(7 downto 4));
   reg_data_s <= reg_data_a(7 downto 0);''')
    source=replace_once(source,'data_s=>reg_data_s','data_s=>open')
    source=replace_once(source,'rs=>unsigned(execute_shiftsettings(7 downto 4))','rs=>to_unsigned(0,4)')
    return source
