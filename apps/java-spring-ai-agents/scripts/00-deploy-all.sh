#!/bin/bash
set -e

echo "=============================================="
echo "00-deploy-all.sh - Full Deployment"
echo "=============================================="
echo ""
echo "This script will run all deployment scripts (01-12) and then test (20)."
echo "Estimated time: 30-45 minutes"
echo ""
echo "Press Ctrl+C within 5 seconds to cancel..."
sleep 5

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# List of scripts to run in order
SCRIPTS=(
    "01-setup.sh"
    "02-memory.sh"
    "03-knowledgebase.sh"
    "04-mcp-cognito.sh"
    "05-mcp-runtime.sh"
    "06-mcp-gateway.sh"
    "07-aiagent-cognito.sh"
    "08-aiagent-runtime.sh"
    "09-aiagent-ui.sh"
    "10-mcp-runtime-redeploy.sh"
    "11-mcp-currency.sh"
    "12-aiagent-redeploy.sh"
)

TOTAL=${#SCRIPTS[@]}
CURRENT=0

for SCRIPT in "${SCRIPTS[@]}"; do
    CURRENT=$((CURRENT + 1))
    echo ""
    echo "======================================================================"
    echo "[${CURRENT}/${TOTAL}] Running ${SCRIPT}"
    echo "======================================================================"

    if [ -f "${SCRIPT_DIR}/${SCRIPT}" ]; then
        bash "${SCRIPT_DIR}/${SCRIPT}"
    else
        echo "Warning: ${SCRIPT} not found, skipping"
    fi
done

echo ""
echo "======================================================================"
echo "Running test script"
echo "======================================================================"

bash "${SCRIPT_DIR}/20-test.sh"

echo ""
echo "=============================================="
echo "Full deployment complete!"
echo "=============================================="
