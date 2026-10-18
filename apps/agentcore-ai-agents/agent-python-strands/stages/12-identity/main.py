from datetime import datetime
import os

import boto3
from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig, RetrievalConfig
from bedrock_agentcore.memory.integrations.strands.session_manager import AgentCoreMemorySessionManager
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from starlette.staticfiles import StaticFiles
from strands import Agent
from strands.models.bedrock import BedrockModel

import auth
import artifacts
from browser_tools import browse_url, take_screenshot
import guardrail
from code_interpreter_tools import execute_code
from knowledge import search_knowledge_base
from mcp_tools import gateway_tools
import compliance_tools
# >> Import the corporate calendar tool
import calendar_tools
# <<

app = BedrockAgentCoreApp()
log = app.logger
app.add_middleware(auth.JwtAuthMiddleware)

model = BedrockModel(model_id="global.anthropic.claude-sonnet-4-6", max_tokens=4096, temperature=0.7,
                     **guardrail.model_config())

SYSTEM_PROMPT = """
You are the travel and expense assistant of the company. You help employees plan business trips,
follow the travel and expense policies, and keep track of their trips and expenses.

Rules:
- Focus on business travel and expenses.
- Ask for missing details such as dates, origin, or destination instead of guessing them.
- Do not invent policy rules; say so when you are not sure.

Format:
- Be friendly and concise.
- Use tables to compare options.
"""
SYSTEM_PROMPT += f"\nFlight and hotel offers: the corporate travel portal {os.environ['PORTAL_URL']}\n"

MEMORY_ID = os.environ["AGENTCORE_MEMORY_ID"]
REGION = os.environ.get("AWS_REGION") or boto3.session.Session().region_name


def discover_namespaces():
    control = boto3.client("bedrock-agentcore-control", region_name=REGION)
    memory = control.get_memory(memoryId=MEMORY_ID)["memory"]
    return [(s["strategyId"], ns) for s in memory.get("strategies", []) for ns in s["namespaces"]]


NAMESPACES = discover_namespaces()
log.info("Discovered %d LTM namespaces", len(NAMESPACES))


def memory_session_manager(conversation_id):
    actor_id, _, session_id = conversation_id.partition(":")
    retrieval = {
        ns.replace("{memoryStrategyId}", strategy_id).replace("{actorId}", actor_id):
            RetrievalConfig(top_k=3, relevance_score=0.2)
        for strategy_id, ns in NAMESPACES
    }
    config = AgentCoreMemoryConfig(
        memory_id=MEMORY_ID,
        actor_id=actor_id,
        session_id=session_id or "default-session",
        retrieval_config=retrieval,
    )
    return AgentCoreMemorySessionManager(config, REGION)


TOOLS = [
    search_knowledge_base,
    browse_url,
    take_screenshot,
    execute_code,
]
TOOLS += gateway_tools()
log.info("MCP tools enabled: %s", bool(os.environ.get("GATEWAY_URL")))
if compliance_tools.AUDITOR_HARNESS_ARN:
    TOOLS.append(compliance_tools.check_compliance)
# >> Add the calendar tool when `CALENDAR_URL` is set
if calendar_tools.CALENDAR_URL:
    TOOLS.append(calendar_tools.get_calendar_events)
# <<


def with_context(prompt, conversation_id):
    timestamp = datetime.now().isoformat(timespec="seconds")
    user_id = conversation_id.split(":")[0]
    return f"[Current date and time: {timestamp}] [UserId: {user_id}]\n{prompt}"


agents = {}


def get_agent(conversation_id):
    if conversation_id not in agents:
        agents[conversation_id] = Agent(
            model=model,
            system_prompt=SYSTEM_PROMPT,
            session_manager=memory_session_manager(conversation_id),
            tools=TOOLS,
            callback_handler=None,
        )
    return agents[conversation_id]


@app.entrypoint
async def invoke(payload, context):
    conversation_id = auth.conversation_id(context)
# >> Tools act on behalf of this user; the callback page sends the consent session back
    authorization = (context.request_headers or {}).get("Authorization", "")
    calendar_tools.current_user.set((conversation_id.split(":")[0],
                                     authorization if authorization.startswith("Bearer ") else ""))
    if "oauthSession" in payload:
        calendar_tools.complete_authorization(payload["oauthSession"])
        yield "The corporate calendar is connected. Send your question again."
        return
# <<
    agent = get_agent(conversation_id)
    artifacts.current_session.set(conversation_id)
    prompt = with_context(payload["prompt"], conversation_id)
    prompt = guardrail.mask_pii(prompt)
    async for event in agent.stream_async(prompt):
        if "data" in event:
            yield event["data"]
    files = artifacts.as_markdown(conversation_id)
    if files:
        yield files


app.mount("/", StaticFiles(directory="static", html=True, check_dir=False))

if __name__ == "__main__":
    app.run()
