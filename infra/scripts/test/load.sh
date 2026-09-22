#!/bin/sh
# =============================================================================
# load.sh — start a fixed load run against the EKS deployment and return while
# it is still flowing, so a measurement taken right after sees traffic.
#
# 120 s at 50 writes/s (POST /unicorns, see benchmark.yaml) in the background,
# returns after 90 s: the rate windows the sensor reads are full and ~30 s of
# load remain for thread-dump sampling. The only command the Claude Code
# workspace in ~/environment is allowed to run (see perf-sensor-ide.sh).
#
#   load.sh              # 120 s @ 50 rps, returns after 90 s
#   load.sh 60 20 45     # duration, arrival rate, seconds to wait before returning
# =============================================================================
DURATION="${1:-120}"
RATE="${2:-50}"
WAIT="${3:-90}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SVC_URL="$("$SCRIPT_DIR/getsvcurl.sh" eks)"
if [ -z "$SVC_URL" ]; then
    echo "load.sh: could not resolve the service URL (getsvcurl.sh eks)" >&2
    exit 1
fi

"$SCRIPT_DIR/benchmark.sh" "$SVC_URL" "$DURATION" "$RATE" >/dev/null 2>&1 &
echo "load started: ${RATE} req/s for ${DURATION} s against ${SVC_URL}"
sleep "$WAIT"
echo "load flowing (${WAIT} s in, ~$((DURATION - WAIT)) s left) — measure now"
