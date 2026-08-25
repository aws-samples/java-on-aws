import json
import os
import time
import urllib.request

import boto3

codebuild = boto3.client("codebuild")
table = boto3.resource("dynamodb").Table(os.environ["PENDING_TABLE_NAME"])


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


def lambda_handler(event, context):
    print(f"RequestType={event['RequestType']} LogicalResourceId={event['LogicalResourceId']}")
    project_name = event["ResourceProperties"]["ProjectName"]
    physical_id = event.get("PhysicalResourceId", project_name)

    if event["RequestType"] == "Delete":
        send_response(event, context, "SUCCESS", {"ProjectName": project_name}, physical_id)
        return

    try:
        build = codebuild.start_build(projectName=project_name)["build"]
        table.put_item(
            Item={
                "BuildId": build["id"],
                "BuildArn": build["arn"],
                "ProjectName": project_name,
                "PhysicalResourceId": project_name,
                "CloudFormationEvent": json.dumps(event),
                "ExpiresAt": int(time.time()) + 7200,
            }
        )
        print(f"Started CodeBuild project {project_name}: {build['id']}")
    except Exception as error:
        print(f"Failed to start or persist CodeBuild callback: {error}")
        send_response(
            event,
            context,
            "FAILED",
            {"ProjectName": project_name},
            physical_id,
            str(error),
        )
