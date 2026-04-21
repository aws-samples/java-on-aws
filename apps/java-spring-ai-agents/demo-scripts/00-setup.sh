#!/bin/bash
set -e

echo "=============================================="
echo "00-setup.sh - Move full app to ~/demo-full/"
echo "=============================================="

if [ -d ~/demo-full ]; then
    echo "~/demo-full/ already exists, skipping move"
else
    echo "Cleaning target directories..."
    rm -rf ~/environment/aiagent/target
    rm -rf ~/environment/backoffice/target
    rm -rf ~/environment/currency/target

    echo "Moving ~/environment/* to ~/demo-full/..."
    mkdir -p ~/demo-full
    mv ~/environment/* ~/demo-full/
    mv ~/environment/.envrc ~/demo-full/ 2>/dev/null || true
fi

echo "Cleaning ~/environment/..."
rm -rf ~/environment/aiagent ~/environment/backoffice ~/environment/currency
rm -f ~/environment/.envrc
mkdir -p ~/environment

echo ""
echo "Done. Full app in ~/demo-full/, ~/environment/ is clean."
