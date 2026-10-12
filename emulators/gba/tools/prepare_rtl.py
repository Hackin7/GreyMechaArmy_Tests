#!/usr/bin/env python3
"""Lower resolved record buses into explicit, zero-masked OR trees for GHDL.

The upstream source remains the simulation reference. Generated files belong
in build/, never in vendor/. Every child has a separate drive record; request
and response fields are merged independently without internal tristates.
"""
import argparse
import re
from pathlib import Path

FIELDS = ('Din', 'Dout', 'Adr', 'rnw', 'ena', 'done', 'acc', 'bEna', 'rst')
ZERO = "((others => '0'), (others => '0'), (others => '0'), '0', '0', '0', \"00\", \"0000\", '0')"


def closing(s, start):
    depth = 0
    for i in range(start, len(s)):
        if s[i] == '(':
            depth += 1
        elif s[i] == ')':
            depth -= 1
            if depth == 0:
                return i
    raise ValueError('unbalanced VHDL')


def split_args(s):
    depth, start, out = 0, 0, []
    for i, c in enumerate(s):
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        elif c == ',' and depth == 0:
            out.append(s[start:i].strip())
            start = i + 1
    return out + [s[start:].strip()]


def prepare(src, dst, shared_backgrounds=False, no_savestates=False, shared_dma=False, shared_cpu=False, obj_ram=False, banked_registers=False, obj_window=False, shared_color=False):
    files = list(src.glob('*.vhd'))
    filenames = {p.stem.lower(): p.name for p in files}
    sources = {p.stem.lower(): p.read_text() for p in files}
    if shared_backgrounds:
        from share_backgrounds import share_backgrounds
        sources['gba_gpu_drawer'] = share_backgrounds(sources['gba_gpu_drawer'])
    if no_savestates:
        from board_reset import reset_only
        sources['gba_savestates'] = reset_only(sources['gba_savestates'])
    if shared_dma:
        from share_dma_arithmetic import share_dma_arithmetic
        sources['gba_dma_module'] = share_dma_arithmetic(sources['gba_dma_module'])
    if shared_cpu:
        from share_cpu_arithmetic import share_cpu_arithmetic
        from share_cpu_shifter import share_cpu_shifter
        sources['gba_cpu'] = share_cpu_arithmetic(sources['gba_cpu'])
        sources['gba_cpu'] = share_cpu_shifter(sources['gba_cpu'])
    if obj_ram:
        from block_obj_metadata import block_obj_metadata, wait_obj_metadata
        sources['gba_drawer_obj'] = block_obj_metadata(sources['gba_drawer_obj'])
        sources['gba_gpu_drawer'] = wait_obj_metadata(sources['gba_gpu_drawer'])
    if banked_registers:
        from bank_cpu_registers import bank_cpu_registers
        sources['gba_cpu'] = bank_cpu_registers(sources['gba_cpu'])
    if obj_window:
        from block_obj_window import block_obj_window
        sources['gba_gpu_drawer'] = block_obj_window(sources['gba_gpu_drawer'])
    if shared_color:
        from share_color_arithmetic import share_color_arithmetic
        sources['gba_drawer_merge'] = share_color_arithmetic(sources['gba_drawer_merge'])
    ports, buses = {}, {}
    for name, s in sources.items():
        ent = re.search(r'entity\s+\w+\s+is.*?port\s*\(', s, re.I | re.S)
        if not ent:
            continue
        start = ent.end() - 1
        header = s[start + 1:closing(s, start)]
        ports[name] = re.findall(r'^\s*(\w+)\s*:', header, re.M)
        buses[name] = re.findall(r'(\w+)\s*:\s*inout\s+proc_bus_gb_type', header, re.I)
    ports['eprocreg_gba'] = ports['proc_bus_gba']
    buses['eprocreg_gba'] = buses['proc_bus_gba']
    for name, original in sources.items():
        # Keep synthesis pragmas: simulation-only checks must not become
        # synthesized $fatal tasks, and upstream debug guards are intentional.
        s = re.sub(r'--(?!\s*synthesis\s+translate_(?:off|on)\b)[^\n]*', '', original)
        own = buses.get(name, [])
        if name == 'proc_bus_gba':
            name_key = 'eprocreg_gba'
            ports[name_key] = ports[name]
            buses[name_key] = own
        children = {}
        declarations = []
        edits = []
        for m in re.finditer(r'(\w+)\s*:\s*entity\s+(?:work|mem)\.(\w+)', s, re.I):
            label, child = m.group(1), m.group(2).lower()
            child_buses = buses.get(child, [])
            if not child_buses:
                continue
            pm = re.search(r'port\s+map\s*\(', s[m.end():], re.I)
            if not pm:
                raise ValueError(f'{name}: no port map for {label}')
            start = m.end() + pm.end() - 1
            end = closing(s, start)
            args = split_args(s[start + 1:end])
            mapping = {}
            for n, arg in enumerate(args):
                if '=>' in arg:
                    formal, actual = arg.split('=>', 1)
                    mapping[formal.strip().lower()] = actual.strip()
                else:
                    mapping[ports[child][n].lower()] = arg
            extra = []
            for bus in child_buses:
                actual = mapping[bus.lower()]
                if not re.fullmatch(r'\w+', actual):
                    raise ValueError(f'unsupported bus actual: {actual}')
                drive = f'{label}_{bus}_drive'
                declarations.append(f'  signal {drive} : proc_bus_gb_type := {ZERO};')
                children.setdefault(actual, []).append(drive)
                extra.append(f'{bus}_drive => {drive}')
            edits.append((end, ', ' + ', '.join(extra)))
        for pos, addition in reversed(edits):
            s = s[:pos] + addition + s[pos:]
        # Turn input/output records into input and separate output ports. New
        # ports are appended to preserve the upstream positional associations.
        if own:
            ent = re.search(r'entity\s+\w+\s+is.*?port\s*\(', s, re.I | re.S)
            start = ent.end() - 1
            end = closing(s, start)
            header = re.sub(r'inout\s+proc_bus_gb_type(?:\s*:=\s*\(.*?\))?(?=\s*[;\n])',
                            'in proc_bus_gb_type', s[start+1:end], flags=re.I | re.S)
            # Remove defaults with a balanced scanner instead of a regex.
            header = s[start+1:end]
            for bus in own:
                pat = re.search(r'\b' + bus + r'\s*:\s*inout\s+proc_bus_gb_type', header, re.I)
                a, b = pat.span()
                tail = header[b:]
                default = re.match(r'\s*:=\s*\(', tail)
                if default:
                    b += closing(tail, default.end()-1) + 1
                header = header[:a] + f'{bus} : in proc_bus_gb_type' + header[b:]
            header = header.rstrip() + ';\n' + ';\n'.join(
                f'      {bus}_drive : out proc_bus_gb_type := {ZERO}' for bus in own) + '\n'
            s = s[:start+1] + header + s[end:]
            for bus in own:
                declarations.append(f'  signal {bus}_self : proc_bus_gb_type := {ZERO};')
                # Only redirect assignment targets, never request reads.
                s = re.sub(r'\b' + bus + r'(\.\w+(?:\([^;\n]*?\))?\s*<=)', bus + r'_self\1', s, flags=re.I)
        if name == 'proc_bus_gba':
            # Fully drive the response word, including unimplemented bits.
            a = s.index('   goutput :')
            b = s.index('   proc_bus_self.done', a)
            s = s[:a] + '''   proc_bus_self.Dout <= std_logic_vector(shift_left(resize(unsigned(Din), 32), Reg.lower))
      when proc_bus.Adr = Adr and (Reg.acccesstype = readwrite or Reg.acccesstype = readonly)
      else (others => '0');
''' + s[b:]
        # Inactive responders drive zero; the parent explicitly ORs them.
        s = s.replace("'Z'", "'0'").replace('"ZZ"', '"00"').replace('"ZZZZ"', '"0000"')
        body = re.search(r'architecture\s+\w+\s+of\s+\w+\s+is', s, re.I)
        if body and (own or children):
            pos = body.end()
            s = s[:pos] + '\n' + '\n'.join(declarations) + '\n' + s[pos:]
            # First architecture begin (functions/procedures may have begins).
            begin = re.search(r'^begin\s*$', s[pos:], re.M | re.I)
            if not begin:
                raise ValueError(f'{name}: architecture begin not found')
            pos = pos + begin.end()
            assignments = []
            for bus in own:
                driven = set(x.lower() for x in re.findall(r'\b' + bus + r'_self\.(\w+).*?<=', s, re.I))
                for field in FIELDS:
                    if field.lower() not in driven:
                        val = "(others => '0')" if field in ('Din','Dout','Adr','acc','bEna') else "'0'"
                        assignments.append(f'  {bus}_self.{field} <= {val};')
            for bus in set(own) | set(children):
                drivers = children.get(bus, []) + ([bus+'_self'] if bus in own else [])
                target = bus+'_drive' if bus in own else bus
                for field in FIELDS:
                    assignments.append(f'  {target}.{field} <= ' + ' or '.join(d+'.'+field for d in drivers) + ';')
            s = s[:pos] + '\n' + '\n'.join(assignments) + '\n' + s[pos:]
        dst.mkdir(parents=True, exist_ok=True)
        (dst / filenames[name]).write_text(s)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('source', type=Path)
    ap.add_argument('output', type=Path)
    ap.add_argument('--shared-backgrounds', action='store_true')
    ap.add_argument('--no-savestates', action='store_true')
    ap.add_argument('--shared-dma-arithmetic', action='store_true')
    ap.add_argument('--shared-cpu-arithmetic', action='store_true')
    ap.add_argument('--obj-metadata-ram', action='store_true')
    ap.add_argument('--banked-register-ram', action='store_true')
    ap.add_argument('--obj-window-ram', action='store_true')
    ap.add_argument('--shared-color-arithmetic', action='store_true')
    args = ap.parse_args()
    prepare(args.source, args.output, args.shared_backgrounds, args.no_savestates, args.shared_dma_arithmetic, args.shared_cpu_arithmetic, args.obj_metadata_ram, args.banked_register_ram, args.obj_window_ram, args.shared_color_arithmetic)
