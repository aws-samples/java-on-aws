import os

import boto3
from langchain_core.tools import tool

# >> Knowledge Base ID from `~/environment/.envrc`
KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
# <<
kb = boto3.client("bedrock-agent-runtime", region_name=os.environ.get("AWS_REGION") or boto3.session.Session().region_name)


# >> `@tool` turns a Python function into a LangChain tool. With `parse_docstring=True`, the docstring describes the tool and its parameters to the model
@tool(parse_docstring=True)
def search_knowledge_base(query: str) -> str:
    """Search the company travel and expense policies. Use for questions about rules, limits, and approvals.

    Args:
        query: What to look up in the policies
    """
# <<
    # >> Retrieve the most relevant policy chunks from the Knowledge Base
    response = kb.retrieve(
        knowledgeBaseId=KNOWLEDGE_BASE_ID,
        retrievalQuery={"text": query},
        retrievalConfiguration={"vectorSearchConfiguration": {"numberOfResults": 5}},
    )
    # <<
    results = response["retrievalResults"]
    if not results:
        return "No relevant policy found."
    # >> Return each chunk with its source document, so the model can cite the policy
    return "\n\n".join(
        f"{r['content']['text']}\n(Source: {r.get('location', {}).get('s3Location', {}).get('uri', 'unknown')})"
        for r in results
    )
    # <<
