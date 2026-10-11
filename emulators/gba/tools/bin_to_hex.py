import sys
from pathlib import Path

data = Path(sys.argv[1]).read_bytes()
data += bytes((-len(data)) % 4)
Path(sys.argv[2]).write_text(''.join('%08x\n' % int.from_bytes(data[i:i+4], 'little')
                                  for i in range(0, len(data), 4)))
