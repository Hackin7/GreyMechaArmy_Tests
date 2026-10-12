"""Share mutually exclusive GBA color effects without changing latency."""
import re

HELPER = '''
   function shared_color(first, second : std_logic_vector(4 downto 0);
                         effect : unsigned(1 downto 0);
                         eva, evb, bldy : integer) return integer is
      variable operand : unsigned(4 downto 0);
      variable factor : unsigned(4 downto 0);
      variable primary, secondary : unsigned(9 downto 0);
      variable mixed : unsigned(10 downto 0);
   begin
      if effect = "10" then operand := not unsigned(first);
      else operand := unsigned(first); end if;
      if effect = "01" then factor := to_unsigned(eva, 5);
      else factor := to_unsigned(bldy, 5); end if;
      primary := operand * factor;
      secondary := unsigned(second) * to_unsigned(evb, 5);
      mixed := resize(primary, 11) + resize(secondary, 11);
      case to_integer(effect) is
         when 1 => return to_integer(mixed(10 downto 4));
         when 2 => return to_integer(unsigned(first)) + to_integer(primary(9 downto 4));
         when 3 => return to_integer(unsigned(first)) - to_integer(primary(9 downto 4));
         when others => return 0;
      end case;
   end function;
'''

def share_color_arithmetic(text):
    original = text
    marker = 'architecture arch of gba_drawer_merge is'
    assert text.count(marker) == 1
    text = text.replace(marker, marker + HELPER)
    pattern = r'^\s*signal (?:alpha|whiter|blacker)_(?:red|green|blue)\s*: integer range [^;]+;'
    text, count = re.subn(pattern, '', text, flags=re.M)
    assert count == 9, count
    declarations = '\n'.join('   signal effect_' + color + ' : integer range 0 to 63;' for color in ('red', 'green', 'blue'))
    text = text.replace('\nbegin ', '\n' + declarations + '\nbegin ', 1)
    start = text.index('         alpha_blue    <=')
    end = text.index('\n      end if;', start)
    assignments = []
    for color, hi, lo in [('blue', 14, 10), ('green', 9, 5), ('red', 4, 0)]:
        assignments.append(f'         effect_{color} <= shared_color(firstpixel_cycle3({hi} downto {lo}), secondpixel({hi} downto {lo}), special_effect_var, EVA_MAXED, EVB_MAXED, BLDY_MAXED);')
    text = text[:start] + '\n'.join(assignments) + '\n' + text[end:]
    start = text.index('                  when 1 => -- alpha')
    end = text.index('                  when others => null;', start)
    result = ['                  when 1 | 2 | 3 =>']
    for color, hi, lo in [('blue', 14, 10), ('green', 9, 5), ('red', 4, 0)]:
        result.append(f'                     if effect_{color} < 31 then pixeldata_out({hi} downto {lo}) <= std_logic_vector(to_unsigned(effect_{color}, 5)); else pixeldata_out({hi} downto {lo}) <= "11111"; end if;')
    text = text[:start] + '\n'.join(result) + '\n' + text[end:]
    assert not re.search(r'\b(?:alpha|whiter|blacker)_(?:red|green|blue)\b', text)
    assert original.count('special_effect_cycle4 <= special_effect_var;') == text.count('special_effect_cycle4 <= special_effect_var;') == 1
    return text
