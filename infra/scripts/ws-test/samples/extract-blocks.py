#!/usr/bin/env python3
"""extract-blocks.py REPORT_DIR — cut a ws-test output.log into the output of each block.

Writes REPORT_DIR/blocks.json: {"<page>:<start>-<end>": "<output>"}, keyed by the
"Source: <page>:<lines>" line the runtime prints before each block, up to the block's
PASSED line. Prints the keys in run order.
"""
import json
import re
import sys
from pathlib import Path

if len(sys.argv) != 2:
    sys.exit(__doc__)
report = Path(sys.argv[1])
blocks, cur = {}, None
for line in (report / 'output.log').read_text().split('\n'):
    m = re.match(r'^Source: (\S+)$', line)
    if m:
        cur = m.group(1)
        blocks[cur] = []
        continue
    if cur and ('\x1b[1mPASSED' in line or line.startswith('PASSED (')):
        cur = None
        continue
    if cur is not None:
        blocks[cur].append(line)
(report / 'blocks.json').write_text(
    json.dumps({k: '\n'.join(v).strip('\n') for k, v in blocks.items()}, indent=1))
print('\n'.join(blocks))
