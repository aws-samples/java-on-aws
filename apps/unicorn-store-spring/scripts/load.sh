#!/bin/bash
# =============================================================================
# load.sh — drive traffic at this service on EKS.
#
# Thin wrapper over the shared test scripts (benchmark.sh drives POST /unicorns
# from benchmark.yaml; getsvcurl.sh resolves the Ingress). Runs in the
# foreground for <duration> seconds. Keep it running in its own terminal for as
# long as the service should be "in production":
#
#   while true; do ./scripts/load.sh 600 50; done     # steady 50 req/s
#   ./scripts/load.sh 120 50                          # one 2-minute run
#
# JAVA_ON_AWS_TEST_DIR overrides where the shared scripts live.
# =============================================================================
set -uo pipefail

DURATION="${1:-120}"
RATE="${2:-50}"
TEST_DIR="${JAVA_ON_AWS_TEST_DIR:-${HOME}/java-on-aws/infra/scripts/test}"

[ -x "${TEST_DIR}/benchmark.sh" ] && [ -x "${TEST_DIR}/getsvcurl.sh" ] \
  || { echo "load.sh: shared test scripts not found in ${TEST_DIR}" >&2; exit 1; }

URL="$("${TEST_DIR}/getsvcurl.sh" eks)" || exit 1

echo "load: ${RATE} req/s for ${DURATION} s against ${URL}/unicorns"
exec "${TEST_DIR}/benchmark.sh" "${URL}" "${DURATION}" "${RATE}" >/dev/null 2>&1
