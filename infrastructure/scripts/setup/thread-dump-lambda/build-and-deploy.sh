#!/bin/bash
# build-and-deploy.sh - Build and deploy Lambda function using virtualenv

# Exit on any error
set -e

# Get script directory for absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
FUNCTION_NAME="unicornstore-thread-dump-lambda"
PACKAGE_NAME="lambda_function"
PYTHON_VERSION="3.13"
TEMP_DIR="build_temp"
DIST_DIR="dist"
OUTPUT_ZIP="$DIST_DIR/$PACKAGE_NAME.zip"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if Python 3.13 is available
check_python() {
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed"
        exit 1
    fi

    local python_version=$(python3 --version)
    print_success "Python available: $python_version"
}

# Build the Lambda package
build_package() {
    print_status "Building Lambda Deployment Package"
    echo "Function name: $FUNCTION_NAME"
    echo "Python version: $PYTHON_VERSION"
    echo "Target region: $AWS_REGION"

    # Create clean directories
    print_status "Creating clean build directories"
    rm -rf "$TEMP_DIR" "$DIST_DIR"
    mkdir -p "$TEMP_DIR/package" "$DIST_DIR"

    # Create and activate virtual environment
    print_status "Creating virtual environment"
    python3 -m venv "$TEMP_DIR/venv"
    source "$TEMP_DIR/venv/bin/activate"

    # Upgrade pip
    print_status "Upgrading pip"
    pip install --upgrade pip --quiet

    # Install dependencies if requirements.txt exists
    if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
        print_status "Installing dependencies"
        pip install -r "$SCRIPT_DIR/requirements.txt" --target "$TEMP_DIR/package" --quiet
        print_success "Dependencies installed"
    else
        print_warning "No requirements.txt found at $SCRIPT_DIR/requirements.txt, skipping dependency installation"
    fi

    # Copy function code
    print_status "Copying function code"
    if [ -d "$SCRIPT_DIR/src" ]; then
        cp "$SCRIPT_DIR/src"/*.py "$TEMP_DIR/package/" 2>/dev/null || true
        print_success "Source files copied from $SCRIPT_DIR/src"
    else
        print_warning "No src directory found at $SCRIPT_DIR/src"
    fi

    # Create deployment package
    print_status "Creating deployment package"
    cd "$TEMP_DIR/package"
    zip -r "../../$OUTPUT_ZIP" . > /dev/null
    cd - > /dev/null

    # Calculate package size
    local package_size=$(du -h "$OUTPUT_ZIP" | cut -f1)
    print_success "Package created: $OUTPUT_ZIP ($package_size)"

    # Clean up virtual environment
    deactivate
    rm -rf "$TEMP_DIR"
}

# Deploy to AWS Lambda
deploy_function() {
    print_status "Deploying to AWS Lambda"

    # Check if function exists
    if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" &>/dev/null; then
        print_status "Updating existing function code"
        aws lambda update-function-code \
            --function-name "$FUNCTION_NAME" \
            --zip-file "fileb://$OUTPUT_ZIP" \
            --region "$AWS_REGION" \
            --output table \
            --no-cli-pager
        print_success "Function code updated successfully"
    else
        print_error "Function '$FUNCTION_NAME' does not exist"
        echo "Please deploy the CDK stack first to create the function"
        exit 1
    fi

    # Wait for function to be updated
    print_status "Waiting for function update to complete"
    aws lambda wait function-updated \
        --function-name "$FUNCTION_NAME" \
        --region "$AWS_REGION" \
        --no-cli-pager
    print_success "Function update completed"

    # Get function info
    print_status "Function Information"
    aws lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --region "$AWS_REGION" \
        --query '{FunctionName:Configuration.FunctionName,Runtime:Configuration.Runtime,Handler:Configuration.Handler,CodeSize:Configuration.CodeSize,LastModified:Configuration.LastModified}' \
        --output table \
        --no-cli-pager
}

# Test the deployed function
test_function() {
    print_status "Testing deployed function"

    local test_payload='{"test": true, "message": "Hello from build script"}'

    aws lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --region "$AWS_REGION" \
        --payload "$test_payload" \
        --cli-binary-format raw-in-base64-out \
        --no-cli-pager \
        response.json

    if [ -f "response.json" ]; then
        print_success "Function test completed"
        echo "Response:"
        cat response.json | python3 -m json.tool
        rm -f response.json
    fi
}

# Main execution
main() {
    print_status "Lambda Build and Deploy Script"

    # Parse command line arguments
    BUILD_ONLY=false
    SKIP_TEST=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-only)
                BUILD_ONLY=true
                shift
                ;;
            --skip-test)
                SKIP_TEST=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --build-only    Only build the package, don't deploy"
                echo "  --skip-test     Skip function testing after deployment"
                echo "  --help          Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Run checks
    check_python

    # Build package
    build_package

    if [ "$BUILD_ONLY" = false ]; then
        # Deploy and test
        deploy_function

        if [ "$SKIP_TEST" = false ]; then
            test_function
        fi
    fi

    print_success "Script completed successfully!"

    # Clean up build artifacts
    print_status "Cleaning up build artifacts"
    rm -rf "$DIST_DIR"
    print_success "Build artifacts cleaned up"
}

# Run main function
main "$@"
