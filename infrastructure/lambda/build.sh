#!/bin/bash
# lambda/build.sh
set -e

# Create dist directory
mkdir -p dist

# Install dependencies
pip install --target ./package -r requirements.txt

# Copy function code
cp src/lambda_function.py dist/
cp src/eks_client.py dist/