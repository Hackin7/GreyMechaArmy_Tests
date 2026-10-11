"""Serialize the upstream background engines without removing display modes.

The board waits for the renderer at HBlank, so four text backgrounds can use
one mode-0 engine and two affine backgrounds can use one mode-2 engine. Keep
the upstream renderers, palette/VRAM arbitration, layer buffers and compositor.
This transformation only changes the board's generated source.
"""
import re


def share_backgrounds(source):
    for mode, indices in ((0, range(4)), (2, range(2, 4))):
        matches = list(re.finditer(
            rf'\s*igba_drawer_mode{mode}_[0-3]\s*:\s*entity work.gba_drawer_mode{mode}'
            r'\s+port map\s*\((.*?)\);', source, re.S))
        assert len(matches) == len(indices), 'unexpected upstream renderer structure'
        maps = [dict(re.findall(r'(\w+)\s*=>\s*([^,\n]+)', m[1])) for m in matches]
        maps = [{k: v.strip() for k, v in p.items()} for p in maps]
        first = maps[0]
        outputs = {'busy', 'pixel_we', 'pixeldata', 'pixel_x',
                   'PALETTE_Drawer_addr', 'VRAM_Drawer_addr'}
        widths = {'mapbase': 'unsigned(4 downto 0)', 'tilebase': 'unsigned(1 downto 0)',
                  'hicolor': 'std_logic', 'mosaic': 'std_logic', 'wrapping': 'std_logic',
                  'screensize': 'unsigned(1 downto 0)', 'scrollX': 'unsigned(8 downto 0)',
                  'scrollY': 'unsigned(8 downto 0)', 'refX': 'signed(27 downto 0)',
                  'refY': 'signed(27 downto 0)', 'refX_mosaic': 'signed(27 downto 0)',
                  'refY_mosaic': 'signed(27 downto 0)', 'dx': 'signed(15 downto 0)',
                  'dy': 'signed(15 downto 0)', 'PALETTE_Drawer_valid': 'std_logic',
                  'VRAM_Drawer_valid': 'std_logic'}
        output_types = {'busy': 'std_logic', 'pixel_we': 'std_logic',
                        'pixeldata': 'std_logic_vector(15 downto 0)',
                        'pixel_x': 'integer range 0 to 239',
                        'PALETTE_Drawer_addr': 'integer range 0 to 127',
                        'VRAM_Drawer_addr': 'integer range 0 to 16383'}
        declarations = [
            'type state_t is (IDLE, SELECT_BG, INIT_AFFINE, START_BG, WAIT_BUSY, WAIT_DONE);',
            'signal state : state_t := IDLE;',
            f'signal pending : std_logic_vector({max(indices)} downto {min(indices)}) := (others => \'0\');',
            f'signal selected : integer range {min(indices)} to {max(indices)} := {min(indices)};',
            'signal launch, initialize : std_logic;',
        ]
        assignments = ["launch <= '1' when state = START_BG else '0';",
                       "initialize <= '1' when state = INIT_AFFINE else '0';"]
        ports = []
        # Affine coordinates are loaded by the original engines on line_trigger,
        # before drawing. Preserve that snapshot for both scheduled backgrounds.
        if mode == 2:
            for i in indices:
                for axis in 'XY':
                    declarations.append(f"signal initial_{axis}{i} : signed(27 downto 0) := (others => '0');")
            capture = ['process(clk100) begin if rising_edge(clk100) then',
                       "if line_trigger_1 = '1' then"]
            for p, i in zip(maps, indices):
                capture += [f"if {p['mosaic']} = '1' and unsigned(REG_MOSAIC_BG_Mosaic_H_Size) > 0 then",
                            f"initial_X{i} <= {p['refX_mosaic']}; initial_Y{i} <= {p['refY_mosaic']};",
                            'else', f"initial_X{i} <= {p['refX']}; initial_Y{i} <= {p['refY']};", 'end if;']
                p['refX'] = p['refX_mosaic'] = f'initial_X{i}'
                p['refY'] = p['refY_mosaic'] = f'initial_Y{i}'
            capture += ['end if; end if; end process;']
            assignments += capture
        for name, value in first.items():
            if name == 'drawline':
                ports.append(f'{name} => launch')
            elif mode == 2 and name == 'line_trigger':
                ports.append(f'{name} => initialize')
            elif name in outputs:
                declarations.append(f'signal shared_{name} : {output_types[name]};')
                ports.append(f'{name} => shared_{name}')
                for p, i in zip(maps, indices):
                    target = p[name]
                    if name == 'busy':
                        assignments.append(f"{target} <= '1' when pending({i}) = '1' or (state /= IDLE and selected = {i}) else '0';")
                    elif name == 'pixel_we':
                        assignments.append(f"{target} <= shared_{name} when selected = {i} else '0';")
                    else:
                        assignments.append(f'{target} <= shared_{name};')
            elif any(p[name] != value for p in maps):
                declarations.append(f'signal mux_{name} : {widths[name]};')
                ports.append(f'{name} => mux_{name}')
                choices = [f"{p[name]} when {i}" for p, i in zip(maps[:-1], list(indices)[:-1])]
                choices.append(f"{maps[-1][name]} when others")
                assignments.append(f'with selected select mux_{name} <= ' + ', '.join(choices) + ';')
            else:
                ports.append(f'{name} => {value}')
        requests = ' or '.join(m['drawline'] for m in maps)
        controller = ['process(clk100) begin if rising_edge(clk100) then',
                      f"if ({requests}) = '1' then",
                      '-- synthesis translate_off',
                      "assert state = IDLE report \"overlapping background render requests\" severity failure;",
                      '-- synthesis translate_on']
        for p, i in zip(maps, indices):
            controller.append(f"pending({i}) <= {p['drawline']};")
        controller += ['state <= SELECT_BG;', 'else', 'case state is', 'when IDLE => null;',
                       'when SELECT_BG =>']
        for j, i in enumerate(indices):
            controller.append(('if' if j == 0 else 'elsif') + f" pending({i}) = '1' then selected <= {i};")
            controller.append('state <= ' + ('INIT_AFFINE;' if mode == 2 else 'START_BG;'))
        controller += ['else state <= IDLE; end if;',
                       'when INIT_AFFINE => state <= START_BG;',
                       'when START_BG => state <= WAIT_BUSY;',
                       "when WAIT_BUSY => if shared_busy = '1' then state <= WAIT_DONE; end if;",
                       "when WAIT_DONE => if shared_busy = '0' then pending(selected) <= '0'; state <= SELECT_BG; end if;",
                       'end case; end if; end if; end process;']
        block = f'\n   shared_mode{mode} : block\n' + '\n'.join(declarations)
        block += '\nbegin\n' + '\n'.join(assignments + controller)
        block += f'\nengine : entity work.gba_drawer_mode{mode} port map (\n' + ',\n'.join(ports) + '\n);\nend block;\n'
        for m in reversed(matches[1:]):
            source = source[:m.start()] + source[m.end():]
        m = matches[0]
        source = source[:m.start()] + block + source[m.end():]
    return source
