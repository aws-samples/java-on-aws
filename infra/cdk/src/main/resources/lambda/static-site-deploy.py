# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Custom resource: writes the files of a static site (resource property Files: [{Key, ContentType, Body}])
# into a bucket, removes objects that are no longer listed, and invalidates the CloudFront distribution
# on updates. Delete is a no-op: CfnPreDeleteCleanup empties the bucket before the stack deletes it.

import boto3
import time
import traceback
import cfnresponse

s3 = boto3.client('s3')
cloudfront = boto3.client('cloudfront')


def sync(bucket, files):
    keys = set()
    for f in files:
        s3.put_object(Bucket=bucket, Key=f['Key'], Body=f['Body'].encode('utf-8'),
                      ContentType=f.get('ContentType', 'application/octet-stream'))
        keys.add(f['Key'])
    stale = []
    for page in s3.get_paginator('list_objects_v2').paginate(Bucket=bucket):
        stale += [{'Key': o['Key']} for o in page.get('Contents', []) if o['Key'] not in keys]
    for i in range(0, len(stale), 1000):
        s3.delete_objects(Bucket=bucket, Delete={'Objects': stale[i:i + 1000], 'Quiet': True})
    return len(keys), len(stale)


def lambda_handler(event, context):
    print(f"RequestType: {event['RequestType']}")
    physical_id = event.get('PhysicalResourceId', 'StaticSiteDeploy')
    try:
        if event['RequestType'] in ('Create', 'Update'):
            props = event['ResourceProperties']
            written, removed = sync(props['BucketName'], props['Files'])
            print(f'Wrote {written} objects, removed {removed}')
            distribution_id = props.get('DistributionId')
            if event['RequestType'] == 'Update' and distribution_id:
                cloudfront.create_invalidation(DistributionId=distribution_id, InvalidationBatch={
                    'Paths': {'Quantity': 1, 'Items': ['/*']}, 'CallerReference': str(time.time())})
                print(f'Invalidated {distribution_id}')
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {}, physical_id)
    except Exception:
        tb = traceback.format_exc()
        print(tb)
        cfnresponse.send(event, context, cfnresponse.FAILED, {'Error': tb[-500:]}, physical_id)
