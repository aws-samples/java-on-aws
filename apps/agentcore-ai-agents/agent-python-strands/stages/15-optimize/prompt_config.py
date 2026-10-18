import os
import time

import boto3
from bedrock_agentcore.runtime import BedrockAgentCoreContext
from strands.hooks.events import BeforeModelCallEvent

CONFIG_BUNDLE_ID = os.environ.get("CONFIG_BUNDLE_ID")
REGION = os.environ.get("AWS_REGION") or boto3.session.Session().region_name

control = boto3.client("bedrock-agentcore-control", region_name=REGION)
latest = {"read_at": 0.0, "system_prompt": None}


def latest_system_prompt():
    # >> The latest version of the bundle, read at most once a minute
    if time.time() - latest["read_at"] > 60:
        bundle = control.get_configuration_bundle(bundleId=CONFIG_BUNDLE_ID)
        component = next(iter(bundle["components"].values()))
        latest.update(read_at=time.time(), system_prompt=component["configuration"].get("system_prompt"))
    # <<
    return latest["system_prompt"]


def apply_system_prompt(event: BeforeModelCallEvent):
    """Set the system prompt from the configuration bundle before every model call."""
    # >> During an A/B test the Gateway passes the session's variant (a bundle version) as W3C baggage
    prompt = BedrockAgentCoreContext.get_config_bundle().get("system_prompt") or latest_system_prompt()
    # <<
    if prompt:
        event.agent.system_prompt = prompt
