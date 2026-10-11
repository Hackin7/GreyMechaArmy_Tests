# Executed by repl_run.py after deployment. Destructive external-PSRAM test.
import sys
import time
import gc
import supervisor
import displayio
supervisor.runtime.autoreload = False

# Release resources retained by the stopped badge menu, without importing it.
main_module = sys.modules.get("hardware.main")
if main_module is not None:
    state = main_module.hw_state
    overlay = state.get("fpga_overlay")
    if overlay is not None:
        existing = getattr(overlay, "existing_state", None)
        if isinstance(existing, list):
            for pin in existing:
                pin.deinit()
        elif existing is not None:
            existing.deinit()
        reset_handle = getattr(overlay, "jtag_rst", None)
        if reset_handle is not None:
            reset_handle.deinit()
        overlay.deinit()
    displayio.release_displays()
    bus = state.get("display_bus")
    if bus is not None:
        bus.deinit()
# Deferred loader may retain a GP20 handle in the root script.
for name in ("_h", "h"):
    handle = globals().get(name)
    if handle is not None and hasattr(handle, "deinit"):
        handle.deinit()
gc.collect()

APP = "/apps/psram_j1"
if APP not in sys.path:
    sys.path.append(APP)
import psram
print("UPLOAD_BEGIN")
psram.load()
print("UPLOAD_DONE")
p = psram.Psram()
device_id = p.id()
print("ID:", [hex(value) for value in device_id])
print("INITIAL_STATUS:", p.status())
if not p.status()["id_good"]:
    raise RuntimeError("PSRAM KGD ID is not 0x5d; refusing to report memory success")

payload = b"Hello FPGA"
p.write(0x100, payload)
actual = p.read(0x100, len(payload))
print("STRING_READBACK:", actual)
assert actual == payload

for address, value in ((0x3ff, 0x80), (0x400, 0x01), (0x400000, 0xc3), (0x7fffff, 0x5a)):
    p.write(address, bytes((value,)))
    actual = p.read(address)
    print("BYTE_READBACK:", hex(address), list(actual))
    assert actual == bytes((value,))

for base in (0, 0x3f0, 0x10000, 0x400000, 0x7fff00):
    result = p.self_test(base)
    print("FPGA_SELF_TEST:", hex(base), result)
    assert result["pass"] and not result["error"]

print("ADDRESS_DATA_TEST_BEGIN")
assert p.address_test()
print("ADDRESS_DATA_TEST_PASS")
time.sleep(0.1)
reset_id = p.id(reset=True)
print("RESET_ID:", [hex(value) for value in reset_id])
assert reset_id == device_id
p.write(0x100, payload)
assert p.read(0x100, len(payload)) == payload
print("POST_RESET_READ_WRITE_PASS")
print("HARDWARE_TEST_PASS")
# Leave p available in the friendly REPL for interactive use.
