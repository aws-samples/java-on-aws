import os
import re
import uuid

import boto3
from botocore.config import Config
from strands import tool

import artifacts

AUDITOR_HARNESS_ARN = os.environ.get("AUDITOR_HARNESS_ARN")
REGION = os.environ.get("AWS_REGION") or boto3.session.Session().region_name
# Report links of the auditor: "Report: <https://.../artifacts/...>", "Report: https://...", or a Markdown link [name](https://...)
REPORT_LINK = re.compile(r"\s*(?:Report:\s*)?<?(?:!?\[[^\]]*\]\()?(https://[^\s)>]+/artifacts/[^\s)>]+)[)>]?")

agentcore = boto3.client("bedrock-agentcore", region_name=REGION, config=Config(read_timeout=300))


def ask_auditor(request):
    # >> InvokeHarness runs the auditor's agent loop on AgentCore; one session per check (at least 33 characters)
    response = agentcore.invoke_harness(
        harnessArn=AUDITOR_HARNESS_ARN,
        runtimeSessionId=str(uuid.uuid4()),
        messages=[{"role": "user", "content": [{"text": request}]}],
    )
    # <<
    parts = []
    # >> The answer arrives as a stream of events; collect the text deltas
    for event in response["stream"]:
        delta = event.get("contentBlockDelta", {}).get("delta", {})
        if "text" in delta:
            parts.append(delta["text"])
        elif "runtimeClientError" in event:
            return f"Policy auditor error: {event['runtimeClientError'].get('message')}"
    # <<
    return "".join(parts)


def forward_links(text):
    """Move the auditor's report links to this agent's answer, so the model doesn't have to copy long URLs."""
    links = REPORT_LINK.findall(text)
    # >> The links are appended after the answer, like screenshots and charts
    for url in links:
        artifacts.store_link("audit-report.md", url, "text/markdown")
    # <<
    if not links:
        return text
    return REPORT_LINK.sub("", text) + "\n\n(The download link for the report is appended after your answer.)"


@tool
def check_compliance(request: str) -> str:
    """Ask the compliance auditor whether a planned trip or an expense complies with the company
    travel and expense policies. Returns COMPLIANT or NOT COMPLIANT with the rules that apply.
    When the user wants a downloadable audit report, ask for one in the request; its link is added to the answer automatically.

    Args:
        request: The trip or expense to check, with all known details (route, travel class, dates, amount, currency)
    """
    return forward_links(ask_auditor(request))
