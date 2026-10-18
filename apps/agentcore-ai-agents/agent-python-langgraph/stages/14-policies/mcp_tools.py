import os

from langchain_mcp_adapters.client import MultiServerMCPClient
from mcp.shared.exceptions import McpError
from mcp.types import CallToolResult, TextContent
from mcp_proxy_for_aws.sigv4_helper import SigV4HTTPXAuth, create_aws_session

BACKOFFICE = "backoffice___"


async def tool_errors_as_results(request, handler):
    try:
        return await handler(request)
    except McpError as error:
        return CallToolResult(content=[TextContent(type="text", text=str(error))], isError=True)


async def gateway_tools():
    url = os.environ.get("GATEWAY_URL")
    if not url:
        return []
    session = create_aws_session()
    auth = SigV4HTTPXAuth(session.get_credentials(), "bedrock-agentcore", os.environ.get("AWS_REGION") or session.region_name)
    client = MultiServerMCPClient({"gateway": {"transport": "streamable_http", "url": url, "auth": auth}},
                                  tool_interceptors=[tool_errors_as_results])
    tools = await client.get_tools()
    # >> With the JWT Gateway, the backoffice tools come from there; the IAM Gateway keeps the other tools
    if os.environ.get("JWT_GATEWAY_URL"):
        tools = [t for t in tools if not t.name.startswith(BACKOFFICE)]
    return tools
    # <<


async def user_gateway_tools(authorization):
    """Backoffice tools from the JWT Gateway, called with the user's token, so that policies see the user's claims."""
    url = os.environ.get("JWT_GATEWAY_URL")
    if not url or not authorization.startswith("Bearer "):
        return []
    # >> The Gateway validates the user's Cognito token and hides the tools that the user's policies forbid
    client = MultiServerMCPClient(
        {"backoffice": {"transport": "streamable_http", "url": url, "headers": {"Authorization": authorization}}},
        tool_interceptors=[tool_errors_as_results])
    return [t for t in await client.get_tools() if t.name.startswith(BACKOFFICE)]
    # <<
