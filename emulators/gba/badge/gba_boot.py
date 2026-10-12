"""Run the GBA install/launch markers before normal menu hardware init."""


def handle_pending():
    import microcontroller
    from gba_menu import INSTALL_MAGIC, LAUNCH_MAGIC, ERROR_MAGIC, defer, validate_rom
    nvm = microcontroller.nvm
    magic = nvm[0]
    if magic not in (INSTALL_MAGIC, LAUNCH_MAGIC, ERROR_MAGIC):
        return
    length = nvm[1]
    payload = bytes(nvm[2:2 + length])
    nvm[0:2] = b'\x00\x00'
    import supervisor
    supervisor.runtime.autoreload = False
    if magic == ERROR_MAGIC:
        import gba_install_status
        status = gba_install_status.create('Game Boy Advance')
        status.hw_state['fpga_overlay'].init()
        status.message(payload.decode('utf-8'), error=True)
        gba_install_status.wait_for_menu(status)
        return
    try:
        if not length or length > min(253, len(nvm) - 2):
            raise ValueError('Invalid GBA launch request')
        path = payload.decode('utf-8')
        validate_rom(path)
        if magic == INSTALL_MAGIC:
            import gba_install_status
            from gba_app import install_rom
            status = gba_install_status.create('Game Boy Advance')
            try:
                install_rom(path, progress=status.callback)
                status.message('Starting game')
                import time
                time.sleep(0.3)
                status.release()
                time.sleep(0.1)
                defer(LAUNCH_MAGIC, path)
            except Exception as error:
                print('GBA_INSTALL_FAILED', error)
                status.message(str(error)[:28], error=True)
                gba_install_status.wait_for_menu(status)
        else:
            import displayio
            displayio.release_displays()
            import hardware.fpga
            handle = hardware.fpga.upload_bitstream('/apps/gba/gba.bit')
            handle.deinit()
            from gba_app import app
            app(path)
    except Exception as error:
        print('GBA_LAUNCH_FAILED', error)
        defer(ERROR_MAGIC, str(error)[:28] or 'GBA launch failed')
