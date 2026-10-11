#!/bin/bash
# =============================================================================
# run-on-ide.sh SCRIPT|- [TIMEOUT_SECONDS] — run a bash script on the IDE instance as
# ec2-user (login shell: /etc/profile.d/workshop.sh, kubectl context) through SSM
# Run Command, wait for it, print its stdout and stderr. `-` reads the script from stdin.
#
# Exit status 0 when the command succeeded, 1 otherwise. SSM marks a command Failed when
# its last command exits non-zero (for example a trailing `grep -c` that counts 0), so
# end scripts with a command that succeeds. SSM keeps only the first 24 KB of output:
# write long output to a file on the IDE and fetch it through S3.
# Default timeout 3600 s.
# =============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

[ $# -ge 1 ] || { sed -n 3,12p "$0" | sed 's/^# \{0,1\}//'; exit 2; }
SRC="$1"; TIMEOUT="${2:-3600}"
if [ "$SRC" = - ]; then B64=$(base64 | tr -d '\n'); else B64=$(base64 < "$SRC" | tr -d '\n'); fi

PARAMS=$(python3 -c 'import json,sys; print(json.dumps({"commands": [
  "echo " + sys.argv[1] + " | base64 -d > /tmp/ws-job.sh && chmod 755 /tmp/ws-job.sh && sudo -iu ec2-user bash -l /tmp/ws-job.sh"],
  "executionTimeout": [sys.argv[2]]}))' "$B64" "$TIMEOUT")
CMD=$(aws ssm send-command --instance-ids "$WS_IDE_INSTANCE" --document-name AWS-RunShellScript \
    --timeout-seconds 60 --parameters "$PARAMS" --query Command.CommandId --output text) || exit 1

while :; do
    sleep 5
    STATUS=$(aws ssm get-command-invocation --command-id "$CMD" --instance-id "$WS_IDE_INSTANCE" \
        --query Status --output text 2>/dev/null)
    case "$STATUS" in Pending|InProgress|Delayed|"") continue ;; esac
    break
done

aws ssm get-command-invocation --command-id "$CMD" --instance-id "$WS_IDE_INSTANCE" \
    --query StandardOutputContent --output text
ERR=$(aws ssm get-command-invocation --command-id "$CMD" --instance-id "$WS_IDE_INSTANCE" \
    --query StandardErrorContent --output text)
[ -n "$ERR" ] && [ "$ERR" != None ] && { echo "--- stderr"; echo "$ERR"; }
echo "--- status: $STATUS"
[ "$STATUS" = Success ]
