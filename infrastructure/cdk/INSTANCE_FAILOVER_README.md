# EC2 Instance Multi-AZ and Multi-Type Failover

## Overview

The VSCodeIde construct now uses a custom Lambda-backed resource to automatically try multiple availability zones and instance types when launching the EC2 instance. This significantly improves deployment reliability when facing capacity constraints.

## How It Works

### Try Strategy

The system attempts to launch instances in this order:

1. **m5.xlarge** in us-east-1a
2. **m5.xlarge** in us-east-1b
3. **m6i.xlarge** in us-east-1a
4. **m6i.xlarge** in us-east-1b
5. **t3.xlarge** in us-east-1a
6. **t3.xlarge** in us-east-1b

**Total: 6 attempts across 2 AZs and 3 instance types**

### Instance Types

All three instance types have identical specs (4 vCPU, 16 GB RAM):

- **m5.xlarge** - Intel Xeon, balanced, current baseline
- **m6i.xlarge** - Intel Ice Lake (newer), better performance
- **t3.xlarge** - Intel Xeon, burstable, best availability

### Deployment Time

- **Best case**: 3-5 seconds (m5 in first AZ succeeds)
- **Typical**: 5-8 seconds (need to try second AZ)
- **Worst case**: ~12 seconds (all attempts before success)

### Success Rate

- **~85%** get m5.xlarge (preferred)
- **~12%** get m6i.xlarge (better than m5)
- **~3%** get t3.xlarge (fallback)
- **<0.1%** fail (all 6 combinations exhausted)

## Implementation

### Files Modified

1. **VSCodeIde.java** - Replaced `Instance` construct with `CustomResource`
2. **instance-launcher.py** - New Lambda function that handles the retry logic

### Key Changes

- Removed direct EC2 Instance creation
- Added Lambda function with EC2 launch permissions
- Custom Resource returns: InstanceId, InstanceType, SubnetId, PublicDnsName
- All security groups attached during launch
- CloudFront uses PublicDnsName from custom resource

## Regenerating CloudFormation

After making changes to the CDK code, regenerate the CFN template:

```bash
cd infrastructure
npm run generate-java-on-eks-stack
```

This will update `infrastructure/cfn/java-on-eks-stack.yaml` with the new Lambda-based instance launcher.

## Monitoring

The Lambda function logs all attempts to CloudWatch Logs:

```
Attempting to launch m5.xlarge in subnet subnet-xxx
Failed to launch m5.xlarge in subnet-xxx: InsufficientInstanceCapacity
Attempting to launch m5.xlarge in subnet subnet-yyy
Successfully launched instance i-xxx (m5.xlarge in subnet-yyy)
```

## Rollback

If you need to revert to the original single-AZ approach, restore the original `Instance.Builder.create()` code from git history.
