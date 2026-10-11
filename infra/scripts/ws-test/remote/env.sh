#!/bin/bash
# =============================================================================
# env.sh — sourced by the other remote/*.sh scripts. Finds a workshop environment from
# the operator's laptop through its AWS account alone: no account, instance or bucket in
# code.
#
#   WS_ENV_FILE      optional file with `export AWS_...=` lines (Workshop Studio
#                    credentials); sourced first. Keep it git-ignored.
#   WS_IDE_NAME      Name tag of the IDE instance (default ide, constructs/Ide.java)
#   WS_STACK         CloudFormation stack (default workshop-stack)
#   WS_LOCAL         local working directory for bundles and reports
#                    (default ~/.cache/ws-test)
#
# Exports WS_ACCOUNT, WS_IDE_INSTANCE, WS_BUCKET, WS_S3 (s3://<bucket>/ws-test) and
# WS_REPO (this java-on-aws checkout). AWS_DEFAULT_REGION from the file wins over a
# preset AWS_REGION. Operator credentials need SSM, S3, EC2 and CloudFormation read; the
# cluster is reached only from the IDE (its role has cluster admin).
# =============================================================================

if [ -n "${WS_ENV_FILE:-}" ]; then
    [ -f "$WS_ENV_FILE" ] || { echo "WS_ENV_FILE not found: $WS_ENV_FILE" >&2; exit 1; }
    set -a; source "$WS_ENV_FILE"; set +a
fi
[ -n "${AWS_DEFAULT_REGION:-}" ] && export AWS_REGION="$AWS_DEFAULT_REGION"

WS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
WS_STACK="${WS_STACK:-workshop-stack}"
WS_IDE_NAME="${WS_IDE_NAME:-ide}"
WS_LOCAL="${WS_LOCAL:-$HOME/.cache/ws-test}"
mkdir -p "$WS_LOCAL"

WS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text) \
    || { echo "No AWS credentials (set WS_ENV_FILE or the AWS_* variables)" >&2; exit 1; }
if [ -z "${WS_IDE_INSTANCE:-}" ]; then
    WS_IDE_INSTANCE=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=${WS_IDE_NAME}" Name=instance-state-name,Values=running \
        --query 'Reservations[0].Instances[0].InstanceId' --output text)
    [[ "$WS_IDE_INSTANCE" == i-* ]] || { echo "No running instance tagged Name=${WS_IDE_NAME}" >&2; exit 1; }
fi
WS_BUCKET="${WS_BUCKET:-$(aws ssm get-parameter --name workshop-bucket-name --query Parameter.Value --output text)}"
WS_S3="s3://${WS_BUCKET}/ws-test"
export WS_ACCOUNT WS_IDE_INSTANCE WS_BUCKET WS_S3 WS_REPO WS_STACK WS_LOCAL

# ws_stack_output <key>: IdeUrl, IdePassword, ...
ws_stack_output() {
    aws cloudformation describe-stacks --stack-name "$WS_STACK" \
        --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
