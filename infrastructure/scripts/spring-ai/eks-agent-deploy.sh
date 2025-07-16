#!/bin/bash
# eks-agent-deploy.sh - Script to restart deployment, and show logs

set -e

echo "Starting deployment process for Spring AI Agent..."

# Restart deployment by applying a rolling update
echo "Restarting deployment..."
kubectl rollout restart deployment unicorn-spring-ai-agent -n unicorn-spring-ai-agent

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
kubectl rollout status deployment unicorn-spring-ai-agent -n unicorn-spring-ai-agent --timeout=300s

# Get the name of a running pod
echo "Finding running pod..."
POD_NAME=$(kubectl get pods -n unicorn-spring-ai-agent -l app=unicorn-spring-ai-agent --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD_NAME" ]; then
  echo "Error: Could not find running pod. Retrying with any pod status..."
  POD_NAME=$(kubectl get pods -n unicorn-spring-ai-agent -l app=unicorn-spring-ai-agent -o jsonpath='{.items[0].metadata.name}')
  if [ -z "$POD_NAME" ]; then
    echo "Error: Could not find any pod. Exiting."
    exit 1
  fi
fi
echo "Found pod: $POD_NAME"

# Show logs
echo "Showing logs from pod $POD_NAME..."
kubectl logs -f $POD_NAME -n unicorn-spring-ai-agent

echo "Deployment process completed successfully!"
