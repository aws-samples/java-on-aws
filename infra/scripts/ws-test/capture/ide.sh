#!/bin/bash
# =============================================================================
# ide.sh open|tools|scm OUT_DIR — Code Editor screenshots of the workshop IDE (ide.mjs).
#
# Headless Chrome renders the terminal blank with GPU acceleration, so this sets
# "terminal.integrated.gpuAcceleration": "off" in the IDE's user settings for the
# capture and restores the file afterwards (also on failure).
#
#   open   the IDE as it opens (both terminals).
#   tools  Claude lists the MCP tools. Never while a ws-test runs.
#   scm    the diff between two commits of the app repo in Source Control: the repo is
#          detached at the commit matching SCM_BASE (default "baseline: profiler
#          attached"), the worktree restored from SCM_TARGET (default "right-size
#          memory and cpu"), SCM_FILE (default deployment.yaml) opened; afterwards the
#          branch is checked out again and untracked files removed. Needs a finished
#          run's commits.
#
# Needs Chrome and `npm install` in this directory once.
# =============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../remote/env.sh"
RUN="$DIR/../remote/run-on-ide.sh"

WHAT="${1:-}"; OUT="${2:-.}"
case "$WHAT" in open|tools|scm) ;; *) sed -n 3,17p "$0" | sed 's/^# \{0,1\}//'; exit 2 ;; esac
mkdir -p "$OUT"
APP='~/environment/unicorn-store-spring'
SETTINGS='~/.code-editor-server/data/User/settings.json'

restore() {
    {
        echo "cp /tmp/ws-capture-settings.json $SETTINGS 2>/dev/null || true"
        [ "$WHAT" = scm ] && echo "B=\$(cat /tmp/ws-capture-branch) && git -C $APP switch -q -f \"\$B\" && git -C $APP clean -qfd"
        echo true
    } | "$RUN" - 120 > /dev/null || echo "Warning: restoring the IDE failed" >&2
}
trap restore EXIT

{
    cat <<EOF
set -euo pipefail
cp $SETTINGS /tmp/ws-capture-settings.json
jq '."terminal.integrated.gpuAcceleration" = "off"' /tmp/ws-capture-settings.json > $SETTINGS
EOF
    [ "$WHAT" = scm ] && cat <<EOF
git -C $APP branch --show-current > /tmp/ws-capture-branch
BASE=\$(git -C $APP log --format=%H --grep='${SCM_BASE:-baseline: profiler attached}' -n1)
TARGET=\$(git -C $APP log --format=%H --grep='${SCM_TARGET:-right-size memory and cpu}' -n1)
[ -n "\$BASE" ] && [ -n "\$TARGET" ] || { echo "commits not found"; exit 1; }
git -C $APP switch -q --detach "\$BASE"
git -C $APP restore --source="\$TARGET" --worktree -- .
git -C $APP status --short
EOF
    echo true
} | "$RUN" - 120

IDE_URL=$(ws_stack_output IdeUrl) node "$DIR/ide.mjs" "$WHAT" "$OUT"
