#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  echo "Usage: $0 <cluster> <service> [task-definition]" >&2
  exit 2
}

if (( $# < 2 || $# > 3 )); then
  usage
fi

ECS_CLUSTER="$1"
ECS_SERVICE="$2"
TASK_DEFINITION="${3:-}"
PROGRESS_INTERVAL_SECONDS="${ECS_REDEPLOY_PROGRESS_INTERVAL_SECONDS:-15}"
WAITER_PID=""

show_service_status() {
  aws ecs describe-services \
    --cluster "${ECS_CLUSTER}" \
    --services "${ECS_SERVICE}" \
    --query '{service:services[0].{deployments:deployments,events:events[:5]},failures:failures}' \
    --no-cli-pager || true
}

stop_waiter() {
  if [[ -n "${WAITER_PID}" ]] && kill -0 "${WAITER_PID}" 2>/dev/null; then
    kill "${WAITER_PID}" 2>/dev/null || true
    wait "${WAITER_PID}" 2>/dev/null || true
  fi
}

trap 'stop_waiter; exit 130' INT
trap 'stop_waiter; exit 143' TERM
trap stop_waiter EXIT

update_arguments=(
  --cluster "${ECS_CLUSTER}"
  --service "${ECS_SERVICE}"
  --force-new-deployment
)
if [[ -n "${TASK_DEFINITION}" ]]; then
  update_arguments+=(--task-definition "${TASK_DEFINITION}")
fi

if ! deployment_id=$(aws ecs update-service "${update_arguments[@]}" \
  --query "service.deployments[?status=='PRIMARY'].id | [0]" \
  --output text \
  --no-cli-pager); then
  echo "Failed to start the ECS deployment." >&2
  show_service_status
  exit 1
fi

if [[ -z "${deployment_id}" || "${deployment_id}" == "None" ]]; then
  echo "ECS did not return the new deployment ID." >&2
  show_service_status
  exit 1
fi

printf 'Waiting for ECS deployment'
aws ecs wait services-stable \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --no-cli-pager &
WAITER_PID=$!

while kill -0 "${WAITER_PID}" 2>/dev/null; do
  printf '.'
  sleep "${PROGRESS_INTERVAL_SECONDS}"
done

waiter_status=0
wait "${WAITER_PID}" || waiter_status=$?
WAITER_PID=""

active_deployment_id=$(aws ecs describe-services \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --query "services[0].deployments[?status=='PRIMARY'].id | [0]" \
  --output text \
  --no-cli-pager 2>/dev/null || true)

if (( waiter_status != 0 )) || [[ "${active_deployment_id}" != "${deployment_id}" ]]; then
  echo " FAILED" >&2
  show_service_status
  exit 1
fi

trap - EXIT INT TERM
echo " COMPLETE"
