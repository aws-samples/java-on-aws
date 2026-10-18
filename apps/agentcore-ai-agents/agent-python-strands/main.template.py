#+tools
from datetime import datetime
#-
import os

import boto3
from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig, RetrievalConfig
from bedrock_agentcore.memory.integrations.strands.session_manager import AgentCoreMemorySessionManager
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from starlette.staticfiles import StaticFiles
from strands import Agent
from strands.models.bedrock import BedrockModel

#+deploy Import JWT validation and the conversation ID resolver
import auth
#-
#+browser Import the artifact store and the browser tools
import artifacts
from browser_tools import browse_url, take_screenshot
#-
#+document-processing Import the attachment handling
import attachments
#-
#+guardrails Import the guardrail helpers
import guardrail
#-
#+code-interpreter Import the code interpreter tool
from code_interpreter_tools import execute_code
#-
#+knowledge Import the Knowledge Base tool
from knowledge import search_knowledge_base
#-
#+mcp-client!policies Import the Gateway tools
from mcp_tools import gateway_tools
#-
#+policies Import the Gateway tools of both Gateways
import mcp_tools
from mcp_tools import gateway_tools
#-
#+agent-as-tool Import the compliance auditor tool
import compliance_tools
#-
#+identity Import the corporate calendar tool
import calendar_tools
#-
#+optimize Import the system prompt from the configuration bundle
import prompt_config
from strands.hooks.events import BeforeModelCallEvent
#-
#+tools!mcp-client Import the web grounding tool (until the Gateway web search replaces it)
from web_grounding import search_web
#-

app = BedrockAgentCoreApp()
log = app.logger
#+deploy Require a valid Cognito JWT for `/invocations` when `COGNITO_ISSUER_URI` is set
app.add_middleware(auth.JwtAuthMiddleware)
#-

#!guardrails
model = BedrockModel(model_id="global.anthropic.claude-sonnet-4-6", max_tokens=4096, temperature=0.7)
#-
#+guardrails Apply the guardrail to every model call when `GUARDRAIL_ID` is set
model = BedrockModel(model_id="global.anthropic.claude-sonnet-4-6", max_tokens=4096, temperature=0.7,
                     **guardrail.model_config())
#-

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
#+browser Tell the model where to find flight and hotel offers
SYSTEM_PROMPT += f"\nFlight and hotel offers: the corporate travel portal {os.environ['PORTAL_URL']}\n"
#-

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


#+knowledge Tools available to the agent
TOOLS = [
    search_knowledge_base,
#-
#+tools!mcp-client Add the web grounding tool
    search_web,
#-
#+browser Add the browser tools
    browse_url,
    take_screenshot,
#-
#+code-interpreter Add the code interpreter tool
    execute_code,
#-
#+knowledge
]
#-
#+mcp-client Add the Gateway tools when `GATEWAY_URL` is set
TOOLS += gateway_tools()
log.info("MCP tools enabled: %s", bool(os.environ.get("GATEWAY_URL")))
#-
#+agent-as-tool Add the compliance auditor tool when `AUDITOR_HARNESS_ARN` is set
if compliance_tools.AUDITOR_HARNESS_ARN:
    TOOLS.append(compliance_tools.check_compliance)
#-
#+identity Add the calendar tool when `CALENDAR_URL` is set
if calendar_tools.CALENDAR_URL:
    TOOLS.append(calendar_tools.get_calendar_events)
#-
#+tools Add context to every prompt: the model always knows the date and the user without a tool call


def with_context(prompt, conversation_id):
    timestamp = datetime.now().isoformat(timespec="seconds")
    user_id = conversation_id.split(":")[0]
    return f"[Current date and time: {timestamp}] [UserId: {user_id}]\n{prompt}"
#-


agents = {}


#!policies
def get_agent(conversation_id):
#-
#+policies The user's token selects the backoffice tools that the user may call
def get_agent(conversation_id, authorization=""):
#-
    if conversation_id not in agents:
        agents[conversation_id] = Agent(
            model=model,
            system_prompt=SYSTEM_PROMPT,
            session_manager=memory_session_manager(conversation_id),
#+knowledge!policies Register the tools with the agent
            tools=TOOLS,
#-
#+policies Add the backoffice tools of the JWT Gateway for this user
            tools=TOOLS + mcp_tools.user_gateway_tools(authorization),
#-
            callback_handler=None,
        )
#+optimize Take the system prompt from the configuration bundle when `CONFIG_BUNDLE_ID` is set
        if prompt_config.CONFIG_BUNDLE_ID:
            agents[conversation_id].hooks.add_callback(BeforeModelCallEvent, prompt_config.apply_system_prompt)
#-
    return agents[conversation_id]


@app.entrypoint
async def invoke(payload, context):
#!deploy
    conversation_id = context.session_id
#-
#+deploy The conversation ID combines the Cognito user ID from the JWT with the session ID
    conversation_id = auth.conversation_id(context)
#-
#+identity Tools act on behalf of this user; the callback page sends the consent session back
    authorization = (context.request_headers or {}).get("Authorization", "")
    calendar_tools.current_user.set((conversation_id.split(":")[0],
                                     authorization if authorization.startswith("Bearer ") else ""))
    if "oauthSession" in payload:
        calendar_tools.complete_authorization(payload["oauthSession"])
        yield "The corporate calendar is connected. Send your question again."
        return
#-
#!policies
    agent = get_agent(conversation_id)
#-
#+policies
    agent = get_agent(conversation_id, (context.request_headers or {}).get("Authorization", ""))
#-
#+browser Tools that run during this request store their files under the conversation ID
    artifacts.current_session.set(conversation_id)
#-
#!tools
    prompt = payload["prompt"]
#-
#+tools Add the current date and time and the user ID to the prompt
    prompt = with_context(payload["prompt"], conversation_id)
#-
#+guardrails Mask payment data before the agent stores the prompt in memory
    prompt = guardrail.mask_pii(prompt)
#-
#+document-processing Add the attached file to the message
    prompt = attachments.message(prompt, payload)
#-
    async for event in agent.stream_async(prompt):
        if "data" in event:
            yield event["data"]
#+browser Append screenshots and generated files after the answer; they are not saved to memory
    files = artifacts.as_markdown(conversation_id)
    if files:
        yield files
#-


app.mount("/", StaticFiles(directory="static", html=True, check_dir=False))

if __name__ == "__main__":
    app.run()
