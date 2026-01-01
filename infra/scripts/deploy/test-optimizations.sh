#!/bin/bash
# Build and optionally deploy/test all optimization images
#
# Prerequisites: containerize.sh and eks.sh must be run first
#
# Usage:
#   ./test-optimizations.sh              # Build all images locally
#   ./test-optimizations.sh --deploy     # Build, push to ECR, deploy to EKS, measure startup
#   ./test-optimizations.sh --only cds   # Build single method
#   ./test-optimizations.sh --only cds --deploy

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
APP_DIR="${REPO_ROOT}/apps/unicorn-store-spring-java25"
DOCKERFILES_DIR="${REPO_ROOT}/apps/dockerfiles-java25"
IMAGE_NAME="unicorn-store-spring"

# Output files (only used in deploy mode)
QUEUE_FILE="${SCRIPT_DIR}/test-optimizations-queue.txt"
RESULTS_FILE="${SCRIPT_DIR}/test-optimizations-results.txt"
WATCHER_PID_FILE="${SCRIPT_DIR}/.watcher.pid"

# Methods in order (tag names)
METHODS=(
    "02-multi-stage"
    "03-jib"
    "04-custom-jre"
    "05-soci"
    "06-cds"
    "07-aot"
    "08-native"
    "09-crac"
)

# Parse arguments
DEPLOY_MODE=false
ONLY_METHOD=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --deploy) DEPLOY_MODE=true; shift ;;
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
        06-cds|07-aot|09-crac) return 0 ;;
        *) return 1 ;;
    esac
}

# Check if method needs code changes (CRaC)
needs_code_change() {
    [[ "$1" == "09-crac" ]]
}

# Start PostgreSQL for training
start_build_db() {
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
    log_info "PostgreSQL ready"
}

stop_build_db() {
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
    local dockerfile="${DOCKERFILES_DIR}/Dockerfile.${tag}"
    local build_args=""

    log_info "Building ${tag}..."

    # Special case: jib uses maven
    if [[ "$tag" == "03-jib" ]]; then
        log_info "Using Maven Jib plugin..."
        (cd "${APP_DIR}" && mvn compile jib:dockerBuild -Dimage=${IMAGE_NAME}:${tag} -q)
        return $?
    fi

    # Check Dockerfile exists
    if [[ ! -f "${dockerfile}" ]]; then
        log_error "Dockerfile not found: ${dockerfile}"
        return 1
    fi

    # Pre-build hooks
    if needs_code_change "$tag"; then
        crac_pre_build
    fi

    # Start DB if needed
    if needs_db "$tag"; then
        start_build_db
        build_args="--build-arg SPRING_DATASOURCE_URL=jdbc:postgresql://host.docker.internal:5432/unicornstore"
        build_args="${build_args} --build-arg SPRING_DATASOURCE_USERNAME=unicorn"
        build_args="${build_args} --build-arg SPRING_DATASOURCE_PASSWORD=unicorn"
    fi

    # Build
    local result=0
    docker build ${build_args} -f "${dockerfile}" -t "${IMAGE_NAME}:${tag}" "${APP_DIR}" || result=$?

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
push_image() {
    local tag="$1"
    local ecr_uri="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}"

    docker tag "${IMAGE_NAME}:${tag}" "${ecr_uri}:${tag}"
    docker push "${ecr_uri}:${tag}"

    # SOCI index for soci method
    if [[ "$tag" == "05-soci" ]]; then
        log_info "Creating SOCI index..."
        sudo soci create "${ecr_uri}:${tag}" 2>/dev/null || true
        sudo soci push "${ecr_uri}:${tag}" 2>/dev/null || true
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
    [[ "$tag" == "09-crac" ]] && log_pattern="Restored StoreApplication"

    kubectl logs $(kubectl get pods -n unicorn-store-spring -o json \
        | jq --raw-output '.items[0].metadata.name') -n unicorn-store-spring 2>/dev/null \
        | grep "${log_pattern}" | tail -1 | grep -oE '[0-9]+\.[0-9]+ seconds' || echo "N/A"
}

# Deploy watcher - runs in background, reads queue, deploys and measures
deploy_watcher() {
    local ecr_uri="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}"

    # Initialize results file
    echo "Method | Size Local | Size ECR | Build Time | Startup Time | Restart Time" > "${RESULTS_FILE}"
    echo "-------|------------|----------|------------|--------------|-------------" >> "${RESULTS_FILE}"

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
                    # Revert to baseline
                    log_info "Reverting to baseline (:latest)..."
                    kubectl set image deployment/unicorn-store-spring \
                        unicorn-store-spring="${ecr_uri}:latest" -n unicorn-store-spring 2>/dev/null
                    kubectl rollout status deployment unicorn-store-spring -n unicorn-store-spring --timeout=180s 2>/dev/null
                    return 0
                fi

                # Handle failed builds
                if [[ "$status" == "FAILED" ]]; then
                    echo "${tag} | ${size_local:-N/A} | ${size_ecr:-N/A} | ${build_time:-N/A} | BUILD FAILED | -" >> "${RESULTS_FILE}"
                    continue
                fi

                # Deploy with new image (cold start)
                log_info "Deploying ${tag}..."
                kubectl set image deployment/unicorn-store-spring \
                    unicorn-store-spring="${ecr_uri}:${tag}" -n unicorn-store-spring 2>/dev/null
                if ! kubectl rollout status deployment unicorn-store-spring -n unicorn-store-spring --timeout=180s 2>/dev/null; then
                    echo "${tag} | ${size_local} | ${size_ecr} | ${build_time} | DEPLOY FAILED | -" >> "${RESULTS_FILE}"
                    continue
                fi
                sleep 15
                local startup_time=$(get_startup_time "$tag")

                # Restart (warm restart)
                kubectl rollout restart deployment unicorn-store-spring -n unicorn-store-spring 2>/dev/null
                local restart_time="RESTART FAILED"
                if kubectl rollout status deployment unicorn-store-spring -n unicorn-store-spring --timeout=180s 2>/dev/null; then
                    sleep 15
                    restart_time=$(get_startup_time "$tag")
                fi

                echo "${tag} | ${size_local} | ${size_ecr} | ${build_time} | ${startup_time} | ${restart_time}" >> "${RESULTS_FILE}"
                log_info "${tag}: startup=${startup_time}, restart=${restart_time}"
            done
        fi

        sleep 5
    done
}

# Start deploy watcher in background
start_watcher() {
    # Clean up old files
    rm -f "${QUEUE_FILE}" "${RESULTS_FILE}" "${WATCHER_PID_FILE}"
    touch "${QUEUE_FILE}"

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

# Write to queue
queue_build_result() {
    local status="$1"
    local tag="$2"
    local size_local="$3"
    local size_ecr="$4"
    local build_time="$5"
    local error_msg="$6"

    if [[ "$status" == "OK" ]]; then
        echo "OK|${tag}|${size_local}|${size_ecr}|${build_time}|" >> "${QUEUE_FILE}"
    else
        echo "FAILED|${tag}|${size_local}|${size_ecr}|${build_time}|${error_msg}" >> "${QUEUE_FILE}"
    fi
}

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

    # Start deploy watcher in background
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
    size_local="N/A"
    size_ecr="N/A"

    if build_image "$tag" >/dev/null 2>&1; then
        build_status="✅"
        size_local=$(docker images "${IMAGE_NAME}:${tag}" --format "{{.Size}}" 2>/dev/null || echo "N/A")

        # Deploy mode: push and queue for deployment
        if [[ "$DEPLOY_MODE" == true ]]; then
            size_ecr=$(push_image "$tag" 2>/dev/null)
        fi
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
        if [[ "$build_status" == "✅" ]]; then
            queue_build_result "OK" "$tag" "$size_local" "$size_ecr" "$elapsed_fmt"
        else
            queue_build_result "FAILED" "$tag" "$size_local" "$size_ecr" "$elapsed_fmt" "Build failed"
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
log_info "Complete"
