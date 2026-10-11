"""Hardware correctness and throughput for the currently deployed variant."""
import sys
import supervisor
supervisor.runtime.autoreload = False
sys.path.append('/apps/psram_j1')
import psram
psram.load()
p = psram.Psram()
try:
    device_id = p.id()
    print('ID:', list(device_id))
    assert p.status()['id_good']
    clocks = sorted(p.measure_clock() for _ in range(3))
    clock_hz = clocks[1]
    print('CLOCK_SAMPLES_HZ:', clocks)
    print('MEASURED_SYS_HZ:', clock_hz)
    print('MODE:', p.status())
    payload = b'Quad FPGA 0123456789'
    p.write(0x100, payload)
    assert p.read(0x100, len(payload)) == payload
    assert p.address_test()
    print('BYTE_ADDRESS_DATA_PASS')
    for base in (0, 0x3f0, 0x10000, 0x400000, 0x7fff00):
        assert p.self_test(base)['pass']
    print('FIVE_REGION_TEST_PASS')
    bases = (0, 0x3f0, 0x10000, 0x400000, 0x7f0000, 0, 0x400000, 0x7f0000)
    for seed, base in enumerate(bases):
        print('BENCHMARK:', hex(base), seed, p.benchmark(base, seed=seed, clock_hz=clock_hz))
    assert p.id(reset=True) == device_id
    p.write(0x100, payload)
    assert p.read(0x100, len(payload)) == payload
    print('RESET_RECOVERY_PASS')
    print('BENCHMARK_HARDWARE_PASS')
finally:
    p.deinit()
