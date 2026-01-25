#!/bin/bash

# Containerize - Create optimized Dockerfile, build and push to ECR
# Based on: java-on-amazon-eks/content/containerize-run/index.en.md
# Section: "Optimizing the Dockerfile" onwards

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

APP_DIR=~/environment/unicorn-store-spring
IMAGE_NAME="unicorn-store-spring"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}"

log_info "Containerizing Unicorn Store Spring application..."
log_info "AWS Account: $ACCOUNT_ID"
log_info "AWS Region: $AWS_REGION"
log_info "ECR URI: $ECR_URI"

cd "$APP_DIR"

# Create optimized multi-stage Dockerfile
log_info "Creating optimized multi-stage Dockerfile..."
cat <<'EOF' > Dockerfile
FROM public.ecr.aws/docker/library/maven:3-amazoncorretto-25-al2023 AS builder

COPY ./pom.xml ./pom.xml
COPY src ./src/

RUN mvn clean package -DskipTests -ntp && mv target/store-spring-1.0.0-exec.jar store-spring.jar

FROM public.ecr.aws/docker/library/amazoncorretto:25-al2023

RUN yum install -y shadow-utils

COPY --from=builder store-spring.jar store-spring.jar

RUN groupadd --system spring -g 1000
RUN adduser spring -u 1000 -g 1000

USER 1000:1000
EXPOSE 8080

ENTRYPOINT ["java", "-XX:+UseCompactObjectHeaders", "-jar", "-Dserver.port=8080", "/store-spring.jar"]
EOF
log_success "Created optimized Dockerfile with multi-stage build"

# Build Docker image
log_info "Building Docker image..."
docker build -t "${IMAGE_NAME}:latest" .
log_success "Docker image built"

# Show image size
log_info "Image size:"
docker images "$IMAGE_NAME"

# Login to ECR
log_info "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
log_success "ECR login successful"

# Tag and push images
log_info "Tagging and pushing image with '01-multi-stage' tag..."
docker tag "${IMAGE_NAME}:latest" "${ECR_URI}:01-multi-stage"
docker push "${ECR_URI}:01-multi-stage"
log_success "Pushed ${ECR_URI}:01-multi-stage"

log_info "Tagging and pushing image with 'latest' tag..."
docker tag "${IMAGE_NAME}:latest" "${ECR_URI}:latest"
docker push "${ECR_URI}:latest"
log_success "Pushed ${ECR_URI}:latest"

log_success "Containerization completed"
echo "✅ Success: Containerized (ECR: ${IMAGE_NAME}:02-multi-stage, ${IMAGE_NAME}:latest)"
