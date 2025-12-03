#!/bin/bash
# Build script for Lambda function deployment package

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LAMBDA_DIR="$PROJECT_ROOT/lambda"
BUILD_DIR="$PROJECT_ROOT/build"

echo "Building Lambda deployment package..."

# Create build directory
mkdir -p "$BUILD_DIR"

# Create temporary directory for packaging
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy Lambda function code
cp -r "$LAMBDA_DIR"/* "$TEMP_DIR/"

# Install dependencies if requirements.txt exists
if [ -f "$LAMBDA_DIR/requirements.txt" ]; then
    echo "Installing Python dependencies..."
    pip install -r "$LAMBDA_DIR/requirements.txt" -t "$TEMP_DIR" --quiet
fi

# Create ZIP file
cd "$TEMP_DIR"
zip -r "$BUILD_DIR/lambda_function.zip" . -q

echo "Lambda package created: $BUILD_DIR/lambda_function.zip"
echo "Package size: $(du -h "$BUILD_DIR/lambda_function.zip" | cut -f1)"

