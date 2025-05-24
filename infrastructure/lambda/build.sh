#!/bin/bash
# build.sh

# Exit on any error
set -e

# Configuration
FUNCTION_NAME="container-thread-dump"
PACKAGE_NAME="lambda_function"
PYTHON_VERSION="3.13"
TEMP_DIR="build_temp"
DIST_DIR="dist"
OUTPUT_ZIP="$DIST_DIR/$PACKAGE_NAME.zip"

# Print header
echo "=== Building Lambda Deployment Package ==="
echo "Function name: $FUNCTION_NAME"
echo "Python version: $PYTHON_VERSION"

# Create clean directories
echo "Creating clean build directories..."
rm -rf "$TEMP_DIR" "$DIST_DIR"
mkdir -p "$TEMP_DIR/package" "$DIST_DIR"

# Create and activate virtual environment
echo "Creating virtual environment..."
python3 -m venv "$TEMP_DIR/venv"
source "$TEMP_DIR/venv/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Install dependencies
echo "Installing dependencies..."
pip install -r requirements.txt --target "$TEMP_DIR/package"

# Copy function code
echo "Copying function code..."
cp src/lambda_function.py "$TEMP_DIR/package/"
cp src/eks_client.py "$TEMP_DIR/package/"

# Create deployment package
echo "Creating deployment package..."
cd "$TEMP_DIR/package"
zip -r "../../../$OUTPUT_ZIP" . > /dev/null
cd -

# Copy to CDK asset output
if [ -d "/asset-output" ]; then
    echo "Copying zip to /asset-output for CDK..."
    cp "$OUTPUT_ZIP" /asset-output/
fi

# Calculate package size
PACKAGE_SIZE=$(du -h "$OUTPUT_ZIP" | cut -f1)

# Clean up
echo "Cleaning up build files..."
deactivate
rm -rf "$TEMP_DIR"

# Print summary
echo ""
echo "=== Build Summary ==="
echo "Package created: $OUTPUT_ZIP"
echo "Package size: $PACKAGE_SIZE"
echo "Build complete!"

# Optional: Deploy to AWS if specified
if [ "$1" == "--deploy" ]; then
    echo ""
    echo "=== Deploying to AWS ==="
    aws lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --zip-file "fileb://$OUTPUT_ZIP"
    echo "Deployment complete!"
fi
