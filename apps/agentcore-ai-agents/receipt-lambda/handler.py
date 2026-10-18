"""Gateway Lambda tool `extractReceipt`: read a receipt image or PDF from S3 with Bedrock Data Automation."""
import json
import os
import time

import boto3

PROJECT_ARN = os.environ["BDA_PROJECT_ARN"]
PROFILE_ARN = os.environ["BDA_PROFILE_ARN"]
OUTPUT_URI = os.environ["BDA_OUTPUT_URI"]  # s3://bucket/prefix/ for BDA results
LOW_CONFIDENCE = float(os.environ.get("LOW_CONFIDENCE", "0.7"))

bda = boto3.client("bedrock-data-automation-runtime")
s3 = boto3.client("s3")


def read_json(uri):
    bucket, key = uri.removeprefix("s3://").split("/", 1)
    return json.loads(s3.get_object(Bucket=bucket, Key=key)["Body"].read())


def handler(event, context):
    # Gateway passes the tool arguments as the event
    s3_uri = event.get("s3Uri", "")
    if not s3_uri.startswith("s3://"):
        return {"error": "s3Uri must be an S3 URI such as s3://bucket/key.png"}
    # >> Start the Data Automation job for the receipt; results go to the workshop bucket
    invocation = bda.invoke_data_automation_async(
        inputConfiguration={"s3Uri": s3_uri},
        outputConfiguration={"s3Uri": OUTPUT_URI},
        dataAutomationConfiguration={"dataAutomationProjectArn": PROJECT_ARN, "stage": "LIVE"},
        dataAutomationProfileArn=PROFILE_ARN,
    )
    # <<
    while True:
        status = bda.get_data_automation_status(invocationArn=invocation["invocationArn"])
        if status["status"] not in ("Created", "InProgress"):
            break
        time.sleep(1)
    if status["status"] != "Success":
        return {"error": f"Data Automation {status['status']}: {status.get('errorMessage', '')}"}

    metadata = read_json(status["outputConfiguration"]["s3Uri"])
    segment = metadata["output_metadata"][0]["segment_metadata"][0]
    if "custom_output_path" not in segment:
        return {"error": "The file doesn't look like a receipt or an invoice."}
    custom = read_json(segment["custom_output_path"])
    # >> The blueprint fields, and a confidence score per field from the explainability information
    fields = custom["inference_result"]
    confidence = {k: round(v.get("confidence", 0), 2) for k, v in custom["explainability_info"][0].items()}
    # <<
    return {
        "fields": fields,
        "confidence": confidence,
        "lowConfidence": sorted(k for k, c in confidence.items() if c < LOW_CONFIDENCE),
    }
