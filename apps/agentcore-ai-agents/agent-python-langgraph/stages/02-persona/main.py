import os

from bedrock_agentcore.runtime import BedrockAgentCoreApp
from langchain.agents import create_agent
from langchain_aws import ChatBedrockConverse
from langchain_core.messages import AIMessageChunk
from starlette.staticfiles import StaticFiles

app = BedrockAgentCoreApp()

model = ChatBedrockConverse(
    # >> `temperature=0.7` balances creativity and consistency
    model="global.anthropic.claude-sonnet-4-6", max_tokens=4096, temperature=0.7, region_name=os.environ.get("AWS_REGION")
    # <<
)

# >> The system prompt defines the persona of the AI agent
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
# <<

# >> `system_prompt` applies the prompt to all requests
agent = create_agent(model, system_prompt=SYSTEM_PROMPT)
# <<


@app.entrypoint
async def invoke(payload):
    async for chunk, _ in agent.astream({"messages": [("user", payload["prompt"])]}, stream_mode="messages"):
        if isinstance(chunk, AIMessageChunk) and chunk.text:
            yield chunk.text


app.mount("/", StaticFiles(directory="static", html=True, check_dir=False))

if __name__ == "__main__":
    app.run()
