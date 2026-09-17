#!/bin/bash
# =============================================================================
# perf-profiler loop (sidecar ENTRYPOINT)
#
# Attaches async-profiler to the target JVM *across a shared PID namespace* and
# pushes rotated JFR recordings to Pyroscope. This is the whole privilege-free
# profiling trick: the pod sets shareProcessNamespace=true and this container
# holds ONLY the SYS_PTRACE capability (no privileged, no hostPID) — which is
# all async-profiler's ctimer engine needs to attach to a sibling process.
#
# Injected into a workload by the Kyverno `inject-perf-profiler` MutatingPolicy
# (add the `perf-profile/sidecar: "true"` label to the workload's pod template
# and apply — the policy matches Pods on CREATE). The app image is untouched.
# =============================================================================
set -uo pipefail

AP_HOME="${AP_HOME:-/opt/async-profiler}"
PYROSCOPE_URL="${PYROSCOPE_URL:-http://pyroscope.monitoring:4040}"
SVC="${PROFILE_SERVICE:-unknown}-eks"

# async-profiler engine / cadence (overridable via env for teaching).
AP_EVENT="${AP_EVENT:-ctimer}"      # ctimer = privilege-free CPU engine
AP_WALL="${AP_WALL:-10ms}"          # wall-clock sampling for off-CPU/blocked time
AP_INTERVAL="${AP_INTERVAL:-10ms}"
AP_LOOP="${AP_LOOP:-15s}"           # rotate a new JFR file every AP_LOOP

# Pyroscope stream name: <service>{pod=<pod>,platform=eks-sidecar}, URL-encoded.
ENC=$(printf '%s{pod=%s,platform=eks-sidecar}' "$SVC" "$HOSTNAME" \
    | sed -e 's/{/%7B/g' -e 's/}/%7D/g' -e 's/=/%3D/g' -e 's/,/%2C/g')

echo "[perf-profiler] service=$SVC; waiting for target JVM in the shared namespace..."
PID=""
while [ -z "$PID" ]; do
  for d in /proc/[0-9]*; do
    [ -r "$d/comm" ] || continue
    if [ "$(cat "$d/comm" 2>/dev/null)" = "java" ]; then PID="${d#/proc/}"; break; fi
  done
  [ -z "$PID" ] && sleep 3
done
echo "[perf-profiler] target pid=$PID"

# async-profiler loads its native agent from a path the *target* JVM can see, so
# copy libasyncProfiler.so into the target's mount namespace (/proc/$PID/root/tmp).
cp "$AP_HOME/lib/libasyncProfiler.so" "/proc/$PID/root/tmp/libasyncProfiler.so"
ASPROF="$AP_HOME/bin/asprof"

# Clear any prior session, then start a rotating ctimer+wall recording. Fall back
# to ctimer-only if the kernel/container rejects the wall-clock engine.
"$ASPROF" stop --libpath /tmp/libasyncProfiler.so "$PID" 2>/dev/null || true
"$ASPROF" start -e "$AP_EVENT" --wall "$AP_WALL" -i "$AP_INTERVAL" -o jfr \
    -f "/tmp/perf-$PID-%t.jfr" --loop "$AP_LOOP" --libpath /tmp/libasyncProfiler.so "$PID" \
  || "$ASPROF" start -e "$AP_EVENT" -i "$AP_INTERVAL" -o jfr \
    -f "/tmp/perf-$PID-%t.jfr" --loop "$AP_LOOP" --libpath /tmp/libasyncProfiler.so "$PID"
echo "[perf-profiler] async-profiler attached (event=$AP_EVENT wall=$AP_WALL loop=$AP_LOOP)"

# Ship completed (non-newest) rotated JFR files to Pyroscope, then delete them.
# The newest file is skipped because async-profiler is still writing to it.
TMP="/proc/$PID/root/tmp"
while [ -d "/proc/$PID" ]; do
  sleep 5
  set -- $(ls -1 "$TMP"/perf-"$PID"-*.jfr 2>/dev/null | sort)
  [ "$#" -lt 2 ] && continue
  last="${@: -1}"
  for f in "$@"; do
    [ "$f" = "$last" ] && continue
    sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
    if [ "$sz" -gt 0 ]; then
      code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
        -H 'Content-Type: application/octet-stream' --data-binary @"$f" \
        "$PYROSCOPE_URL/ingest?name=$ENC&format=jfr&spyName=javaspy" || echo 000)
      echo "[perf-profiler] pushed $(basename "$f") sz=$sz http=$code"
    fi
    rm -f "$f"
  done
done
echo "[perf-profiler] target gone; exiting"
