#!/bin/bash
# =============================================================================
# fetch-report.sh WORKSHOP [RUN_ID] — copy a ws-test report from the IDE to
# $WS_LOCAL/reports/WORKSHOP/RUN_ID (default: the newest run) through S3, together with
# ~/ws-test-run/{reset,console}.log of run-ws-test.sh, and cut its output.log into
# blocks.json (samples/extract-blocks.py). Writes the account ID to account, for masking.
# Prints the local directory.
# =============================================================================
set -euo pipefail
DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$DIR/env.sh"

[ $# -ge 1 ] || { sed -n 3,7p "$0" | sed 's/^# \{0,1\}//'; exit 2; }
WORKSHOP="$1"; RUN="${2:-}"

OUT=$("$DIR/run-on-ide.sh" - 300 <<EOF
set -euo pipefail
cd ~/java-on-aws/infra/scripts/ws-test/reports/$WORKSHOP
RUN="${RUN:-\$(ls -1 | sort | tail -1)}"
[ -d "\$RUN" ] || { echo "no report \$RUN"; exit 1; }
cp ~/ws-test-run/reset.log ~/ws-test-run/console.log "\$RUN/" 2>/dev/null || true
tar czf /tmp/ws-report.tgz "\$RUN"
aws s3 cp --quiet /tmp/ws-report.tgz "$WS_S3/report.tgz"
echo "run: \$RUN"
EOF
) || { echo "$OUT"; exit 1; }
RUN=$(echo "$OUT" | sed -n 's/^run: //p')

DEST="$WS_LOCAL/reports/$WORKSHOP"
mkdir -p "$DEST"
aws s3 cp --quiet "$WS_S3/report.tgz" "$WS_LOCAL/report.tgz"
rm -rf "${DEST:?}/$RUN"
tar xzf "$WS_LOCAL/report.tgz" -C "$DEST"
echo "$WS_ACCOUNT" > "$DEST/$RUN/account"
python3 "$DIR/../samples/extract-blocks.py" "$DEST/$RUN" > /dev/null
echo "$DEST/$RUN"
