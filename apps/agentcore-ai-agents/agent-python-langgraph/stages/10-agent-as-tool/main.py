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
from knowledge import search_knowledge_base
import memory
from mcp_tools import gateway_tools
# >> Import the compliance auditor tool
import compliance_tools
# <<

app = BedrockAgentCoreApp()
app.add_middleware(auth.JwtAuthMiddleware)

model = ChatBedrockConverse(
    model="global.anthropic.claude-sonnet-5-5", max_tokens=4096, region_name=os.environ.get("AWS_REGION")
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
# >> Add the compliance auditor tool when `AUDITOR_HARNESS_ARN` is set
if compliance_tools.AUDITOR_HARNESS_ARN:
    TOOLS.append(compliance_tools.check_compliance)
# <<


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


_agent = None


async def get_agent():
    global _agent
    if _agent is None:
        _agent = build_agent(TOOLS + await gateway_tools())
    return _agent


@app.entrypoint
async def invoke(payload, context):
    conversation_id = auth.conversation_id(context)
    agent = await get_agent()
    ctx, config = memory.memory_config(conversation_id)
    artifacts.current_session.set(conversation_id)
    prompt = with_context(payload["prompt"], conversation_id)
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
