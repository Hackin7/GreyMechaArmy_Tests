"""Load from a stopped/fresh CircuitPython REPL, or use Load Bitstream.

The FPGA owns capture, SCCB, buttons and display after configuration.
No root code.py, firmware, configuration flash or NVM changes are made.
"""
import time

BITSTREAM_PATH = "/fpga/app_bitstreams/fpga_ov7670.bit"


def release_resources(hw_state=None):
    import displayio
    import sys
    displayio.release_displays()
    if hw_state is None:
        main_module = sys.modules.get("hardware.main")
        hw_state = getattr(main_module, "hw_state", None)
    if hw_state is None:
        try:
            import hardware
            hw_state = getattr(hardware, "hw_state", None)
        except ImportError:
            hw_state = None
    if not hw_state:
        return
    overlay = hw_state.get("fpga_overlay")
    if overlay is not None:
        release_buttons = getattr(overlay, "deinit_mode_buttons", None)
        if release_buttons and (not hasattr(overlay,"existing_state") or overlay.existing_state is not None):
            release_buttons()
        reset_owner = getattr(overlay,"jtag_rst",None)
        if reset_owner is not None:
            reset_owner.deinit()
        release = getattr(overlay, "deinit", None)
        if release:
            release()
    for key in ("display_bus", "jtag_rst"):
        resource = hw_state.get(key)
        if resource is not None:
            resource.deinit()


def app(hw_state=None, path=BITSTREAM_PATH):
    import hardware.fpga
    release_resources(hw_state)
    handle = hardware.fpga.upload_bitstream(path)
    try:
        print("OV7670 FPGA demo loaded. Grey: correction; left/right: offset.")
    finally:
        if handle is not None:
            handle.deinit()
    while True:
        time.sleep(0.25)


if __name__ == "__main__":
    app()
