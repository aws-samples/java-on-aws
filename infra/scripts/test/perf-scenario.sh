#!/usr/bin/env bash
# ============================================================================
# perf-scenario.sh
# Build + deploy + measure the optimization variants of unicorn-store-spring
# on EKS, applying the VALIDATED right-sizing/GC, preserving state in git+ECR.
#
# RUN THIS ON THE amd64 "ide" INSTANCE (it matches the amd64 EKS nodes — required
# for CRaC checkpoint + AOT cache; do NOT build these on an arm64 box).
#
# Validated config (from live experiments): request ~512Mi (near the ~380MB RSS
# floor), limit 768Mi, 1 vCPU; SerialGC + MaxRAMPercentage=75 (G1 regresses here).
#
# Variants (default: all, in order):
#   rightsize  current image, right-sized + SerialGC/heap via JAVA_TOOL_OPTIONS
#   aot        Dockerfile.06-aot  -> :aot   (SerialGC/heap via JAVA_TOOL_OPTIONS)
#   crac       Dockerfile.08-crac -> :crac  (GC/heap are BAKED at checkpoint;
#                                            no runtime JAVA_TOOL_OPTIONS — it
#                                            would conflict with the checkpoint)
#   boost      baseline booted at 2 vCPU, then IN-PLACE resize CPU->1 (no restart)
#
# Usage:  bash perf-scenario.sh                 # all
#         bash perf-scenario.sh rightsize aot   # subset
#         bash perf-scenario.sh crac            # just CRaC
# ============================================================================
set -uo pipefail

NS=${NS:-unicorn-store-spring}
APP=${APP:-unicorn-store-spring}
REGION=${AWS_REGION:-us-east-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_BASE=${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
REPO=${ECR_BASE}/${APP}
OUT=${OUT:-$HOME/perf-scenario-out}; mkdir -p "$OUT"
RES=$OUT/results.md
BUCKET=$(aws ssm get-parameter --name workshop-bucket-name --query Parameter.Value --output text 2>/dev/null || true)

# Validated right-size + GC
REQ_CPU=${REQ_CPU:-250m}; REQ_MEM=${REQ_MEM:-512Mi}; LIM_CPU=${LIM_CPU:-1}; LIM_MEM=${LIM_MEM:-768Mi}
JTO_SERIAL="-XX:+UseSerialGC -XX:MaxRAMPercentage=75 -XX:InitialRAMPercentage=50"

# Locate sources on the instance
DF_DIR=${DF_DIR:-$HOME/java-on-aws/apps/dockerfiles}
APP_SRC=${APP_SRC:-$HOME/java-on-aws/apps/unicorn-store-spring}
[ -f "$APP_SRC/pom.xml" ] || APP_SRC=$HOME/environment/unicorn-store-spring

log(){ echo -e "\n=== $* ==="; }
die(){ echo "ERROR: $*" >&2; exit 1; }

VARIANTS=("$@"); [ ${#VARIANTS[@]} -eq 0 ] && VARIANTS=(rightsize aot crac boost)

log "config"
echo "cluster ns=$NS app=$APP  repo=$REPO"
echo "right-size: req ${REQ_CPU}/${REQ_MEM}  lim ${LIM_CPU}/${LIM_MEM}  GC='${JTO_SERIAL}'"
echo "app source: $APP_SRC   dockerfiles: $DF_DIR"
echo "variants: ${VARIANTS[*]}"
kubectl get deploy "$APP" -n "$NS" >/dev/null 2>&1 || die "deployment $APP not found in ns $NS (is kubectl pointed at the cluster?)"
[ -f "$APP_SRC/pom.xml" ] || die "app source with pom.xml not found (set APP_SRC=...)"

# Back up original deployment so you can revert
kubectl get deploy "$APP" -n "$NS" -o yaml > "$OUT/ORIGINAL-deployment.yaml"
echo "backed up original deployment -> $OUT/ORIGINAL-deployment.yaml"
# Capture the true baseline image ONCE, before any variant swaps it (so 'boost'
# and 'rightsize' never accidentally reuse the CRaC/AOT image).
BASE_IMG=$(kubectl -n "$NS" get deploy "$APP" -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "baseline image: $BASE_IMG"
echo "| variant | Spring 'Started in' | CRaC restore line | RSS | restarts | time→Ready |" >  "$RES"
echo "|---|---|---|---|---|---|"                                                          >> "$RES"

ecr_login(){ aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_BASE" >/dev/null; }
ensure_repo(){ aws ecr describe-repositories --repository-names "$APP" >/dev/null 2>&1 || aws ecr create-repository --repository-name "$APP" >/dev/null; }

db_args(){
  local url user pass secret
  url=$(aws ssm get-parameter --name workshop-db-connection-string --query Parameter.Value --output text 2>/dev/null || true)
  secret=$(aws secretsmanager get-secret-value --secret-id workshop-db-secret --query SecretString --output text 2>/dev/null || true)
  user=$(echo "$secret" | jq -r .username 2>/dev/null); pass=$(echo "$secret" | jq -r .password 2>/dev/null)
  DB_BUILD_ARGS=()
  if [ -n "$url" ] && [ "$url" != "None" ]; then
    DB_BUILD_ARGS=(--build-arg "SPRING_DATASOURCE_URL=$url" --build-arg "SPRING_DATASOURCE_USERNAME=$user" --build-arg "SPRING_DATASOURCE_PASSWORD=$pass")
    echo "using DB build-args for training/checkpoint"
  else
    echo "no DB params found; building without DB (training excludes DB auto-config)"
  fi
}

build_push(){ # $1=dockerfile  $2=tag
  local df=$1 tag=$2
  log "build $tag  ($df)"
  docker build --progress=plain -f "$DF_DIR/$df" "${DB_BUILD_ARGS[@]}" -t "$REPO:$tag" "$APP_SRC" || die "docker build $df failed"
  docker push "$REPO:$tag" || die "docker push $tag failed"
}

rightsize(){
  kubectl -n "$NS" patch deployment "$APP" --type=strategic -p \
   '{"spec":{"template":{"spec":{"containers":[{"name":"'"$APP"'","resources":{"requests":{"cpu":"'"$REQ_CPU"'","memory":"'"$REQ_MEM"'"},"limits":{"cpu":"'"$LIM_CPU"'","memory":"'"$LIM_MEM"'"}}}]}}}}' >/dev/null
}

set_jto(){ # $1=value or "-" to remove
  if [ "$1" = "-" ]; then kubectl -n "$NS" set env deployment/"$APP" JAVA_TOOL_OPTIONS- >/dev/null
  else kubectl -n "$NS" set env deployment/"$APP" JAVA_TOOL_OPTIONS="$1" >/dev/null; fi
}

measure(){ # $1=variant label
  local v=$1 pod started restore rss restarts created ready csec rsec delta rss_mb
  kubectl -n "$NS" rollout status deployment/"$APP" --timeout=360s || echo "WARN: rollout not complete for $v"
  sleep 20
  pod=$(kubectl -n "$NS" get pods -l app="$APP" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  [ -z "$pod" ] && { echo "| $v | NO RUNNING POD |||||" >> "$RES"; return; }
  started=$(kubectl -n "$NS" logs "$pod" -c "$APP" 2>/dev/null | grep -oE '(Started|Restored) [A-Za-z]+ in [0-9.]+ seconds' | tail -1)
  restore=$(kubectl -n "$NS" logs "$pod" -c "$APP" 2>/dev/null | grep -iE 'restor|checkpoint' | tail -1 | cut -c1-70)
  rss=$(kubectl -n "$NS" exec "$pod" -c "$APP" -- sh -c 'cat /sys/fs/cgroup/memory.current 2>/dev/null' 2>/dev/null)
  rss_mb=$(( ${rss:-0} / 1048576 ))
  restarts=$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.containerStatuses[?(@.name=="'"$APP"'")].restartCount}' 2>/dev/null)
  created=$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)
  ready=$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)
  csec=$(date -d "$created" +%s 2>/dev/null || echo 0); rsec=$(date -d "$ready" +%s 2>/dev/null || echo 0)
  delta=$(( rsec - csec ))
  echo "| $v | ${started:-n/a} | ${restore:-} | ${rss_mb}Mi | ${restarts:-?} | ${delta}s |" >> "$RES"
  kubectl -n "$NS" get deploy "$APP" -o yaml > "$OUT/${v}-deployment.yaml" 2>/dev/null
  kubectl -n "$NS" logs "$pod" -c "$APP" --tail=60 > "$OUT/${v}-startup.log" 2>/dev/null
  echo ">>> $v: startup='${started:-n/a}' restore='${restore:-}' rss=${rss_mb}Mi restarts=${restarts} ready=${delta}s"
}

deploy_measure(){ # $1=tag $2=jto $3=label
  kubectl -n "$NS" set image deployment/"$APP" "$APP=$REPO:$1" >/dev/null
  rightsize; set_jto "$2"; measure "$3"
}

ecr_login; ensure_repo; db_args

for v in "${VARIANTS[@]}"; do
  case "$v" in
    rightsize)
      log "VARIANT rightsize (baseline image + right-size + SerialGC)"
      deploy_measure "${BASE_IMG##*:}" "$JTO_SERIAL" "rightsize" ;;
    aot)
      build_push Dockerfile.06-aot aot
      log "VARIANT aot (right-size + SerialGC via env)"
      deploy_measure aot "$JTO_SERIAL" "aot" ;;
    crac)
      build_push Dockerfile.08-crac crac
      log "VARIANT crac (checkpoint-baked flags; NO runtime JAVA_TOOL_OPTIONS)"
      deploy_measure crac "-" "crac" ;;
    boost)
      log "VARIANT boost (baseline image booted at 2 vCPU, then in-place resize CPU->1, no restart)"
      kubectl -n "$NS" set image deployment/"$APP" "$APP=$BASE_IMG" >/dev/null
      set_jto "$JTO_SERIAL"
      kubectl -n "$NS" patch deployment "$APP" --type=strategic -p \
        '{"spec":{"template":{"spec":{"containers":[{"name":"'"$APP"'","resources":{"requests":{"cpu":"1","memory":"'"$REQ_MEM"'"},"limits":{"cpu":"2","memory":"'"$LIM_MEM"'"}}}]}}}}' >/dev/null
      measure "boost-2cpu"
      POD=$(kubectl -n "$NS" get pods -l app="$APP" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
      echo "in-place resize CPU 2->1 on $POD (expect NO restart)..."
      kubectl -n "$NS" patch pod "$POD" --subresource=resize --type=merge -p \
        '{"spec":{"containers":[{"name":"'"$APP"'","resources":{"requests":{"cpu":"'"$REQ_CPU"'","memory":"'"$REQ_MEM"'"},"limits":{"cpu":"'"$LIM_CPU"'","memory":"'"$LIM_MEM"'"}}}]}}' \
        && echo "in-place resize applied" || echo "WARN: in-place resize failed (check resizePolicy / K8s version)"
      sleep 6
      echo "after resize: restarts=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}')  cpuLim=$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[0].resources.limits.cpu}')"
      echo "| boost-after-resize | (in-place, no rebuild) | | | $(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}') restarts | cpuLim now $(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[0].resources.limits.cpu}') |" >> "$RES" ;;
    *) echo "unknown variant '$v' (rightsize|aot|crac|boost)";;
  esac
done

log "RESULTS"
cat "$RES"
echo
echo "artifacts in $OUT (deployment yamls + startup logs + results.md)"
echo "images tagged in ECR: $REPO:{aot,crac,...}"
echo "revert to original:  kubectl apply -f $OUT/ORIGINAL-deployment.yaml"

# Push results back to S3 for review
if [ -n "$BUCKET" ]; then
  aws s3 cp "$OUT" "s3://$BUCKET/perf-scenario/results/" --recursive >/dev/null 2>&1 \
    && echo "results uploaded -> s3://$BUCKET/perf-scenario/results/"
fi
