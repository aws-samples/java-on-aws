import base64
import re
import uuid

import artifacts

IMAGE_FORMATS = {"png": "png", "jpg": "jpeg", "jpeg": "jpeg", "gif": "gif", "webp": "webp"}
DOCUMENT_FORMATS = {"pdf", "csv", "doc", "docx", "xls", "xlsx", "html", "txt", "md"}


def message(prompt, payload):
    """The user's message: the prompt, plus the attached file as an image or document block.

    The file is also uploaded to S3, and its URI is added to the prompt, so tools such as extractReceipt can read it.
    """
    # >> The UI sends the file as base64 with its name; without a file, the prompt stays plain text
    name, data = payload.get("fileName"), payload.get("fileBase64")
    if not (name and data):
        return prompt
    # <<
    raw = base64.b64decode(data)
    # >> Upload under `artifacts/uploads/` (expires after one day) and add the S3 URI to the prompt
    key = f"artifacts/uploads/{uuid.uuid4()}/{name}"
    artifacts.s3.put_object(Bucket=artifacts.BUCKET, Key=key, Body=raw)
    blocks = [{"text": f"{prompt}\n[Attached file: {name}, S3 URI: s3://{artifacts.BUCKET}/{key}]"}]
    # <<
    ext = name.rsplit(".", 1)[-1].lower()
    # >> Strands content blocks: the model reads images and documents directly
    if ext in IMAGE_FORMATS:
        blocks.append({"image": {"format": IMAGE_FORMATS[ext], "source": {"bytes": raw}}})
    elif ext in DOCUMENT_FORMATS:
        # Bedrock allows letters, digits, spaces, hyphens, parentheses, and square brackets in document names
        safe_name = re.sub(r"[^\w\s\-\(\)\[\]]", "-", name.rsplit(".", 1)[0])[:100]
        blocks.append({"document": {"format": ext, "name": safe_name, "source": {"bytes": raw}}})
    # <<
    return blocks
