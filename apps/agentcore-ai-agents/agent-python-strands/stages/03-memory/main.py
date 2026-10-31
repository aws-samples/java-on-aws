import os

import boto3
# >> The AgentCore SDK provides the Strands memory integration: configuration and session manager
from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig, RetrievalConfig
from bedrock_agentcore.memory.integrations.strands.session_manager import AgentCoreMemorySessionManager
# <<
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from starlette.staticfiles import StaticFiles
from strands import Agent
from strands.models.bedrock import BedrockModel

app = BedrockAgentCoreApp()
log = app.logger

model = BedrockModel(model_id="global.anthropic.claude-sonnet-5-5", max_tokens=4096)

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

# >> Memory ID from `~/environment/.envrc`
MEMORY_ID = os.environ["AGENTCORE_MEMORY_ID"]
# <<
REGION = os.environ.get("AWS_REGION") or boto3.session.Session().region_name


# >> Discover LTM strategy namespaces at startup — no need to save individual strategy IDs
def discover_namespaces():
    control = boto3.client("bedrock-agentcore-control", region_name=REGION)
    memory = control.get_memory(memoryId=MEMORY_ID)["memory"]
    return [(s["strategyId"], ns) for s in memory.get("strategies", []) for ns in s["namespaces"]]
# <<


NAMESPACES = discover_namespaces()
log.info("Discovered %d LTM namespaces", len(NAMESPACES))


def memory_session_manager(conversation_id):
    # >> The session header has the format `actorId` or `actorId:sessionId`. LTM is retrieved from every strategy namespace of this actor
    actor_id, _, session_id = conversation_id.partition(":")
    retrieval = {
        ns.replace("{memoryStrategyId}", strategy_id).replace("{actorId}", actor_id):
            RetrievalConfig(top_k=3, relevance_score=0.2)
        for strategy_id, ns in NAMESPACES
    }
    # <<
    config = AgentCoreMemoryConfig(
        memory_id=MEMORY_ID,
        actor_id=actor_id,
        session_id=session_id or "default-session",
        retrieval_config=retrieval,
    )
    # >> `AgentCoreMemorySessionManager` restores STM history and saves each new message
    return AgentCoreMemorySessionManager(config, REGION)
    # <<


agents = {}


def get_agent(conversation_id):
    if conversation_id not in agents:
        agents[conversation_id] = Agent(
            model=model,
            system_prompt=SYSTEM_PROMPT,
            # >> Attach the session manager to the agent; one agent per conversation
            session_manager=memory_session_manager(conversation_id),
            # <<
            callback_handler=None,
        )
    return agents[conversation_id]


@app.entrypoint
async def invoke(payload, context):
    # >> `context.session_id` is the `X-Amzn-Bedrock-AgentCore-Runtime-Session-Id` header. In local mode, the Web UI sends the login username as the session ID
    agent = get_agent(context.session_id)
    # <<
    async for event in agent.stream_async(payload["prompt"]):
        if "data" in event:
            yield event["data"]


app.mount("/", StaticFiles(directory="static", html=True, check_dir=False))

if __name__ == "__main__":
    app.run()
