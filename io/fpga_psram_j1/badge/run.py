"""Run this file from Thonny after copying the three app files to the badge."""
import sys
APP = "/apps/psram_j1"
if APP not in sys.path:
    sys.path.append(APP)
import psram

psram.load()
p = psram.Psram()
print("PSRAM ID:", p.id())
print("Status:", p.status())
print("Client is p. Try p.write(0x100, b'Hello'), then p.read(0x100, 5).")
print("p.self_test(0) overwrites 256 bytes. p.address_test() overwrites scattered addresses.")
