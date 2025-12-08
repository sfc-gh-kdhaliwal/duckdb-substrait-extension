#!/bin/bash

# Optimized script to build DuckDB Substrait extension in Docker using local source
# with layer caching, ccache, and parallel builds
#
# Usage: ./build_extension_docker_local_optimized.sh [DUCKDB_VERSION] [OUTPUT_DIR] [PLATFORM] [ARCHITECTURE]
#
# Platform options:
#   - linux (default)
#   - darwin (macOS)
#   - all (builds for both linux and darwin with all architectures)
#
# Architecture options:
#   - amd64 (default)
#   - arm64
#   - all (builds both architectures)
#
# Environment variables:
#   - SKIP_CACHE: Set to 1 to disable cache (forces clean build)
#   - VERBOSE: Set to 1 for verbose output
#   - BUILD_PARALLEL_LEVEL: Set parallel build level (default: 2, was 4 before)

set -e

# Default values
DUCKDB_VERSION=${1:-v1.4.2}
OUTPUT_DIR=${2:-./output_optimized}
PLATFORM=${3:-linux}
ARCHITECTURE=${4:-amd64}

# Enable Docker BuildKit for better caching and parallel builds
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Function to build for a specific platform and architecture
build_for_platform() {
    local platform=$1
    local arch=$2
    local platform_name=$3
    local build_start=$(date +%s)

    echo ""
    echo "=========================================="
    echo "Building for ${platform_name}_${arch} (OPTIMIZED)"
    echo "=========================================="
    echo "  DuckDB Version: ${DUCKDB_VERSION}"
    echo "  Platform: ${platform}"
    echo "  Architecture: ${arch}"
    echo "  Output Directory: ${OUTPUT_DIR}"
    echo "  BuildKit: Enabled"
    echo "  ccache: Enabled"
    echo ""

    # Create output directory if it doesn't exist
    mkdir -p "${OUTPUT_DIR}"

    # Build cache arguments
    local cache_args=""
    if [ "${SKIP_CACHE}" != "1" ]; then
        log_info "Using Docker layer cache and ccache..."
        cache_args="--cache-from substrait-extension-builder-local-opt:${DUCKDB_VERSION}-latest"
        cache_args="${cache_args} --cache-from substrait-extension-builder-local-opt:latest"
        cache_args="${cache_args} --build-arg BUILDKIT_INLINE_CACHE=1"
    else
        log_warn "Cache disabled (SKIP_CACHE=1), building from scratch..."
        cache_args="--no-cache"
    fi

    # Verbose output
    local progress="auto"
    if [ "${VERBOSE}" = "1" ]; then
        progress="plain"
    fi

    # Build the Docker image
    log_info "Building Docker image with optimized Dockerfile..."

    # Set parallel level (default 2 to avoid OOM on amd64)
    local parallel_level=${BUILD_PARALLEL_LEVEL:-2}
    log_info "Using CMAKE_BUILD_PARALLEL_LEVEL=${parallel_level}"

    docker build \
      ${cache_args} \
      --progress=${progress} \
      --build-arg DUCKDB_VERSION="${DUCKDB_VERSION}" \
      --build-arg TARGETARCH="${arch}" \
      --build-arg TARGETOS="${platform}" \
      --build-arg BUILD_PARALLEL_LEVEL="${parallel_level}" \
      --platform linux/${arch} \
      -f Dockerfile.local.optimized \
      -t substrait-extension-builder-local-opt:${DUCKDB_VERSION}-${platform}-${arch} \
      -t substrait-extension-builder-local-opt:${DUCKDB_VERSION}-latest \
      -t substrait-extension-builder-local-opt:latest \
      .

    echo ""
    log_info "Extracting extension binary..."

    # Run container and copy the extension
    docker run --rm \
      -v "$(cd "${OUTPUT_DIR}" && pwd):/output_mount" \
      substrait-extension-builder-local-opt:${DUCKDB_VERSION}-${platform}-${arch}

    echo ""
    local output_file="${OUTPUT_DIR}/substrait.duckdb_extension.${platform_name}_${arch}.gz"
    if [ -f "${output_file}" ]; then
        local build_end=$(date +%s)
        local build_time=$((build_end - build_start))
        log_success "Build complete for ${platform_name}_${arch} in ${build_time}s!"
        echo "Extension binary: ${output_file}"
        ls -lh "${output_file}"
    else
        log_warn "Expected output file not found: ${output_file}"
    fi
    echo ""
}

# Print optimization info
echo "=========================================="
echo "DuckDB Substrait Extension - Optimized Build"
echo "=========================================="
log_info "BuildKit: Enabled (better caching & parallel builds)"
log_info "ccache: Enabled (incremental C++ compilation)"
log_info "Multi-stage: Enabled (DuckDB build cached per version)"
log_info "Parallel builds: Enabled (using all CPU cores)"
echo ""

# Main build logic
total_start=$(date +%s)

if [ "${PLATFORM}" = "all" ]; then
    log_info "Building for all platforms and architectures..."
    echo ""

    # Build for Linux
    if [ "${ARCHITECTURE}" = "all" ]; then
        build_for_platform "linux" "amd64" "linux"
        build_for_platform "linux" "arm64" "linux"
    else
        build_for_platform "linux" "${ARCHITECTURE}" "linux"
    fi

    # Build for macOS
    if [ "${ARCHITECTURE}" = "all" ]; then
        build_for_platform "darwin" "amd64" "osx"
        build_for_platform "darwin" "arm64" "osx"
    else
        build_for_platform "darwin" "${ARCHITECTURE}" "osx"
    fi

    echo "=========================================="
    log_success "All builds complete!"
    echo "=========================================="
    echo "Output directory: ${OUTPUT_DIR}"
    ls -lh "${OUTPUT_DIR}"/*.gz
else
    # Single platform build
    platform_name="${PLATFORM}"
    if [ "${PLATFORM}" = "darwin" ]; then
        platform_name="osx"
    fi

    if [ "${ARCHITECTURE}" = "all" ]; then
        build_for_platform "${PLATFORM}" "amd64" "${platform_name}"
        build_for_platform "${PLATFORM}" "arm64" "${platform_name}"

        echo "=========================================="
        log_success "All builds complete for ${platform_name}!"
        echo "=========================================="
        echo "Output directory: ${OUTPUT_DIR}"
        ls -lh "${OUTPUT_DIR}"/*.gz
    else
        build_for_platform "${PLATFORM}" "${ARCHITECTURE}" "${platform_name}"
    fi
fi

total_end=$(date +%s)
total_time=$((total_end - total_start))

echo ""
echo "=========================================="
log_success "Total build time: ${total_time}s"
echo "=========================================="
echo ""
log_info "Tips for faster subsequent builds:"
echo "  • First build creates cache layers (slower)"
echo "  • Subsequent builds reuse cached DuckDB build (much faster)"
echo "  • ccache accumulates across builds for even faster iteration"
echo "  • To force clean build: SKIP_CACHE=1 $0"
echo ""
