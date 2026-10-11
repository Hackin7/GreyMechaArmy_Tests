"""Use native banked general-register RAM; preserve PC/CPSR/SPSR stages.

Only the board path uses this transform. No instruction stage or bus timing
changes: the RAM's read ports are asynchronous, like the original register mux.
"""
import re


def bank_cpu_registers(source):
    start=source.index("            if (execute_writeback_calc = '1') then")
    end=source.index("            if (execute_writeback_r17 = '1') then",start)
    # The general file has one write port; execution selects calc/load/user.
    source=source[:start]+source[end:]
    start=source.index("            if (execute_writeback_userreg = '1') then")
    end=source.index("            if (execute_saveState = '1'",start)
    source=source[:start]+source[end:]
    start=source.index("            if (execute_switchregs = '1') then")
    end=source.index("            if (cpu_IRP = '1'",start)
    block=source[start:end]
    # General register copying disappears. Keep every saved-status assignment
    # and its existing priority, mode and exception predicates.
    block=re.sub(r'^\s*regs_[0-5]_(?:8|9|10|11|12|13|14)\s*<=.*?;[^\n]*\n','\n',block,flags=re.M)
    block=re.sub(r'^\s*regs\((?:8|9|10|11|12|13|14)\)\s*<=.*?;[^\n]*\n','\n',block,flags=re.M)
    source=source[:start]+block+source[end:]
    # Replace the seven actual CPU read ports, retaining constant special regs.
    ports={'execute_Rn_op1':'reg_data_n','execute_Rm_op2':'reg_data_m',
           'execute_rdest':'reg_data_d','execute_muladd':'reg_data_a'}
    for index, data in ports.items():
        pattern=r'regs\(to_integer\(unsigned\('+index+r'\)\)\)'
        source=re.sub(pattern,data,source,flags=re.I)
    source=source.replace('regs(to_integer(unsigned(execute_shiftsettings(7 downto 4))))(7 downto 0)','reg_data_s')
    source=source.replace('regs(block_regindex)','reg_data_b')
    source=source.replace('regs(14)(31 downto 1)','reg_data_lr(31 downto 1)')
    # STM^ selects the user bank through the same block read port.
    a=source.index("                        if (execute_block_usermoderegs = '1' and cpu_mode")
    b=source.index('                        elsif (block_regindex = 15)',a)
    source=source[:a]+'''                        if (execute_block_usermoderegs = '1' and cpu_mode /= CPUMODE_USER and cpu_mode /= CPUMODE_SYSTEM) then
                           if block_regindex>=8 and block_regindex<=14 then
                              block_writevalue <= reg_data_b;
                           else block_writevalue <= (others=>'0'); end if;
''' + source[b:]
    # These are the pinned upstream consumers whose instruction cases permit
    # sharing. Reject additions until their simultaneous reads are reviewed.
    for data, count in [('reg_data_d',2),('reg_data_a',1),('reg_data_b',2),('reg_data_lr',1)]:
        assert len(re.findall(r'\b'+data+r'\b',source))==count, data
    declarations='''
   signal reg_read_mode : std_logic_vector(3 downto 0) := x"0";
   signal reg_write_mode : std_logic_vector(3 downto 0);
   signal reg_write_index : unsigned(3 downto 0);
   signal reg_write_enable, reg_block_user : std_logic;
   signal reg_dest_user : std_logic;
   signal reg_dest_index,reg_acc_index : unsigned(3 downto 0);
   signal reg_write_overlap : std_logic := '0';
   signal reg_data_n,reg_data_m,reg_data_d,reg_data_a,reg_data_b,reg_data_lr : unsigned(31 downto 0);
   signal reg_data_s : unsigned(7 downto 0);
'''
    pos=re.search(r'^begin\s*$',source,re.M).start()
    source=source[:pos]+declarations+source[pos:]
    pos=re.search(r'^begin\s*$',source,re.M).end()
    logic='''
   reg_block_user <= '1' when execute_block_usermoderegs='1' and
      cpu_mode/=CPUMODE_USER and cpu_mode/=CPUMODE_SYSTEM else '0';
   -- Block transfers never consume the normal store/multiply destination
   -- read, and Thumb BL never consumes the multiply accumulator read.
   reg_dest_index <= to_unsigned(block_regindex,4) when
      execute_functions_detail=block_read or execute_functions_detail=block_write
      else unsigned(execute_rdest);
   reg_dest_user <= reg_block_user when
      execute_functions_detail=block_read or execute_functions_detail=block_write else '0';
   reg_acc_index <= to_unsigned(14,4) when execute_functions_detail=long_branch_with_link_low
      else unsigned(execute_muladd);
   reg_data_b <= reg_data_d;
   reg_data_lr <= reg_data_a;
   reg_write_index <= unsigned(load_writeback_reg) when execute_writeback_load='1'
      else unsigned(writeback_reg);
   reg_write_mode <= x"0" when execute_writeback_userreg='1' else
      cpu_mode when execute_switchregs='1' else reg_read_mode;
   reg_write_enable <= '1' when gb_on='1' and
      (execute_writeback_calc='1' or execute_writeback_load='1' or
       (execute_writeback_userreg='1' and unsigned(writeback_reg)>=8 and unsigned(writeback_reg)<=14)) else '0';
   registers : entity work.gba_cpu_regfile port map(
      clk=>clk100, reset=>reset, write_enable=>reg_write_enable,
      read_mode=>reg_read_mode, write_mode=>reg_write_mode,
      write_index=>reg_write_index, write_data=>calc_result, pc=>regs(15),
      rn=>unsigned(execute_Rn_op1),rm=>unsigned(execute_Rm_op2),
      rd=>reg_dest_index,ra=>reg_acc_index,
      rs=>unsigned(execute_shiftsettings(7 downto 4)),rb=>to_unsigned(0,4),
      block_user=>'0',dest_user=>reg_dest_user, data_n=>reg_data_n,data_m=>reg_data_m,
      data_d=>reg_data_d,data_a=>reg_data_a,data_s=>reg_data_s,
      data_b=>open,data_lr=>open);
   process(clk100)
   begin
      if rising_edge(clk100) then
         if reset='1' then
            reg_read_mode<=SAVESTATE_cpu_mode;
            reg_write_overlap<='0';
         elsif gb_on='1' then
            if execute_switchregs='1' then reg_read_mode<=cpu_mode; end if;
            if (execute_writeback_calc='1' and execute_writeback_load='1') or
               (execute_writeback_userreg='1' and (execute_writeback_calc='1' or execute_writeback_load='1')) then
               reg_write_overlap<='1';
            end if;
         end if;
         -- synthesis translate_off
         assert not (execute_writeback_calc='1' and execute_writeback_load='1')
            report "General register write ports overlap" severity failure;
         assert not (execute_writeback_userreg='1' and
            (execute_writeback_calc='1' or execute_writeback_load='1'))
            report "User and active register write ports overlap" severity failure;
         -- synthesis translate_on
      end if;
   end process;
'''
    source=source[:pos]+logic+source[pos:]
    source=source.replace("debug_cpu_mixed(31 downto 12) <= (others => '0');",
        "debug_cpu_mixed(12) <= reg_write_overlap;\n   debug_cpu_mixed(31 downto 13) <= (others => '0');")
    return source
