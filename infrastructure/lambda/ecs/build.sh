#!/bin/bash
# build.sh

# Exit on any error
set -e

# Configuration
FUNCTION_NAME="ecs-thread-dump"
PACKAGE_NAME="lambda_function"
PYTHON_VERSION="3.13"
TEMP_DIR="build_temp"
DIST_DIR="dist"

# Print header
echo "=== Building Lambda Deployment Package ==="
echo "Function name: $FUNCTION_NAME"
echo "Python version: $PYTHON_VERSION"

# Create clean directories
echo "Creating clean build directories..."
rm -rf $TEMP_DIR $DIST_DIR
mkdir -p $TEMP_DIR $DIST_DIR

# Create and activate virtual environment
echo "Creating virtual environment..."
python3 -m venv $TEMP_DIR/venv
source $TEMP_DIR/venv/bin/activate

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Install dependencies
echo "Installing dependencies..."
pip install -r requirements.txt --target $TEMP_DIR/package

# Copy function code
echo "Copying function code..."
cp src/lambda_function.py $TEMP_DIR/package/

# Create deployment package
echo "Creating deployment package..."
cd $TEMP_DIR/package
zip -r ../../$DIST_DIR/$PACKAGE_NAME.zip .
cd ../..

# Calculate package size
PACKAGE_SIZE=$(du -h $DIST_DIR/$PACKAGE_NAME.zip | cut -f1)

# Clean up
echo "Cleaning up build files..."
deactivate
rm -rf $TEMP_DIR

# Print summary
echo ""
echo "=== Build Summary ==="
echo "Package created: $DIST_DIR/$PACKAGE_NAME.zip"
echo "Package size: $PACKAGE_SIZE"
echo "Build complete!"

# Optional: Upload to AWS if specified
if [ "$1" == "--deploy" ]; then
    echo ""
    echo "=== Deploying to AWS ==="
    aws lambda update-function-code \
        --function-name $FUNCTION_NAME \
        --zip-file fileb://$DIST_DIR/$PACKAGE_NAME.zip

    echo "Deployment complete!"
fi
