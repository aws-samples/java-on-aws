import os
import re

import boto3
from mcp_proxy_for_aws.client import aws_iam_streamablehttp_client
from strands.tools.mcp.mcp_client import MCPClient

BACKOFFICE = re.compile(r"^backoffice___")


def gateway_tools():
    url = os.environ.get("GATEWAY_URL")
    if not url:
        return []
    transport = lambda: aws_iam_streamablehttp_client(
        url, aws_service="bedrock-agentcore", aws_region=os.environ.get("AWS_REGION") or boto3.session.Session().region_name
    )
    # >> With the JWT Gateway, the backoffice tools come from there; the IAM Gateway keeps the other tools
    filters = {"rejected": [BACKOFFICE]} if os.environ.get("JWT_GATEWAY_URL") else None
    return [MCPClient(transport, tool_filters=filters)]
    # <<


def user_gateway_tools(authorization):
    """Backoffice tools from the JWT Gateway, called with the user's token, so that policies see the user's claims."""
    url = os.environ.get("JWT_GATEWAY_URL")
    if not url or not authorization.startswith("Bearer "):
        return []
    # >> The Gateway validates the user's Cognito token and hides the tools that the user's policies forbid
    return [MCPClient(url=url, headers={"Authorization": authorization}, tool_filters={"allowed": [BACKOFFICE]})]
    # <<
