import os

from langchain_mcp_adapters.client import MultiServerMCPClient
from mcp.shared.exceptions import McpError
from mcp.types import CallToolResult, TextContent
from mcp_proxy_for_aws.sigv4_helper import SigV4HTTPXAuth, create_aws_session


# >> The Gateway answers some failed calls with a JSON-RPC error (for example, a call denied by a policy). Return it to the model as a failed tool result, so the turn continues
async def tool_errors_as_results(request, handler):
    try:
        return await handler(request)
    except McpError as error:
        return CallToolResult(content=[TextContent(type="text", text=str(error))], isError=True)
# <<


async def gateway_tools():
    # >> Gateway URL from `~/environment/.envrc`; without it, the agent runs without Gateway tools
    url = os.environ.get("GATEWAY_URL")
    if not url:
        return []
    # <<
    # >> Sign every request with SigV4 for the `bedrock-agentcore` service, using the IAM credentials of the application
    session = create_aws_session()
    auth = SigV4HTTPXAuth(session.get_credentials(), "bedrock-agentcore", os.environ.get("AWS_REGION") or session.region_name)
    # <<
    # >> `MultiServerMCPClient` discovers the Gateway tools with `tools/list` and converts them to LangChain tools; the interceptor wraps every tool call
    client = MultiServerMCPClient({"gateway": {"transport": "streamable_http", "url": url, "auth": auth}},
                                  tool_interceptors=[tool_errors_as_results])
    return await client.get_tools()
    # <<
