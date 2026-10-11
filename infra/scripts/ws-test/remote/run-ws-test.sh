#!/bin/bash
# =============================================================================
# run-ws-test.sh WORKSHOP [--no-reset] [--no-wait] [-- WS_TEST_ARGS...] — run the
# generated ws-test of WORKSHOP on the IDE, detached from SSM, and wait for it.
#
# On the IDE: infra/scripts/deploy/WORKSHOP/reset-app.sh (when it exists, unless
# --no-reset) > ~/ws-test-run/reset.log, then infra/scripts/ws-test/WORKSHOP.sh
# WS_TEST_ARGS > ~/ws-test-run/console.log, then its exit code in ~/ws-test-run/exit.
# Polls every 30 s and prints the last console line; --no-wait returns after the start
# (poll later with --status). A java-performance run takes about 20 min.
#
#   run-ws-test.sh --status   last console lines and the exit code, if finished
#
# ws-test reads the commands from the content at generation time: regenerate
# (node infra/scripts/ws-test/generate.mjs WORKSHOP), commit and sync-branch.sh first.
# Never run interactive Claude on the IDE during a run: `claude -c` in the run resumes
# the most recent session.
# =============================================================================
set -euo pipefail
DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$DIR/env.sh"

usage() { sed -n 3,18p "$0" | sed 's/^# \{0,1\}//'; exit 2; }
STATUS_SCRIPT='cd ~/ws-test-run 2>/dev/null || { echo "no run"; exit 0; }
tail -n "${1:-3}" console.log 2>/dev/null | sed "s/\x1b\[[0-9;]*m//g"
[ -f exit ] && echo "exit: $(cat exit)"; true'

status() { printf '%s\n' "$STATUS_SCRIPT" | "$DIR/run-on-ide.sh" - 120 | sed '/^--- status: Success$/d'; }

[ $# -ge 1 ] || usage
if [ "$1" = --status ]; then status; exit 0; fi
WORKSHOP="$1"; shift
RESET=1; WAIT=1
while [ $# -gt 0 ]; do
    case "$1" in
        --no-reset) RESET=0 ;;
        --no-wait) WAIT=0 ;;
        --) shift; break ;;
        *) usage ;;
    esac
    shift
done
ARGS=""; [ $# -gt 0 ] && ARGS=$(printf ' %q' "$@")

"$DIR/run-on-ide.sh" - 120 <<EOF
set -euo pipefail
cd ~/java-on-aws
[ -f infra/scripts/ws-test/$WORKSHOP.sh ] || { echo "no ws-test for $WORKSHOP"; exit 1; }
rm -rf ~/ws-test-run && mkdir -p ~/ws-test-run
cat > ~/ws-test-run/job.sh <<'JOB'
cd ~/java-on-aws
R=infra/scripts/deploy/$WORKSHOP/reset-app.sh
if [ $RESET = 1 ] && [ -f "\$R" ]; then bash "\$R" > ~/ws-test-run/reset.log 2>&1 || { echo \$? > ~/ws-test-run/exit; exit; }; fi
date -u +%FT%TZ > ~/ws-test-run/started
bash infra/scripts/ws-test/$WORKSHOP.sh$ARGS > ~/ws-test-run/console.log 2>&1
echo \$? > ~/ws-test-run/exit
JOB
setsid nohup bash -l ~/ws-test-run/job.sh > /dev/null 2>&1 < /dev/null &
echo "started on \$(hostname) at \$(date -u +%FT%TZ), git \$(git log --oneline -1)"
EOF

[ "$WAIT" = 1 ] || exit 0
while :; do
    sleep 30
    OUT=$(status) || continue
    echo "$OUT" | grep -v '^exit:' | tail -1
    if CODE=$(echo "$OUT" | sed -n 's/^exit: //p') && [ -n "$CODE" ]; then
        echo "finished, exit $CODE"
        [ "$CODE" = 0 ]; exit
    fi
done
