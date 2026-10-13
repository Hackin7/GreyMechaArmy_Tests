"""Instrument pinned mGBA 0.10.5; never change the FPGA or a ROM."""
import argparse
import difflib
import re
import subprocess
from pathlib import Path

REVISION = '26b7884bc25a5933960f3cdcd98bac1ae14d42e2'


def instrument(source, harness, control=False):
    revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != REVISION:
        raise ValueError('Expected mGBA 0.10.5 at ' + REVISION)
    paths = ['src/arm/arm.c', 'src/arm/isa-arm.c',
             'include/mgba/internal/arm/isa-inlines.h', 'src/gba/memory.c', 'src/gba/core.c',
             'src/gba/renderers/software-bg.c', 'src/gba/renderers/software-mode0.c',
             'src/gba/renderers/software-obj.c', 'src/gba/renderers/video-software.c']
    patches = []
    for name in paths:
        original = subprocess.check_output(['git', '-C', str(source), 'show', 'HEAD:' + name], text=True)
        text = original
        if control and name not in ('src/gba/core.c', 'src/gba/renderers/video-software.c'):
            (source / name).write_text(original)
            continue
        # Instruction prefetch bypasses the normal GBA load handlers. Include
        # sequential fetches AND branch/exception pipeline refills.
        if '/arm/' in name:
            pattern = r'(\s*)(LOAD_(16|32)\(cpu->prefetch\[[01]\], (.*) & cpu->memory.activeMask, cpu->memory.activeRegion\);)'
            def fetch(m):
                return m[1] + f'gp_access((uint32_t) ({m[4]}), 0, {int(m[3]) // 8});' + m[1] + m[2]
            text, count = re.subn(pattern, fetch, text)
            expected = {'src/arm/arm.c': 2, 'src/arm/isa-arm.c': 4,
                        'include/mgba/internal/arm/isa-inlines.h': 4}[name]
            assert count == expected, (name, count)
        elif name == 'src/gba/core.c':
            # The FPGA runs these raw cartridges without enforcing Nintendo's
            # header/logo CRC. mGBA otherwise silently skips the custom BIOS.
            marker = 'if (crc != LOGO_CRC32) {'
            assert text.count(marker) == 1
            text = text.replace(marker, 'if (false && crc != LOGO_CRC32) {')
        elif '/renderers/' in name:
            # Wrap both LOAD macros and the direct byte indexing used by
            # affine tilemaps/textures and indexed bitmap mode 4. The hook
            # maps actual host pointers back to VRAM/palette/OAM offsets.
            role = 5 if name.endswith('software-mode0.c') else 7 if name.endswith('software-bg.c') else 8 if name.endswith('software-obj.c') else 9
            if name.endswith('video-software.c'):
                marker = 'bool dirty = softwareRenderer->scanlineDirty[y >> 5] & (1U << (y & 0x1F));'
                assert text.count(marker) == 1
                text = text.replace(marker, 'bool dirty = true; /* Profile scanout every frame, including static images. */')
            if not control:
                text = re.sub(r'\bLOAD_(16|32)\(', lambda m: f'GP_PPU_LOAD_{m[1]}({role}, ', text)
            if name.endswith('software-mode0.c'):
                text = re.sub(r'GP_PPU_LOAD_16\(5, mapData,', 'GP_PPU_LOAD_16(6, mapData,', text)
            if name.endswith('software-bg.c'):
                text, n = re.subn(r'\b(screenBase|charBase)\[([^\n;]*?)\]',
                                 lambda m: f'gp_ppu_read8({m[1]}, {m[2]}, {6 if m[1]=="screenBase" else 5})', text)
                assert n == 2, n
                text, n = re.subn(r'\(\(uint8_t\*\)renderer->d.vram\)\[([^\n;]*?)\]',
                                 r'gp_ppu_read8(renderer->d.vram, \1, 7)', text)
                assert n == 2, n
        else:
            # LDM/STM use direct host-memory accesses instead of load/store
            # callbacks. Record each actual transferred word in their loops.
            text, n = re.subn(r'^(\s*)LDM; \\', r'\1gp_memory(cpu, address, 4, 0); LDM; \\', text, flags=re.M)
            assert n == 5, n
            text, n = re.subn(r'^(\s*)STM; \\', r'\1gp_memory(cpu, address, 4, 1); STM; \\', text, flags=re.M)
            assert n == 5, n
            wrappers = []
            for op in ('Load', 'Store'):
                for bits in (8, 16, 32):
                    name_fn = f'GBA{op}{bits}'
                    pattern = rf'^(\w+) {name_fn}\(([^\n]*)\) \{{'
                    match = re.search(pattern, text, re.M)
                    assert match, name_fn
                    signature = match[2]
                    text = text[:match.start()] + match[0].replace(name_fn, 'GPOriginal' + name_fn) + text[match.end():]
                    args = 'cpu, address, ' + ('value, ' if op == 'Store' else '') + 'cycleCounter'
                    ret = 'return result;' if op == 'Load' else ''
                    call = ('uint32_t result = ' if op == 'Load' else '') + f'GPOriginal{name_fn}({args});'
                    wrappers.append(f'''{match[1]} {name_fn}({signature}) {{
    if (!gp_depth) gp_memory(cpu, address, {bits // 8}, {int(op == 'Store')});
    ++gp_depth;
    {call}
    --gp_depth;
    {ret}
}}
''')
            # Suppress callbacks used internally by multi-register transfers.
            for op in ('Load', 'Store'):
                fn = 'GBA' + op + 'Multiple'
                pattern = rf'^uint32_t {fn}\(([^\n]*)\) \{{'
                match = re.search(pattern, text, re.M)
                assert match
                text = text[:match.start()] + match[0].replace(fn, 'GPOriginal' + fn) + text[match.end():]
                wrappers.append(f'''uint32_t {fn}({match[1]}) {{
    ++gp_depth;
    uint32_t result = GPOriginal{fn}(cpu, address, mask, direction, cycleCounter);
    --gp_depth;
    return result;
}}
''')
            text += '\n' + '\n'.join(wrappers)
        text = '#include "gp_hooks.h"\n' + text
        (source / name).write_text(text)
        patches.extend(difflib.unified_diff(original.splitlines(True), text.splitlines(True),
                                           fromfile='a/' + name, tofile='b/' + name))
    (source / 'include/gp_hooks.h').write_text('''#ifndef GP_HOOKS_H
#define GP_HOOKS_H
#include <stdint.h>
struct ARMCore;
extern unsigned gp_depth;
void gp_access(uint32_t address, unsigned kind, unsigned size);
void gp_memory(struct ARMCore* cpu, uint32_t address, unsigned size, unsigned write);
void gp_ppu(const void* base, uint32_t offset, unsigned size, unsigned kind);
uint8_t gp_ppu_read8(const void* base, uint32_t offset, unsigned kind);
#define GP_PPU_LOAD_16(K, OUT, OFF, BASE) do { \
    uint32_t gp_off=(OFF); const void* gp_base=(BASE); \
    gp_ppu(gp_base,gp_off,2,K); LOAD_16(OUT,gp_off,gp_base); \
} while (0)
#define GP_PPU_LOAD_32(K, OUT, OFF, BASE) do { \
    uint32_t gp_off=(OFF); const void* gp_base=(BASE); \
    gp_ppu(gp_base,gp_off,4,K); LOAD_32(OUT,gp_off,gp_base); \
} while (0)
#endif
''')
    cmake = subprocess.check_output(['git', '-C', str(source), 'show', 'HEAD:CMakeLists.txt'], text=True)
    cmake += '\nadd_executable(gba-memory-profile "' + harness.resolve().as_posix() + '")\n'
    cmake += 'target_link_libraries(gba-memory-profile ${BINARY_NAME})\n'
    (source / 'CMakeLists.txt').write_text(cmake)
    (source / 'gp-instrumentation.patch').write_text(''.join(patches))
    print('Instrumented CPU prefetch, scalar loads/stores, LDM/STM, DMA and software-renderer VRAM reads')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--harness', type=Path, default=Path(__file__).with_name('profile.c'))
    parser.add_argument('--control', action='store_true', help='Keep cartridge/render settings but omit all access hooks')
    args = parser.parse_args()
    instrument(args.source, args.harness, args.control)
