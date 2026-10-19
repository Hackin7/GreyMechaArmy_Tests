"""Exercise launcher ownership/cleanup with CircuitPython hardware stand-ins."""
import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("camera_launcher", Path(__file__).parents[1] / "badge/main.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.events = []
        events = self.events

        class Resource:
            def __init__(self, name):
                self.name = name

            def deinit(self):
                events.append(self.name)

            def deinit_mode_buttons(self):
                events.append("buttons")

        self.handle = Resource("handle")
        self.state = {key: Resource(key) for key in ("fpga_overlay", "display_bus", "jtag_rst")}
        displayio = types.ModuleType("displayio")
        displayio.release_displays = lambda: events.append("display")
        hardware = types.ModuleType("hardware")
        hardware.__path__ = []
        hardware.hw_state = self.state
        self.fpga = types.ModuleType("hardware.fpga")
        hardware.fpga = self.fpga

        def upload(path):
            events.append(path)
            return self.handle

        self.fpga.upload_bitstream = upload
        self.modules = {"displayio": displayio, "hardware": hardware, "hardware.fpga": self.fpga}

    def test_release_before_upload_and_close_handle(self):
        with patch.dict(sys.modules, self.modules), patch.object(launcher.time, "sleep", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                launcher.app()
        self.assertEqual(self.events, ["display", "buttons", "fpga_overlay", "display_bus", "jtag_rst",
                                       launcher.BITSTREAM_PATH, "handle"])

    def test_missing_resources_in_fresh_session(self):
        self.modules["hardware"].hw_state = {}
        with patch.dict(sys.modules, self.modules):
            launcher.release_resources()
        self.assertEqual(self.events, ["display"])

    def test_upload_failure_is_reported(self):
        def fail(path):
            raise OSError("missing bitstream")
        self.fpga.upload_bitstream = fail
        with patch.dict(sys.modules, self.modules):
            with self.assertRaisesRegex(OSError, "missing bitstream"):
                launcher.app(self.state)
        self.assertNotIn("handle", self.events)

    def test_real_main_module_and_overlay_reset_owner(self):
        self.modules['hardware'].hw_state = None
        main = types.ModuleType('hardware.main')
        main.hw_state = self.state
        self.modules['hardware.main'] = main
        overlay=self.state['fpga_overlay']
        overlay.existing_state=None
        overlay.jtag_rst=self.handle
        with patch.dict(sys.modules,self.modules):
            launcher.release_resources()
        self.assertEqual(self.events,['display','handle','fpga_overlay','display_bus','jtag_rst'])


if __name__ == "__main__":
    unittest.main()
