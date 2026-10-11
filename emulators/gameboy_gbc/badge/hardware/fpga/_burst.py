# CircuitPython's rp2pio implementation supplies the DMA-backed simultaneous
# TX/RX operation required by both bitstream and flash transfers. No custom UF2
# or native module is required.

from .burst_pio import BurstDriverPIO as BurstDriver
