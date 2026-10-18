from datetime import datetime
import os

import boto3
from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig, RetrievalConfig
from bedrock_agentcore.memory.integrations.strands.session_manager import AgentCoreMemorySessionManager
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from starlette.staticfiles import StaticFiles
from strands import Agent
from strands.models.bedrock import BedrockModel

# >> Import JWT validation and the conversation ID resolver
import auth
# <<
import artifacts
from browser_tools import browse_url, take_screenshot
from code_interpreter_tools import execute_code
from knowledge import search_knowledge_base
from mcp_tools import gateway_tools

app = BedrockAgentCoreApp()
log = app.logger
# >> Require a valid Cognito JWT for `/invocations` when `COGNITO_ISSUER_URI` is set
app.add_middleware(auth.JwtAuthMiddleware)
# <<

model = BedrockModel(model_id="global.anthropic.claude-sonnet-4-6", max_tokens=4096, temperature=0.7)

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
# >> The conversation ID combines the Cognito user ID from the JWT with the session ID
    conversation_id = auth.conversation_id(context)
# <<
    agent = get_agent(conversation_id)
    artifacts.current_session.set(conversation_id)
    prompt = with_context(payload["prompt"], conversation_id)
    async for event in agent.stream_async(prompt):
        if "data" in event:
            yield event["data"]
    files = artifacts.as_markdown(conversation_id)
    if files:
        yield files


app.mount("/", StaticFiles(directory="static", html=True, check_dir=False))

if __name__ == "__main__":
    app.run()
