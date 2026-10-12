"""Bounded recovery for the BIOS startup stall observed on GreyMecha."""
import time


def start_with_recovery(host, size, timeout=90, max_restarts=2):
    host.start(size)
    host.keys(None)
    deadline = time.monotonic() + timeout
    previous = None
    stalled = 0
    restarts = 0
    first_guest_frame = None
    while time.monotonic() < deadline:
        status = host.status()
        if status['error'] or status['ram_fault'] or status['overflow']:
            raise RuntimeError('GBA hardware fault: ' + repr(status))
        # A PC in guest memory plus advancing frames establishes startup.
        # Sampling a BIOS interrupt later must not erase this observation.
        if 0x02000000 <= status['pc'] < 0x0e000000:
            if first_guest_frame is None:
                first_guest_frame = status['frames']
        if first_guest_frame is not None and status['frames'] > first_guest_frame:
            print('GBA_STARTED', status, 'warm_restarts', restarts)
            return status
        sample = (status['pc'], status['frames'])
        stalled = stalled + 1 if sample == previous and status['ram_idle'] else 0
        previous = sample
        # Only retry the known startup signature. Never reset a ROM merely
        # because it is sitting in a BIOS call after guest execution begins.
        if first_guest_frame is None and status['pc'] < 0x4000 and stalled >= 8:
            if restarts >= max_restarts:
                raise RuntimeError('GBA BIOS startup stalled after warm retries')
            restarts += 1
            print('GBA_BIOS_STALL_RESTART', restarts)
            host.start(size)
            host.keys(None)
            previous = None
            stalled = 0
        time.sleep(1)
    raise RuntimeError('GBA startup timed out')
