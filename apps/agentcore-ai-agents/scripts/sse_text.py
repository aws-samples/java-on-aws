#!/usr/bin/env python3
"""Print an AgentCore Runtime SSE stream (stdin) as text."""
import json, sys
# Same decoding as the UI (apps/ui/chat.js): `data: text` (SSE spec, Python and TypeScript SDKs) or `data:text`
# (Spring) decided by the first data line, data lines of one event joined by newlines, JSON strings decoded
def decode(data):
    if len(data.strip()) >= 2 and data.strip()[0] == data.strip()[-1] == "\"":
        try:
            return json.loads(data)  # the Python SDK sends JSON-encoded strings
        except ValueError:
            pass
    return data
event, prefix = [], None
for line in sys.stdin:
    line = line.rstrip("\n").rstrip("\r")
    if line.startswith("data:"):
        prefix = prefix or ("data: " if line.startswith("data: ") else "data:")
        event.append(line[len(prefix):] if line.startswith(prefix) else line[5:])
    elif line == "" and event:
        print(decode("\n".join(event)), end="", flush=True)
        event = []
if event:
    print(decode("\n".join(event)), end="")
print()
