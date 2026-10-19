"""Fail builds with missing/failing clocks or RAM inference regressions."""
import json
import pathlib
import sys

netlist = json.loads(pathlib.Path(sys.argv[1]).read_text())
report = json.loads(pathlib.Path(sys.argv[2]).read_text())
log = pathlib.Path(sys.argv[3]).read_text()
cells = netlist["modules"]["top"]["cells"].values()
ram_count = sum(cell["type"] == "DP16KD" for cell in cells)
assert ram_count == 56, f"Expected 56 image RAM blocks, got {ram_count}"
fmax = report.get("fmax", {})
assert len(fmax) >= 2, f"Missing system or PCLK timing: {fmax}"
assert any("cam_pclk" in clock for clock in fmax), fmax
for clock, timing in fmax.items():
    assert timing["achieved"] >= timing["constraint"], (clock, timing)
assert "ERROR:" not in log
print(f"Build checks passed: {ram_count} DP16KD blocks; clocks: {fmax}")
