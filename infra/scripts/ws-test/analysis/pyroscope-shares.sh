#!/bin/bash
# =============================================================================
# pyroscope-shares.sh WINDOW... — run pyroscope-shares.py on the IDE against the
# cluster's Pyroscope (port-forward svc/pyroscope 4040 in monitoring for the call).
# WINDOW is "label|pod-suffix|from|to", see pyroscope-shares.py.
#
# Pod names and their start: on the IDE,
#   kubectl -n unicorn-store-spring get pods -o custom-columns=NAME:.metadata.name,START:.status.startTime
# =============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -ge 1 ] || { sed -n 3,8p "$0" | sed 's/^# \{0,1\}//'; exit 2; }

{
    echo 'kubectl -n monitoring port-forward svc/pyroscope 4040:4040 > /dev/null 2>&1 & PF=$!'
    echo 'trap "kill $PF" EXIT; sleep 4'
    printf 'python3 - %s <<'\''PY'\''\n' "$(printf '%q ' "$@")"
    cat "$DIR/pyroscope-shares.py"
    echo 'PY'
} | "$DIR/../remote/run-on-ide.sh" - 600
