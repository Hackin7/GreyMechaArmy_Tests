# nextpnr pre-pack context. PCLK is asynchronous to the FPGA clock:
# constrain it conservatively above the programmed, divided camera rate.
ctx.addClock("cam_pclk", 12.5)
