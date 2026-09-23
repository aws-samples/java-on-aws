#!/bin/bash
# =============================================================================
# verify.sh — end-of-bootstrap checks for the java-on-amazon-eks environment.
#
# Each check names what a participant would hit if it failed. Waits for the two things
# that are legitimately still provisioning when the platform installs finish (the
# app's ALB, the sensor's first measurement); everything else must already be there.
# Exit 1 on the first hard failure so the bootstrap signals FAILURE, not a green stack
# with a broken session.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
[ -f /etc/profile.d/workshop.sh ] && source /etc/profile.d/workshop.sh

APP_NS="unicorn-store-spring"
ENV_DIR="${HOME}/environment"
FAIL=0
fail() { log_error "$*"; FAIL=1; }

# 1. Application answers through the ALB (the load script needs it).
log_info "Waiting for the application's ALB..."
URL=""
for _ in $(seq 1 60); do
  HOST="$(kubectl -n "${APP_NS}" get ingress "${APP_NS}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [ -n "${HOST}" ] && [ "$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "http://${HOST}/actuator/health" || true)" = "200" ]; then
    URL="http://${HOST}"; break
  fi
  sleep 5
done
[ -n "${URL}" ] && log_success "Application: ${URL}" || fail "Application not reachable through the ALB after 5 min"

# 2. Starting-point repo and files the pages rely on.
[ -d "${ENV_DIR}/${APP_NS}/.git" ] || fail "${ENV_DIR}/${APP_NS} is not a git repo"
git -C "${ENV_DIR}/${APP_NS}" log --format=%s -n 1 2>/dev/null | grep -q "^Starting point" \
  && log_success "Starting-point commit present" || fail "starting-point commit missing"
for f in k8s/deployment.yaml scripts/load.sh scripts/build.sh CLAUDE.md; do
  [ -f "${ENV_DIR}/${APP_NS}/${f}" ] || fail "missing ${f} in the participant repo"
done
grep -q "org.crac" "${ENV_DIR}/${APP_NS}/pom.xml" && fail "pom.xml still carries org.crac (de-spoil failed)"
grep -q "perf-profile/sidecar" "${ENV_DIR}/${APP_NS}/k8s/deployment.yaml" && fail "deployment.yaml already carries the profiler label"

# 3. Prebuilt fallback tags.
for tag in aot-prebuilt crac-prebuilt; do
  aws ecr describe-images --repository-name "${APP_NS}" --image-ids imageTag="${tag}" >/dev/null 2>&1 \
    || fail "ECR ${APP_NS}:${tag} missing"
done

# 4. Platform: profiler policy, boost controller, sensor.
kubectl get mutatingpolicy inject-perf-profiler >/dev/null 2>&1 && log_success "Sidecar inject policy present" || fail "MutatingPolicy inject-perf-profiler missing"
kubectl -n kube-startup-cpu-boost-system get deploy kube-startup-cpu-boost-controller-manager >/dev/null 2>&1 \
  && log_success "Startup CPU Boost controller present" || log_warning "Startup CPU Boost controller missing (manual resize path still works)"
kubectl -n monitoring rollout status deploy/perf-sensor --timeout=60s >/dev/null 2>&1 && log_success "perf-sensor Ready" || fail "perf-sensor not Ready"

# 5. Sensor answers with facts for the app (measure over a port-forward).
kubectl -n monitoring port-forward svc/perf-sensor 18090:8080 >/dev/null 2>&1 &
PF=$!
sleep 4
M="$(curl -s --max-time 60 "localhost:18090/api/v1/measure/${APP_NS}" || true)"
kill "${PF}" 2>/dev/null || true
echo "${M}" | jq -e '.workload.memLimitMi != null and .runtime.uptimeSeconds != null' >/dev/null 2>&1 \
  && log_success "perf-sensor measures ${APP_NS} (limit $(echo "${M}" | jq -r .workload.memLimitMi) Mi, uptime $(echo "${M}" | jq -r .runtime.uptimeSeconds) s)" \
  || fail "perf-sensor returned no workload/runtime facts for ${APP_NS}: $(echo "${M}" | head -c 300)"

# 6. Claude Code wiring on the IDE.
[ -f "${ENV_DIR}/.mcp.json" ] && jq -e '.mcpServers["perf-sensor"] and .mcpServers["eks-mcp"]' "${ENV_DIR}/.mcp.json" >/dev/null \
  && log_success ".mcp.json has perf-sensor + eks-mcp" || fail ".mcp.json missing or incomplete"
jq -e '.permissions.deny | index("Bash")' "${ENV_DIR}/.claude/settings.json" >/dev/null 2>&1 \
  && log_success "settings.json denies Bash" || fail "settings.json does not deny Bash"
for s in java-on-eks-checklist java-on-eks-optimization; do
  [ -f "${ENV_DIR}/.claude/skills/${s}/SKILL.md" ] || fail "skill ${s} missing"
done
command -v claude >/dev/null 2>&1 || [ -x "${HOME}/.local/bin/claude" ] || fail "claude CLI not installed"

if [ "${FAIL}" -eq 0 ]; then
  echo "✅ Success: java-on-amazon-eks environment verified (app ${URL})"
else
  echo "❌ java-on-amazon-eks environment has failures (see above)"
  exit 1
fi
