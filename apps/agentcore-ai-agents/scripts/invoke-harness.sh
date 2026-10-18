#!/bin/bash
# Send a prompt to an AgentCore harness and print the streamed answer (InvokeHarness through boto3).
#   invoke-harness.sh HARNESS_ARN SESSION_ID PROMPT [--actor ACTOR]
exec uv run --quiet --no-project --with boto3 python "$(dirname "$0")/invoke_harness.py" "$@"
