#!/bin/bash

dt=$(date +%s)

if [ -z "$1" ]; then
    start_seconds=dt
else
    start_seconds=$1
fi

if [ -z "$2" ]; then
    end_seconds=dt
else
    end_seconds=$2
fi

seconds2hhmmss() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(( (seconds % 3600) / 60 ))
    local seconds=$((seconds % 60))
    printf "%02d:%02d:%02d" "$hours" "$minutes" "$seconds"
}

difference=$((end_seconds - start_seconds))

formatted_difference=$(seconds2hhmmss "$difference")

echo $formatted_difference
