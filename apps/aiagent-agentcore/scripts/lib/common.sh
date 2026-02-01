#!/bin/bash
# ============================================================
# common.sh - Shared functions for deployment scripts
# ============================================================
# Source this file: source "$(dirname "$0")/lib/common.sh"
# ============================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${BLUE}ℹ️  ${1}${NC}"
}

log_success() {
  echo -e "${GREEN}✓ ${1}${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠️  ${1}${NC}"
}

log_error() {
  echo -e "${RED}❌ ${1}${NC}"
}

log_step() {
  echo -e "${1}"
}

# Wait for resource to reach target status
# Usage: wait_for_status "command" "target_status" "resource_name" [max_attempts] [sleep_seconds]
wait_for_status() {
  local cmd="$1"
  local target="$2"
  local name="$3"
  local max_attempts="${4:-30}"
  local sleep_sec="${5:-5}"

  for i in $(seq 1 "${max_attempts}"); do
    local status
    status=$(eval "${cmd}" 2>/dev/null || echo "UNKNOWN")

    if [ "${status}" = "${target}" ]; then
      log_success "${name} is ${target}"
      return 0
    fi

    if [ "${status}" = "FAILED" ] || [ "${status}" = "CREATE_FAILED" ] || [ "${status}" = "UPDATE_FAILED" ]; then
      log_error "${name} failed: ${status}"
      return 1
    fi

    if [ $((i % 5)) -eq 0 ]; then
      echo "   ⏳ Status: ${status}"
    fi
    sleep "${sleep_sec}"
  done

  log_warning "${name} did not reach ${target} in time"
  return 1
}

# Detect container runtime (Docker or Finch)
detect_container_runtime() {
  if command -v finch >/dev/null 2>&1; then
    echo "finch"
  elif command -v docker >/dev/null 2>&1; then
    echo "docker"
  else
    log_error "Neither Docker nor Finch found"
    exit 1
  fi
}

# Get script directory
get_script_dir() {
  cd "$(dirname "$0")" && pwd
}

# Check if value is empty or "None" or "null"
is_empty() {
  local val="$1"
  [ -z "${val}" ] || [ "${val}" = "None" ] || [ "${val}" = "null" ]
}

# Check if value is not empty
is_not_empty() {
  local val="$1"
  [ -n "${val}" ] && [ "${val}" != "None" ] && [ "${val}" != "null" ]
}
