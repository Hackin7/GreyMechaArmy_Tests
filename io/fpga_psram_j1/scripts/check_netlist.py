"""Check required board pins survive synthesis as connected numeric nets."""
import json
import sys

module = json.load(open(sys.argv[1]))["modules"]["top"]
ports = module["ports"]
for name, direction in (("host_sck", "input"), ("host_mosi", "input"),
                        ("host_cs_n", "input"), ("host_miso", "output")):
    port = ports[name]
    assert port["direction"] == direction, (name, port)
    assert len(port["bits"]) == 1 and isinstance(port["bits"][0], int), (name, port)
    bit = port["bits"][0]
    connected = any(bit in cell["connections"][pin]
                    for cell in module["cells"].values()
                    for pin, pin_direction in cell["port_directions"].items()
                    if pin_direction == direction)
    assert connected, "Disconnected " + name
# IO1 must remain a real bidirectional wire for PSRAM readback.
assert all(isinstance(bit, int) for bit in ports["pmod_j1"]["bits"][:6]), ports["pmod_j1"]
print("PASS: synthesized host input/output pins and PSRAM IO1 preserved")
