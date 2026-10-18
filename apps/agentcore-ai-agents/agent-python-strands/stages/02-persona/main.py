from bedrock_agentcore.runtime import BedrockAgentCoreApp
from starlette.staticfiles import StaticFiles
from strands import Agent
from strands.models.bedrock import BedrockModel

app = BedrockAgentCoreApp()

# >> `temperature=0.7` balances creativity and consistency
model = BedrockModel(model_id="global.anthropic.claude-sonnet-4-6", max_tokens=4096, temperature=0.7)
# <<

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


@app.entrypoint
async def invoke(payload):
    # >> `system_prompt` applies the prompt to all requests
    agent = Agent(model=model, system_prompt=SYSTEM_PROMPT, callback_handler=None)
    # <<
    async for event in agent.stream_async(payload["prompt"]):
        if "data" in event:
            yield event["data"]


app.mount("/", StaticFiles(directory="static", html=True, check_dir=False))

if __name__ == "__main__":
    app.run()
