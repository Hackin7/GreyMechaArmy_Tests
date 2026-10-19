"""Decode wire snapshots with a stand-in for the badge's diagnostic pins."""
import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch


class StatusTests(unittest.TestCase):
    def decode(self, payload):
        stream=iter((byte>>bit)&1 for byte in payload for bit in range(7,-1,-1))
        handles=[]
        class Pin:
            def __init__(self, name): self.name=name; self.closed=False; self.output=False; handles.append(self)
            def switch_to_output(self, value=False): self.output=True
            def switch_to_input(self): self.output=False
            def deinit(self): self.closed=True
            @property
            def value(self): return next(stream) if self.name==10 else False
            @value.setter
            def value(self, value): pass
        spec=importlib.util.spec_from_file_location('camera_diagnostics',Path(__file__).parents[1]/'badge/status.py')
        module=importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules,{'board':types.SimpleNamespace(GP8=8,GP10=10,GP11=11),
                                   'digitalio':types.SimpleNamespace(DigitalInOut=Pin)}):
            spec.loader.exec_module(module)
            try: return module.camera_status(False)
            finally: self.assertTrue(all(pin.closed for pin in handles))

    def snapshot(self):
        data=bytearray(116)
        data[:4]=b'CAM2';data[4]=0x76;data[5]=0x73;data[7]=0xfd
        data[28:32]=((120<<22)|320).to_bytes(4,'big')
        return data

    def test_rate_extension(self):
        data=self.snapshot();data[64:68]=b'FPS1'
        for index,value in enumerate((2,301,0,0,7,300,299)):
            data[68+index*4:72+index*4]=value.to_bytes(4,'big')
        result=self.decode(data)
        self.assertEqual((result['pid'],result['version']),('0x76','0x73'))
        self.assertEqual((result['last_frame_lines'],result['last_line_bytes']),(120,320))
        self.assertEqual((result['timing_profile'],result['valid_frames'],result['display_frames']),(2,301,299))
        self.assertEqual(result['replaced_frames'],7)

    def test_old_snapshot_has_no_rates(self):
        self.assertNotIn('valid_frames',self.decode(self.snapshot()))

    def test_raw_colors(self):
        data=self.snapshot();data[96:100]=b'COL1'
        words=(0xffff,0xffe0,0x07ff,0x07e0,0xf81f,0xf800,0x001f,0)
        for index,word in enumerate(words): data[100+index*2:102+index*2]=word.to_bytes(2,'big')
        self.assertEqual(self.decode(data)['raw_color_samples'],[hex(word) for word in words])

    def test_rejects_wrong_bitstream(self):
        with self.assertRaises(AssertionError): self.decode(bytearray(116))


if __name__=='__main__': unittest.main()
