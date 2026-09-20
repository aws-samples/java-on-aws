#!/bin/bash

# Common functions for all workshop scripts

log_info() {
    echo "ℹ️  $1"
}

log_success() {
    echo "✅ $1"
}

log_error() {
    echo "❌ $1"
}

log_warning() {
    echo "⚠️  $1"
}

# Error handling function
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Command failed with exit code $exit_code at line $line_number"
    log_error "Check the logs above for details"
    log_error "Contact workshop support if this persists"
    exit $exit_code
}

# Set up error handling for scripts that source this file
setup_error_handling() {
    set -e
    trap 'handle_error $? $LINENO' ERR
}

# --- Verbose-command logging -------------------------------------------------
# Bootstrap scripts run as EC2 UserData, so their stdout goes to CloudWatch. Keep
# big command output (docker build, mvn, helm, ...) OUT of stdout by sending it to
# an on-box log file, leaving only log_info/log_success/log_error on the console.
: "${WORKSHOP_LOG_DIR:=/var/log/workshop}"
mkdir -p "$WORKSHOP_LOG_DIR" 2>/dev/null || WORKSHOP_LOG_DIR="${TMPDIR:-/tmp}"

# run_logged <logfile> <cmd...> : run cmd with stdout+stderr appended to logfile.
# On failure, print the last 40 log lines to the console and return the exit code.
# For piped/compound commands that can't be passed as argv, redirect inline instead:
#   some | pipeline >> "$LOG" 2>&1 || { log_error "..."; tail -n 40 "$LOG"; exit 1; }
run_logged() {
    local log="$1"; shift
    local rc=0
    "$@" >>"$log" 2>&1 || rc=$?
    if (( rc != 0 )); then
        log_error "Command failed (rc=$rc): $* — last 40 lines of $log:"
        tail -n 40 "$log"
    fi
    return $rc
}

# Call setup by default when sourced
setup_error_handling