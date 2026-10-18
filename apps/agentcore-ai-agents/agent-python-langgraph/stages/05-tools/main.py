# >> 
from datetime import datetime
# <<
import os

from bedrock_agentcore.runtime import BedrockAgentCoreApp
from langchain.agents import create_agent
from langchain_aws import ChatBedrockConverse
from langchain_core.messages import AIMessageChunk
from starlette.staticfiles import StaticFiles

from knowledge import search_knowledge_base
import memory
# >> Import the web grounding tool (until the Gateway web search replaces it)
from web_grounding import search_web
# <<

app = BedrockAgentCoreApp()

model = ChatBedrockConverse(
    model="global.anthropic.claude-sonnet-4-6", max_tokens=4096, temperature=0.7, region_name=os.environ.get("AWS_REGION")
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

TOOLS = [
    search_knowledge_base,
# >> Add the web grounding tool
    search_web,
# <<
]


# >> Add context to every prompt: the model always knows the date and the user without a tool call
def with_context(prompt, conversation_id):
    timestamp = datetime.now().isoformat(timespec="seconds")
    user_id = conversation_id.split(":")[0]
    return f"[Current date and time: {timestamp}] [UserId: {user_id}]\n{prompt}"
# <<


def build_agent(tools):
    return create_agent(
        model,
        tools=tools,
        middleware=[memory.with_long_term_memory(SYSTEM_PROMPT), memory.save_turn],
        context_schema=memory.Context,
        checkpointer=memory.checkpointer,
        store=memory.store,
    )


agent = build_agent(TOOLS)


@app.entrypoint
async def invoke(payload, context):
    conversation_id = context.session_id
    ctx, config = memory.memory_config(conversation_id)
# >> Add the current date and time and the user ID to the prompt
    prompt = with_context(payload["prompt"], conversation_id)
# <<
    stream = agent.astream({"messages": [prompt]}, config=config, context=ctx, stream_mode="messages")
    async for chunk, _ in stream:
        if isinstance(chunk, AIMessageChunk) and chunk.text:
            yield chunk.text


app.mount("/", StaticFiles(directory="static", html=True, check_dir=False))

if __name__ == "__main__":
    app.run()
