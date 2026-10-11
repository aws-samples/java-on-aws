#!/bin/bash
# =============================================================================
# ide-layout.sh — the two terminals of the session, set at bootstrap, nothing in
# ~/environment: the terminal in the editor area (Code Editor's startup editor, a zsh in
# ~/environment) is where Claude Code runs; a user-level task opens the Shell terminal in
# the bottom panel each time the IDE opens.
#
# Writes ~/.code-editor-server/data/User/tasks.json (task "Shell", runOn folderOpen) and
# sets "task.allowAutomaticTasks": "on" in the user settings (without it Code Editor asks
# before running the task). Runs as ec2-user after ide/code-editor.sh. Idempotent.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

USER_DIR="${HOME}/.code-editor-server/data/User"
SETTINGS="${USER_DIR}/settings.json"
[ -f "${SETTINGS}" ] || { log_error "no Code Editor user settings at ${SETTINGS} (ide/code-editor.sh)"; exit 1; }

tmp="$(mktemp)"
jq '. + {"workbench.startupEditor": "terminal", "task.allowAutomaticTasks": "on"}' "${SETTINGS}" > "${tmp}"
mv "${tmp}" "${SETTINGS}"

cat > "${USER_DIR}/tasks.json" <<'JSON'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Shell",
      "type": "shell",
      "command": "exec zsh -l",
      "isBackground": true,
      "problemMatcher": [],
      "presentation": {"reveal": "always", "panel": "dedicated", "focus": false, "showReuseMessage": false, "echo": false},
      "runOptions": {"runOn": "folderOpen"}
    }
  ]
}
JSON
log_success "IDE layout: Claude Code terminal in the editor area, Shell terminal in the panel"
