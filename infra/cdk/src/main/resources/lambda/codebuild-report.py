import json
import os
import urllib.request

import boto3

codebuild = boto3.client("codebuild")
table = boto3.resource("dynamodb").Table(os.environ["PENDING_TABLE_NAME"])

FAILURE_STATUSES = {"FAILED", "FAULT", "STOPPED", "TIMED_OUT"}


def normalized_build_id(value):
    if ":build/" in value:
        return value.split(":build/", 1)[1]
    return value


def send_response(event, context, status, data, physical_id, reason=None):
    body = json.dumps(
        {
            "Status": status,
            "Reason": reason or f"See CloudWatch Logs: {context.log_stream_name}",
            "PhysicalResourceId": physical_id,
            "StackId": event["StackId"],
            "RequestId": event["RequestId"],
            "LogicalResourceId": event["LogicalResourceId"],
            "NoEcho": False,
            "Data": data,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        event["ResponseURL"],
        data=body,
        method="PUT",
        headers={"content-type": "", "content-length": str(len(body))},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status >= 300:
            raise RuntimeError(f"CloudFormation response failed with HTTP {response.status}")


def failure_details(build):
    details = []
    for phase in build.get("phases", []):
        contexts = "; ".join(
            context.get("message", "") for context in phase.get("contexts", [])
        )
        if phase.get("phaseStatus") in FAILURE_STATUSES or contexts:
            details.append(
                f"{phase.get('phaseType')}={phase.get('phaseStatus')}: {contexts}".strip()
            )
    logs = build.get("logs", {})
    if logs.get("deepLink"):
        details.append(f"logs={logs['deepLink']}")
    return " | ".join(details) or "No phase failure details were returned"


def lambda_handler(event, context):
    detail = event["detail"]
    event_build_id = detail["build-id"]
    build_id = normalized_build_id(event_build_id)
    print(f"Terminal CodeBuild event for {event_build_id}: {detail['build-status']}")

    item = table.get_item(Key={"BuildId": build_id}, ConsistentRead=True).get("Item")
    if not item:
        raise RuntimeError(f"Pending CloudFormation callback not found for {build_id}")

    build_response = codebuild.batch_get_builds(ids=[item.get("BuildArn", event_build_id)])
    builds = build_response.get("builds", [])
    if len(builds) != 1:
        raise RuntimeError(f"CodeBuild build not found: {event_build_id}")

    build = builds[0]
    status = build["buildStatus"]
    original_event = json.loads(item["CloudFormationEvent"])
    data = {
        "BuildId": build["id"],
        "BuildArn": build["arn"],
        "ProjectName": item["ProjectName"],
        "BuildStatus": status,
    }

    if status == "SUCCEEDED":
        response_status = "SUCCESS"
        reason = None
    elif status in FAILURE_STATUSES:
        response_status = "FAILED"
        reason = f"CodeBuild finished with {status}: {failure_details(build)}"
    else:
        raise RuntimeError(f"Received non-terminal CodeBuild status {status}")

    send_response(
        original_event,
        context,
        response_status,
        data,
        item["PhysicalResourceId"],
        reason,
    )
    table.delete_item(Key={"BuildId": build_id})
    print(f"Sent {response_status} to CloudFormation for {build_id}")
