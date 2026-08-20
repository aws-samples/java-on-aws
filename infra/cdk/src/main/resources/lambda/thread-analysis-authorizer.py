import base64
import hmac
import json
import os

import boto3

secretsmanager = boto3.client("secretsmanager")


def lambda_handler(event, context):
    headers = event.get("headers") or {}
    authorization = next(
        (value for name, value in headers.items() if name.lower() == "authorization"),
        "",
    )

    try:
        scheme, encoded_credentials = authorization.split(" ", 1)
        if scheme.lower() != "basic":
            return {"isAuthorized": False}

        username, password = base64.b64decode(encoded_credentials).decode("utf-8").split(":", 1)
        secret = secretsmanager.get_secret_value(SecretId=os.environ["SECRET_NAME"])
        expected_password = json.loads(secret["SecretString"])["password"]
        authorized = hmac.compare_digest(username, "grafana-alerts") and hmac.compare_digest(
            password, expected_password
        )
        return {"isAuthorized": authorized}
    except (ValueError, KeyError, TypeError, UnicodeDecodeError, json.JSONDecodeError):
        return {"isAuthorized": False}
