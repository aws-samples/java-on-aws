import base64
import re
import uuid

from langchain_core.messages import HumanMessage

import artifacts

IMAGE_TYPES = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp"}
DOCUMENT_TYPES = {
    "pdf": "application/pdf", "csv": "text/csv", "html": "text/html", "txt": "text/plain", "md": "text/markdown",
    "doc": "application/msword", "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "xls": "application/vnd.ms-excel", "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
}


def message(prompt, payload):
    """The user's message: the prompt, plus the attached file as an image or document block.

    The file is also uploaded to S3, and its URI is added to the prompt, so tools such as extractReceipt can read it.
    """
    # >> The UI sends the file as base64 with its name; without a file, the message is the prompt
    name, data = payload.get("fileName"), payload.get("fileBase64")
    if not (name and data):
        return HumanMessage(prompt)
    # <<
    # >> Upload under `artifacts/uploads/` (expires after one day) and add the S3 URI to the prompt
    key = f"artifacts/uploads/{uuid.uuid4()}/{name}"
    artifacts.s3.put_object(Bucket=artifacts.BUCKET, Key=key, Body=base64.b64decode(data))
    content = [{"type": "text", "text": f"{prompt}\n[Attached file: {name}, S3 URI: s3://{artifacts.BUCKET}/{key}]"}]
    # <<
    ext = name.rsplit(".", 1)[-1].lower()
    # >> LangChain content blocks: `ChatBedrockConverse` sends them as Converse image and document blocks
    if ext in IMAGE_TYPES:
        content.append({"type": "image", "base64": data, "mime_type": IMAGE_TYPES[ext]})
    elif ext in DOCUMENT_TYPES:
        # Bedrock allows letters, digits, spaces, hyphens, parentheses, and square brackets in document names
        safe_name = re.sub(r"[^\w\s\-\(\)\[\]]", "-", name.rsplit(".", 1)[0])[:100]
        content.append({"type": "file", "base64": data, "mime_type": DOCUMENT_TYPES[ext], "name": safe_name})
    # <<
    return HumanMessage(content)
