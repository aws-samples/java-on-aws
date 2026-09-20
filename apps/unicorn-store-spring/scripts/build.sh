#!/bin/bash
# =============================================================================
# build.sh <tag> [dockerfile]
#
# Build + push a unicorn-store-spring image to the workshop ECR repo, resolving the
# account/region and the Aurora build-args (SSM + Secrets Manager) — no placeholders.
# Run on the amd64 "ide" instance (in the VPC, so the DB is reachable when a build
# step runs the app).
#
#   ./scripts/build.sh latest                  # build ./Dockerfile        -> :latest
#   ./scripts/build.sh <tag> <Dockerfile.x>    # build a given Dockerfile  -> :<tag>
#
# The tag is arbitrary; pass the Dockerfile to build (defaults to ./Dockerfile).
# =============================================================================
set -euo pipefail

TAG="${1:?usage: build.sh <tag> [dockerfile]}"
DOCKERFILE="${2:-Dockerfile}"
APP="unicorn-store-spring"

REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
ACCOUNT_ID="${ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
ECR="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
REPO="${ECR}/${APP}"

[ -f "$DOCKERFILE" ] || { echo "ERROR: Dockerfile '$DOCKERFILE' not found next to pom.xml"; exit 1; }

echo "[build] resolving Aurora build-args from SSM + Secrets Manager..."
DB_URL="$(aws ssm get-parameter --name workshop-db-connection-string --query Parameter.Value --output text)"
DB_JSON="$(aws secretsmanager get-secret-value --secret-id workshop-db-secret --query SecretString --output text)"
DB_USER="$(printf '%s' "$DB_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["username"])')"
DB_PASS="$(printf '%s' "$DB_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["password"])')"

echo "[build] ECR login ($ECR)..."
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR" >/dev/null
aws ecr describe-repositories --repository-names "$APP" --region "$REGION" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name "$APP" --region "$REGION" >/dev/null

echo "[build] docker build -f $DOCKERFILE -> ${REPO}:${TAG} (build-args from SSM/Secrets)..."
docker build \
  --build-arg "SPRING_DATASOURCE_URL=${DB_URL}" \
  --build-arg "SPRING_DATASOURCE_USERNAME=${DB_USER}" \
  --build-arg "SPRING_DATASOURCE_PASSWORD=${DB_PASS}" \
  -t "${REPO}:${TAG}" -f "$DOCKERFILE" .
docker push "${REPO}:${TAG}"
echo "[build] pushed ${REPO}:${TAG}"
echo "${REPO}:${TAG}"
