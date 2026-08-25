#!/usr/bin/env bash
set -Eeuo pipefail

SUITE_NAME="java-spring-ai-agents"
SUITE_OWNER="java-spring-ai-agents-suite"
ENVIRONMENT_DIR="${ENVIRONMENT_DIR:-${HOME}/environment}"
STATE_FILE="${SUITE_STATE_FILE:-${ENVIRONMENT_DIR}/.java-spring-ai-agents-suite.env}"
WORK_DIR="${SUITE_WORK_DIR:-${ENVIRONMENT_DIR}/.java-spring-ai-agents-suite}"
AIAGENT_DIR="${ENVIRONMENT_DIR}/aiagent"
MCPSERVER_DIR="${ENVIRONMENT_DIR}/mcpserver"
CLUSTER_NAME="${CLUSTER_NAME:-workshop-eks}"

log() { printf '[%s] %s\n' "${SUITE_NAME}" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "${SUITE_NAME}" "$*" >&2; }
die() { printf '[%s] ERROR: %s\n' "${SUITE_NAME}" "$*" >&2; exit 1; }

secure_work_dir() {
  mkdir -p "${WORK_DIR}"
  chmod 700 "${WORK_DIR}"
}

sanitize_k8s_resource_json() {
  jq '
    del(
      .metadata.creationTimestamp,
      .metadata.generation,
      .metadata.managedFields,
      .metadata.resourceVersion,
      .metadata.uid,
      .metadata.annotations."deployment.kubernetes.io/revision",
      .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
      .status
    )
    | if .kind == "Service" then
        del(.spec.clusterIP,.spec.clusterIPs,.spec.ipFamilies,.spec.ipFamilyPolicy,.spec.internalTrafficPolicy,.spec.sessionAffinity)
      else . end
  '
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

print_prerequisites() {
  log "Prerequisites: configured AWS CLI credentials, jq, curl, and access to the predeployed workshop resources."
  if (($#)); then log "This stage also requires: $*"; fi
}

load_workshop_environment() {
  if [[ -r /etc/profile.d/workshop.sh ]]; then
    set +u
    # shellcheck disable=SC1091
    source /etc/profile.d/workshop.sh
    set -u
  fi
}

load_state() {
  if [[ -r "${STATE_FILE}" ]]; then
    set +u
    # shellcheck disable=SC1090
    source "${STATE_FILE}"
    set -u
  fi
}

state_set() {
  local key="$1" value="$2" tmp
  [[ "${key}" =~ ^[A-Z0-9_]+$ ]] || die "Invalid state key: ${key}"
  [[ "${key}" != *PASSWORD* && "${key}" != *TOKEN* && "${key}" != *SECRET_VALUE* ]] || \
    die "Refusing to persist a secret-like state key: ${key}"
  mkdir -p "${ENVIRONMENT_DIR}"
  tmp=$(mktemp "${STATE_FILE}.tmp.XXXXXX")
  if [[ -f "${STATE_FILE}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      [[ "${line}" == "export ${key}="* ]] || printf '%s\n' "${line}" >> "${tmp}"
    done < "${STATE_FILE}"
  fi
  printf 'export %s=%q\n' "${key}" "${value}" >> "${tmp}"
  chmod 600 "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
  export "${key}=${value}"
}

state_unset() {
  local key="$1" tmp
  [[ -f "${STATE_FILE}" ]] || return 0
  tmp=$(mktemp "${STATE_FILE}.tmp.XXXXXX")
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" == "export ${key}="* ]] || printf '%s\n' "${line}" >> "${tmp}"
  done < "${STATE_FILE}"
  chmod 600 "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
  unset "${key}" || true
}

init_context() {
  require_cmd aws
  require_cmd jq
  load_workshop_environment
  load_state

  local discovered_account discovered_region
  discovered_account=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
  discovered_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  if [[ -z "${discovered_region}" ]]; then
    discovered_region=$(aws configure get region 2>/dev/null || true)
  fi
  [[ -n "${discovered_region}" && "${discovered_region}" != "None" ]] || die "AWS Region is not configured"

  if [[ -n "${SUITE_ACCOUNT_ID:-}" && "${SUITE_ACCOUNT_ID}" != "${discovered_account}" ]]; then
    die "State belongs to account ${SUITE_ACCOUNT_ID}; current credentials use ${discovered_account}"
  fi
  if [[ -n "${SUITE_AWS_REGION:-}" && "${SUITE_AWS_REGION}" != "${discovered_region}" ]]; then
    die "State belongs to Region ${SUITE_AWS_REGION}; current Region is ${discovered_region}"
  fi

  ACCOUNT_ID="${discovered_account}"
  AWS_REGION="${discovered_region}"
  export ACCOUNT_ID AWS_REGION AWS_DEFAULT_REGION="${AWS_REGION}"
  state_set SUITE_ACCOUNT_ID "${ACCOUNT_ID}"
  state_set SUITE_AWS_REGION "${AWS_REGION}"
  secure_work_dir
  log "Account: ${ACCOUNT_ID}; Region: ${AWS_REGION}"
}

init_context_read_only() {
  require_cmd aws
  require_cmd jq
  load_workshop_environment
  load_state

  local discovered_account discovered_region
  discovered_account=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
  discovered_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  if [[ -z "${discovered_region}" ]]; then
    discovered_region=$(aws configure get region 2>/dev/null || true)
  fi
  [[ -n "${discovered_region}" && "${discovered_region}" != "None" ]] || die "AWS Region is not configured"
  [[ -z "${SUITE_ACCOUNT_ID:-}" || "${SUITE_ACCOUNT_ID}" == "${discovered_account}" ]] || \
    die "State belongs to account ${SUITE_ACCOUNT_ID}; current credentials use ${discovered_account}"
  [[ -z "${SUITE_AWS_REGION:-}" || "${SUITE_AWS_REGION}" == "${discovered_region}" ]] || \
    die "State belongs to Region ${SUITE_AWS_REGION}; current Region is ${discovered_region}"
  ACCOUNT_ID="${discovered_account}"
  AWS_REGION="${discovered_region}"
  export ACCOUNT_ID AWS_REGION AWS_DEFAULT_REGION="${AWS_REGION}"
  log "Account: ${ACCOUNT_ID}; Region: ${AWS_REGION}"
}

aws_cli() {
  aws --region "${AWS_REGION}" --no-cli-pager "$@"
}

require_state() {
  local key
  for key in "$@"; do
    [[ -n "${!key:-}" ]] || die "Missing ${key}. Run the prerequisite stage first."
  done
}

is_none() { [[ -z "${1:-}" || "${1}" == "None" || "${1}" == "null" ]]; }

wait_for_command() {
  local description="$1" attempts="$2" interval="$3"
  shift 3
  local i
  for ((i=1; i<=attempts; i++)); do
    if "$@"; then
      log "${description}: ready"
      return 0
    fi
    ((i == attempts)) || sleep "${interval}"
  done
  die "Timed out waiting for ${description} after $((attempts * interval)) seconds"
}

http_status() {
  curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 "$1" 2>/dev/null || true
}

dns_resolves() {
  local hostname="$1"
  if command -v getent >/dev/null 2>&1; then
    getent ahosts "${hostname}" >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import socket, sys; socket.getaddrinfo(sys.argv[1], None)' "${hostname}" >/dev/null 2>&1
  else
    die "DNS readiness checks require getent or python3"
  fi
}

wait_for_ingress_hostname() {
  local description="$1" namespace="$2" ingress="$3" attempts="${4:-40}" interval="${5:-15}"
  local i
  INGRESS_HOST=""
  printf '[%s] Waiting for %s' "${SUITE_NAME}" "${description}"
  for ((i=1; i<=attempts; i++)); do
    INGRESS_HOST=$(kubectl get ingress "${ingress}" -n "${namespace}" \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    if [[ -n "${INGRESS_HOST}" ]]; then
      printf ' READY\n'
      return 0
    fi
    printf '.'
    ((i == attempts)) || sleep "${interval}"
  done
  printf '\n'
  die "Timed out waiting for ${description} after $((attempts * interval)) seconds"
}

wait_for_dns() {
  local description="$1" hostname="$2" attempts="${3:-30}" interval="${4:-10}"
  local i
  printf '[%s] Waiting for %s DNS' "${SUITE_NAME}" "${description}"
  for ((i=1; i<=attempts; i++)); do
    if dns_resolves "${hostname}"; then
      printf ' READY\n'
      return 0
    fi
    printf '.'
    ((i == attempts)) || sleep "${interval}"
  done
  printf '\n'
  die "Timed out waiting for ${description} DNS after $((attempts * interval)) seconds"
}

wait_for_http_status() {
  local description="$1" url="$2" expected_regex="$3" attempts="${4:-40}" interval="${5:-15}"
  local i http_code=""
  printf '[%s] Waiting for %s' "${SUITE_NAME}" "${description}"
  for ((i=1; i<=attempts; i++)); do
    http_code=$(http_status "${url}")
    if [[ "${http_code}" =~ ${expected_regex} ]]; then
      printf ' HTTP %s\n' "${http_code}"
      return 0
    fi
    printf '.'
    ((i == attempts)) || sleep "${interval}"
  done
  printf '\n'
  die "Timed out waiting for ${description}; last HTTP status was ${http_code:-000}"
}

require_workshop_role() {
  local role_name="$1"
  aws_cli iam get-role --role-name "${role_name}" >/dev/null || die "Required IAM role not found: ${role_name}"
}

ensure_eks_context() {
  require_cmd kubectl
  local cluster_json expected_endpoint expected_ca context_cluster context_endpoint context_ca
  cluster_json=$(aws_cli eks describe-cluster --name "${CLUSTER_NAME}" --query cluster)
  expected_endpoint=$(jq -r '.endpoint' <<<"${cluster_json}")
  expected_ca=$(jq -r '.certificateAuthority.data' <<<"${cluster_json}")
  kubectl config current-context >/dev/null 2>&1 || die "kubectl has no current context"
  context_cluster=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}')
  context_endpoint=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  context_ca=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
  [[ "${context_cluster}" == *"${CLUSTER_NAME}"* ]] || die "kubectl context does not target ${CLUSTER_NAME}: ${context_cluster}"
  [[ "${context_endpoint}" == "${expected_endpoint}" ]] || \
    die "kubectl endpoint does not match ${CLUSTER_NAME} in account ${ACCOUNT_ID}, Region ${AWS_REGION}"
  [[ -z "${context_ca}" || "${context_ca}" == "${expected_ca}" ]] || \
    die "kubectl certificate authority does not match ${CLUSTER_NAME} in account ${ACCOUNT_ID}, Region ${AWS_REGION}"
}

ensure_ecr_repository() {
  local repository="$1" templates matching
  if aws_cli ecr describe-repositories --repository-names "${repository}" >/dev/null 2>&1; then
    return 0
  fi

  templates=$(aws_cli ecr describe-repository-creation-templates)
  matching=$(jq --arg repository "${repository}" '[
    .repositoryCreationTemplates[]
    | .prefix as $prefix
    | select((.appliedFor | index("CREATE_ON_PUSH")) != null)
    | select($prefix == "ROOT" or ($repository | startswith($prefix)))
  ] | length' <<<"${templates}")
  if [[ "${matching}" -gt 0 ]]; then
    log "ECR repository ${repository} will be created by the matching CREATE_ON_PUSH template on first push"
    return 0
  fi

  die "ECR repository ${repository} does not exist and no matching CREATE_ON_PUSH template is configured"
}

build_and_push_jib() {
  local app_dir="$1" repository="$2" tag="${3:-latest}"
  require_cmd docker
  require_cmd mvn
  ensure_ecr_repository "${repository}"
  local registry="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  aws_cli ecr get-login-password | docker login --username AWS --password-stdin "${registry}"
  (cd "${app_dir}" && mvn -ntp compile jib:build -Dimage="${registry}/${repository}:${tag}" -DskipTests)
}

upsert_pod_identity() {
  local namespace="$1" service_account="$2" role_arn="$3" prefix="$4"
  local association_id current_role response
  association_id=$(aws_cli eks list-pod-identity-associations --cluster-name "${CLUSTER_NAME}" \
    --query "associations[?namespace=='${namespace}' && serviceAccount=='${service_account}'].associationId | [0]" --output text)
  if is_none "${association_id}"; then
    response=$(aws_cli eks create-pod-identity-association --cluster-name "${CLUSTER_NAME}" \
      --namespace "${namespace}" --service-account "${service_account}" --role-arn "${role_arn}")
    association_id=$(jq -r '.association.associationId' <<<"${response}")
    state_set "${prefix}_POD_IDENTITY_CREATED" true
  else
    current_role=$(aws_cli eks describe-pod-identity-association --cluster-name "${CLUSTER_NAME}" \
      --association-id "${association_id}" --query 'association.roleArn' --output text)
    local created_var="${prefix}_POD_IDENTITY_CREATED" original_role_var="${prefix}_ORIGINAL_POD_ROLE_ARN"
    if [[ "${!created_var:-}" != true ]]; then
      state_set "${prefix}_POD_IDENTITY_CREATED" false
      [[ -n "${!original_role_var:-}" ]] || state_set "${prefix}_ORIGINAL_POD_ROLE_ARN" "${current_role}"
    fi
    if [[ "${current_role}" != "${role_arn}" ]]; then
      aws_cli eks update-pod-identity-association --cluster-name "${CLUSTER_NAME}" \
        --association-id "${association_id}" --role-arn "${role_arn}" >/dev/null
    fi
  fi
  state_set "${prefix}_POD_IDENTITY_ID" "${association_id}"
}

backup_k8s_resource() {
  local namespace="$1" kind="$2" name="$3" state_key="$4" backup_dir backup_file existing_json get_error
  local existing_path="${!state_key:-}"
  [[ -z "${existing_path}" ]] || return 0
  get_error=$(mktemp "${WORK_DIR}/k8s-read.XXXXXX")
  chmod 600 "${get_error}"
  if existing_json=$(kubectl get "${kind}" "${name}" -n "${namespace}" -o json 2>"${get_error}"); then
    backup_dir="${WORK_DIR}/k8s-backups"
    mkdir -p "${backup_dir}"
    chmod 700 "${backup_dir}"
    backup_file="${backup_dir}/${namespace}-${kind}-${name}.json"
    sanitize_k8s_resource_json <<<"${existing_json}" > "${backup_file}"
    chmod 600 "${backup_file}"
    state_set "${state_key}" "${backup_file}"
  elif ! grep -Eq '^Error from server \(NotFound\):' "${get_error}"; then
    die "Could not inspect ${kind} ${namespace}/${name} before reconciliation: $(tr '\n' ' ' < "${get_error}")"
  fi
  rm -f "${get_error}"
}

get_mcp_url() {
  local host
  host=$(kubectl get ingress mcpserver -n mcpserver -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [[ -n "${host}" ]] || return 1
  printf 'http://%s' "${host}"
}

get_cognito_issuer() {
  require_state COGNITO_USER_POOL_ID
  printf 'https://cognito-idp.%s.amazonaws.com/%s' "${AWS_REGION}" "${COGNITO_USER_POOL_ID}"
}

encode_b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
decode_b64() {
  if printf '' | base64 --decode >/dev/null 2>&1; then
    printf '%s' "$1" | base64 --decode
  else
    printf '%s' "$1" | base64 -D
  fi
}
