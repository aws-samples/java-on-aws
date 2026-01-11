#!/bin/bash
# Build and optionally deploy/test all optimization images
#
# Prerequisites: containerize.sh and eks.sh must be run first
#
# Usage:
#   ./test-optimizations.sh --pre-clean --deploy --revert  # Full test: clean, build all, deploy, measure, revert
#   ./test-optimizations.sh                                # Build all images locally
#   ./test-optimizations.sh --only cds                     # Build single method
#   ./test-optimizations.sh --only cds --deploy            # Build, push, deploy single method

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
APP_DIR="${REPO_ROOT}/apps/unicorn-store-spring"
DOCKERFILES_DIR="${REPO_ROOT}/apps/dockerfiles"
IMAGE_NAME="unicorn-store-spring"

# Output directory (use /tmp if writable, otherwise script dir)
if [[ -w /tmp ]]; then
    OUTPUT_DIR="/tmp/test-optimizations"
else
    OUTPUT_DIR="${SCRIPT_DIR}/.test-optimizations"
fi

# Cleanup on exit/interrupt
cleanup() {
    local exit_code=$?
    log_info "Cleaning up..."

    # Kill watcher if running
    if [[ -f "${WATCHER_PID_FILE}" ]]; then
        local pid=$(cat "${WATCHER_PID_FILE}")
        kill "$pid" 2>/dev/null || true
        rm -f "${WATCHER_PID_FILE}"
    fi

    # Stop build database if running
    docker rm -f build-postgres 2>/dev/null || true

    # Restore UnicornPublisher if backup exists
    if [[ -f "${APP_DIR}/src/main/java/com/unicorn/store/data/UnicornPublisher.java.orig" ]]; then
        mv "${APP_DIR}/src/main/java/com/unicorn/store/data/UnicornPublisher.java.orig" \
           "${APP_DIR}/src/main/java/com/unicorn/store/data/UnicornPublisher.java"
    fi

    # Revert deployment to baseline if --revert flag is set
    if [[ "$REVERT_MODE" == true && "$DEPLOY_MODE" == true && -n "$ACCOUNT_ID" ]]; then
        log_info "Reverting deployment to :latest..."
        local ecr_uri="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}"
        kubectl set image deployment/unicorn-store-spring \
            unicorn-store-spring="${ecr_uri}:latest" -n unicorn-store-spring 2>/dev/null || true
    fi

    exit $exit_code
}
trap cleanup EXIT INT TERM
QUEUE_FILE="${OUTPUT_DIR}/queue.txt"
RESULTS_FILE="${OUTPUT_DIR}/results.txt"
WATCHER_PID_FILE="${OUTPUT_DIR}/watcher.pid"

# Methods in order (tag names)
METHODS=(
    "01-multi-stage"
    "01-multi-stage-2cpu"
    "01-multi-stage-pod-resize"
    "02-jib"
    "03-custom-jre"
    "04-soci"
    "05-cds"
    "06-aot"
    "07-native"
    "08-crac"
)

# Parse arguments
DEPLOY_MODE=false
REVERT_MODE=false
PRE_CLEAN=false
ONLY_METHOD=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --deploy) DEPLOY_MODE=true; shift ;;
        --revert) REVERT_MODE=true; shift ;;
        --pre-clean) PRE_CLEAN=true; shift ;;
        --only) ONLY_METHOD="$2"; shift 2 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Filter methods if --only specified
if [[ -n "${ONLY_METHOD}" ]]; then
    found=false
    for m in "${METHODS[@]}"; do
        if [[ "$m" == *"${ONLY_METHOD}"* ]]; then
            METHODS=("$m")
            found=true
            break
        fi
    done
    if [[ "$found" == false ]]; then
        log_error "Method '${ONLY_METHOD}' not found"
        exit 1
    fi
fi

# Check if method needs DB for training
needs_db() {
    case "$1" in
        05-cds|06-aot|08-crac) return 0 ;;
        *) return 1 ;;
    esac
}

# Check if method needs code changes (CRaC)
needs_code_change() {
    [[ "$1" == "08-crac" ]]
}

# Check if method is a deploy-only variant (uses 01-multi-stage image)
is_deploy_variant() {
    case "$1" in
        01-multi-stage-2cpu|01-multi-stage-pod-resize) return 0 ;;
        *) return 1 ;;
    esac
}

# Database configuration - try AWS first, fallback to local Docker
USE_AWS_DB=false
SPRING_DATASOURCE_URL=""
SPRING_DATASOURCE_USERNAME=""
SPRING_DATASOURCE_PASSWORD=""

init_db_config() {
    log_info "Checking for AWS database configuration..."

    # Try to get AWS database credentials
    local aws_url aws_secret
    aws_url=$(aws ssm get-parameter --name workshop-db-connection-string --no-cli-pager 2>/dev/null | jq --raw-output '.Parameter.Value' 2>/dev/null) || true
    aws_secret=$(aws secretsmanager get-secret-value --secret-id workshop-db-secret --no-cli-pager 2>/dev/null | jq --raw-output '.SecretString' 2>/dev/null) || true

    if [[ -n "$aws_url" && "$aws_url" != "null" && -n "$aws_secret" && "$aws_secret" != "null" ]]; then
        SPRING_DATASOURCE_URL="$aws_url"
        SPRING_DATASOURCE_USERNAME=$(echo "$aws_secret" | jq -r .username)
        SPRING_DATASOURCE_PASSWORD=$(echo "$aws_secret" | jq -r .password)

        if [[ -n "$SPRING_DATASOURCE_USERNAME" && "$SPRING_DATASOURCE_USERNAME" != "null" ]]; then
            USE_AWS_DB=true
            log_info "Using AWS RDS database for training"
            return 0
        fi
    fi

    log_info "AWS database not available, will use local Docker PostgreSQL"
    USE_AWS_DB=false
}

# Start PostgreSQL for training (only if not using AWS DB)
start_build_db() {
    if [[ "$USE_AWS_DB" == true ]]; then
        log_info "Using AWS RDS database (no local DB needed)"
        return 0
    fi

    log_info "Starting PostgreSQL for training..."
    docker rm -f build-postgres 2>/dev/null || true
    docker run -d --name build-postgres \
        -e POSTGRES_DB=unicornstore \
        -e POSTGRES_USER=unicorn \
        -e POSTGRES_PASSWORD=unicorn \
        -p 5432:5432 \
        postgres:16-alpine >/dev/null

    sleep 3
    until docker exec build-postgres pg_isready -U unicorn -d unicornstore >/dev/null 2>&1; do
        sleep 1
    done

    # Set local DB credentials
    SPRING_DATASOURCE_URL="jdbc:postgresql://host.docker.internal:5432/unicornstore"
    SPRING_DATASOURCE_USERNAME="unicorn"
    SPRING_DATASOURCE_PASSWORD="unicorn"

    log_info "PostgreSQL ready"
}

stop_build_db() {
    if [[ "$USE_AWS_DB" == true ]]; then
        return 0
    fi
    docker rm -f build-postgres 2>/dev/null || true
}

# CRaC code swap
crac_pre_build() {
    log_info "Swapping UnicornPublisher for CRaC..."
    cp "${APP_DIR}/src/main/java/com/unicorn/store/data/UnicornPublisher.java" \
       "${APP_DIR}/src/main/java/com/unicorn/store/data/UnicornPublisher.java.orig"
    cp "${APP_DIR}/src/main/java/com/unicorn/store/data/UnicornPublisher.crac" \
       "${APP_DIR}/src/main/java/com/unicorn/store/data/UnicornPublisher.java"
}

crac_post_build() {
    log_info "Restoring UnicornPublisher..."
    mv "${APP_DIR}/src/main/java/com/unicorn/store/data/UnicornPublisher.java.orig" \
       "${APP_DIR}/src/main/java/com/unicorn/store/data/UnicornPublisher.java"
}

# Format elapsed time
format_time() {
    local seconds=$1
    if (( seconds >= 60 )); then
        printf "%dm%ds" $((seconds/60)) $((seconds%60))
    else
        printf "%ds" $seconds
    fi
}

# Build single image
build_image() {
    local tag="$1"
    local log_file="$2"
    local build_args=""

    log_info "Building ${tag}..."

    # Deploy variants use 01-multi-stage image - no build needed
    if is_deploy_variant "$tag"; then
        log_info "Deploy variant, using 01-multi-stage image..."
        return 0
    fi

    # Special case: jib uses maven
    if [[ "$tag" == "02-jib" ]]; then
        log_info "Using Maven Jib plugin..."
        (cd "${APP_DIR}" && mvn compile jib:dockerBuild -Dimage=${IMAGE_NAME}:${tag}) >> "${log_file}" 2>&1
        return $?
    fi

    # Special case: CDS uses Paketo Buildpacks
    if [[ "$tag" == "05-cds" ]]; then
        log_info "Using Paketo Buildpacks for CDS..."

        # Install pack CLI if not available
        if ! command -v pack &> /dev/null; then
            log_info "Installing pack CLI..."
            curl -sSL "https://github.com/buildpacks/pack/releases/download/v0.38.2/pack-v0.38.2-linux.tgz" | \
                sudo tar -C /usr/local/bin/ --no-same-owner -xzv pack >> "${log_file}" 2>&1
        fi

        start_build_db
        pack build "${IMAGE_NAME}:${tag}" \
            --builder paketobuildpacks/builder-noble-java-tiny \
            --path "${APP_DIR}" \
            --env BP_JVM_VERSION=25 \
            --env BP_JVM_CDS_ENABLED=true \
            --env BPL_JVM_CDS_ENABLED=true \
            --env SPRING_DATASOURCE_URL="${SPRING_DATASOURCE_URL}" \
            --env SPRING_DATASOURCE_USERNAME="${SPRING_DATASOURCE_USERNAME}" \
            --env SPRING_DATASOURCE_PASSWORD="${SPRING_DATASOURCE_PASSWORD}" \
            >> "${log_file}" 2>&1
        local result=$?
        stop_build_db
        return $result
    fi

    # Dockerfile name matches tag (e.g., 01-multi-stage -> Dockerfile.01-multi-stage)
    local dockerfile="${DOCKERFILES_DIR}/Dockerfile.${tag}"

    # Check Dockerfile exists
    if [[ ! -f "${dockerfile}" ]]; then
        log_error "Dockerfile not found: ${dockerfile}"
        echo "ERROR: Dockerfile not found: ${dockerfile}" >> "${log_file}"
        return 1
    fi

    # Pre-build hooks
    if needs_code_change "$tag"; then
        crac_pre_build
    fi

    # Start DB if needed and set build args (all methods use same SPRING_DATASOURCE_* args)
    if needs_db "$tag"; then
        start_build_db
        build_args="--build-arg SPRING_DATASOURCE_URL=${SPRING_DATASOURCE_URL}"
        build_args="${build_args} --build-arg SPRING_DATASOURCE_USERNAME=${SPRING_DATASOURCE_USERNAME}"
        build_args="${build_args} --build-arg SPRING_DATASOURCE_PASSWORD=${SPRING_DATASOURCE_PASSWORD}"
    fi

    # Build with --progress=plain for cleaner logs
    # Use --no-cache for consistent, reproducible build times
    local result=0
    docker build --progress=plain --no-cache ${build_args} -f "${dockerfile}" -t "${IMAGE_NAME}:${tag}" "${APP_DIR}" >> "${log_file}" 2>&1 || result=$?

    # Cleanup
    if needs_db "$tag"; then
        stop_build_db
    fi

    # Post-build hooks
    if needs_code_change "$tag"; then
        crac_post_build
    fi

    return $result
}

# Push image to ECR and return ECR size
# Returns: "SIZE" on success, "PUSH_FAILED:reason" on failure
push_image() {
    local tag="$1"
    local log_file="$2"
    local ecr_uri="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}"

    echo "=== PUSH ${tag} ===" >> "${log_file}"
    docker tag "${IMAGE_NAME}:${tag}" "${ecr_uri}:${tag}"

    # Capture push output for error reporting and logging
    local push_output
    if ! push_output=$(docker push "${ecr_uri}:${tag}" 2>&1); then
        echo "$push_output" >> "${log_file}"
        # Extract last meaningful error line
        local error_msg=$(echo "$push_output" | grep -iE '(error|denied|failed|unauthorized)' | tail -1 | cut -c1-50)
        echo "PUSH_FAILED:${error_msg:-push failed}"
        return 1
    fi
    echo "$push_output" >> "${log_file}"

    # SOCI index for soci method
    if [[ "$tag" == "04-soci" ]]; then
        echo "=== SOCI INDEX ===" >> "${log_file}"
        sudo soci create "${ecr_uri}:${tag}" >> "${log_file}" 2>&1 || true
        sudo soci push "${ecr_uri}:${tag}" >> "${log_file}" 2>&1 || true
    fi

    # Get ECR image size
    local ecr_size=$(aws ecr describe-images --repository-name "${IMAGE_NAME}" \
        --image-ids imageTag="${tag}" --query 'imageDetails[0].imageSizeInBytes' \
        --output text 2>/dev/null | awk '{printf "%.0fMB", $1/1024/1024}')
    echo "${ecr_size:-N/A}"
}

# Get startup time from pod logs
get_startup_time() {
    local tag="$1"
    local log_pattern="Started StoreApplication"
    [[ "$tag" == "08-crac" ]] && log_pattern="Restored StoreApplication"

    kubectl logs $(kubectl get pods -n unicorn-store-spring -o json \
        | jq --raw-output '.items[0].metadata.name') -n unicorn-store-spring 2>/dev/null \
        | grep "${log_pattern}" | tail -1 | grep -oE '[0-9]+\.[0-9]+ seconds' || echo "N/A"
}

# Deploy watcher - runs in background, reads queue, deploys and measures
deploy_watcher() {
    local ecr_uri="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}"

    # Initialize results file
    echo "Method | Size Local | Size ECR | Build Time | Startup Time" > "${RESULTS_FILE}"
    echo "-------|------------|----------|------------|-------------" >> "${RESULTS_FILE}"

    local last_line_num=0

    while true; do
        # Read new lines from queue
        if [[ -f "${QUEUE_FILE}" ]]; then
            local current_lines=$(wc -l < "${QUEUE_FILE}")

            while (( last_line_num < current_lines )); do
                last_line_num=$((last_line_num + 1))
                local line=$(sed -n "${last_line_num}p" "${QUEUE_FILE}")
                IFS='|' read -r status tag size_local size_ecr build_time error_msg <<< "$line"

                # Check for END marker
                if [[ "$status" == "END" ]]; then
                    return 0
                fi

                local deploy_log="${OUTPUT_DIR}/${tag}-deploy.txt"
                echo "=== DEPLOY ${tag} ===" > "${deploy_log}"

                # Handle failed builds/pushes
                if [[ "$status" == "FAILED" ]]; then
                    local fail_reason="${error_msg:-BUILD FAILED}"
                    echo "${tag} | ${size_local:-N/A} | ${size_ecr:-N/A} | ${build_time:-N/A} | ${fail_reason}" >> "${RESULTS_FILE}"
                    echo "Skipped: ${fail_reason}" >> "${deploy_log}"
                    log_info "${tag}: ${fail_reason}"
                    continue
                fi

                # Handle special deploy variants and normal deployments
                case "$tag" in
                    01-multi-stage)
                        log_info "Deploying 01-multi-stage with 1 CPU (baseline)..."
                        # Ensure 1 CPU
                        kubectl patch deployment unicorn-store-spring -n unicorn-store-spring \
                            --type='json' -p='[
                                {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "1"},
                                {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "1"}
                            ]' >> "${deploy_log}" 2>&1
                        # Deploy the image
                        kubectl set image deployment/unicorn-store-spring \
                            unicorn-store-spring="${ecr_uri}:${tag}" -n unicorn-store-spring >> "${deploy_log}" 2>&1
                        ;;
                    01-multi-stage-2cpu)
                        log_info "Deploying 01-multi-stage with 2 CPUs..."
                        # Increase to 2 CPU, use same 01-multi-stage image
                        kubectl patch deployment unicorn-store-spring -n unicorn-store-spring \
                            --type='json' -p='[
                                {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "2"},
                                {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "2"}
                            ]' >> "${deploy_log}" 2>&1
                        kubectl rollout restart deployment unicorn-store-spring -n unicorn-store-spring >> "${deploy_log}" 2>&1
                        ;;
                    01-multi-stage-pod-resize)
                        log_info "Deploying 01-multi-stage with in-place pod resize (CPU boost)..."
                        # Revert to 1 CPU first
                        kubectl patch deployment unicorn-store-spring -n unicorn-store-spring \
                            --type='json' -p='[
                                {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "1"},
                                {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "1"}
                            ]' >> "${deploy_log}" 2>&1

                        # Install Kube Startup CPU Boost if not present
                        if ! kubectl get crd startupcpuboosts.autoscaling.x-k8s.io &>/dev/null; then
                            log_info "Installing Kube Startup CPU Boost..."
                            kubectl apply -f https://github.com/google/kube-startup-cpu-boost/releases/download/v0.17.1/manifests.yaml >> "${deploy_log}" 2>&1
                            # Wait for controller with longer timeout for first install
                            if ! kubectl wait --for=condition=ready pod -l control-plane=controller-manager \
                                -n kube-startup-cpu-boost-system --timeout=180s >> "${deploy_log}" 2>&1; then
                                log_info "CPU boost controller not ready, skipping pod-resize test"
                                echo "${tag} | ${size_local:-N/A} | ${size_ecr:-N/A} | ${build_time:-N/A} | CONTROLLER NOT READY" >> "${RESULTS_FILE}"
                                # Cleanup
                                kubectl delete -f https://github.com/google/kube-startup-cpu-boost/releases/download/v0.17.1/manifests.yaml >> "${deploy_log}" 2>&1 || true
                                continue
                            fi
                        fi

                        # Create StartupCPUBoost resource
                        cat <<BOOST_EOF | kubectl apply -f - >> "${deploy_log}" 2>&1
apiVersion: autoscaling.x-k8s.io/v1alpha1
kind: StartupCPUBoost
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store-spring
selector:
  matchExpressions:
  - key: app
    operator: In
    values: ["unicorn-store-spring"]
spec:
  resourcePolicy:
    containerPolicies:
    - containerName: unicorn-store-spring
      percentageIncrease:
        value: 100
  durationPolicy:
    podCondition:
      type: Ready
      status: "True"
BOOST_EOF
                        kubectl rollout restart deployment unicorn-store-spring -n unicorn-store-spring >> "${deploy_log}" 2>&1
                        ;;
                    *)
                        # Normal image deployment - ensure 1 CPU
                        log_info "Deploying ${tag}..."
                        kubectl patch deployment unicorn-store-spring -n unicorn-store-spring \
                            --type='json' -p='[
                                {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "1"},
                                {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "1"}
                            ]' >> "${deploy_log}" 2>&1 || true
                        echo "--- kubectl set image ---" >> "${deploy_log}"
                        kubectl set image deployment/unicorn-store-spring \
                            unicorn-store-spring="${ecr_uri}:${tag}" -n unicorn-store-spring >> "${deploy_log}" 2>&1
                        ;;
                esac

                echo "--- kubectl rollout status ---" >> "${deploy_log}"
                if ! kubectl rollout status deployment unicorn-store-spring -n unicorn-store-spring --timeout=180s >> "${deploy_log}" 2>&1; then
                    echo "--- kubectl describe deployment ---" >> "${deploy_log}"
                    kubectl describe deployment unicorn-store-spring -n unicorn-store-spring >> "${deploy_log}" 2>&1
                    echo "--- kubectl get events ---" >> "${deploy_log}"
                    kubectl get events -n unicorn-store-spring --sort-by='.lastTimestamp' | tail -20 >> "${deploy_log}" 2>&1
                    echo "${tag} | ${size_local} | ${size_ecr} | ${build_time} | DEPLOY FAILED" >> "${RESULTS_FILE}"
                    continue
                fi
                sleep 15
                local startup_time=$(get_startup_time "$tag")
                echo "Startup time: ${startup_time}" >> "${deploy_log}"

                # Cleanup after pod-resize test
                if [[ "$tag" == "01-multi-stage-pod-resize" ]]; then
                    log_info "Cleaning up CPU boost..."
                    kubectl delete startupcpuboost unicorn-store-spring -n unicorn-store-spring >> "${deploy_log}" 2>&1 || true
                    kubectl delete -f https://github.com/google/kube-startup-cpu-boost/releases/download/v0.17.1/manifests.yaml >> "${deploy_log}" 2>&1 || true
                fi

                echo "${tag} | ${size_local} | ${size_ecr} | ${build_time} | ${startup_time}" >> "${RESULTS_FILE}"
                log_info "${tag}: startup=${startup_time}"
            done
        fi

        sleep 5
    done
}

# Start deploy watcher in background
start_watcher() {
    # Start watcher in background
    deploy_watcher &
    echo $! > "${WATCHER_PID_FILE}"
    log_info "Deploy watcher started (PID: $(cat ${WATCHER_PID_FILE}))"
}

# Wait for watcher to finish
wait_for_watcher() {
    if [[ -f "${WATCHER_PID_FILE}" ]]; then
        local pid=$(cat "${WATCHER_PID_FILE}")
        log_info "Waiting for deploy watcher to finish..."
        wait $pid 2>/dev/null
        rm -f "${WATCHER_PID_FILE}"
    fi
}

# Write to queue (atomic write to avoid race conditions)
queue_build_result() {
    local status="$1"
    local tag="$2"
    local size_local="$3"
    local size_ecr="$4"
    local build_time="$5"
    local error_msg="${6:-}"

    # Sanitize fields - remove newlines and limit length
    size_ecr=$(echo "$size_ecr" | tr -d '\n' | head -c 20)
    error_msg=$(echo "$error_msg" | tr -d '\n' | head -c 50)

    # Use consistent format: status|tag|size_local|size_ecr|build_time|error_msg
    echo "${status}|${tag}|${size_local}|${size_ecr}|${build_time}|${error_msg}" >> "${QUEUE_FILE}"
}

# Initialize output directory
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"
log_info "Output: ${OUTPUT_DIR}"

# Pre-clean Docker if requested
if [[ "$PRE_CLEAN" == true ]]; then
    log_info "Pre-cleaning Docker (full prune)..."
    docker system prune -af --volumes
    docker builder prune -af
    # Clean Jib cache (macOS and Linux)
    rm -rf ~/.cache/google-cloud-tools-java/jib 2>/dev/null || true
    rm -rf ~/Library/Caches/google-cloud-tools-java/jib 2>/dev/null || true
    log_info "Docker pre-clean complete"
fi

# Initialize database configuration (AWS or local Docker)
init_db_config

# Initialize deploy mode
if [[ "$DEPLOY_MODE" == true ]]; then
    log_info "Deploy mode enabled - will push to ECR and deploy to EKS"

    # Source workshop environment
    if [[ -f /etc/profile.d/workshop.sh ]]; then
        source /etc/profile.d/workshop.sh
    else
        log_error "Workshop environment not found. Run on workshop instance."
        exit 1
    fi

    # ECR login
    aws ecr get-login-password --region "${AWS_REGION}" \
        | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

    # Initialize queue and start deploy watcher
    touch "${QUEUE_FILE}"
    start_watcher
fi

# Print header for stdout
echo ""
if [[ "$DEPLOY_MODE" == true ]]; then
    echo "Method | Build | Size Local | Size ECR | Build Time"
    echo "-------|-------|------------|----------|------------"
else
    echo "Method | Build | Size Local | Time"
    echo "-------|-------|------------|-----"
fi

# Build all methods
for tag in "${METHODS[@]}"; do
    start_time=$(date +%s)

    build_status="❌"
    push_status="OK"
    size_local="N/A"
    size_ecr="N/A"
    error_msg=""

    build_log="${OUTPUT_DIR}/${tag}-build.txt"

    if build_image "$tag" "$build_log"; then
        build_status="✅"

        # Deploy variants don't have local images
        if ! is_deploy_variant "$tag"; then
            size_local=$(docker images "${IMAGE_NAME}:${tag}" --format "{{.Size}}" 2>/dev/null || echo "N/A")
        fi

        # Deploy mode: push and queue for deployment (skip push for deploy variants)
        if [[ "$DEPLOY_MODE" == true ]]; then
            if ! is_deploy_variant "$tag"; then
                size_ecr=$(push_image "$tag" "$build_log")
                # Check if push failed
                if [[ "$size_ecr" == PUSH_FAILED:* ]]; then
                    error_msg="${size_ecr#PUSH_FAILED:}"
                    size_ecr="N/A"
                    push_status="FAILED"
                fi
            fi
        fi
    else
        error_msg="Build failed"
    fi

    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    elapsed_fmt=$(format_time $elapsed)

    # Output to stdout
    if [[ "$DEPLOY_MODE" == true ]]; then
        echo "${tag} | ${build_status} | ${size_local} | ${size_ecr} | ${elapsed_fmt}"
    else
        echo "${tag} | ${build_status} | ${size_local} | ${elapsed_fmt}"
    fi

    # Queue for deploy watcher
    if [[ "$DEPLOY_MODE" == true ]]; then
        if [[ "$build_status" == "✅" && "$push_status" == "OK" ]]; then
            queue_build_result "OK" "$tag" "$size_local" "$size_ecr" "$elapsed_fmt"
        else
            queue_build_result "FAILED" "$tag" "$size_local" "$size_ecr" "$elapsed_fmt" "$error_msg"
        fi
    fi
done

# Signal end and wait for watcher
if [[ "$DEPLOY_MODE" == true ]]; then
    echo "END|||||" >> "${QUEUE_FILE}"
    wait_for_watcher

    echo ""
    log_info "=== RESULTS ==="
    cat "${RESULTS_FILE}"
fi

echo ""
log_info "Complete (logs: ${OUTPUT_DIR})"
