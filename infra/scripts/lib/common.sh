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

# Call setup by default when sourced
setup_error_handling