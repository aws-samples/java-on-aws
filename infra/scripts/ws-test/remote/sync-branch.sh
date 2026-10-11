#!/bin/bash
# =============================================================================
# sync-branch.sh [--skills] [--sensor] [BRANCH] — move the IDE's ~/java-on-aws to a
# local branch that is not pushed: bundle origin/main..BRANCH (default: the current
# branch), upload it to S3, fetch it on the IDE and `checkout -B` the branch there.
# Only commits travel: commit first.
#
#   --skills   then reinstall the Claude Code skills and settings (claude-code.sh);
#              reset-app.sh does not
#   --sensor   then rebuild and reinstall the sensor (perf-sensor.sh)
#
# The IDE clones java-on-aws main at bootstrap, so a fresh environment needs this
# before every run of a branch.
# =============================================================================
set -euo pipefail
DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$DIR/env.sh"

SKILLS=0; SENSOR=0; BRANCH=""
for a in "$@"; do
    case "$a" in
        --skills) SKILLS=1 ;;
        --sensor) SENSOR=1 ;;
        -*) sed -n 3,13p "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
        *) BRANCH="$a" ;;
    esac
done
BRANCH="${BRANCH:-$(git -C "$WS_REPO" branch --show-current)}"
[ -z "$(git -C "$WS_REPO" status --porcelain --untracked-files=no)" ] \
    || echo "Warning: uncommitted changes in $WS_REPO are not synced" >&2

BUNDLE="$WS_LOCAL/java-on-aws.bundle"
git -C "$WS_REPO" bundle create -q "$BUNDLE" "origin/main..$BRANCH"
aws s3 cp --quiet "$BUNDLE" "$WS_S3/java-on-aws.bundle"

DEPLOY='~/java-on-aws/infra/scripts/deploy/java-performance'
{
    cat <<EOF
set -euo pipefail
aws s3 cp --quiet "$WS_S3/java-on-aws.bundle" /tmp/java-on-aws.bundle
cd ~/java-on-aws
git fetch -q origin main
git fetch -q -f /tmp/java-on-aws.bundle "+$BRANCH:refs/ws-test/$BRANCH"
git checkout -q -B "$BRANCH" "refs/ws-test/$BRANCH"
git log --oneline -1
EOF
    [ "$SKILLS" = 1 ] && echo "bash $DEPLOY/claude-code.sh > /tmp/claude-code.log 2>&1 && echo 'skills reinstalled'"
    [ "$SENSOR" = 1 ] && echo "bash $DEPLOY/perf-sensor.sh > /tmp/perf-sensor.log 2>&1 && echo 'sensor rebuilt and installed'"
    echo true
} | "$DIR/run-on-ide.sh" - 1800
