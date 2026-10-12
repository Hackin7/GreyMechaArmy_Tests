# Pico 2 Linux Build Notes

This repo was built successfully on Windows by doing the actual Buildroot work inside a Linux Docker volume. Building directly from the Windows checkout caused line-ending and symlink issues.

## Output Files

The final images are in the repo root:

- `flash-image.uf2` - use this for normal Pico 2 / RP2350 flashing
- `flash-image.bin` - raw flash image
- `flash-image-usb-cdc.uf2` - same image, named to make the USB CDC build obvious
- `flash-image-usb-cdc.bin` - same raw image, named to make the USB CDC build obvious

## Build Steps Used

1. Clone the upstream repo with submodules:

   ```powershell
   git clone --recursive https://github.com/Mr-Bossman/pi-pico2-linux .
   ```

2. Create a Docker volume so Linux symlinks are preserved:

   ```powershell
   docker volume create pi_pico2_linux_build
   ```

3. Build inside Debian 13 using the Docker volume:

   ```powershell
   docker run --rm -e DEBIAN_FRONTEND=noninteractive `
     -v pi_pico2_linux_build:/srcvol `
     -v ${PWD}:/out `
     -w /srcvol debian:13 bash -lc "apt-get update >/dev/null && apt-get install -y --no-install-recommends ca-certificates patch git make binutils gcc file wget cpio unzip rsync bc bzip2 g++ picotool >/dev/null && if [ ! -d pi-pico2-linux/.git ]; then git clone --recursive https://github.com/Mr-Bossman/pi-pico2-linux pi-pico2-linux; fi && cd pi-pico2-linux && git submodule update --init --recursive && make -C buildroot BR2_EXTERNAL=/srcvol/pi-pico2-linux raspberrypi-pico2_defconfig && make -C buildroot -j8 && cp buildroot/output/images/flash-image.uf2 /out/flash-image.uf2 && cp buildroot/output/images/flash-image.bin /out/flash-image.bin"
   ```

4. If the build fails only at the final `target-post-image` step after creating `flash-image.uf2`, patch `board/raspberrypi/raspberrypi-pico2/post-image.sh` so `tput` failures are ignored in non-interactive shells:

   ```sh
   tput smso 2>/dev/null || true
   tput rmso 2>/dev/null || true
   ```

5. Rerun the build command. It should reuse most existing artifacts and copy the final images to the workspace root.

## Flashing

Flash with `picotool`:

```powershell
picotool load -fu .\flash-image.uf2
```

Or hold BOOTSEL while plugging in the board and copy `flash-image.uf2` to the mounted RP2350 drive.

## USB CDC Shell

**Known issue: USB functionality under Linux on the RP2350 is not working.** The USB CDC ACM serial shell remains experimental and is not a usable console at present. Use the hardware UART console described below. The cause remains unresolved; successful compilation does not establish working USB operation on hardware.

This tree includes the following implementation work for the RP2350 USB-C connector:

- Kernel gadget serial is enabled with `CONFIG_USB_G_SERIAL=y`.
- A minimal RP2350 USB device-controller driver is added as a Linux patch.
- The device tree exposes the RP2350 USB controller in peripheral mode, including the reset controller resource.
- The USB gadget driver releases the RP2350 `USBCTRL` reset before enabling the device controller.
- `/etc/init.d/S40usb-gadget-shell` starts a root shell on `/dev/ttyGS0` when gadget serial appears.

Intended behavior once the USB issue is fixed (currently not working):

1. Early boot logs still go to hardware UART0.
2. After Linux initializes USB gadget serial, the host should enumerate a CDC ACM serial port.
3. Open the new COM port on Windows, or `/dev/ttyACM*` on Linux/macOS, then press Enter for a shell.

The hardware UART shell is the current console/debug path. This Linux USB limitation is separate from the RP2350 ROM BOOTSEL USB flashing mode.

## UART Pins

The bootloader UART0 pinmux has been moved off GPIO0/GPIO1. The serial console still uses `ttyAMA0`, but UART0 is now on:

- TX: GPIO28
- RX: GPIO29

Use a 3.3 V USB-to-UART adapter and cross the wires: adapter RX to GPIO28, adapter TX to GPIO29, and common GND.

## Notes

- The upstream `2.1` tag was not present when checked, so the build used `master`.
- The board uses APS6404L PSRAM according to the Greybadge schematic/BOM.
- The bootloader default PSRAM CS pin was left unchanged because no schematic evidence showed a different CS GPIO.
- Avoid building from the Windows bind-mounted checkout. Buildroot symlink files can be flattened by Windows, which caused errors such as missing GCC hashes.
- CRLF line endings in the Windows checkout also caused shell script failures such as `/usr/bin/env: 'bash\r': No such file or directory`.
