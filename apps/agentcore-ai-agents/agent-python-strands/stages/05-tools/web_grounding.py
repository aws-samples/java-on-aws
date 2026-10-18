import logging
import os

import boto3
from strands import tool

log = logging.getLogger(__name__)

# >> Configurable model ID with Amazon Nova 2 Lite as default
MODEL_ID = os.environ.get("WEB_GROUNDING_MODEL", "us.amazon.nova-2-lite-v1:0")
# <<
bedrock = boto3.client("bedrock-runtime", region_name=os.environ.get("AWS_REGION") or boto3.session.Session().region_name)


@tool
def search_web(query: str) -> str:
    """Search the web for current information. Use for news, real-time data, or facts needing verification.

    Args:
        query: Search query
    """
    log.info("Web search: %s", query)
    try:
        # >> Use the `nova_grounding` system tool through the Bedrock Converse API
        response = bedrock.converse(
            modelId=MODEL_ID,
            messages=[{"role": "user", "content": [{"text": query}]}],
            toolConfig={"tools": [{"systemTool": {"name": "nova_grounding"}}]},
        )
        # <<
    except Exception as e:
        log.error("Web search failed: %s", e)
        return "Web search failed. Try again later."

    text, sources = [], []
    for block in response["output"]["message"]["content"]:
        text.append(block.get("text", ""))
        # >> Collect the web citations as sources
        for citation in block.get("citationsContent", {}).get("citations", []):
            url = citation.get("location", {}).get("web", {}).get("url")
            if url:
                sources.append(f"- {url}")
        # <<
    result = "".join(text) or "No results found."
    return result + ("\n\nSources:\n" + "\n".join(sources) if sources else "")
