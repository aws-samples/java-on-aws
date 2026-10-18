#!/bin/bash
# Assemble every stage into a temp dir and run the smoke test with the app's dependencies.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK=$(mktemp -d)
cd "$HERE" && uv sync --frozen -q
for stage in $(ls "$HERE/stages"); do
  python3 "$HERE/build_stages.py" assemble "$stage" "$WORK/$stage"
  mkdir -p "$WORK/$stage/static" && cp "$HERE/../ui/"* "$WORK/$stage/static/"
  (cd "$WORK/$stage" && "$HERE/.venv/bin/python" -W ignore "$HERE/tests/smoke.py" "$stage")
done
rm -rf "$WORK"
