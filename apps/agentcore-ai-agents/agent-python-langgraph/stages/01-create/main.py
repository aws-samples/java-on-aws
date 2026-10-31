import os

from bedrock_agentcore.runtime import BedrockAgentCoreApp
from langchain.agents import create_agent
from langchain_aws import ChatBedrockConverse
from langchain_core.messages import AIMessageChunk
from starlette.staticfiles import StaticFiles

# >> `BedrockAgentCoreApp` is an HTTP service with the `/invocations` and `/ping` endpoints
app = BedrockAgentCoreApp()
# <<

# >> `ChatBedrockConverse` connects LangChain to Amazon Bedrock through the Converse API
model = ChatBedrockConverse(
    model="global.anthropic.claude-sonnet-5-5", max_tokens=4096, region_name=os.environ.get("AWS_REGION")
)
# <<
# >> `create_agent` builds a LangGraph graph: the model node calls tools in a loop until it has the answer
agent = create_agent(model)
# <<


# >> `@app.entrypoint` marks this function as the handler for the `/invocations` endpoint
@app.entrypoint
# <<
async def invoke(payload):
    # >> `stream_mode="messages"` streams the model output token by token
    async for chunk, _ in agent.astream({"messages": [("user", payload["prompt"])]}, stream_mode="messages"):
        if isinstance(chunk, AIMessageChunk) and chunk.text:
            yield chunk.text
    # <<


# >> Serve the Web UI from the `static` folder
app.mount("/", StaticFiles(directory="static", html=True, check_dir=False))
# <<

if __name__ == "__main__":
    app.run()
