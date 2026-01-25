#!/bin/bash
# Extract Dockerfiles from workshop content to apps/dockerfiles/
# Run this script periodically to sync Dockerfiles with content changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CONTENT_DIR="${REPO_ROOT}/../java-on-amazon-eks/content"
OUTPUT_DIR="${REPO_ROOT}/apps/dockerfiles"

mkdir -p "${OUTPUT_DIR}"

log_info "Extracting Dockerfiles from workshop content..."
log_info "Content dir: ${CONTENT_DIR}"
log_info "Output dir: ${OUTPUT_DIR}"

# Map of content paths to Dockerfile names
# Format: "content_path:tag"
DOCKERFILE_SOURCES=(
    "optimize-containers/custom-jre:04-custom-jre"
    "optimize-containers/soci:05-soci"
    "optimize-containers/cds:06-cds"
    "optimize-containers/aot:07-aot"
    "optimize-containers/native:08-native"
    "optimize-containers/crac:09-crac"
)

extract_dockerfile() {
    local content_path="$1"
    local tag="$2"
    local md_file="${CONTENT_DIR}/${content_path}/index.en.md"
    local output_file="${OUTPUT_DIR}/Dockerfile.${tag}"

    if [[ ! -f "${md_file}" ]]; then
        log_warning "${md_file} not found, skipping ${tag}"
        return 1
    fi

    # Extract Dockerfile content between cat <<'EOF' > .../Dockerfile and EOF
    # Handles both ~/environment/unicorn-store-spring/Dockerfile patterns
    awk '
        /cat <<.*EOF.*>.*Dockerfile$/ { capture=1; next }
        /^EOF$/ { if(capture) exit }
        capture { print }
    ' "${md_file}" > "${output_file}"

    if [[ -s "${output_file}" ]]; then
        log_success "Extracted ${tag} ($(wc -l < "${output_file}") lines)"
        return 0
    else
        log_warning "No Dockerfile found in ${md_file}"
        rm -f "${output_file}"
        return 1
    fi
}

# Extract each Dockerfile
success=0
failed=0

for source in "${DOCKERFILE_SOURCES[@]}"; do
    content_path="${source%%:*}"
    tag="${source##*:}"

    if extract_dockerfile "${content_path}" "${tag}"; then
        ((success++))
    else
        ((failed++))
    fi
done

log_info "Extraction complete: ${success} success, ${failed} failed"
ls -la "${OUTPUT_DIR}/"

# Note: 02-multi-stage is manually maintained (from containerize-run)
# Note: 03-jib uses maven plugin, no Dockerfile needed
