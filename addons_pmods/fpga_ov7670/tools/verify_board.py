"""Print connector/FPGA nets and bank supplies from a published KiCad PCB.

Usage: python3 tools/verify_board.py /path/to/greybadge_pcb.kicad_pcb
This checks the source PCB; it cannot verify the physical badge revision.
"""
import json
import pathlib
import re
import sys


def parse(text):
    stack = [[]]
    for token in re.findall(r'\(|\)|"(?:\\.|[^"\\])*"|[^\s()]+', text):
        if token == "(":
            child = []
            stack[-1].append(child)
            stack.append(child)
        elif token == ")":
            stack.pop()
        else:
            stack[-1].append(json.loads(token) if token.startswith('"') else token)
    return stack[0][0]


def field(node, key):
    return next((child[1:] for child in node if isinstance(child, list) and child[0] == key), [])


def main():
    pcb = parse(pathlib.Path(sys.argv[1]).read_text())
    parts = {}
    for item in pcb:
        if not isinstance(item, list) or item[0] != "footprint":
            continue
        reference = next((child[2] for child in item if isinstance(child, list)
                          and child[:2] == ["property", "Reference"]), None)
        if reference:
            parts[reference] = {pad[1]: (field(pad, "net")[-1:], field(pad, "pinfunction"))
                                for pad in item if isinstance(pad, list) and pad[0] == "pad"}
    fpga = parts["U8"]
    expected = {
        "J1": {5:"A10",7:"A9",9:"A8",11:"A3",6:"B10",8:"B9",10:"B8",12:"A4"},
        "J2": {5:"A14",7:"A13",9:"A12",11:"A11",6:"B14",8:"B13",10:"B12",12:"B11"},
    }
    for connector, mapping in expected.items():
        for pad in (1,2,3,4):
            net = parts[connector][str(pad)][0]
            assert net == (["+3V3"] if pad < 3 else ["GND"]), (connector,pad,net)
            print(connector, pad, net[0])
        for pad, ball in sorted(mapping.items()):
            net = parts[connector][str(pad)][0]
            assert net == fpga[ball][0], (connector,pad,ball,net,fpga[ball])
            print(connector, pad, ball, net[0], fpga[ball][1])
    supplies = [(ball, net, function) for ball,(net,function) in fpga.items()
                if function and function[0].startswith("VCCIO")]
    for ball, net, function in supplies:
        print(ball, function[0], net)
        assert net == ["+3V3"], (ball,function,net)
    assert supplies, "No VCCIO pads found"
    print("Published connector mapping and FPGA bank supplies verified")


if __name__ == "__main__":
    main()
