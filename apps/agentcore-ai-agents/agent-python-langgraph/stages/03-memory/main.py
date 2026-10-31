import os

from bedrock_agentcore.runtime import BedrockAgentCoreApp
from langchain.agents import create_agent
from langchain_aws import ChatBedrockConverse
from langchain_core.messages import AIMessageChunk
from starlette.staticfiles import StaticFiles

# >> Import the AgentCore Memory checkpointer, store, and middleware
import memory
# <<

app = BedrockAgentCoreApp()

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

TOOLS = []


def build_agent(tools):
    return create_agent(
        model,
        tools=tools,
# >> Long-term memory in the system prompt and saving each turn for extraction
        middleware=[memory.with_long_term_memory(SYSTEM_PROMPT), memory.save_turn],
        context_schema=memory.Context,
        checkpointer=memory.checkpointer,
        store=memory.store,
# <<
    )


agent = build_agent(TOOLS)


@app.entrypoint
async def invoke(payload, context):
    conversation_id = context.session_id
# >> `context.session_id` is the `X-Amzn-Bedrock-AgentCore-Runtime-Session-Id` header. In local mode, the Web UI sends the login username as the session ID
    ctx, config = memory.memory_config(conversation_id)
# <<
    prompt = payload["prompt"]
# >> Pass actor and session as `config` for the checkpointer and as `context` for the middleware; only the new message is sent, the checkpointer restores the history
    stream = agent.astream({"messages": [prompt]}, config=config, context=ctx, stream_mode="messages")
# <<
    async for chunk, _ in stream:
        if isinstance(chunk, AIMessageChunk) and chunk.text:
            yield chunk.text


app.mount("/", StaticFiles(directory="static", html=True, check_dir=False))

if __name__ == "__main__":
    app.run()
