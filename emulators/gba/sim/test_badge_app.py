"""Host-side tests of menu integration and startup recovery decisions."""
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'badge'))
sys.path.insert(0, str(PROJECT / 'tools'))
import gba_launch
import gba_menu
import gba_boot
from build_badge_app import patch_root, patch_registry, GB_BADGE, HOOK


class Clock:
    def __init__(self): self.now = 0
    def monotonic(self): return self.now
    def sleep(self, seconds): self.now += seconds


def status(pc=0x08000000, frames=5, **fields):
    result = dict(pc=pc, frames=frames, ram_idle=True, error=0, ram_fault=False, overflow=False)
    result.update(fields)
    return result


class Host:
    def __init__(self, samples):
        self.samples = iter(samples)
        self.last = status()
        self.starts = 0
        self.keys_enabled = []
    def start(self, size): self.starts += 1
    def keys(self, mask): self.keys_enabled.append(mask)
    def status(self):
        self.last = next(self.samples, self.last)
        return self.last


class BadgeTests(unittest.TestCase):
    def test_badge_sources_have_no_circuitpython_incompatible_bom(self):
        for source in (PROJECT / "badge").glob("*.py"):
            self.assertFalse(source.read_bytes().startswith(b"\xef\xbb\xbf"), str(source))

    def test_normal_boot_does_not_shadow_gameboy_protocol(self):
        original = list(sys.path)
        fake_boot = types.SimpleNamespace(handle_pending=lambda: None)
        with patch.dict(sys.modules, gba_boot=fake_boot):
            exec(HOOK, {})
        self.assertEqual(sys.path, original)

    def run_host(self, host, **options):
        with patch.object(gba_launch, 'time', Clock()):
            return gba_launch.start_with_recovery(host, 524288, **options)

    def test_start_requires_frame_progress(self):
        host = Host([status(frames=5), status(pc=0x100, frames=6)])
        self.assertEqual(self.run_host(host)['frames'], 6)
        self.assertEqual(host.starts, 1)
        self.assertEqual(host.keys_enabled, [None])

    def test_known_bios_stall_recovers(self):
        host = Host([status(pc=0x764, frames=1)] * 9 + [status(frames=2), status(frames=3)])
        self.run_host(host)
        self.assertEqual(host.starts, 2)
        self.assertEqual(host.keys_enabled, [None, None])

    def test_permanent_bios_stall_has_bounded_retries(self):
        host = Host([status(pc=0x764, frames=1)] * 40)
        with self.assertRaisesRegex(RuntimeError, 'warm retries'):
            self.run_host(host)
        self.assertEqual(host.starts, 3)

    def test_memory_fault_never_triggers_restart(self):
        host = Host([status(ram_fault=True)])
        with self.assertRaisesRegex(RuntimeError, 'hardware fault'):
            self.run_host(host)
        self.assertEqual(host.starts, 1)

    def test_guest_stall_is_not_treated_as_cold_boot(self):
        host = Host([status(), status(pc=0x764, frames=5)] * 30)
        with self.assertRaisesRegex(RuntimeError, 'timed out'):
            self.run_host(host, timeout=20)
        self.assertEqual(host.starts, 1)

    def test_menu_patches_preserve_existing_entries_and_are_idempotent(self):
        root = (GB_BADGE / 'code.py').read_text()
        registry = (GB_BADGE / 'apps_init.py').read_text()
        root_result = patch_root(root)
        registry_result = patch_registry(registry)
        self.assertEqual(patch_root(root_result), root_result)
        self.assertEqual(patch_registry(registry_result), registry_result)
        self.assertIn('"Game Boy",', registry_result)
        self.assertIn('"Load Bitstream",', registry_result)
        self.assertLess(root_result.index('gba_boot.handle_pending()'), root_result.index('import hardware.main as hardware'))
        with self.assertRaises(ValueError): patch_root('import hardware.main as hardware\n')

    def test_deferred_request_uses_utf8_byte_length_and_resets(self):
        class Reset(BaseException): pass
        nvm = bytearray(256)
        module = types.SimpleNamespace(nvm=nvm, reset=lambda: (_ for _ in ()).throw(Reset()))
        with patch.dict(sys.modules, microcontroller=module):
            with self.assertRaises(Reset): gba_menu.defer(gba_menu.INSTALL_MAGIC, '/apps/gba/games/caf\u00e9.gba')
            self.assertEqual(nvm[0], gba_menu.INSTALL_MAGIC)
            self.assertEqual(bytes(nvm[2:2 + nvm[1]]).decode(), '/apps/gba/games/caf\u00e9.gba')
            before = bytes(nvm)
            with self.assertRaises(ValueError): gba_menu.defer(gba_menu.INSTALL_MAGIC, 'x' * 254)
            self.assertEqual(bytes(nvm), before)

    def test_rom_picker_skips_invalid_files_and_sorts_directories(self):
        def names(directory):
            return ['z.gba', 'a.gba', 'note.txt'] if directory == gba_menu.APP_PATH else ['bad.gba', 'demo.GBA']
        def stat(path):
            return (0,) * 6 + (12 if path.endswith('bad.gba') else 524288,)
        with patch.object(gba_menu.os, 'listdir', names), patch.object(gba_menu.os, 'stat', stat):
            self.assertEqual(gba_menu.list_roms(), ['/apps/gba/a.gba', '/apps/gba/z.gba', '/apps/gba/games/demo.GBA'])
            with self.assertRaises(ValueError): gba_menu.validate_rom('/apps/gba/../other.gba')

    def test_boot_does_not_consume_other_apps_marker(self):
        nvm = bytearray([0xab, 3, 1, 2, 3])
        with patch.dict(sys.modules, microcontroller=types.SimpleNamespace(nvm=nvm)):
            gba_boot.handle_pending()
        self.assertEqual(bytes(nvm), bytes([0xab, 3, 1, 2, 3]))

    def test_install_failure_consumes_request_and_never_queues_launch(self):
        from unittest.mock import Mock
        path = b'/apps/gba/diagnostic.gba'
        nvm = bytearray(256)
        nvm[:2] = bytes((gba_menu.INSTALL_MAGIC, len(path)))
        nvm[2:2 + len(path)] = path
        status_view = Mock()
        installer = Mock(side_effect=RuntimeError('Flash verification failed'))
        menu_wait = Mock()
        modules = dict(microcontroller=types.SimpleNamespace(nvm=nvm),
            supervisor=types.SimpleNamespace(runtime=types.SimpleNamespace(autoreload=True)),
            gba_install_status=types.SimpleNamespace(create=lambda name: status_view, wait_for_menu=menu_wait),
            gba_app=types.SimpleNamespace(install_rom=installer))
        with patch.dict(sys.modules, modules), patch.object(gba_menu, 'validate_rom', return_value=524288), patch.object(gba_menu, 'defer') as deferred:
            gba_boot.handle_pending()
            deferred.assert_not_called()
        self.assertEqual(nvm[0], 0)
        installer.assert_called_once_with(path.decode(), progress=status_view.callback)
        menu_wait.assert_called_once_with(status_view)


if __name__ == '__main__': unittest.main()
