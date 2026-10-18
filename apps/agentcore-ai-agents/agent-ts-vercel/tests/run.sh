#!/bin/bash
# Assemble every stage into a temp dir and run the smoke test (AWS calls mocked); compile the backoffice stages.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
BACKOFFICE="${HERE}/../backoffice-ts"
WORK=$(mktemp -d)
for stage in $(ls "$HERE/stages"); do
  python3 "$HERE/build_stages.py" assemble "$stage" "$WORK/$stage" >/dev/null
  ln -s "$HERE/node_modules" "$WORK/$stage/node_modules"
  mkdir -p "$WORK/$stage/static" && cp "$HERE/../ui/"* "$WORK/$stage/static/"
  (cd "$WORK/$stage" && npx tsc --noEmit -p . && npx tsx "$HERE/tests/smoke.ts" "$stage" 2>&1 | grep -v '"level":30')
done
# The backoffice stages build on each other like the participant's working copy
mkdir -p "$WORK/backoffice"
cp "$BACKOFFICE/app/"*.ts "$BACKOFFICE/app/tsconfig.json" "$WORK/backoffice/"
ln -s "$BACKOFFICE/node_modules" "$WORK/backoffice/node_modules"
for stage in $(ls "$BACKOFFICE/stages"); do
  cp "$BACKOFFICE/stages/$stage/"* "$WORK/backoffice/"
  (cd "$WORK/backoffice" && "$HERE/node_modules/.bin/tsc" --noEmit -p . && echo "backoffice ${stage}: compiles")
done
rm -rf "$WORK"
