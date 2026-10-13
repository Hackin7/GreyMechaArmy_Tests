"""Retain a paired-word transport register, using the QSPI cache for locality."""
def replace_cache(source):
    header=source[:source.index('architecture arch of cache')]
    return header+'''architecture arch of cache is
  signal waiting,valid,odd:std_logic:='0';
  signal tag:std_logic_vector(SIZEBASEBITS-2 downto 0):=(others=>'0');
  signal pair_data:std_logic_vector(63 downto 0):=(others=>'0');
begin
  read_full<=pair_data;
  process(clk)begin
    if rising_edge(clk)then
      read_done<='0';mem_read_ena<='0';
      if gb_on='0'then waiting<='0';valid<='0';
      elsif waiting='1'then
        if mem_read_done='1'then
          if odd='0'then pair_data<=mem_read_data2&mem_read_data;
          else pair_data<=mem_read_data&mem_read_data2;end if;
          read_data<=mem_read_data;read_done<='1';valid<='1';waiting<='0';
        end if;
      elsif read_enable='1'then
        if valid='1'and tag=read_addr(SIZEBASEBITS-1 downto 1)then
          if read_addr(0)='0'then read_data<=pair_data(31 downto 0);
          else read_data<=pair_data(63 downto 32);end if;
          read_done<='1';
        else
          mem_read_addr<=std_logic_vector(to_unsigned(Softmap_GBA_Gamerom_ADDR,25)+unsigned(read_addr));
          mem_read_ena<='1';waiting<='1';odd<=read_addr(0);
          tag<=read_addr(SIZEBASEBITS-1 downto 1);
        end if;
      end if;
    end if;
  end process;
end architecture;
'''
