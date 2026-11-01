#+tools
from datetime import datetime
#-
import os

from bedrock_agentcore.runtime import BedrockAgentCoreApp
from langchain.agents import create_agent
from langchain_aws import ChatBedrockConverse
from langchain_core.messages import AIMessageChunk
from starlette.staticfiles import StaticFiles

#+deploy Import JWT validation and the conversation ID resolver
import auth
#-
#+browser Import the artifact store and the browser tools
import artifacts
from browser_tools import browse_url, take_screenshot
#-
#+code-interpreter Import the code interpreter tool
from code_interpreter_tools import execute_code
#-
#+document-processing Import the attachment handling
import attachments
#-
#+guardrails Import the guardrail settings and checks
import guardrail
#-
#+knowledge Import the Knowledge Base tool
from knowledge import search_knowledge_base
#-
#+memory Import the AgentCore Memory checkpointer, store, and middleware
import memory
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
#-
#+tools!mcp-client Import the web grounding tool (until the Gateway web search replaces it)
from web_grounding import search_web
#-

app = BedrockAgentCoreApp()
#+deploy Require a valid Cognito JWT for `/invocations` when `COGNITO_ISSUER_URI` is set
app.add_middleware(auth.JwtAuthMiddleware)
#-

#!guardrails
model = ChatBedrockConverse(
    model="global.anthropic.claude-sonnet-5-5", max_tokens=4096, region_name=os.environ.get("AWS_REGION")
)
#-
#+guardrails Apply the guardrail to the latest user message and to every answer when `GUARDRAIL_ID` is set
model = ChatBedrockConverse(
    model="global.anthropic.claude-sonnet-5-5", max_tokens=4096, region_name=os.environ.get("AWS_REGION"),
    **guardrail.model_config(),
)
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

#!knowledge
TOOLS = []
#-
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
    timestamp = datetime.now().strftime("%A, %Y-%m-%d %H:%M")
    user_id = conversation_id.split(":")[0]
    return f"[Current date and time: {timestamp}] [UserId: {user_id}]\n{prompt}"
#-


def build_agent(tools):
    return create_agent(
        model,
        tools=tools,
#+memory!optimize Long-term memory in the system prompt and saving each turn for extraction
        middleware=[memory.with_long_term_memory(SYSTEM_PROMPT), memory.save_turn],
#-
#+optimize The prompt from the configuration bundle replaces `SYSTEM_PROMPT` when `CONFIG_BUNDLE_ID` is set; the memory middleware adds the facts to it
        system_prompt=SYSTEM_PROMPT,
        middleware=[prompt_config.system_prompt_from_bundle, memory.with_long_term_memory(), memory.save_turn],
#-
#+memory
        context_schema=memory.Context,
#-
#+memory The checkpointer keeps the conversation (short-term memory), the store gives the middleware access to long-term memory
        checkpointer=memory.checkpointer,
        store=memory.store,
#-
    )


#!mcp-client
agent = build_agent(TOOLS)
#-
#+mcp-client!policies Gateway tools are discovered asynchronously, so the agent is built on the first request
_agent = None


async def get_agent():
    global _agent
    if _agent is None:
        _agent = build_agent(TOOLS + await gateway_tools())
    return _agent
#-
#+policies The IAM Gateway's tools are discovered once; each conversation gets an agent with the backoffice tools that its user may call
_gateway_tools = None
agents = {}


async def get_agent(conversation_id, authorization=""):
    global _gateway_tools
    if _gateway_tools is None:
        _gateway_tools = await gateway_tools()
    if conversation_id not in agents:
        agents[conversation_id] = build_agent(TOOLS + _gateway_tools + await mcp_tools.user_gateway_tools(authorization))
    return agents[conversation_id]
#-


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
#+mcp-client!policies
    agent = await get_agent()
#-
#+policies The user's token selects the backoffice tools that the user may call
    agent = await get_agent(conversation_id, authorization)
#-
#+memory The session header (`context.session_id`) has the format `actorId:sessionId`. `memory_config` splits it into the actor and the session
    ctx, config = memory.memory_config(conversation_id)
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
#+document-processing The message with the attached file: the image for the model, the S3 URI in the text for tools
    prompt = attachments.message(prompt, payload)
#-
#+memory Pass actor and session as `config` for the checkpointer and as `context` for the middleware; only the new message is sent, the checkpointer restores the history
    stream = agent.astream({"messages": [prompt]}, config=config, context=ctx, stream_mode="messages")
#-
    async for chunk, _ in stream:
        if isinstance(chunk, AIMessageChunk) and chunk.text:
            yield chunk.text
#+browser Append screenshots and generated files after the answer; they are not saved to memory
    files = artifacts.as_markdown(conversation_id)
    if files:
        yield files
#-


app.mount("/", StaticFiles(directory="static", html=True, check_dir=False))

if __name__ == "__main__":
    app.run()
