from datetime import datetime
import os

from bedrock_agentcore.runtime import BedrockAgentCoreApp
from langchain.agents import create_agent
from langchain_aws import ChatBedrockConverse
from langchain_core.messages import AIMessageChunk
from starlette.staticfiles import StaticFiles

import auth
import artifacts
from browser_tools import browse_url, take_screenshot
from code_interpreter_tools import execute_code
import attachments
import guardrail
from knowledge import search_knowledge_base
import memory
# >> Import the Gateway tools of both Gateways
import mcp_tools
from mcp_tools import gateway_tools
# <<
import compliance_tools
import calendar_tools

app = BedrockAgentCoreApp()
app.add_middleware(auth.JwtAuthMiddleware)

model = ChatBedrockConverse(
    model="global.anthropic.claude-sonnet-5-5", max_tokens=4096, region_name=os.environ.get("AWS_REGION"),
    **guardrail.model_config(),
)

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

TOOLS = [
    search_knowledge_base,
    browse_url,
    take_screenshot,
    execute_code,
]
if compliance_tools.AUDITOR_HARNESS_ARN:
    TOOLS.append(compliance_tools.check_compliance)
if calendar_tools.CALENDAR_URL:
    TOOLS.append(calendar_tools.get_calendar_events)


def with_context(prompt, conversation_id):
    timestamp = datetime.now().strftime("%A, %Y-%m-%d %H:%M")
    user_id = conversation_id.split(":")[0]
    return f"[Current date and time: {timestamp}] [UserId: {user_id}]\n{prompt}"


def build_agent(tools):
    return create_agent(
        model,
        tools=tools,
        middleware=[memory.with_long_term_memory(SYSTEM_PROMPT), memory.save_turn],
        context_schema=memory.Context,
        checkpointer=memory.checkpointer,
        store=memory.store,
    )


# >> The IAM Gateway's tools are discovered once; each conversation gets an agent with the backoffice tools that its user may call
_gateway_tools = None
agents = {}


async def get_agent(conversation_id, authorization=""):
    global _gateway_tools
    if _gateway_tools is None:
        _gateway_tools = await gateway_tools()
    if conversation_id not in agents:
        agents[conversation_id] = build_agent(TOOLS + _gateway_tools + await mcp_tools.user_gateway_tools(authorization))
    return agents[conversation_id]
# <<


@app.entrypoint
async def invoke(payload, context):
    conversation_id = auth.conversation_id(context)
    authorization = (context.request_headers or {}).get("Authorization", "")
    calendar_tools.current_user.set((conversation_id.split(":")[0],
                                     authorization if authorization.startswith("Bearer ") else ""))
    if "oauthSession" in payload:
        calendar_tools.complete_authorization(payload["oauthSession"])
        yield "The corporate calendar is connected. Send your question again."
        return
# >> The user's token selects the backoffice tools that the user may call
    agent = await get_agent(conversation_id, authorization)
# <<
    ctx, config = memory.memory_config(conversation_id)
    artifacts.current_session.set(conversation_id)
    prompt = with_context(payload["prompt"], conversation_id)
    prompt = guardrail.mask_pii(prompt)
    prompt = attachments.message(prompt, payload)
    stream = agent.astream({"messages": [prompt]}, config=config, context=ctx, stream_mode="messages")
    async for chunk, _ in stream:
        if isinstance(chunk, AIMessageChunk) and chunk.text:
            yield chunk.text
    files = artifacts.as_markdown(conversation_id)
    if files:
        yield files


app.mount("/", StaticFiles(directory="static", html=True, check_dir=False))

if __name__ == "__main__":
    app.run()
