"""Smoke test for one assembled stage, without AWS: run from the stage directory with the app's venv.

Stubs AWS API calls, then checks /ping, the Web UI, tool registration, agent creation, and (deploy stage) JWT handling.
"""

import os
import sys

os.environ.setdefault("AWS_REGION", "us-east-1")
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "test")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "test")
os.environ.setdefault("AGENTCORE_MEMORY_ID", "mem-test")
os.environ.setdefault("KNOWLEDGE_BASE_ID", "kb-test")
os.environ.setdefault("ARTIFACTS_BUCKET", "workshop-bucket-test")
os.environ.setdefault("PORTAL_URL", "https://portal.example.com")
if sys.argv[1] >= "12":
    os.environ.setdefault("CALENDAR_URL", "https://calendar.example.com")
if sys.argv[1] >= "10":
    os.environ.setdefault("AUDITOR_HARNESS_ARN", "arn:aws:bedrock-agentcore:us-east-1:111122223333:harness/compliance_auditor-test")

import botocore.client

FAKE = {
    "ApplyGuardrail": {"action": "GUARDRAIL_INTERVENED", "outputs": [{"text": "blocked"}], "assessments": [
        {"contentPolicy": {"filters": [{"type": "PROMPT_ATTACK", "confidence": "HIGH", "action": "BLOCKED"}]}}]},
    "GetMemory": {"memory": {"id": "mem-test", "strategies": [
        {"strategyId": "s1", "name": "SemanticFacts", "type": "SEMANTIC",
         "namespaces": ["/strategies/{memoryStrategyId}/actors/{actorId}"]},
    ]}},
}
calls = []


def fake_api_call(self, operation, params):
    calls.append(operation)
    return FAKE.get(operation, {})


botocore.client.BaseClient._make_api_call = fake_api_call
sys.path.insert(0, os.getcwd())

import main  # noqa: E402
from starlette.testclient import TestClient  # noqa: E402

stage = sys.argv[1]
client = TestClient(main.app)
assert client.get("/ping").json()["status"] == "Healthy", "ping"
assert client.get("/").status_code == 200, "web ui"
assert "decodeEventData" in client.get("/chat.js").text, "shared ui"

expected = {
    "01-create": set(), "02-persona": set(), "03-memory": set(),
    "04-knowledge": {"search_knowledge_base"},
    "05-tools": {"search_knowledge_base", "search_web"},
    "06-browser": {"search_knowledge_base", "search_web", "browse_url", "take_screenshot"},
}
expected["07-code-interpreter"] = expected["06-browser"] | {"execute_code"}
expected["08-mcp-client"] = expected["07-code-interpreter"] - {"search_web"}  # Gateway web search replaces it
expected["09-deploy"] = expected["08-mcp-client"]
expected["10-agent-as-tool"] = expected["08-mcp-client"] | {"check_compliance"}
expected["11-guardrails"] = expected["10-agent-as-tool"]
expected["12-identity"] = expected["11-guardrails"] | {"get_calendar_events"}
expected["13-document-processing"] = expected["12-identity"]
expected["14-policies"] = expected["12-identity"]
expected["15-optimize"] = expected["12-identity"]

if hasattr(main, "get_agent"):
    agent = main.get_agent("alice:s1")
    tools = set(agent.tool_names)
    assert tools == expected[stage], f"tools {tools} != {expected[stage]}"
    assert "GetMemory" in calls, "memory discovery"
    print(f"agent tools: {sorted(tools) or '-'}")

if hasattr(main, "with_context"):
    assert main.with_context("hi", "alice:s1").startswith("[Current date and time: "), "context"

if stage >= "08":
    import mcp_tools
    os.environ["GATEWAY_URL"] = "https://example.com/mcp"
    assert type(mcp_tools.gateway_tools()[0]).__name__ == "MCPClient", "gateway client"

if stage >= "14":
    assert mcp_tools.user_gateway_tools("Bearer t") == [], "no JWT Gateway configured"
    os.environ["JWT_GATEWAY_URL"] = "https://example.com/jwt/mcp"
    assert mcp_tools.user_gateway_tools("") == [], "no user token"
    assert type(mcp_tools.user_gateway_tools("Bearer t")[0]).__name__ == "MCPClient", "user gateway client"
    del os.environ["JWT_GATEWAY_URL"]

if stage >= "09":
    import jwt
    import auth
    token = jwt.encode({"sub": "user-123"}, "secret", algorithm="HS256")

    class Ctx:
        session_id = "sess-1"
        request_headers = {"Authorization": f"Bearer {token}"}

    assert auth.conversation_id(Ctx) == "user-123:sess-1", "conversation id"
    auth.ISSUER = "https://cognito-idp.us-east-1.amazonaws.com/pool"
    auth.jwks = jwt.PyJWKClient(f"{auth.ISSUER}/.well-known/jwks.json")
    assert client.post("/invocations", json={"prompt": "hi"}).status_code == 401, "jwt required"
    assert client.get("/ping").status_code == 200, "ping stays public"

if stage >= "06":
    import artifacts
    artifacts.current_session.set("alice:s1")
    artifacts.store("chart.png", b"\x89PNG", "image/png")
    artifacts.store("data.csv", b"a,b", "text/csv")
    md = artifacts.as_markdown("alice:s1")
    assert "![chart.png](https://workshop-bucket-test.s3" in md and "[Download data.csv](https://" in md, md
    assert "X-Amz-Expires=3600" in md and calls.count("PutObject") == 2, "s3 upload + presign"

if stage >= "11":
    import guardrail
    assert guardrail.model_config() == {}, "no guardrail without GUARDRAIL_ID"
    assert guardrail.check_content("page") == "page", "no check without GUARDRAIL_ID"
    guardrail.GUARDRAIL_ID = "gr-test"
    assert guardrail.model_config()["guardrail_latest_message"] is True, "guardrail on the latest message"
    assert guardrail.check_content("page") == guardrail.BLOCKED_CONTENT, "prompt attack in tool output blocked"
    assert "ApplyGuardrail" in calls, "apply guardrail"

if stage >= "13":
    import base64
    import attachments
    assert attachments.message("hi", {}) == "hi", "no attachment"
    blocks = attachments.message("hi", {"fileName": "r.png", "fileBase64": base64.b64encode(b"\x89PNG").decode()})
    assert "s3://workshop-bucket-test/artifacts/uploads/" in blocks[0]["text"], blocks[0]
    assert blocks[1]["image"]["format"] == "png", "image block"

if stage >= "10":
    import compliance_tools
    artifacts.current_session.set("alice:s1")
    text = compliance_tools.forward_links("COMPLIANT.\n\n[audit-report.md](https://b.s3.amazonaws.com/artifacts/1/audit-report.md?X=1)")
    assert "https://" not in text and text.startswith("COMPLIANT."), text
    text = compliance_tools.forward_links("NOT COMPLIANT.\nReport: https://b.s3.amazonaws.com/artifacts/2/audit-report.md?X=2")
    assert "https://" not in text, text
    assert "artifacts/1/audit-report.md?X=1)" in artifacts.as_markdown("alice:s1"), artifacts.as_markdown("alice:s1")

if stage >= "12":
    import calendar_tools
    calendar_tools.current_user.set(("alice", ""))
    assert calendar_tools.RETURN_URL == "http://localhost:8080/callback.html", calendar_tools.RETURN_URL

if stage >= "15":
    import prompt_config
    prompt_config.latest.update(read_at=__import__("time").time(), system_prompt="From the bundle")

    class Event:
        agent = type("A", (), {"system_prompt": "default"})()

    prompt_config.CONFIG_BUNDLE_ID = "bundle-test"
    prompt_config.apply_system_prompt(Event)
    assert Event.agent.system_prompt == "From the bundle", Event.agent.system_prompt

print(f"{stage}: ok")
