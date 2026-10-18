"""Send a prompt to an AgentCore harness and print the streamed answer; tool calls and usage go to stderr.

Usage: uv run --no-project --with boto3 invoke_harness.py HARNESS_ARN SESSION_ID PROMPT [--actor ACTOR]

SESSION_ID is padded to the 33 characters AgentCore requires. ACTOR scopes the harness memory to a user.
"""
import argparse
import sys
import time

import boto3
from botocore.config import Config

parser = argparse.ArgumentParser()
parser.add_argument("arn")
parser.add_argument("session")
parser.add_argument("prompt")
parser.add_argument("--actor")
args = parser.parse_args()

client = boto3.client("bedrock-agentcore", config=Config(read_timeout=900, retries={"max_attempts": 1}))
request = {
    "harnessArn": args.arn,
    "runtimeSessionId": args.session.ljust(33, "0"),
    "messages": [{"role": "user", "content": [{"text": args.prompt}]}],
}
if args.actor:
    request["actorId"] = args.actor

start = time.time()
for event in client.invoke_harness(**request)["stream"]:
    if "contentBlockStart" in event:
        tool_use = event["contentBlockStart"].get("start", {}).get("toolUse")
        if tool_use:
            print(f"\n[tool: {tool_use.get('name')}]", file=sys.stderr, flush=True)
    elif "contentBlockDelta" in event:
        text = event["contentBlockDelta"].get("delta", {}).get("text")
        if text:
            print(text, end="", flush=True)
    elif "metadata" in event:
        usage = event["metadata"].get("usage", {})
        print(f"\n[tokens: {usage.get('inputTokens')} in, {usage.get('outputTokens')} out]", file=sys.stderr, flush=True)
    elif "runtimeClientError" in event:
        print(f"\n[error: {event['runtimeClientError']}]", file=sys.stderr, flush=True)
        sys.exit(1)
print(f"\n[{time.time() - start:.0f} s]", file=sys.stderr)
