#!/bin/bash
# Shared helper functions for IDE bootstrap scripts

retry_command() {
    local max_attempts="$1"
    local delay="$2"
    local fail_mode="$3"
    local tool_name="$4"
    shift 4
    local cmd="$*"

    for attempt in $(seq 1 $max_attempts); do
        if eval "$cmd"; then
            echo "✅ Success: $tool_name"
            return 0
        fi
        echo "❌ Failed attempt $attempt/$max_attempts: $tool_name"

        if [ $attempt -lt $max_attempts ]; then
            echo "Waiting ${delay}s before retry..."
            sleep $delay
        fi
    done

    if [ "$fail_mode" = "FAIL" ]; then
        echo "💥 FATAL: $tool_name failed after $max_attempts attempts"
        exit 1
    else
        echo "⚠️  WARNING: $tool_name failed after $max_attempts attempts (continuing)"
        return 1
    fi
}

retry_critical() { retry_command 5 5 "FAIL" "$@"; }
retry_optional() { retry_command 5 5 "LOG" "$@"; }

install_with_version() {
    local tool_name="$1"
    local install_cmd="$2"
    local version_cmd="$3"
    local fail_mode="${4:-FAIL}"

    if eval "$install_cmd"; then
        if [ -n "$version_cmd" ]; then
            local version=$(eval "$version_cmd" 2>/dev/null | head -1 || echo "unknown")
            echo "✅ Success: $tool_name $version"
        else
            echo "✅ Success: $tool_name"
        fi
        return 0
    else
        if [ "$fail_mode" = "FAIL" ]; then
            echo "💥 FATAL: $tool_name failed"
            exit 1
        else
            echo "⚠️  WARNING: $tool_name failed (continuing)"
            return 1
        fi
    fi
}

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

download_and_verify() {
    local url="$1"
    local output="$2"
    local description="$3"

    log_info "Downloading $description..."
    retry_critical "$description" "wget -q '$url' -O '$output'"
}
