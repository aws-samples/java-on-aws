import os
import uuid
from contextvars import ContextVar

import boto3
from botocore.config import Config

current_session = ContextVar("current_session", default="default")
_files = {}

BUCKET = os.environ["ARTIFACTS_BUCKET"]
REGION = os.environ.get("AWS_REGION") or boto3.session.Session().region_name
s3 = boto3.client("s3", region_name=REGION, config=Config(signature_version="s3v4"))


def store(name, data, media_type):
    _files.setdefault(current_session.get(), []).append((name, data, media_type))


# >> Files that another agent already uploaded: keep the link instead of the content
def store_link(name, url, media_type):
    _files.setdefault(current_session.get(), []).append((name, url, media_type))
# <<


def link(name, data, media_type):
    key = f"artifacts/{uuid.uuid4()}/{name}"
    s3.put_object(Bucket=BUCKET, Key=key, Body=data, ContentType=media_type)
    return s3.generate_presigned_url("get_object", Params={"Bucket": BUCKET, "Key": key}, ExpiresIn=3600)


def as_markdown(conversation_id):
    parts = []
    for name, data, media_type in _files.pop(conversation_id, []):
        # >> A string is a link from another agent; bytes are uploaded here
        url = data if isinstance(data, str) else link(name, data, media_type)
        # <<
        if media_type.startswith("image/"):
            parts.append(f"\n\n![{name}]({url})")
        else:
            parts.append(f"\n\n[Download {name}]({url})")
    return "".join(parts)
