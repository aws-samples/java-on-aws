#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="unicorn-store-spring"
DURATION=60
EVENT="${1:-wall}"   # default: wall, you can pass cpu, alloc, lock...
RPS=200

# --- Find pod and PID ---
POD_NAME=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
PID=$(kubectl exec $POD_NAME -n $NAMESPACE -- jps | grep store-spring | awk '{print $1}')

SVC_URL=$(~/java-on-aws/infrastructure/scripts/test/getsvcurl.sh eks)
echo "Using pod=$POD_NAME, PID=$PID, event=$EVENT, duration=${DURATION}s, target=$SVC_URL"

# --- Cleanup old profiles ---
kubectl exec $POD_NAME -n $NAMESPACE -- sh -c "rm -f /tmp/profile-*.html /tmp/asprof.log || true"

# --- Trap for cleanup ---
cleanup() {
  echo "--- Caught interrupt, cleaning up ---"
  if [[ -n "${BENCH_PID:-}" ]]; then
    kill "$BENCH_PID" 2>/dev/null || true
  fi
  # Try to stop profiler gracefully
  kubectl exec $POD_NAME -n $NAMESPACE -- \
    /async-profiler/bin/asprof stop -f /tmp/profile-interrupted.html $PID \
    >/dev/null 2>&1 || true
  # Copy interrupted profile if it exists
  if kubectl exec $POD_NAME -n $NAMESPACE -- test -f /tmp/profile-interrupted.html; then
    kubectl cp "$NAMESPACE/$POD_NAME:/tmp/profile-interrupted.html" "./profile-${EVENT}-interrupted-$(date +%Y%m%d-%H%M%S).html"
    echo "⚠️ Interrupted: partial profile saved."
  fi
  exit 1
}
trap cleanup INT TERM

echo "--- Start benchmark in background ---"
~/java-on-aws/infrastructure/scripts/test/benchmark.sh $SVC_URL $DURATION $RPS &
BENCH_PID=$!

echo "--- Run profiler (same user as JVM) ---"
kubectl exec $POD_NAME -n $NAMESPACE -- \
  /async-profiler/bin/asprof -d $DURATION -e $EVENT -f /tmp/profile-%t.html $PID \
  || true

# --- Wait for benchmark to finish ---
wait $BENCH_PID || true

echo "--- Fetch newest profile ---"
PROFILE_FILE=$(kubectl exec $POD_NAME -n $NAMESPACE -- \
  sh -c "ls -t /tmp/profile-*.html | head -1" | tr -d '\r')
LOCAL_FILE="./profile-${EVENT}-$(date +%Y%m%d-%H%M%S).html"

kubectl cp "$NAMESPACE/$POD_NAME:$PROFILE_FILE" "$LOCAL_FILE"

echo "🔥 Profile saved as $LOCAL_FILE"
echo "👉 Open it in your browser to view the flame graph"
