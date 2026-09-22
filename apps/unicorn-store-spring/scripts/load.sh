#!/bin/bash
# =============================================================================
# load.sh — load-test this service on EKS and return while the load still flows.
#
# Thin wrapper over the shared test scripts (benchmark.sh drives POST /unicorns
# from benchmark.yaml; getsvcurl.sh resolves the Ingress). Defaults: 50 req/s
# for 120 s, return after 90 s — by then every 1-minute rate window is full and
# ~30 s of load remain for anything that samples the running process (thread
# dumps, profiles). Measure right after this script returns.
#
#   ./scripts/load.sh              # 120 s @ 50 req/s, returns after 90 s
#   ./scripts/load.sh 60 20 45     # duration, arrival rate, seconds to wait
#
# JAVA_ON_AWS_TEST_DIR overrides where the shared scripts live.
# =============================================================================
set -uo pipefail

DURATION="${1:-120}"
RATE="${2:-50}"
WAIT="${3:-90}"
TEST_DIR="${JAVA_ON_AWS_TEST_DIR:-${HOME}/java-on-aws/infra/scripts/test}"

[ -x "${TEST_DIR}/benchmark.sh" ] && [ -x "${TEST_DIR}/getsvcurl.sh" ] \
  || { echo "load.sh: shared test scripts not found in ${TEST_DIR}" >&2; exit 1; }

URL="$("${TEST_DIR}/getsvcurl.sh" eks)" || exit 1

"${TEST_DIR}/benchmark.sh" "${URL}" "${DURATION}" "${RATE}" >/dev/null 2>&1 &
echo "load started: ${RATE} req/s for ${DURATION} s against ${URL}/unicorns"
sleep "${WAIT}"
echo "load flowing (${WAIT} s in, ~$((DURATION - WAIT)) s left) — measure now"
