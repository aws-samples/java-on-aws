import logging
import mimetypes
import os

import boto3
from bedrock_agentcore.tools.code_interpreter_client import code_session
from langchain_core.tools import tool

import artifacts

log = logging.getLogger(__name__)
REGION = os.environ.get("AWS_REGION") or boto3.session.Session().region_name


@tool(parse_docstring=True)
def execute_code(code: str, output_files: list[str] | None = None) -> str:
    """Execute Python code in a secure sandbox with numpy, pandas, and matplotlib. Use for calculations, data analysis, and charts. Save generated files (for example a chart as PNG) to the current directory and list their file names in output_files to show them to the user.

    Args:
        code: Python code to execute
        output_files: Names of the files the code creates that the user should see
    """
    # >> Start an AgentCore Code Interpreter session; it stops when the block exits
    with code_session(REGION) as client:
    # <<
        # >> Run the code and collect the text output
        response = client.execute_code(code)
        output = []
        for event in response["stream"]:
            for item in event.get("result", {}).get("content", []):
                if item.get("type") == "text":
                    output.append(item["text"])
        # <<
        # >> Download the generated files and keep them for the user instead of returning them to the model
        for name in output_files or []:
            try:
                data = client.download_file(name)
            except FileNotFoundError:
                output.append(f"File not found: {name}")
                continue
            if isinstance(data, str):
                data = data.encode()
            media_type = mimetypes.guess_type(name)[0] or "application/octet-stream"
            artifacts.store(os.path.basename(name), data, media_type)
            output.append(f"{name} is shown to the user below your answer.")
        # <<
    log.info("Code executed, %d output files", len(output_files or []))
    return "\n".join(output) or "Code executed with no output."
