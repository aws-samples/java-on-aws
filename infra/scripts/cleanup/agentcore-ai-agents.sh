#!/usr/bin/env bash
set -Eeuo pipefail

# Cleanup for the agentcore-ai-agents workshop ("Building AI agents with Amazon Bedrock AgentCore").
# Derived from java-performance.sh; differences:
#   - WorkshopId is agentcore-ai-agents (stack infra/cfn/agentcore-ai-agents-stack.yaml).
#   - No EKS cluster and no load balancers: the participant creates AgentCore, Bedrock, Cognito,
#     DynamoDB, ECR, S3, CloudFront, Lambda, and IAM resources with the AWS CLI. They carry no
#     ownership tags, so they are found by the names the content uses (apps/agentcore-ai-agents,
#     the workshop pages): runtimes aiagent and backoffice, Gateways mcp-gateway and mcp-gateway-jwt,
#     memories aiagent_memory-*, roles aiagent-*, backoffice-role, mcp-*-role, and so on.
#   - Account-level settings stay: Transaction Search and its aws/spans log group, the stack's
#     resources (travel portal, calendar, workshop bucket, workshop-boundary).
#
# Safety model:
#   1. Validate the immutable CloudFormation stack ID, account, Region, and workshop ID.
#   2. Delete only resources with the workshop's names in the validated account and Region,
#      never a resource of the stack.
#   3. Retain the validated CloudFormation stack.

readonly EXPECTED_WORKSHOP_ID="agentcore-ai-agents"
readonly HARNESSES=(travel_agent compliance_auditor policy_auditor)
readonly RUNTIMES=(aiagent backoffice)
readonly GATEWAYS=(mcp-gateway-jwt mcp-gateway)
readonly OAUTH_PROVIDERS=(calendar-provider mcp-backoffice-oauth)
readonly API_KEY_PROVIDERS=(mcp-holidays-apikey-provider)
readonly WORKLOAD_IDENTITIES=(aiagent-local)
readonly KNOWLEDGE_BASES=(aiagent-policies-managed aiagent-kb)
readonly USER_POOLS=(mcp-gateway-pool aiagent-user-pool)
readonly TABLES=(backoffice-trip backoffice-expense)
readonly ECR_REPOSITORIES=(aiagent backoffice)
readonly LAMBDA_FUNCTIONS=(mcp-receipt-reader)
readonly ROLES=(aiagent-kb-role backoffice-role mcp-gateway-role mcp-currency-role aiagent-runtime-role)
readonly DEFAULT_WAIT_SECONDS=900
readonly POLL_SECONDS=10

MODE="interactive"
WAIT_SECONDS="${WORKSHOP_CLEANUP_WAIT_SECONDS:-$DEFAULT_WAIT_SECONDS}"
ERRORS=0
CALLER_ACCOUNT=""
declare -a STACK_RESOURCE_IDS=()
declare -a PLAN=()

log_info() { printf '[INFO] %s\n' "$*"; }
log_success() { printf '[OK] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }
record_error() { log_error "$*"; ERRORS=$((ERRORS + 1)); }

usage() {
    cat <<'EOF'
Usage: agentcore-ai-agents.sh [--plan | --yes] [--wait-seconds SECONDS]

  --plan          Validate the stack and show the workshop resources found by name only.
  --yes           Execute without prompting. This explicitly confirms deletion.
  --wait-seconds  Per-phase timeout in seconds (default: 900).
  -h, --help      Show this help.

Without --plan or --yes, the exact stack name must be typed before deletion.
EOF
}

aws_cli() {
    aws --region "$AWS_REGION" --no-cli-pager "$@"
}

ctl() {
    aws_cli bedrock-agentcore-control "$@"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --plan)
                [[ "$MODE" == "interactive" ]] || { log_error "Choose only one mode"; exit 2; }
                MODE="plan"
                ;;
            --yes)
                [[ "$MODE" == "interactive" ]] || { log_error "Choose only one mode"; exit 2; }
                MODE="confirmed"
                ;;
            --wait-seconds)
                shift
                [[ $# -gt 0 && "$1" =~ ^[1-9][0-9]*$ ]] || {
                    log_error "--wait-seconds requires a positive integer"
                    exit 2
                }
                WAIT_SECONDS="$1"
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                usage >&2
                exit 2
                ;;
        esac
        shift
    done
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        log_error "Required command not found: $1"
        exit 1
    }
}

require_value() {
    local name="$1"
    [[ -n "${!name:-}" ]] || {
        log_error "$name is not set; source /etc/profile.d/workshop.sh"
        exit 1
    }
}

array_contains() {
    local needle="$1" item
    shift
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

wait_until() {
    local description="$1"
    shift
    local deadline=$((SECONDS + WAIT_SECONDS))
    until "$@" >/dev/null 2>&1; do
        if (( SECONDS >= deadline )); then
            record_error "Timed out waiting for $description"
            return 1
        fi
        sleep "$POLL_SECONDS"
    done
}

# delete DESCRIPTION COMMAND...: run a delete call, count a failure instead of stopping
delete() {
    local description="$1"
    shift
    if "$@" >/dev/null; then
        log_info "Deleted $description"
    else
        record_error "Could not delete $description"
    fi
}

# Lookups by name: print the ID, or nothing when the resource does not exist
none_to_empty() { local value; value=$(cat); [[ "$value" == "None" ]] || printf '%s' "$value"; }
harness_id() { ctl list-harnesses --query "harnesses[?harnessName=='$1'].harnessId | [0]" --output text | none_to_empty; }
runtime_id() { ctl list-agent-runtimes --query "agentRuntimes[?agentRuntimeName=='$1'].agentRuntimeId | [0]" --output text | none_to_empty; }
gateway_id() { ctl list-gateways --query "items[?name=='$1'].gatewayId | [0]" --output text | none_to_empty; }
online_evaluation_id() { ctl list-online-evaluation-configs --query "onlineEvaluationConfigs[?onlineEvaluationConfigName=='aiagent_online'].onlineEvaluationConfigId | [0]" --output text | none_to_empty; }
evaluator_id() { ctl list-evaluators --query "evaluators[?evaluatorName=='aiagent_policy_compliance'].evaluatorId | [0]" --output text | none_to_empty; }
bundle_id() { ctl list-configuration-bundles --query "bundles[?bundleName=='aiagentPrompt'].bundleId | [0]" --output text | none_to_empty; }
policy_engine_id() { ctl list-policy-engines --query "policyEngines[?name=='BackofficePolicyEngine'].policyEngineId | [0]" --output text | none_to_empty; }
knowledge_base_id() { aws_cli bedrock-agent list-knowledge-bases --query "knowledgeBaseSummaries[?name=='$1'].knowledgeBaseId | [0]" --output text | none_to_empty; }
guardrail_id() { aws_cli bedrock list-guardrails --query "guardrails[?name=='aiagent-guardrail'].id | [0]" --output text | none_to_empty; }
bda_project_arn() { aws_cli bedrock-data-automation list-data-automation-projects --query "projects[?projectName=='travel-receipts'].projectArn | [0]" --output text | none_to_empty; }
bda_blueprint_arn() { aws_cli bedrock-data-automation list-blueprints --resource-owner ACCOUNT --query "blueprints[?blueprintName=='travel-receipt'].blueprintArn | [0]" --output text | none_to_empty; }
user_pool_id() { aws_cli cognito-idp list-user-pools --max-results 60 --query "UserPools[?Name=='$1'].Id | [0]" --output text | none_to_empty; }
memory_ids() { ctl list-memories --query "memories[?starts_with(id, 'aiagent_memory-')].id" --output text | none_to_empty; }
ui_buckets() { aws_cli s3api list-buckets --query "Buckets[?starts_with(Name, 'aiagent-ui-${CALLER_ACCOUNT}-')].Name" --output text | none_to_empty; }
ui_oai_ids() { aws_cli cloudfront list-cloud-front-origin-access-identities --query "CloudFrontOriginAccessIdentityList.Items[?Comment=='OAI for aiagent UI'].Id" --output text | none_to_empty; }
delivery_ids() { aws_cli logs describe-deliveries --query "deliveries[?starts_with(deliverySourceName, 'mcp-gateway')].id" --output text | none_to_empty; }
role_exists() { aws_cli iam get-role --role-name "$1" >/dev/null 2>&1; }
table_exists() { aws_cli dynamodb describe-table --table-name "$1" >/dev/null 2>&1; }
repository_exists() { aws_cli ecr describe-repositories --repository-names "$1" >/dev/null 2>&1; }
function_exists() { aws_cli lambda get-function --function-name "$1" >/dev/null 2>&1; }
bucket_exists() { aws_cli s3api head-bucket --bucket "$1" >/dev/null 2>&1; }

validate_identity() {
    local stack_json actual_id actual_name stack_status stack_region stack_account

    [[ "$WORKSHOP_ID" == "$EXPECTED_WORKSHOP_ID" ]] || {
        log_error "This cleanup only supports WorkshopId=$EXPECTED_WORKSHOP_ID; found $WORKSHOP_ID"
        exit 1
    }

    stack_json=$(aws_cli cloudformation describe-stacks --stack-name "$WORKSHOP_STACK_NAME" --output json)
    actual_id=$(jq -r '.Stacks[0].StackId // empty' <<<"$stack_json")
    actual_name=$(jq -r '.Stacks[0].StackName // empty' <<<"$stack_json")
    stack_status=$(jq -r '.Stacks[0].StackStatus // empty' <<<"$stack_json")

    [[ -n "$actual_id" && "$actual_id" == "$WORKSHOP_DEPLOYMENT_ID" ]] || {
        log_error "WORKSHOP_DEPLOYMENT_ID does not match the deployed stack"
        exit 1
    }
    [[ "$actual_name" == "$WORKSHOP_STACK_NAME" ]] || {
        log_error "WORKSHOP_STACK_NAME does not match the deployed stack"
        exit 1
    }
    [[ "$stack_status" != DELETE_* ]] || {
        log_error "Stack deletion is already in progress or complete: $stack_status"
        exit 1
    }

    CALLER_ACCOUNT=$(aws_cli sts get-caller-identity --query Account --output text)
    stack_region=$(cut -d: -f4 <<<"$actual_id")
    stack_account=$(cut -d: -f5 <<<"$actual_id")
    [[ "$CALLER_ACCOUNT" == "$stack_account" ]] || {
        log_error "Current account $CALLER_ACCOUNT does not own the stack"
        exit 1
    }
    [[ "$AWS_REGION" == "$stack_region" ]] || {
        log_error "Current Region $AWS_REGION does not match stack Region $stack_region"
        exit 1
    }

    while IFS= read -r physical_id; do
        [[ -n "$physical_id" ]] && STACK_RESOURCE_IDS+=("$physical_id")
    done < <(aws_cli cloudformation list-stack-resources --stack-name "$actual_id" \
        --query 'StackResourceSummaries[].PhysicalResourceId' --output json | jq -r '.[]')

    log_info "Validated stack: $WORKSHOP_DEPLOYMENT_ID"
    log_info "Validated account/Region: $CALLER_ACCOUNT / $AWS_REGION"
}

# plan_add KIND NAME [ID]: a found resource; never one of the stack
plan_add() {
    local kind="$1" name="$2" id="${3:-$2}"
    if array_contains "$id" "${STACK_RESOURCE_IDS[@]}" || array_contains "$name" "${STACK_RESOURCE_IDS[@]}"; then
        log_error "$kind $name belongs to the stack; stopping"
        exit 1
    fi
    PLAN+=("$(printf '%-28s %s' "$kind" "$name")")
}

discover_resources() {
    local name id bucket
    for name in "${HARNESSES[@]}"; do id=$(harness_id "$name"); [[ -z "$id" ]] || plan_add "AgentCore harness" "$name" "$id"; done
    id=$(online_evaluation_id); [[ -z "$id" ]] || plan_add "Online evaluation" aiagent_online "$id"
    id=$(evaluator_id); [[ -z "$id" ]] || plan_add "Evaluator" aiagent_policy_compliance "$id"
    id=$(bundle_id); [[ -z "$id" ]] || plan_add "Configuration bundle" aiagentPrompt "$id"
    for name in "${RUNTIMES[@]}"; do id=$(runtime_id "$name"); [[ -z "$id" ]] || plan_add "AgentCore runtime" "$name" "$id"; done
    for name in "${GATEWAYS[@]}"; do id=$(gateway_id "$name"); [[ -z "$id" ]] || plan_add "AgentCore Gateway" "$name" "$id"; done
    id=$(policy_engine_id); [[ -z "$id" ]] || plan_add "Policy engine" BackofficePolicyEngine "$id"
    for id in $(delivery_ids); do plan_add "Log delivery" "$id"; done
    for id in $(memory_ids); do plan_add "AgentCore Memory" "$id"; done
    for name in "${OAUTH_PROVIDERS[@]}" "${API_KEY_PROVIDERS[@]}"; do
        ctl get-oauth2-credential-provider --name "$name" >/dev/null 2>&1 \
            || ctl get-api-key-credential-provider --name "$name" >/dev/null 2>&1 \
            && plan_add "Credential provider" "$name"
    done
    for name in "${WORKLOAD_IDENTITIES[@]}"; do
        ctl get-workload-identity --name "$name" >/dev/null 2>&1 && plan_add "Workload identity" "$name"
    done
    for name in "${KNOWLEDGE_BASES[@]}"; do id=$(knowledge_base_id "$name"); [[ -z "$id" ]] || plan_add "Knowledge Base" "$name" "$id"; done
    aws_cli s3vectors get-vector-bucket --vector-bucket-name "aiagent-kb-vectors-${CALLER_ACCOUNT}" >/dev/null 2>&1 \
        && plan_add "S3 vector bucket" "aiagent-kb-vectors-${CALLER_ACCOUNT}"
    bucket_exists "aiagent-kb-data-${CALLER_ACCOUNT}" && plan_add "S3 bucket" "aiagent-kb-data-${CALLER_ACCOUNT}"
    id=$(guardrail_id); [[ -z "$id" ]] || plan_add "Guardrail" aiagent-guardrail "$id"
    id=$(bda_project_arn); [[ -z "$id" ]] || plan_add "Data Automation project" travel-receipts "$id"
    id=$(bda_blueprint_arn); [[ -z "$id" ]] || plan_add "Data Automation blueprint" travel-receipt "$id"
    for name in "${LAMBDA_FUNCTIONS[@]}"; do function_exists "$name" && plan_add "Lambda function" "$name"; done
    for name in "${USER_POOLS[@]}"; do id=$(user_pool_id "$name"); [[ -z "$id" ]] || plan_add "Cognito user pool" "$name" "$id"; done
    for name in "${TABLES[@]}"; do table_exists "$name" && plan_add "DynamoDB table" "$name"; done
    for name in "${ECR_REPOSITORIES[@]}"; do repository_exists "$name" && plan_add "ECR repository" "$name"; done
    for bucket in $(ui_buckets); do plan_add "UI bucket and distribution" "$bucket"; done
    for id in $(ui_oai_ids); do plan_add "CloudFront OAI" "$id"; done
    for name in "${ROLES[@]}"; do role_exists "$name" && plan_add "IAM role" "$name"; done
    return 0
}

print_plan() {
    local line
    printf '\nagentcore-ai-agents cleanup plan (%d resources):\n' "${#PLAN[@]}"
    for line in "${PLAN[@]}"; do
        printf '  %s\n' "$line"
    done
    printf '  CloudFormation stack (kept):  %s\n\n' "$WORKSHOP_STACK_NAME"
}

confirm_cleanup() {
    [[ "$MODE" == "confirmed" ]] && return
    local confirmation
    printf 'This permanently deletes the resources above in the account of stack %s (the stack itself is kept).\n' "$WORKSHOP_STACK_NAME"
    read -r -p "Type the exact stack name to continue: " confirmation
    [[ "$confirmation" == "$WORKSHOP_STACK_NAME" ]] || {
        log_error "Confirmation did not match; nothing was deleted"
        exit 1
    }
}

gateway_has_no_targets() { [[ "$(ctl list-gateway-targets --gateway-identifier "$1" --query 'length(items)' --output text)" == "0" ]]; }
engine_has_no_policies() { [[ "$(ctl list-policies --policy-engine-id "$1" --query 'length(policies)' --output text)" == "0" ]]; }
kb_has_no_data_sources() { [[ "$(aws_cli bedrock-agent list-data-sources --knowledge-base-id "$1" --query 'length(dataSourceSummaries)' --output text)" == "0" ]]; }
kb_gone() { ! aws_cli bedrock-agent get-knowledge-base --knowledge-base-id "$1" >/dev/null 2>&1; }
distribution_deployed() { [[ "$(aws_cli cloudfront get-distribution --id "$1" --query 'Distribution.Status' --output text)" == "Deployed" ]]; }

# Modules 1100-1900: harnesses, evaluations, configuration bundle, recommendations
cleanup_day2_agents() {
    local name id
    for name in "${HARNESSES[@]}"; do
        id=$(harness_id "$name"); [[ -z "$id" ]] || delete "harness $name" ctl delete-harness --harness-id "$id"
    done
    id=$(online_evaluation_id); [[ -z "$id" ]] || delete "online evaluation $id" ctl delete-online-evaluation-config --online-evaluation-config-id "$id"
    id=$(evaluator_id); [[ -z "$id" ]] || delete "evaluator $id" ctl delete-evaluator --evaluator-id "$id"
    id=$(bundle_id); [[ -z "$id" ]] || delete "configuration bundle $id" ctl delete-configuration-bundle --bundle-id "$id"
    for id in $(aws_cli bedrock-agentcore list-recommendations \
        --query "recommendationSummaries[?starts_with(name, 'aiagent')].recommendationId" --output text 2>/dev/null | none_to_empty); do
        delete "recommendation $id" aws_cli bedrock-agentcore delete-recommendation --recommendation-id "$id"
    done
    return 0
}

cleanup_runtimes() {
    local name id
    for name in "${RUNTIMES[@]}"; do
        id=$(runtime_id "$name"); [[ -z "$id" ]] || delete "runtime $name" ctl delete-agent-runtime --agent-runtime-id "$id"
    done
    return 0
}

# Gateways (the policy engine is detached first), then the policy engine
cleanup_gateways_and_policies() {
    local name id target engine policy
    for name in "${GATEWAYS[@]}"; do
        id=$(gateway_id "$name"); [[ -n "$id" ]] || continue
        ctl get-gateway --gateway-identifier "$id" --output json | jq '{gatewayIdentifier: .gatewayId, name, roleArn,
            protocolType, authorizerType, authorizerConfiguration, protocolConfiguration} | with_entries(select(.value != null))' \
            > "${TMPDIR:-/tmp}/agentcore-cleanup-gateway.json"
        ctl update-gateway --cli-input-json "file://${TMPDIR:-/tmp}/agentcore-cleanup-gateway.json" >/dev/null 2>&1 || true
        for target in $(ctl list-gateway-targets --gateway-identifier "$id" --query 'items[].targetId' --output text | none_to_empty); do
            delete "target $target of $name" ctl delete-gateway-target --gateway-identifier "$id" --target-id "$target"
        done
        wait_until "the targets of $name" gateway_has_no_targets "$id" || continue
        delete "Gateway $name" ctl delete-gateway --gateway-identifier "$id"
    done
    rm -f "${TMPDIR:-/tmp}/agentcore-cleanup-gateway.json"
    engine=$(policy_engine_id)
    if [[ -n "$engine" ]]; then
        for policy in $(ctl list-policies --policy-engine-id "$engine" --query 'policies[].policyId' --output text | none_to_empty); do
            delete "policy $policy" ctl delete-policy --policy-engine-id "$engine" --policy-id "$policy"
        done
        wait_until "the policies of BackofficePolicyEngine" engine_has_no_policies "$engine" || return 0
        wait_until "the deletion of BackofficePolicyEngine" ctl delete-policy-engine --policy-engine-id "$engine" \
            && log_info "Deleted policy engine $engine"
    fi
    return 0
}

cleanup_log_deliveries() {
    local id name group
    for id in $(delivery_ids); do
        delete "log delivery $id" aws_cli logs delete-delivery --id "$id"
    done
    for name in $(aws_cli logs describe-delivery-sources --query "deliverySources[?starts_with(name, 'mcp-gateway')].name" --output text | none_to_empty); do
        delete "delivery source $name" aws_cli logs delete-delivery-source --name "$name"
    done
    for name in $(aws_cli logs describe-delivery-destinations --query "deliveryDestinations[?starts_with(name, 'mcp-gateway')].name" --output text | none_to_empty); do
        delete "delivery destination $name" aws_cli logs delete-delivery-destination --name "$name"
    done
    for group in $(aws_cli logs describe-log-groups --log-group-name-prefix /aws/vendedlogs/bedrock-agentcore/gateway/ \
        --query 'logGroups[].logGroupName' --output text | none_to_empty); do
        delete "log group $group" aws_cli logs delete-log-group --log-group-name "$group"
    done
    return 0
}

cleanup_identity_and_memory() {
    local name id
    for name in "${OAUTH_PROVIDERS[@]}"; do
        ctl get-oauth2-credential-provider --name "$name" >/dev/null 2>&1 \
            && delete "credential provider $name" ctl delete-oauth2-credential-provider --name "$name"
    done
    for name in "${API_KEY_PROVIDERS[@]}"; do
        ctl get-api-key-credential-provider --name "$name" >/dev/null 2>&1 \
            && delete "credential provider $name" ctl delete-api-key-credential-provider --name "$name"
    done
    for name in "${WORKLOAD_IDENTITIES[@]}"; do
        ctl get-workload-identity --name "$name" >/dev/null 2>&1 \
            && delete "workload identity $name" ctl delete-workload-identity --name "$name"
    done
    for id in $(memory_ids); do
        delete "memory $id" ctl delete-memory --memory-id "$id"
    done
    return 0
}

cleanup_knowledge_bases() {
    local name id source vectors="aiagent-kb-vectors-${CALLER_ACCOUNT}" data="aiagent-kb-data-${CALLER_ACCOUNT}"
    for name in "${KNOWLEDGE_BASES[@]}"; do
        id=$(knowledge_base_id "$name"); [[ -n "$id" ]] || continue
        for source in $(aws_cli bedrock-agent list-data-sources --knowledge-base-id "$id" \
            --query 'dataSourceSummaries[].dataSourceId' --output text | none_to_empty); do
            delete "data source $source of $name" aws_cli bedrock-agent delete-data-source --knowledge-base-id "$id" --data-source-id "$source"
        done
        wait_until "the data sources of $name" kb_has_no_data_sources "$id" || continue
        delete "Knowledge Base $name" aws_cli bedrock-agent delete-knowledge-base --knowledge-base-id "$id"
        wait_until "the deletion of $name" kb_gone "$id" || true
    done
    if aws_cli s3vectors get-vector-bucket --vector-bucket-name "$vectors" >/dev/null 2>&1; then
        aws_cli s3vectors delete-index --vector-bucket-name "$vectors" --index-name aiagent-index >/dev/null 2>&1 || true
        delete "vector bucket $vectors" aws_cli s3vectors delete-vector-bucket --vector-bucket-name "$vectors"
    fi
    if bucket_exists "$data"; then
        delete "bucket $data" aws_cli s3 rb "s3://$data" --force
    fi
    return 0
}

cleanup_guardrail_and_documents() {
    local id name
    id=$(guardrail_id); [[ -z "$id" ]] || delete "guardrail $id" aws_cli bedrock delete-guardrail --guardrail-identifier "$id"
    id=$(bda_project_arn); [[ -z "$id" ]] || delete "Data Automation project travel-receipts" aws_cli bedrock-data-automation delete-data-automation-project --project-arn "$id"
    id=$(bda_blueprint_arn); [[ -z "$id" ]] || delete "Data Automation blueprint travel-receipt" aws_cli bedrock-data-automation delete-blueprint --blueprint-arn "$id"
    for name in "${LAMBDA_FUNCTIONS[@]}"; do
        function_exists "$name" && delete "Lambda function $name" aws_cli lambda delete-function --function-name "$name"
    done
    return 0
}

cleanup_user_pools_tables_repositories() {
    local name id domain
    for name in "${USER_POOLS[@]}"; do
        id=$(user_pool_id "$name"); [[ -n "$id" ]] || continue
        domain=$(aws_cli cognito-idp describe-user-pool --user-pool-id "$id" --query 'UserPool.Domain' --output text | none_to_empty)
        [[ -z "$domain" ]] || delete "domain of $name" aws_cli cognito-idp delete-user-pool-domain --user-pool-id "$id" --domain "$domain"
        delete "user pool $name" aws_cli cognito-idp delete-user-pool --user-pool-id "$id"
    done
    for name in "${TABLES[@]}"; do
        table_exists "$name" && delete "table $name" aws_cli dynamodb delete-table --table-name "$name"
    done
    for name in "${ECR_REPOSITORIES[@]}"; do
        repository_exists "$name" && delete "ECR repository $name" aws_cli ecr delete-repository --repository-name "$name" --force
    done
    return 0
}

# The UI: disable the distribution, wait until it is deployed, delete it, then the bucket and the OAI
cleanup_ui() {
    local bucket dist etag config oai
    config="${TMPDIR:-/tmp}/agentcore-cleanup-distribution.json"
    for bucket in $(ui_buckets); do
        dist=$(aws_cli cloudfront list-distributions \
            --query "DistributionList.Items[?Origins.Items[0].DomainName=='${bucket}.s3.${AWS_REGION}.amazonaws.com'].Id | [0]" \
            --output text | none_to_empty)
        if [[ -n "$dist" ]]; then
            if [[ "$(aws_cli cloudfront get-distribution --id "$dist" --query 'Distribution.DistributionConfig.Enabled' --output text)" == "True" ]]; then
                etag=$(aws_cli cloudfront get-distribution-config --id "$dist" --query ETag --output text)
                aws_cli cloudfront get-distribution-config --id "$dist" --query DistributionConfig | jq '.Enabled = false' > "$config"
                aws_cli cloudfront update-distribution --id "$dist" --if-match "$etag" --distribution-config "file://$config" >/dev/null \
                    || record_error "Could not disable CloudFront distribution $dist"
                log_info "Disabling CloudFront distribution $dist (several minutes)"
            fi
            if wait_until "CloudFront distribution $dist" distribution_deployed "$dist"; then
                etag=$(aws_cli cloudfront get-distribution --id "$dist" --query ETag --output text)
                delete "CloudFront distribution $dist" aws_cli cloudfront delete-distribution --id "$dist" --if-match "$etag"
            fi
        fi
        delete "bucket $bucket" aws_cli s3 rb "s3://$bucket" --force
    done
    rm -f "$config"
    for oai in $(ui_oai_ids); do
        etag=$(aws_cli cloudfront get-cloud-front-origin-access-identity --id "$oai" --query ETag --output text)
        delete "CloudFront OAI $oai" aws_cli cloudfront delete-cloud-front-origin-access-identity --id "$oai" --if-match "$etag"
    done
    return 0
}

cleanup_roles() {
    local role policy arn
    for role in "${ROLES[@]}"; do
        role_exists "$role" || continue
        for policy in $(aws_cli iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text | none_to_empty); do
            aws_cli iam delete-role-policy --role-name "$role" --policy-name "$policy" || record_error "Could not delete policy $policy of $role"
        done
        for arn in $(aws_cli iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text | none_to_empty); do
            aws_cli iam detach-role-policy --role-name "$role" --policy-arn "$arn" || record_error "Could not detach $arn from $role"
        done
        delete "role $role" aws_cli iam delete-role --role-name "$role"
    done
    return 0
}

report_remaining() {
    local remaining
    PLAN=()
    discover_resources
    remaining=${#PLAN[@]}
    if (( remaining > 0 )); then
        record_error "$remaining resource(s) remain:"
        print_plan
    fi
    if (( ERRORS > 0 )); then
        log_error "$ERRORS cleanup operation(s) failed; run the cleanup again or fix them by hand"
        exit 1
    fi
    log_success "Workshop resources removed; stack $WORKSHOP_STACK_NAME is kept"
    log_info "Delete it from the CloudFormation console or CloudShell with your own credentials:"
    log_info "  aws cloudformation delete-stack --stack-name $WORKSHOP_STACK_NAME --region $AWS_REGION"
}

main() {
    parse_args "$@"
    require_command aws
    require_command jq

    if [[ -r /etc/profile.d/workshop.sh ]]; then
        # shellcheck disable=SC1091
        source /etc/profile.d/workshop.sh
    fi
    require_value AWS_REGION
    require_value WORKSHOP_ID
    require_value WORKSHOP_STACK_NAME
    require_value WORKSHOP_DEPLOYMENT_ID
    export AWS_PAGER=""

    validate_identity
    discover_resources
    print_plan
    if [[ "$MODE" == "plan" ]]; then
        log_info "Plan only; nothing was deleted"
        return
    fi
    if [[ ${#PLAN[@]} -eq 0 ]]; then
        log_success "No workshop resources found; stack $WORKSHOP_STACK_NAME is kept"
        return
    fi

    confirm_cleanup
    cleanup_day2_agents
    cleanup_runtimes
    cleanup_gateways_and_policies
    cleanup_log_deliveries
    cleanup_identity_and_memory
    cleanup_knowledge_bases
    cleanup_guardrail_and_documents
    cleanup_user_pools_tables_repositories
    cleanup_ui
    cleanup_roles
    report_remaining
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
