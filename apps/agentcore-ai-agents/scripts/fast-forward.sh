#!/bin/bash
# Facilitators only (FACILITATOR_GUIDE.md): bring a fresh Code Editor to the start of a module, unattended.
#
#   fast-forward.sh --to WEIGHT [FRAMEWORK] [ws-test arguments...]
#
# WEIGHT: the module to stop before (title -> weight table in FACILITATOR_GUIDE.md), for example 1100.
# FRAMEWORK: python-strands, python-langgraph, ts-vercel, java-spring-ai; default: FRAMEWORK in ~/environment/.envrc.
# Runs the workshop's ws-test script (every code block of the pages before WEIGHT, in order) with --onlyTab FRAMEWORK
# from the start. Resources found by name are reused, project folders are created from scratch: run it on a fresh
# home only. A failed run continues with --from WEIGHT[:BLOCK] (printed at the end).
# Output: one line per step; the full log in ~/environment/fast-forward.log.
set -uo pipefail
[ "${1:-}" = "--to" ] || { echo "usage: fast-forward.sh --to WEIGHT [FRAMEWORK] [ws-test arguments...]" >&2; exit 2; }
TO="${2:?WEIGHT}"; shift 2
[ -f ~/environment/.envrc ] && source ~/environment/.envrc
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then FRAMEWORK="$1"; shift; fi
FRAMEWORK="${FRAMEWORK:?no FRAMEWORK in ~/environment/.envrc: pass python-strands, python-langgraph, ts-vercel, or java-spring-ai}"
WS_TEST_DIR="${WS_TEST_DIR:-${HOME}/java-on-aws/infra/scripts/ws-test}"
LOG=~/environment/fast-forward.log
mkdir -p ~/environment

if [ $# -eq 0 ]; then
  for dir in aiagent backoffice; do
    if [ -d ~/environment/${dir} ]; then
      echo "~/environment/${dir} exists: fast-forward starts from a fresh home (or continue a failed run with --from)" >&2
      exit 1
    fi
  done
fi

echo "Fast-forward ${FRAMEWORK} to module ${TO}, log: ${LOG}"
start=$(date +%s)
bash "${WS_TEST_DIR}/agentcore-ai-agents.sh" --onlyTab "${FRAMEWORK}" --to "${TO}" "$@" > "${LOG}" 2>&1 &
run=$!
tail -n +1 -f "${LOG}" --pid "${run}" 2>/dev/null | grep --line-buffered -E "PASSED|FAILED" \
  | sed -u -E 's/\x1b\[[0-9;]*m//g; s/ - [0-9]+\/[0-9]+ - / - /'
wait "${run}"
status=$?
if [ "${status}" -ne 0 ]; then
  echo "Fast-forward stopped after $(( $(date +%s) - start )) s; see ${LOG}. Fix the cause and continue with:"
  echo "  fast-forward.sh --to ${TO} ${FRAMEWORK} --from $(grep -oE 'FAILED \([0-9]+s\) - [0-9]+:[0-9]+' "${LOG}" | tail -1 | awk '{print $4}')"
  exit "${status}"
fi
echo "Ready for module ${TO} after $(( $(date +%s) - start )) s"
