#!/usr/bin/env bash

set -Eeuo pipefail

WS_RUNTIME_VERSION=1
WS_RUN_ACTIVE=0
WS_RUN_FINISHED=0
WS_FAILURE_WRITTEN=0
WS_TOTAL=0
WS_PASSED=0
WS_FAILED=0
WS_SKIPPED=0
WS_EXECUTED=0
WS_CURRENT_PAGE=""
WS_CURRENT_WEIGHT=""
WS_CURRENT_SOURCE=""
WS_CURRENT_BLOCK=""
WS_CURRENT_SECTION=""
WS_CURRENT_STEP=""
WS_CURRENT_LINES=""
WS_CURRENT_TIMEOUT=""
WS_CURRENT_LANGUAGE=""
WS_CURRENT_CODE_FILE=""
WS_CURRENT_STARTED=0
WS_WATCHDOG_PID=""

ws_json_escape() {
  WS_ESCAPED=${1//\\/\\\\}
  WS_ESCAPED=${WS_ESCAPED//\"/\\\"}
  WS_ESCAPED=${WS_ESCAPED//$'\n'/\\n}
  WS_ESCAPED=${WS_ESCAPED//$'\r'/\\r}
  WS_ESCAPED=${WS_ESCAPED//$'\t'/\\t}
}

ws_xml_escape() {
  WS_ESCAPED=${1//&/&amp;}
  WS_ESCAPED=${WS_ESCAPED//</&lt;}
  WS_ESCAPED=${WS_ESCAPED//>/&gt;}
  WS_ESCAPED=${WS_ESCAPED//\"/&quot;}
  WS_ESCAPED=${WS_ESCAPED//\'/&apos;}
}

ws_markdown_escape() {
  WS_ESCAPED=${1//|/\\|}
  WS_ESCAPED=${WS_ESCAPED//$'\n'/ }
}

ws_now_iso() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

ws_append_event() {
  local status="$1"
  local duration="$2"
  local message="${3:-}"
  ws_json_escape "${WS_CURRENT_PAGE}"; local page="$WS_ESCAPED"
  ws_json_escape "${WS_CURRENT_SOURCE}"; local source="$WS_ESCAPED"
  ws_json_escape "${WS_CURRENT_BLOCK}"; local block="$WS_ESCAPED"
  ws_json_escape "${WS_CURRENT_SECTION}"; local section="$WS_ESCAPED"
  ws_json_escape "${WS_CURRENT_STEP}"; local step="$WS_ESCAPED"
  ws_json_escape "$message"; local escaped_message="$WS_ESCAPED"
  printf '{"status":"%s","page":"%s","weight":%s,"source":"%s","block":"%s","section":"%s","step":"%s","lines":"%s","durationSeconds":%s,"message":"%s"}\n' \
    "$status" "$page" "${WS_CURRENT_WEIGHT:-0}" "$source" "$block" "$section" "$step" \
    "${WS_CURRENT_LINES}" "$duration" "$escaped_message" >> "$WS_EVENTS_FILE"
}

ws_append_markdown_row() {
  local status="$1"
  local duration="$2"
  local detail="${3:-}"
  ws_markdown_escape "$WS_CURRENT_PAGE"; local page="$WS_ESCAPED"
  ws_markdown_escape "$WS_CURRENT_STEP"; local step="$WS_ESCAPED"
  ws_markdown_escape "$WS_CURRENT_BLOCK"; local block="$WS_ESCAPED"
  ws_markdown_escape "$detail"; local escaped_detail="$WS_ESCAPED"
  printf '| %s | %s | %s | %s | %ss | %s |\n' "$status" "$page" "$step" "$block" "$duration" "$escaped_detail" >> "$WS_SUMMARY_MD"
}

ws_append_junit() {
  local status="$1"
  local duration="$2"
  local message="${3:-}"
  ws_xml_escape "$WS_CURRENT_PAGE"; local page="$WS_ESCAPED"
  ws_xml_escape "$WS_CURRENT_STEP ($WS_CURRENT_BLOCK)"; local block="$WS_ESCAPED"
  ws_xml_escape "$message"; local escaped_message="$WS_ESCAPED"
  if [[ "$status" == "passed" ]]; then
    printf '  <testcase classname="%s" name="%s" time="%s"/>\n' "$page" "$block" "$duration" >> "$WS_JUNIT_FRAGMENT"
  elif [[ "$status" == "skipped" ]]; then
    printf '  <testcase classname="%s" name="%s" time="0"><skipped message="%s"/></testcase>\n' "$page" "$block" "$escaped_message" >> "$WS_JUNIT_FRAGMENT"
  else
    printf '  <testcase classname="%s" name="%s" time="%s"><failure message="%s"/></testcase>\n' "$page" "$block" "$duration" "$escaped_message" >> "$WS_JUNIT_FRAGMENT"
  fi
}

ws_write_summary_json() {
  local status="$1"
  local exit_code="$2"
  local duration="$3"
  local message="${4:-}"
  ws_json_escape "$WS_WORKSHOP_TITLE"; local title="$WS_ESCAPED"
  ws_json_escape "$message"; local escaped_message="$WS_ESCAPED"
  ws_json_escape "$WS_RUN_DIR"; local run_dir="$WS_ESCAPED"
  cat > "$WS_SUMMARY_JSON" <<EOF
{
  "status": "${status}",
  "workshop": "${title}",
  "runtimeVersion": ${WS_RUNTIME_VERSION},
  "startedAt": "${WS_STARTED_AT}",
  "finishedAt": "$(ws_now_iso)",
  "durationSeconds": ${duration},
  "exitCode": ${exit_code},
  "counts": {
    "total": ${WS_TOTAL},
    "passed": ${WS_PASSED},
    "failed": ${WS_FAILED},
    "skipped": ${WS_SKIPPED}
  },
  "message": "${escaped_message}",
  "runDirectory": "${run_dir}"
}
EOF
}

ws_write_junit() {
  local duration="$1"
  ws_xml_escape "$WS_WORKSHOP_TITLE"; local title="$WS_ESCAPED"
  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<testsuite name="%s" tests="%s" failures="%s" skipped="%s" time="%s">\n' \
      "$title" "$WS_TOTAL" "$WS_FAILED" "$WS_SKIPPED" "$duration"
    cat "$WS_JUNIT_FRAGMENT"
    printf '</testsuite>\n'
  } > "$WS_JUNIT_FILE"
}

ws_write_failure() {
  local exit_code="$1"
  local message="$2"
  [[ "$WS_FAILURE_WRITTEN" == "1" ]] && return 0
  WS_FAILURE_WRITTEN=1
  WS_FAILED=$((WS_FAILED + 1))
  WS_TOTAL=$((WS_TOTAL + 1))
  local now duration
  now=$(date +%s)
  duration=$((now - WS_CURRENT_STARTED))
  (( duration < 0 )) && duration=0

  ws_append_event "failed" "$duration" "$message"
  ws_append_markdown_row "FAILED" "$duration" "$message"
  ws_append_junit "failed" "$duration" "$message"
  local run_duration=$((now - WS_RUN_STARTED))
  ws_write_summary_json "failed" "$exit_code" "$run_duration" "$message"
  ws_write_junit "$run_duration"

  {
    echo '# Workshop test failure'
    echo
    echo "- **Workshop:** ${WS_WORKSHOP_TITLE}"
    echo "- **Chapter:** ${WS_CURRENT_WEIGHT} ${WS_CURRENT_PAGE}"
    echo "- **Section:** ${WS_CURRENT_SECTION}"
    echo "- **Step:** ${WS_CURRENT_STEP}"
    echo "- **Block:** ${WS_CURRENT_BLOCK}"
    echo "- **Source:** ${WS_CURRENT_SOURCE}:${WS_CURRENT_LINES}"
    echo "- **Language:** ${WS_CURRENT_LANGUAGE:-<none>}"
    echo "- **Timeout:** ${WS_CURRENT_TIMEOUT}s"
    echo "- **Exit code:** ${exit_code}"
    echo "- **Duration:** ${duration}s"
    echo
    echo '## Failed code block'
    echo
    echo "~~~~${WS_CURRENT_LANGUAGE}"
    if [[ -f "$WS_CURRENT_CODE_FILE" ]]; then
      cat "$WS_CURRENT_CODE_FILE"
    else
      echo '(code block unavailable)'
    fi
    echo '~~~~'
    echo
    echo '## Error'
    echo
    echo '```text'
    echo "$message"
    echo '```'
    echo
    echo '## Recent output'
    echo
    echo '```text'
    tail -100 "$WS_OUTPUT_LOG" 2>/dev/null || true
    echo '```'
  } > "$WS_FAILURE_MD"
}

ws_print_failure() {
  local exit_code="$1"
  local message="$2"
  echo >&2
  echo "FAILED" >&2
  echo "Chapter: ${WS_CURRENT_WEIGHT} ${WS_CURRENT_PAGE}" >&2
  echo "Section: ${WS_CURRENT_SECTION}" >&2
  echo "Step: ${WS_CURRENT_STEP}" >&2
  echo "Block: ${WS_CURRENT_BLOCK}" >&2
  echo "Source: ${WS_CURRENT_SOURCE}:${WS_CURRENT_LINES}" >&2
  echo "Exit code: ${exit_code}" >&2
  echo >&2
  echo "Failed code block:" >&2
  echo '----------------------------------------' >&2
  if [[ -f "$WS_CURRENT_CODE_FILE" ]]; then
    cat "$WS_CURRENT_CODE_FILE" >&2
  else
    echo '(code block unavailable)' >&2
  fi
  echo '----------------------------------------' >&2
  echo "Error:" >&2
  echo "$message" >&2
  echo >&2
  echo "Reports: ${WS_RUN_DIR}" >&2
}

ws_handle_error() {
  local exit_code="$1"
  local command="$2"
  trap - ERR
  local message="command failed: ${command}"
  ws_write_failure "$exit_code" "$message"
  ws_print_failure "$exit_code" "$message"
  exit "$exit_code"
}

ws_handle_signal() {
  local signal="$1"
  local exit_code="$2"
  local message
  trap - ERR TERM INT
  if [[ -f "${WS_RUN_DIR:-/nonexistent}/.timeout" ]]; then
    exit_code=124
    message="block exceeded ${WS_CURRENT_TIMEOUT}s timeout"
  else
    message="runner received ${signal}"
  fi
  ws_write_failure "$exit_code" "$message"
  ws_print_failure "$exit_code" "$message"
  exit "$exit_code"
}

ws_handle_exit() {
  local exit_code="$1"
  if [[ "$WS_RUN_ACTIVE" == "1" && "$WS_RUN_FINISHED" != "1" && "$WS_FAILURE_WRITTEN" != "1" ]]; then
    trap - ERR EXIT TERM INT
    [[ "$exit_code" == "0" ]] && exit_code=1
    ws_write_failure "$exit_code" "runner exited before the active block completed"
    exit "$exit_code"
  fi
}

ws_source_environment() {
  local environment_file="$1"
  if [[ ! -f "$environment_file" ]]; then
    echo "Environment file not found; continuing with current environment: ${environment_file}"
    return 0
  fi

  WS_CURRENT_PAGE="Environment setup"
  WS_CURRENT_WEIGHT=0
  WS_CURRENT_SOURCE="$environment_file"
  WS_CURRENT_BLOCK="source-environment"
  WS_CURRENT_SECTION="Environment setup"
  WS_CURRENT_STEP="Load workshop environment"
  WS_CURRENT_LINES="1"
  WS_CURRENT_LANGUAGE="bash"
  WS_CURRENT_TIMEOUT=0
  WS_CURRENT_STARTED=$(date +%s)
  echo "Loading environment: ${environment_file}"
  # shellcheck disable=SC1090
  source "$environment_file"
  ws_restore_runtime_guards
}

ws_restore_runtime_guards() {
  set -Eeuo pipefail
  trap 'ws_handle_error "$?" "$BASH_COMMAND" "$LINENO"' ERR
  trap 'ws_handle_signal TERM 143' TERM
  trap 'ws_handle_signal INT 130' INT
  trap 'ws_handle_exit "$?"' EXIT
}

ws_begin_run() {
  WS_WORKSHOP_TITLE="$1"
  WS_REPORT_ROOT="$2"
  WS_DELAY_SECONDS="$3"
  WS_RUN_STARTED=$(date +%s)
  WS_STARTED_AT=$(ws_now_iso)
  WS_RUN_ID=$(date -u '+%Y%m%dT%H%M%SZ')-$$
  WS_RUN_DIR="${WS_REPORT_ROOT}/${WS_RUN_ID}"
  mkdir -p "$WS_RUN_DIR"
  WS_OUTPUT_LOG="${WS_RUN_DIR}/output.log"
  WS_EVENTS_FILE="${WS_RUN_DIR}/events.jsonl"
  WS_SUMMARY_JSON="${WS_RUN_DIR}/summary.json"
  WS_SUMMARY_MD="${WS_RUN_DIR}/summary.md"
  WS_FAILURE_MD="${WS_RUN_DIR}/failure.md"
  WS_JUNIT_FILE="${WS_RUN_DIR}/junit.xml"
  WS_JUNIT_FRAGMENT="${WS_RUN_DIR}/.junit-fragment.xml"
  : > "$WS_OUTPUT_LOG"
  : > "$WS_EVENTS_FILE"
  : > "$WS_JUNIT_FRAGMENT"
  cat > "$WS_SUMMARY_MD" <<EOF
# Workshop test report

- **Workshop:** ${WS_WORKSHOP_TITLE}
- **Started:** ${WS_STARTED_AT}

| Status | Chapter | Step | Block | Duration | Detail |
|---|---|---|---|---:|---|
EOF
  WS_RUN_ACTIVE=1
  exec > >(tee -a "$WS_OUTPUT_LOG") 2>&1
  WS_TEE_PID=$!
  ws_restore_runtime_guards
  echo "Workshop: ${WS_WORKSHOP_TITLE}"
  echo "Run directory: ${WS_RUN_DIR}"
}

ws_begin_page() {
  WS_CURRENT_PAGE="$1"
  WS_CURRENT_WEIGHT="$2"
  WS_CURRENT_SOURCE="$3"
  echo
  echo "=== ${WS_CURRENT_WEIGHT} ${WS_CURRENT_PAGE} ==="
}

ws_run_block() {
  WS_CURRENT_BLOCK="$1"
  WS_CURRENT_SECTION="$2"
  WS_CURRENT_STEP="$3"
  local start_line="$4"
  local end_line="$5"
  WS_CURRENT_LANGUAGE="$6"
  WS_CURRENT_TIMEOUT="$7"
  WS_CURRENT_LINES="${start_line}-${end_line}"
  WS_CURRENT_CODE_FILE="${WS_RUN_DIR}/.current-block.sh"
  cat > "$WS_CURRENT_CODE_FILE"

  if (( WS_EXECUTED > 0 )); then
    echo "Waiting ${WS_DELAY_SECONDS}s before the next command block..."
    sleep "$WS_DELAY_SECONDS"
  fi
  WS_EXECUTED=$((WS_EXECUTED + 1))
  WS_CURRENT_STARTED=$(date +%s)
  local token="${WS_CURRENT_WEIGHT}-${WS_CURRENT_BLOCK}-${WS_CURRENT_STARTED}-$RANDOM"
  printf '%s\n' "$token" > "${WS_RUN_DIR}/.active-block"
  rm -f "${WS_RUN_DIR}/.timeout"

  echo
  echo "--- ${WS_CURRENT_STEP} [${WS_CURRENT_BLOCK}] ---"
  echo "Section: ${WS_CURRENT_SECTION}"
  echo "Source: ${WS_CURRENT_SOURCE}:${WS_CURRENT_LINES}"

  local runner_pid=$$
  sh -c '
    tee_pid=$6
    collect_descendants() {
      for child in $(pgrep -P "$1" 2>/dev/null || true); do
        if [ "$child" = "$$" ] || [ "$child" = "$tee_pid" ]; then
          continue
        fi
        collect_descendants "$child"
        printf "%s\n" "$child"
      done
    }

    sleep "$1"
    if [ -f "$2" ] && [ "$(cat "$2")" = "$3" ]; then
      : > "$4"
      descendants=$(collect_descendants "$5")
      kill -TERM "$5" 2>/dev/null || true
      for child in $descendants; do
        kill -TERM "$child" 2>/dev/null || true
      done
      sleep 2
      for child in $descendants; do
        kill -KILL "$child" 2>/dev/null || true
      done
    fi
  ' ws-test-watchdog \
    "$WS_CURRENT_TIMEOUT" \
    "${WS_RUN_DIR}/.active-block" \
    "$token" \
    "${WS_RUN_DIR}/.timeout" \
    "$runner_pid" \
    "$WS_TEE_PID" &
  WS_WATCHDOG_PID=$!

  # Source in the current shell so variables and working directory persist exactly
  # as they do when a participant uses one terminal throughout the workshop.
  source "$WS_CURRENT_CODE_FILE"
  ws_restore_runtime_guards

  rm -f "${WS_RUN_DIR}/.active-block"
  kill "$WS_WATCHDOG_PID" 2>/dev/null || true
  wait "$WS_WATCHDOG_PID" 2>/dev/null || true
  WS_WATCHDOG_PID=""

  local finished duration
  finished=$(date +%s)
  duration=$((finished - WS_CURRENT_STARTED))
  WS_PASSED=$((WS_PASSED + 1))
  WS_TOTAL=$((WS_TOTAL + 1))
  ws_append_event "passed" "$duration" ""
  ws_append_markdown_row "PASSED" "$duration" ""
  ws_append_junit "passed" "$duration" ""
  echo "PASSED (${duration}s)"
}

ws_skip_block() {
  WS_CURRENT_BLOCK="$1"
  WS_CURRENT_SECTION="$2"
  WS_CURRENT_STEP="$3"
  local start_line="$4"
  local end_line="$5"
  WS_CURRENT_LANGUAGE="$6"
  local reason="$7"
  WS_CURRENT_LINES="${start_line}-${end_line}"
  WS_CURRENT_CODE_FILE=""
  WS_CURRENT_TIMEOUT=0
  WS_CURRENT_STARTED=$(date +%s)
  WS_SKIPPED=$((WS_SKIPPED + 1))
  WS_TOTAL=$((WS_TOTAL + 1))
  ws_append_event "skipped" 0 "$reason"
  ws_append_markdown_row "SKIPPED" 0 "$reason"
  ws_append_junit "skipped" 0 "$reason"
  echo "SKIPPED ${WS_CURRENT_SOURCE}:${WS_CURRENT_LINES} ${WS_CURRENT_BLOCK} ${WS_CURRENT_STEP}: ${reason}"
}

ws_end_page() {
  :
}

ws_finish_run() {
  local finished duration
  finished=$(date +%s)
  duration=$((finished - WS_RUN_STARTED))
  WS_RUN_FINISHED=1
  ws_write_summary_json "passed" 0 "$duration" ""
  ws_write_junit "$duration"
  rm -f "$WS_JUNIT_FRAGMENT" "$WS_RUN_DIR/.active-block" "$WS_RUN_DIR/.timeout" "$WS_RUN_DIR/.current-block.sh"
  echo
  echo "PASSED: ${WS_PASSED}, skipped: ${WS_SKIPPED}, duration: ${duration}s"
  echo "Reports: ${WS_RUN_DIR}"
}
