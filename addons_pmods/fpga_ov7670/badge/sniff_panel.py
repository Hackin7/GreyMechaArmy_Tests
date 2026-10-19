"""Passive PIO capture of one 160-pixel SPI line; never drives LCD pins."""
import board,array,rp2pio,adafruit_pioasm,time
program=adafruit_pioasm.assemble('''
pull block
wait 1 pin 3
wait 0 pin 3
wait 1 pin 2
.wrap_target
wait 1 pin 0
in pins, 2
wait 0 pin 0
.wrap
''')
words=array.array('I',[0]*160)
sm=rp2pio.StateMachine(program,frequency=150000000,
    first_in_pin=board.GP2,in_pin_count=4,in_shift_right=False,
    auto_push=True,push_threshold=32,wrap_target=4,wrap=6)
try:
    print('PANEL_SNIFF_FREQUENCY',sm.frequency)
    sm.background_read(once=words)
    kick=array.array('I',[0])
    sm.background_write(kick)  # Arm only after RX DMA is ready; no TX-stall wait.
    deadline=time.monotonic()+3
    while sm.reading:
        if time.monotonic()>deadline: raise RuntimeError('No complete panel line within 3 seconds')
finally:
    sm.deinit()
decoded=[]
for packed in words:
    word=0
    for bit in range(16): word=(word<<1)|((packed>>(31-bit*2))&1)
    decoded.append(word)
print('PANEL_WIRE_FIRST_WORDS',[hex(word) for word in decoded[:12]])
print('PANEL_WIRE_COLOR_SAMPLES',[hex(decoded[x]) for x in (10,30,50,70,90,110,130,150)])
print('PANEL_CLOCK_HIGH_SAMPLES',[hex(packed&0x55555555) for packed in words[:8]])
