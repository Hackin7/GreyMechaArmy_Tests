"""Measurement acceptance with simulated time and diagnostic snapshots."""
import ast
import contextlib
import io
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch

class MeasurementTests(unittest.TestCase):
    def run_measure(self, change=False, starve=False, expected=4, wait=0, delay=False):
        clock=[0.0]
        def sleep(seconds): clock[0]+=seconds
        def status(verbose=False):
            n=max(0,int((clock[0]-3)*32))
            return dict(configured=True,live=True,pid='0x76',version='0x73',
                camera_frames=n,valid_frames=n,accepted_frames=n,display_frames=n,
                malformed_frames=0,capture_drops=0,replaced_frames=0,error_code=0,
                last_frame_lines=120,last_line_bytes=320,active=True,timing_profile=2,
                isp_mode=0 if (change and n) or (delay and clock[0]<5) else 4,
                isp_enabled=True,isp_presets=[4,6,10,10,3],
                pixel_wait_cycles=n if starve else 0)
        namespace=dict(duration_seconds=60,expected_mode=expected,require_enabled=True,wait_for_mode_seconds=wait,
            status_source='import measurement_stub\ncamera_status=measurement_stub.status')
        output=io.StringIO()
        with patch.dict(sys.modules,{'board':types.SimpleNamespace(board_id='greybadge'),
            'time':types.SimpleNamespace(sleep=sleep,monotonic=lambda:clock[0]),
            'measurement_stub':types.SimpleNamespace(status=status)}),contextlib.redirect_stdout(output):
            exec((Path(__file__).parents[1]/'badge/measure.py').read_text(),namespace)
        line=[line for line in output.getvalue().splitlines() if line.startswith('MEASURE_RESULT ')][0]
        return ast.literal_eval(line[len('MEASURE_RESULT '):])

    def test_steady_32fps(self): self.assertTrue(self.run_measure()['passed'])
    def test_changed_mode_fails(self):
        result=self.run_measure(change=True)
        self.assertFalse(result['passed']);self.assertEqual(result['issues'][0][0],'settings_changed')
    def test_queue_starvation_fails(self): self.assertFalse(self.run_measure(starve=True)['passed'])
    def test_wrong_requested_mode_rejected(self):
        with self.assertRaises(AssertionError): self.run_measure(expected=0)
    def test_wait_for_physical_selection(self):
        self.assertTrue(self.run_measure(wait=10,delay=True)['passed'])
    def test_selection_timeout(self):
        with self.assertRaises(AssertionError): self.run_measure(wait=1,delay=True)

if __name__=='__main__': unittest.main()
