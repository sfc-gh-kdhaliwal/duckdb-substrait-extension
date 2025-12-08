#!/bin/bash

# Script to build DuckDB Substrait extension natively on macOS
# Usage: ./build_extension_macos.sh [DUCKDB_VERSION] [OUTPUT_DIR] [ARCHITECTURE]

set -e

# Change to script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "${SCRIPT_DIR}"

# Default values
DUCKDB_VERSION=${1:-v1.4.2}
OUTPUT_DIR=${2:-./output_macos}
ARCHITECTURE=${3:-$(uname -m)}  # Default to current system architecture

# Normalize architecture names
if [ "$ARCHITECTURE" = "x86_64" ]; then
    ARCH_NAME="amd64"
elif [ "$ARCHITECTURE" = "arm64" ] || [ "$ARCHITECTURE" = "aarch64" ]; then
    ARCH_NAME="arm64"
else
    ARCH_NAME="$ARCHITECTURE"
fi

echo "Building DuckDB Substrait Extension (Native macOS Build)"
echo "  DuckDB Version: ${DUCKDB_VERSION}"
echo "  Architecture: ${ARCHITECTURE} (osx_${ARCH_NAME})"
echo "  Output Directory: ${OUTPUT_DIR}"
echo ""

# Create output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"

# Check if we're in the extension directory
if [ ! -f "extension_config.cmake" ]; then
    echo "Error: Must be run from the duckdb-substrait-extension directory"
    exit 1
fi

# Initialize submodules if not already done
echo "Initializing submodules..."
git submodule update --init --recursive

# Checkout the specific DuckDB version in the submodule
echo "Checking out DuckDB version ${DUCKDB_VERSION}..."
cd duckdb
git fetch --all --tags
git checkout ${DUCKDB_VERSION}
cd ..

# Clean previous build
echo "Cleaning previous build..."
rm -rf build/release

# Set SDK root for proper C++ standard library detection
SDKROOT=$(xcrun --show-sdk-path)
export SDKROOT
echo "Using SDK: ${SDKROOT}"

# Build the extension
echo "Building extension for ${ARCHITECTURE}..."
if [ "$ARCHITECTURE" != "$(uname -m)" ]; then
    # Cross-compilation attempt
    echo "Warning: Cross-compiling from $(uname -m) to ${ARCHITECTURE}"
    echo "This may require additional setup or may not work."
    export CMAKE_OSX_ARCHITECTURES="${ARCHITECTURE}"
fi

# Pass sysroot directly to CMake via EXT_RELEASE_FLAGS
export EXT_RELEASE_FLAGS="-DCMAKE_OSX_SYSROOT=${SDKROOT}"
echo "EXT_RELEASE_FLAGS: ${EXT_RELEASE_FLAGS}"

make release

# Check if build was successful
if [ ! -f "build/release/extension/substrait/substrait.duckdb_extension" ]; then
    echo "Error: Build failed - extension file not found"
    exit 1
fi

# Create gzipped output with architecture name
OUTPUT_FILE="substrait.duckdb_extension.osx_${ARCH_NAME}.gz"
echo ""
echo "Packaging extension..."
gzip -c build/release/extension/substrait/substrait.duckdb_extension > "${OUTPUT_DIR}/${OUTPUT_FILE}"

# Create platform info file
echo "osx_${ARCH_NAME}" > "${OUTPUT_DIR}/platform.txt"

echo ""
echo "Build complete!"
echo "Extension binary: ${OUTPUT_DIR}/${OUTPUT_FILE}"
ls -lh "${OUTPUT_DIR}/${OUTPUT_FILE}"

# Show file info
if command -v file &> /dev/null; then
    echo ""
    echo "File info:"
    gunzip -c "${OUTPUT_DIR}/${OUTPUT_FILE}" | file -
fi
