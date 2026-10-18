import os

import boto3
from mcp_proxy_for_aws.client import aws_iam_streamablehttp_client
from strands.tools.mcp.mcp_client import MCPClient


def gateway_tools():
    # >> Gateway URL from `~/environment/.envrc`; without it, the agent runs without Gateway tools
    url = os.environ.get("GATEWAY_URL")
    if not url:
        return []
    # <<
    # >> Streamable HTTP transport that signs every request with SigV4 for the `bedrock-agentcore` service
    transport = lambda: aws_iam_streamablehttp_client(
        url, aws_service="bedrock-agentcore", aws_region=os.environ.get("AWS_REGION") or boto3.session.Session().region_name
    )
    # <<
    # >> `MCPClient` discovers the Gateway tools with `tools/list`; the agent calls them like local tools
    return [MCPClient(transport)]
    # <<
