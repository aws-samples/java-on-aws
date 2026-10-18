from bedrock_agentcore.runtime import BedrockAgentCoreApp
from starlette.staticfiles import StaticFiles
from strands import Agent
from strands.models.bedrock import BedrockModel

# >> `BedrockAgentCoreApp` is an HTTP service with the `/invocations` and `/ping` endpoints
app = BedrockAgentCoreApp()
# <<

# >> `BedrockModel` connects the agent to Amazon Bedrock
model = BedrockModel(model_id="global.anthropic.claude-sonnet-4-6", max_tokens=4096)
# <<


# >> `@app.entrypoint` marks this function as the handler for the `/invocations` endpoint
@app.entrypoint
# <<
async def invoke(payload):
    agent = Agent(model=model, callback_handler=None)
    # >> `stream_async()` returns events as the model generates them; text chunks are in `data`
    async for event in agent.stream_async(payload["prompt"]):
        if "data" in event:
            yield event["data"]
    # <<


# >> Serve the Web UI from the `static` folder
app.mount("/", StaticFiles(directory="static", html=True, check_dir=False))
# <<

if __name__ == "__main__":
    app.run()
