#!/usr/bin/env bash
set -Eeuo pipefail

# Cleanup for the java-on-amazon-eks workshop (re:Invent Builders' Session).
# Derived from java-on-aws.sh; differences:
#   - WorkshopId is java-on-amazon-eks (stack infra/cfn/java-on-amazon-eks-stack.yaml).
#   - No ECS path is deployed: the ECS discovery and cleanup phases are removed.
#   - The workshop's ECR repositories (unicorn-store-spring with :latest/:aot/:crac,
#     perf-sensor, perf-profiler) are created by scripts and carry no ownership tags,
#     so they are cleaned by name (WORKSHOP_ECR_REPOSITORIES) after an ownership check:
#     untagged, or tagged for this workshop; never if tagged for another stack.
#
# Safety model:
#   1. Validate the immutable CloudFormation stack ID, account, Region, workshop
#      ID, stack-owned VPC, and stack-owned EKS cluster.
#   2. Treat the validated EKS cluster and VPC as dedicated workshop boundaries.
#   3. Enumerate Kubernetes workloads instead of naming applications.
#   4. Retain the validated CloudFormation stack after external dependencies are removed.

readonly EXPECTED_WORKSHOP_ID="java-on-amazon-eks"
readonly WORKSHOP_ECR_REPOSITORIES=(unicorn-store-spring perf-sensor perf-profiler)
readonly FOUNDATION_OWNER="cloudformation"
readonly RUNTIME_OWNER="workshop-run"
readonly DEFAULT_WAIT_SECONDS=600
readonly POLL_SECONDS=10

MODE="interactive"
WAIT_SECONDS="${WORKSHOP_CLEANUP_WAIT_SECONDS:-$DEFAULT_WAIT_SECONDS}"
ERRORS=0
VPC_ID=""
EKS_CLUSTER_NAME=""
STACK_RESOURCES_JSON=""
KUBE_CONFIG=""
KUBE_CONTEXT=""

declare -a VPC_SUBNET_IDS=()
declare -a RUNTIME_LOAD_BALANCERS=()
declare -a RUNTIME_TARGET_GROUPS=()
declare -a RUNTIME_ECR_REPOSITORIES=()
declare -a NAMED_ECR_REPOSITORIES=()
declare -a SECURITY_GROUPS=()
declare -a STACK_RESOURCE_IDS=()

log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }
record_error() { log_error "$*"; ERRORS=$((ERRORS + 1)); }

usage() {
    cat <<'EOF'
Usage: java-on-amazon-eks.sh [--plan | --yes] [--wait-seconds SECONDS]

  --plan          Validate ownership and show discovered resources only.
  --yes           Execute without prompting. This explicitly confirms deletion.
  --wait-seconds  Per-phase timeout in seconds (default: 600).
  -h, --help      Show this help.

Without --plan or --yes, the exact stack name must be typed before deletion.
EOF
}

aws_cli() {
    aws --region "$AWS_REGION" --no-cli-pager "$@"
}

kubectl_cli() {
    command kubectl --kubeconfig "$KUBE_CONFIG" --context "$KUBE_CONTEXT" "$@"
}

cleanup_local_state() {
    [[ -z "$KUBE_CONFIG" ]] || rm -f "$KUBE_CONFIG"
}

fail_discovery() {
    log_error "$*"
    exit 1
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

append_unique() {
    local array_name="$1" value="$2"
    [[ -n "$value" && "$value" != "None" ]] || return
    case "$array_name" in
        SECURITY_GROUPS)
            array_contains "$value" "${SECURITY_GROUPS[@]:-}" || SECURITY_GROUPS+=("$value")
            ;;
        *)
            log_error "Unsupported cleanup collection: $array_name"
            exit 1
            ;;
    esac
}

is_stack_resource() {
    array_contains "$1" "${STACK_RESOURCE_IDS[@]:-}"
}

json_array_tag() {
    local json="$1" key="$2"
    jq -r --arg key "$key" \
        '[(.Tags // .tags // [])[] | select((.Key // .key) == $key) | (.Value // .value)][0] // empty' \
        <<<"$json"
}

json_map_tag() {
    local json="$1" key="$2"
    jq -r --arg key "$key" '.tags[$key] // empty' <<<"$json"
}

assert_not_owned_by_other_stack() {
    local description="$1" id="$2" tags_json="$3" format="${4:-array}" owner_stack
    if [[ "$format" == "map" ]]; then
        owner_stack=$(json_map_tag "$tags_json" 'aws:cloudformation:stack-id')
    else
        owner_stack=$(json_array_tag "$tags_json" 'aws:cloudformation:stack-id')
    fi
    if [[ -n "$owner_stack" && "$owner_stack" != "$WORKSHOP_DEPLOYMENT_ID" ]]; then
        fail_discovery "$description $id belongs to another CloudFormation stack: $owner_stack"
    fi
}

wait_until() {
    local description="$1"
    shift
    local deadline=$((SECONDS + WAIT_SECONDS))
    until "$@"; do
        if (( SECONDS >= deadline )); then
            record_error "Timed out waiting for $description"
            return 1
        fi
        sleep "$POLL_SECONDS"
    done
}

validate_foundation_tags() {
    local description="$1" id="$2" deployment="$3" workshop="$4" owner="$5"
    [[ "$deployment" == "$WORKSHOP_DEPLOYMENT_ID" ]] || {
        log_error "$description $id has a different WorkshopDeploymentId"
        exit 1
    }
    [[ "$workshop" == "$EXPECTED_WORKSHOP_ID" && "$owner" == "$FOUNDATION_OWNER" ]] || {
        log_error "$description $id is not owned by this java-on-amazon-eks foundation"
        exit 1
    }
}

validate_identity() {
    local stack_json actual_id actual_name stack_status caller_account stack_region stack_account
    local -a vpc_ids=() eks_names=()

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

    caller_account=$(aws_cli sts get-caller-identity --query Account --output text)
    stack_region=$(cut -d: -f4 <<<"$actual_id")
    stack_account=$(cut -d: -f5 <<<"$actual_id")
    [[ "$caller_account" == "$stack_account" ]] || {
        log_error "Current account $caller_account does not own the stack"
        exit 1
    }
    [[ "$AWS_REGION" == "$stack_region" ]] || {
        log_error "Current Region $AWS_REGION does not match stack Region $stack_region"
        exit 1
    }

    STACK_RESOURCES_JSON=$(aws_cli cloudformation list-stack-resources --stack-name "$actual_id" --output json)
    while IFS= read -r physical_id; do
        [[ -n "$physical_id" ]] && STACK_RESOURCE_IDS+=("$physical_id")
    done < <(jq -r '.StackResourceSummaries[].PhysicalResourceId // empty' <<<"$STACK_RESOURCES_JSON")

    mapfile -t vpc_ids < <(jq -r \
        '.StackResourceSummaries[] | select(.ResourceType == "AWS::EC2::VPC") | .PhysicalResourceId' \
        <<<"$STACK_RESOURCES_JSON")
    [[ ${#vpc_ids[@]} -eq 1 && -n "${vpc_ids[0]}" ]] || {
        log_error "Expected exactly one stack VPC; found ${#vpc_ids[@]}"
        exit 1
    }
    VPC_ID="${vpc_ids[0]}"

    local vpc_json vpc_resource
    vpc_json=$(aws_cli ec2 describe-vpcs --vpc-ids "$VPC_ID" --output json)
    vpc_resource=$(jq -c '.Vpcs[0]' <<<"$vpc_json")
    validate_foundation_tags "VPC" "$VPC_ID" \
        "$(json_array_tag "$vpc_resource" WorkshopDeploymentId)" \
        "$(json_array_tag "$vpc_resource" WorkshopId)" \
        "$(json_array_tag "$vpc_resource" WorkshopOwner)"

    mapfile -t VPC_SUBNET_IDS < <(aws_cli ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text | tr '\t' '\n')
    [[ ${#VPC_SUBNET_IDS[@]} -gt 0 ]] || {
        log_error "Validated VPC $VPC_ID has no subnets"
        exit 1
    }

    mapfile -t eks_names < <(jq -r \
        '.StackResourceSummaries[] | select(.ResourceType == "AWS::EKS::Cluster") | .PhysicalResourceId' \
        <<<"$STACK_RESOURCES_JSON")
    [[ ${#eks_names[@]} -eq 1 && -n "${eks_names[0]}" ]] || {
        log_error "Expected exactly one stack EKS cluster; found ${#eks_names[@]}"
        exit 1
    }
    EKS_CLUSTER_NAME="${eks_names[0]}"

    local cluster_json cluster_arn cluster_tags
    cluster_json=$(aws_cli eks describe-cluster --name "$EKS_CLUSTER_NAME" --output json)
    cluster_arn=$(jq -r '.cluster.arn' <<<"$cluster_json")
    [[ "$(jq -r '.cluster.resourcesVpcConfig.vpcId' <<<"$cluster_json")" == "$VPC_ID" ]] || {
        log_error "EKS cluster $EKS_CLUSTER_NAME is outside validated VPC $VPC_ID"
        exit 1
    }
    cluster_tags=$(aws_cli eks list-tags-for-resource --resource-arn "$cluster_arn" --output json)
    validate_foundation_tags "EKS cluster" "$EKS_CLUSTER_NAME" \
        "$(json_map_tag "$cluster_tags" WorkshopDeploymentId)" \
        "$(json_map_tag "$cluster_tags" WorkshopId)" \
        "$(json_map_tag "$cluster_tags" WorkshopOwner)"

    log_info "Validated stack: $WORKSHOP_DEPLOYMENT_ID"
    log_info "Validated account/Region: $caller_account / $AWS_REGION"
    log_info "Validated dedicated VPC: $VPC_ID"
    log_info "Validated dedicated EKS cluster: $EKS_CLUSTER_NAME"
}

discover_vpc_load_balancers() {
    local load_balancer_output target_group_output arn lb_json tags subnet target_vpc belongs

    load_balancer_output=$(aws_cli elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null) || \
        fail_discovery "Could not enumerate load balancers"
    for arn in ${load_balancer_output//$'\t'/ }; do
        [[ -n "$arn" && "$arn" != "None" ]] || continue
        is_stack_resource "$arn" && continue
        lb_json=$(aws_cli elbv2 describe-load-balancers --load-balancer-arns "$arn" --output json 2>/dev/null) || \
            fail_discovery "Could not describe load balancer $arn"
        belongs=0
        while IFS= read -r subnet; do
            array_contains "$subnet" "${VPC_SUBNET_IDS[@]}" && belongs=1
        done < <(jq -r '.LoadBalancers[0].AvailabilityZones[].SubnetId' <<<"$lb_json")
        if (( belongs == 1 )); then
            tags=$(aws_cli elbv2 describe-tags --resource-arns "$arn" --query 'TagDescriptions[0]' --output json 2>/dev/null) || \
                fail_discovery "Could not inspect ownership tags for load balancer $arn"
            assert_not_owned_by_other_stack "Load balancer" "$arn" "$tags"
            RUNTIME_LOAD_BALANCERS+=("$arn")
            while IFS= read -r subnet; do append_unique SECURITY_GROUPS "$subnet"; done \
                < <(jq -r '.LoadBalancers[0].SecurityGroups[]?' <<<"$lb_json")
        fi
    done

    target_group_output=$(aws_cli elbv2 describe-target-groups \
        --query 'TargetGroups[].[TargetGroupArn,VpcId]' --output text 2>/dev/null) || \
        fail_discovery "Could not enumerate target groups"
    while IFS=$'\t' read -r arn target_vpc; do
        [[ -n "$arn" && "$target_vpc" == "$VPC_ID" ]] || continue
        is_stack_resource "$arn" && continue
        tags=$(aws_cli elbv2 describe-tags --resource-arns "$arn" --query 'TagDescriptions[0]' --output json 2>/dev/null) || \
            fail_discovery "Could not inspect ownership tags for target group $arn"
        assert_not_owned_by_other_stack "Target group" "$arn" "$tags"
        RUNTIME_TARGET_GROUPS+=("$arn")
    done <<<"$target_group_output"
}

discover_runtime_ecr() {
    local repository_output name arn tags
    repository_output=$(aws_cli ecr describe-repositories \
        --query 'repositories[].[repositoryName,repositoryArn]' --output text 2>/dev/null) || \
        fail_discovery "Could not enumerate ECR repositories"
    while IFS=$'\t' read -r name arn; do
        [[ -n "$name" && -n "$arn" ]] || continue
        tags=$(aws_cli ecr list-tags-for-resource --resource-arn "$arn" --output json 2>/dev/null) || \
            fail_discovery "Could not inspect ownership tags for ECR repository $arn"
        if [[ "$(json_array_tag "$tags" WorkshopId)" == "$EXPECTED_WORKSHOP_ID" &&
              "$(json_array_tag "$tags" WorkshopDeploymentId)" == "$WORKSHOP_DEPLOYMENT_ID" &&
              "$(json_array_tag "$tags" WorkshopOwner)" == "$RUNTIME_OWNER" ]]; then
            assert_not_owned_by_other_stack "ECR repository" "$arn" "$tags"
            RUNTIME_ECR_REPOSITORIES+=("$name")
        fi
    done <<<"$repository_output"
    discover_named_ecr
}

# The workshop scripts (apps/unicorn-store-spring/scripts/build.sh, deploy/java-on-amazon-eks/
# perf-sensor.sh, perf-profiler.sh) create repositories without ownership tags. Accept them
# by name when they are untagged or tagged for this workshop; refuse foreign ownership.
discover_named_ecr() {
    local name arn tags workshop_tag
    for name in "${WORKSHOP_ECR_REPOSITORIES[@]}"; do
        array_contains "$name" "${RUNTIME_ECR_REPOSITORIES[@]:-}" && continue
        arn=$(aws_cli ecr describe-repositories --repository-names "$name" \
            --query 'repositories[0].repositoryArn' --output text 2>/dev/null) || continue
        [[ -n "$arn" && "$arn" != "None" ]] || continue
        tags=$(aws_cli ecr list-tags-for-resource --resource-arn "$arn" --output json 2>/dev/null) || \
            fail_discovery "Could not inspect ownership tags for ECR repository $arn"
        assert_not_owned_by_other_stack "ECR repository" "$arn" "$tags"
        workshop_tag=$(json_array_tag "$tags" WorkshopId)
        if [[ -n "$workshop_tag" && "$workshop_tag" != "$EXPECTED_WORKSHOP_ID" ]]; then
            fail_discovery "ECR repository $name is tagged for another workshop: $workshop_tag"
        fi
        NAMED_ECR_REPOSITORIES+=("$name")
    done
}

validate_pod_identity_ownership() {
    local association_output association association_json association_tags
    association_output=$(aws_cli eks list-pod-identity-associations --cluster-name "$EKS_CLUSTER_NAME" \
        --query 'associations[].associationId' --output text 2>/dev/null) || \
        fail_discovery "Could not enumerate EKS Pod Identity associations"
    for association in ${association_output//$'\t'/ }; do
        [[ -n "$association" && "$association" != "None" ]] || continue
        association_json=$(aws_cli eks describe-pod-identity-association --cluster-name "$EKS_CLUSTER_NAME" \
            --association-id "$association" --output json 2>/dev/null) || \
            fail_discovery "Could not inspect Pod Identity association $association"
        association_tags=$(jq -c '{tags:(.association.tags // {})}' <<<"$association_json")
        assert_not_owned_by_other_stack "Pod Identity association" "$association" "$association_tags" map
    done
}

discover_resources() {
    KUBE_CONFIG=$(mktemp "${TMPDIR:-/tmp}/java-on-amazon-eks-cleanup-kubeconfig.XXXXXX")
    KUBE_CONTEXT="cleanup-${EKS_CLUSTER_NAME}-${WORKSHOP_DEPLOYMENT_ID##*/}"
    aws_cli eks update-kubeconfig --name "$EKS_CLUSTER_NAME" \
        --alias "$KUBE_CONTEXT" --kubeconfig "$KUBE_CONFIG" >/dev/null
    validate_pod_identity_ownership
    discover_vpc_load_balancers
    discover_runtime_ecr
}

print_plan() {
    local ingress_count service_count association_count
    ingress_count=$(kubectl_cli get ingress --all-namespaces -o json | jq '.items | length')
    service_count=$(kubectl_cli get service --all-namespaces -o json | jq '[.items[] | select(.spec.type == "LoadBalancer")] | length')
    association_count=$(aws_cli eks list-pod-identity-associations --cluster-name "$EKS_CLUSTER_NAME" \
        --query 'length(associations)' --output text)

    printf '\njava-on-amazon-eks cleanup plan:\n'
    printf '  Kubernetes Ingresses:             %s\n' "$ingress_count"
    printf '  Kubernetes LoadBalancer Services: %s\n' "$service_count"
    printf '  EKS Pod Identity associations:    %s\n' "$association_count"
    printf '  Load balancers in VPC:            %d\n' "${#RUNTIME_LOAD_BALANCERS[@]}"
    printf '  Target groups in VPC:             %d\n' "${#RUNTIME_TARGET_GROUPS[@]}"
    printf '  Tagged runtime ECR repositories:  %d\n' "${#RUNTIME_ECR_REPOSITORIES[@]}"
    printf '  Workshop ECR repositories:        %s\n' "${NAMED_ECR_REPOSITORIES[*]:-none}"
    printf '  CloudFormation stack:             %s\n\n' "$WORKSHOP_STACK_NAME"
}

confirm_cleanup() {
    [[ "$MODE" == "confirmed" ]] && return
    local confirmation
    printf 'This permanently deletes java-on-amazon-eks runtime resources and stack %s.\n' "$WORKSHOP_STACK_NAME"
    read -r -p "Type the exact stack name to continue: " confirmation
    [[ "$confirmation" == "$WORKSHOP_STACK_NAME" ]] || {
        log_error "Confirmation did not match; nothing was deleted"
        exit 1
    }
}

kubernetes_dependencies_gone() {
    local ingress_count service_count
    ingress_count=$(kubectl_cli get ingress --all-namespaces -o json 2>/dev/null | jq '.items | length') || return 1
    service_count=$(kubectl_cli get service --all-namespaces -o json 2>/dev/null | jq '[.items[] | select(.spec.type == "LoadBalancer")] | length') || return 1
    [[ "$ingress_count" -eq 0 && "$service_count" -eq 0 ]]
}

cleanup_eks_dependencies() {
    local namespace name association association_json association_tags ingress_json service_json association_output
    ingress_json=$(kubectl_cli get ingress --all-namespaces -o json) || {
        record_error "Could not enumerate EKS Ingresses before deletion"
        return
    }
    service_json=$(kubectl_cli get service --all-namespaces -o json) || {
        record_error "Could not enumerate EKS Services before deletion"
        return
    }

    log_info "Deleting every Ingress from validated EKS cluster $EKS_CLUSTER_NAME"
    while IFS=$'\t' read -r namespace name; do
        [[ -n "$namespace" && -n "$name" ]] || continue
        kubectl_cli delete ingress "$name" --namespace "$namespace" --ignore-not-found \
            --wait=true --timeout="${WAIT_SECONDS}s" || record_error "Failed to delete Ingress $namespace/$name"
    done < <(jq -r '.items[] | [.metadata.namespace,.metadata.name] | @tsv' <<<"$ingress_json")

    log_info "Deleting every LoadBalancer Service from validated EKS cluster"
    while IFS=$'\t' read -r namespace name; do
        [[ -n "$namespace" && -n "$name" ]] || continue
        kubectl_cli delete service "$name" --namespace "$namespace" --ignore-not-found \
            --wait=true --timeout="${WAIT_SECONDS}s" || record_error "Failed to delete Service $namespace/$name"
    done < <(jq -r '.items[] | select(.spec.type == "LoadBalancer") | [.metadata.namespace,.metadata.name] | @tsv' <<<"$service_json")
    wait_until "Kubernetes load-balancer dependencies" kubernetes_dependencies_gone || true

    association_output=$(aws_cli eks list-pod-identity-associations --cluster-name "$EKS_CLUSTER_NAME" \
        --query 'associations[].associationId' --output text 2>/dev/null) || {
        record_error "Could not enumerate EKS Pod Identity associations"
        return
    }
    log_info "Deleting all Pod Identity associations from validated EKS cluster"
    for association in ${association_output//$'\t'/ }; do
        [[ -n "$association" && "$association" != "None" ]] || continue
        association_json=$(aws_cli eks describe-pod-identity-association --cluster-name "$EKS_CLUSTER_NAME" \
            --association-id "$association" --output json 2>/dev/null) || {
            record_error "Could not inspect Pod Identity association $association"
            continue
        }
        association_tags=$(jq -c '{tags:(.association.tags // {})}' <<<"$association_json")
        assert_not_owned_by_other_stack "Pod Identity association" "$association" "$association_tags" map
        aws_cli eks delete-pod-identity-association --cluster-name "$EKS_CLUSTER_NAME" \
            --association-id "$association" >/dev/null || record_error "Failed to delete Pod Identity association $association"
    done
}

load_balancer_state() {
    local output
    if output=$(aws_cli elbv2 describe-load-balancers --load-balancer-arns "$1" 2>&1); then
        return 0
    fi
    if [[ "$output" == *"LoadBalancerNotFound"* || "$output" == *"not found"* ]]; then
        return 1
    fi
    return 2
}

load_balancer_gone() {
    local state=0
    load_balancer_state "$1" || state=$?
    [[ "$state" -eq 1 ]]
}

target_group_state() {
    local output
    if output=$(aws_cli elbv2 describe-target-groups --target-group-arns "$1" 2>&1); then
        return 0
    fi
    if [[ "$output" == *"TargetGroupNotFound"* || "$output" == *"not found"* ]]; then
        return 1
    fi
    return 2
}

cleanup_vpc_load_balancers() {
    local arn listener_output listener state
    for arn in "${RUNTIME_LOAD_BALANCERS[@]}"; do
        state=0
        load_balancer_state "$arn" || state=$?
        if (( state == 1 )); then
            log_info "Load balancer already removed by its controller: $arn"
            continue
        elif (( state != 0 )); then
            record_error "Could not verify load balancer state: $arn"
            continue
        fi
        log_info "Deleting non-stack load balancer in workshop VPC: $arn"
        listener_output=$(aws_cli elbv2 describe-listeners --load-balancer-arn "$arn" \
            --query 'Listeners[].ListenerArn' --output text 2>/dev/null) || {
            record_error "Could not enumerate listeners for load balancer $arn"
            continue
        }
        for listener in ${listener_output//$'\t'/ }; do
            [[ -n "$listener" && "$listener" != "None" ]] || continue
            aws_cli elbv2 delete-listener --listener-arn "$listener" >/dev/null || record_error "Failed to delete listener $listener"
        done
        aws_cli elbv2 delete-load-balancer --load-balancer-arn "$arn" >/dev/null || record_error "Failed to delete load balancer $arn"
        wait_until "load balancer $arn" load_balancer_gone "$arn" || true
    done

    for arn in "${RUNTIME_TARGET_GROUPS[@]}"; do
        state=0
        target_group_state "$arn" || state=$?
        if (( state == 1 )); then
            log_info "Target group already removed by its controller: $arn"
            continue
        elif (( state != 0 )); then
            record_error "Could not verify target group state: $arn"
            continue
        fi
        log_info "Deleting non-stack target group in workshop VPC: $arn"
        aws_cli elbv2 delete-target-group --target-group-arn "$arn" >/dev/null || record_error "Failed to delete target group $arn"
    done
}

cleanup_runtime_ecr() {
    local repository repository_json repository_arn tags
    for repository in "${RUNTIME_ECR_REPOSITORIES[@]}"; do
        if ! repository_json=$(aws_cli ecr describe-repositories --repository-names "$repository" --output json 2>&1); then
            if [[ "$repository_json" == *"RepositoryNotFoundException"* || "$repository_json" == *"not found"* ]]; then
                log_info "ECR repository already removed: $repository"
            else
                record_error "Could not verify ECR repository state: $repository"
            fi
            continue
        fi
        repository_arn=$(jq -r '.repositories[0].repositoryArn // empty' <<<"$repository_json")
        [[ -n "$repository_arn" ]] || {
            record_error "ECR repository $repository returned no ARN"
            continue
        }
        tags=$(aws_cli ecr list-tags-for-resource --resource-arn "$repository_arn" --output json 2>/dev/null) || {
            record_error "Could not re-check ownership tags for ECR repository $repository"
            continue
        }
        assert_not_owned_by_other_stack "ECR repository" "$repository_arn" "$tags"
        if [[ "$(json_array_tag "$tags" WorkshopId)" != "$EXPECTED_WORKSHOP_ID" ||
              "$(json_array_tag "$tags" WorkshopDeploymentId)" != "$WORKSHOP_DEPLOYMENT_ID" ||
              "$(json_array_tag "$tags" WorkshopOwner)" != "$RUNTIME_OWNER" ]]; then
            record_error "ECR repository $repository no longer matches workshop runtime ownership"
            continue
        fi
        log_info "Deleting tagged runtime ECR repository: $repository"
        aws_cli ecr delete-repository --repository-name "$repository" --force >/dev/null || record_error "Failed to delete ECR repository $repository"
    done
}

cleanup_named_ecr() {
    local repository arn tags workshop_tag
    for repository in "${NAMED_ECR_REPOSITORIES[@]:-}"; do
        [[ -n "$repository" ]] || continue
        arn=$(aws_cli ecr describe-repositories --repository-names "$repository" \
            --query 'repositories[0].repositoryArn' --output text 2>/dev/null) || {
            log_info "ECR repository already removed: $repository"
            continue
        }
        tags=$(aws_cli ecr list-tags-for-resource --resource-arn "$arn" --output json 2>/dev/null) || {
            record_error "Could not re-check ownership tags for ECR repository $repository"
            continue
        }
        assert_not_owned_by_other_stack "ECR repository" "$arn" "$tags"
        workshop_tag=$(json_array_tag "$tags" WorkshopId)
        if [[ -n "$workshop_tag" && "$workshop_tag" != "$EXPECTED_WORKSHOP_ID" ]]; then
            record_error "ECR repository $repository is tagged for another workshop: $workshop_tag"
            continue
        fi
        log_info "Deleting workshop ECR repository: $repository"
        aws_cli ecr delete-repository --repository-name "$repository" --force >/dev/null || record_error "Failed to delete ECR repository $repository"
    done
}

cleanup_security_groups() {
    local group_id group_json group_resource
    for group_id in "${SECURITY_GROUPS[@]}"; do
        [[ -n "$group_id" ]] || continue
        is_stack_resource "$group_id" && continue
        if ! group_json=$(aws_cli ec2 describe-security-groups --group-ids "$group_id" --output json 2>&1); then
            if [[ "$group_json" == *"InvalidGroup.NotFound"* || "$group_json" == *"not found"* ]]; then
                log_info "Security group already removed: $group_id"
            else
                record_error "Could not verify security group state: $group_id"
            fi
            continue
        fi
        group_resource=$(jq -c '.SecurityGroups[0]' <<<"$group_json")
        assert_not_owned_by_other_stack "Security group" "$group_id" "$group_resource"
        log_info "Deleting security group used by removed runtime dependency: $group_id"
        wait_until "security group $group_id" aws_cli ec2 delete-security-group --group-id "$group_id" || true
    done
}

request_stack_deletion() {
    if (( ERRORS > 0 )); then
        log_error "$ERRORS cleanup operation(s) failed; stack deletion was not requested"
        exit 1
    fi
    aws_cli cloudformation delete-stack --stack-name "$WORKSHOP_DEPLOYMENT_ID"
    log_info "CloudFormation deletion requested for validated stack $WORKSHOP_DEPLOYMENT_ID"
}

main() {
    parse_args "$@"
    require_command aws
    require_command jq
    require_command kubectl

    if [[ -r /etc/profile.d/workshop.sh ]]; then
        # shellcheck disable=SC1091
        source /etc/profile.d/workshop.sh
    fi
    require_value AWS_REGION
    require_value WORKSHOP_ID
    require_value WORKSHOP_STACK_NAME
    require_value WORKSHOP_DEPLOYMENT_ID
    export AWS_PAGER=""
    trap cleanup_local_state EXIT

    validate_identity
    discover_resources
    print_plan
    if [[ "$MODE" == "plan" ]]; then
        log_info "Plan only; nothing was deleted"
        return
    fi

    confirm_cleanup
    cleanup_eks_dependencies
    cleanup_vpc_load_balancers
    cleanup_runtime_ecr
    cleanup_named_ecr
    cleanup_security_groups
    request_stack_deletion
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
