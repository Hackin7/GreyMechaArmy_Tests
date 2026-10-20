"""Raw-REPL measurement; set duration_seconds=60 or 600 before exec().

Host captures stdout in a log. Does not reset/reload the FPGA or write USB files.
"""
import time
import board
assert board.board_id=='greybadge', 'Expected GreyMecha badge'
namespace={'__name__':'camera_diagnostics'}
exec(globals().get('status_source') or open('/apps/ov7670/status.py').read(),namespace)
read_status=namespace['camera_status']
duration_seconds=globals().get('duration_seconds',60)
assert duration_seconds in (60,600)
time.sleep(3)  # Exclude sensor color-bar startup.
expected_mode=globals().get('expected_mode',None)
require_enabled=globals().get('require_enabled',False)
wait_seconds=globals().get('wait_for_mode_seconds',0)
first=read_status(False)
if wait_seconds and expected_mode is not None:
    deadline=time.monotonic()+wait_seconds
    print('MEASURE_WAIT_MODE',expected_mode,'enabled',require_enabled)
    while first.get('isp_mode')!=expected_mode or (require_enabled and not first.get('isp_enabled')):
        assert time.monotonic()<deadline,'Timed out waiting for physical mode selection'
        time.sleep(.25)
        first=read_status(False)
    time.sleep(1)
    first=read_status(False)
assert 'valid_frames' in first, 'FPS diagnostic extension missing'
assert first['configured'] and first['live'], first
assert first['pid']=='0x76' and first['version']=='0x73', first
if expected_mode is not None:
    assert first.get('isp_mode')==expected_mode, 'Select the requested ISP mode first: '+repr(first)
if require_enabled:
    assert first.get('isp_enabled'), 'Enable processing with Grey before measurement'
start=time.monotonic()
previous=first
samples=0
issues=[]
keys=('camera_frames','valid_frames','accepted_frames','display_frames',
      'malformed_frames','capture_drops','replaced_frames')
if 'pixel_wait_cycles' in first: keys+=('pixel_wait_cycles',)
print('MEASURE_START',duration_seconds,first)
while time.monotonic()-start<duration_seconds:
    time.sleep(min(10,max(0,duration_seconds-(time.monotonic()-start))))
    current=read_status(False)
    elapsed=time.monotonic()-start
    samples+=1
    if not current['configured'] or not current['live'] or current['error_code']:
        issues.append(('initialization',elapsed))
    if current['last_frame_lines']!=120 or current['last_line_bytes']!=320:
        issues.append(('geometry',elapsed))
    if not current['active'] or current['valid_frames']==previous['valid_frames']:
        issues.append(('stalled',elapsed))
    if 'isp_mode' in first and any(current.get(key)!=first[key] for key in
            ('isp_mode','isp_enabled','isp_presets')):
        issues.append(('settings_changed',elapsed))
    print('MEASURE_SAMPLE',round(elapsed,3),{key:current[key] for key in keys})
    previous=current
elapsed=time.monotonic()-start
deltas={key:(current[key]-first[key])&0xffffffff for key in keys}
rates={key:round(value/elapsed,3) for key,value in deltas.items()}
passed=(not issues and 28<=rates['valid_frames']<=33 and
        28<=rates['display_frames']<=33 and deltas['malformed_frames']==0 and
        deltas['capture_drops']==0 and deltas['replaced_frames']==0)
passed=passed and deltas.get('pixel_wait_cycles',0)==0
print('MEASURE_RESULT',{'duration':round(elapsed,3),'timing_profile':current['timing_profile'],
    'deltas':deltas,'rates':rates,'issues':issues,'passed':passed,'samples':samples})
