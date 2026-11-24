#!/bin/bash
# =============================================================================
# skills.sh — install the workshop skills on the IDE for every coding agent.
#
# Copies the two skills (SKILL.md and references/) from apps/perf-sensor/skills to
# ~/environment/skills/. claude-code.sh links each skill into
# ~/environment/.claude/skills/. Run before it. No cluster needed. Idempotent.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
SKILLS_SRC="${REPO_ROOT}/apps/perf-sensor/skills"
ENV_DIR="${ENVIRONMENT_DIR:-${HOME}/environment}"
SKILLS_DIR="${ENV_DIR}/skills"

mkdir -p "${SKILLS_DIR}"
for skill in java-on-eks-optimization java-on-eks-checklist; do
  rm -rf "${SKILLS_DIR:?}/${skill}"
  cp -R "${SKILLS_SRC}/${skill}" "${SKILLS_DIR}/${skill}"
  echo "installed skill: ${SKILLS_DIR}/${skill}"
done
