# Bring-up Checklist

1. Build `arduboy_fx.bit` with `make bit`.
2. Copy the bitstream to `/apps/arduboy_fx/arduboy_fx.bit`.
3. Copy `greymecha_working/greymecha_app/arduboy_fx/main.py` to
   `/apps/arduboy_fx/main.py`.
4. Add an Arduboy FX menu entry in the GreyMecha app menu.
5. Launch without a game first. The app writes a 128x64 border/grid pattern to
   the framebuffer.
6. Confirm the pattern appears exactly centered on the round LCD, with no
   scaling.
7. Confirm LEDs reflect reset, host select, and button state.
8. Hold A after releasing reset to hear the simple buzzer tone.

The emulator CPU is not present yet. The first hardware acceptance target for
this layer is host-loaded framebuffer plus program/EEPROM/FX memory writes.
