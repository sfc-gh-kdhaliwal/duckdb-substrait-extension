# Docker Build Guide

This document explains how to use `build_extension_docker_local_optimized.sh` to build the DuckDB Substrait extension for multiple platforms and architectures.

## Quick Start

```bash
# Basic build (Linux amd64)
./build_extension_docker_local_optimized.sh

# Build for specific DuckDB version
./build_extension_docker_local_optimized.sh v1.4.2

# Build for specific output directory
./build_extension_docker_local_optimized.sh v1.4.2 ./output

# Build all platforms and architectures
./build_extension_docker_local_optimized.sh v1.4.2 ./output all all

# Force clean build (no cache)
SKIP_CACHE=1 ./build_extension_docker_local_optimized.sh

# Verbose output
VERBOSE=1 ./build_extension_docker_local_optimized.sh
```

## Complete Usage Guide

### Script Syntax

```bash
./build_extension_docker_local_optimized.sh [DUCKDB_VERSION] [OUTPUT_DIR] [PLATFORM] [ARCHITECTURE]
```

### Parameters

**1. DUCKDB_VERSION** (optional, default: `v1.4.2`)
   - Any valid DuckDB git tag or version
   - Examples: `v1.4.2`, `v1.4.1`, `v1.4.0`, `v1.3.0`
   - Must match an existing tag at https://github.com/duckdb/duckdb/tags

**2. OUTPUT_DIR** (optional, default: `./output_optimized`)
   - Directory where the built extension binaries will be saved
   - Created automatically if it doesn't exist
   - Examples: `./output`, `./build_artifacts`, `/tmp/duckdb-builds`

**3. PLATFORM** (optional, default: `linux`)
   - `linux` - Build for Linux
   - `darwin` - Build for macOS
   - `all` - Build for both Linux and macOS

**4. ARCHITECTURE** (optional, default: `amd64`)
   - `amd64` - Build for x86_64/AMD64 (Intel/AMD processors)
   - `arm64` - Build for ARM64 (Apple Silicon, AWS Graviton, etc.)
   - `all` - Build for both architectures

### Environment Variables

**SKIP_CACHE** (optional, default: not set)
   - Set to `1` to disable all caching and force a clean build
   - Useful for troubleshooting or ensuring a completely fresh build
   - Example: `SKIP_CACHE=1 ./build_extension_docker_local_optimized.sh`

**VERBOSE** (optional, default: not set)
   - Set to `1` to enable verbose Docker output
   - Shows detailed build logs and compilation steps
   - Example: `VERBOSE=1 ./build_extension_docker_local_optimized.sh`

**BUILD_PARALLEL_LEVEL** (optional, default: `2`)
   - Controls number of parallel compilation jobs
   - Default is `2` to prevent out-of-memory issues
   - Can increase for systems with more RAM (e.g., `4`, `8`)
   - Example: `BUILD_PARALLEL_LEVEL=4 ./build_extension_docker_local_optimized.sh`

### Common Usage Examples

#### Basic Builds

```bash
# Default build (Linux amd64, DuckDB v1.4.2)
./build_extension_docker_local_optimized.sh

# Build for DuckDB v1.4.1
./build_extension_docker_local_optimized.sh v1.4.1

# Build to specific output directory
./build_extension_docker_local_optimized.sh v1.4.2 ./my-builds
```

#### Platform-Specific Builds

```bash
# Build for Linux AMD64 (x86_64)
./build_extension_docker_local_optimized.sh v1.4.2 ./output linux amd64

# Build for Linux ARM64
./build_extension_docker_local_optimized.sh v1.4.2 ./output linux arm64

# Build for macOS AMD64 (Intel Macs)
./build_extension_docker_local_optimized.sh v1.4.2 ./output darwin amd64

# Build for macOS ARM64 (Apple Silicon)
./build_extension_docker_local_optimized.sh v1.4.2 ./output darwin arm64
```

#### Multi-Platform Builds

```bash
# Build for Linux on both architectures
./build_extension_docker_local_optimized.sh v1.4.2 ./output linux all

# Build for macOS on both architectures
./build_extension_docker_local_optimized.sh v1.4.2 ./output darwin all

# Build everything (all platforms and architectures)
./build_extension_docker_local_optimized.sh v1.4.2 ./output all all
```

#### Advanced Usage

```bash
# Clean build without cache (troubleshooting)
SKIP_CACHE=1 ./build_extension_docker_local_optimized.sh v1.4.2

# Verbose build with detailed output
VERBOSE=1 ./build_extension_docker_local_optimized.sh v1.4.2

# High-memory system with more parallel compilation
BUILD_PARALLEL_LEVEL=8 ./build_extension_docker_local_optimized.sh v1.4.2

# Combine multiple options
VERBOSE=1 BUILD_PARALLEL_LEVEL=4 ./build_extension_docker_local_optimized.sh v1.4.2 ./output all all
```

### Output Files

The script produces gzipped extension binaries with platform-specific naming:

```
output_optimized/
├── substrait.duckdb_extension.linux_amd64.gz
├── substrait.duckdb_extension.linux_arm64.gz
├── substrait.duckdb_extension.osx_amd64.gz
└── substrait.duckdb_extension.osx_arm64.gz
```

To use the extension:

```bash
# Extract the extension (creates uncompressed file)
gunzip output_optimized/substrait.duckdb_extension.linux_amd64.gz

# Load in DuckDB
./duckdb
LOAD 'output_optimized/substrait.duckdb_extension.linux_amd64';
```

## Performance Improvements

### Expected Build Times

| Build Type | Original | Optimized | Improvement |
|------------|----------|-----------|-------------|
| First build (cold cache) | ~30-40 min | ~25-30 min | ~20-30% |
| Second build (warm cache) | ~30-40 min | ~3-5 min | **85-90%** |
| Code-only change | ~30-40 min | ~2-3 min | **92-95%** |

### Key Optimizations

## 1. Multi-Stage Builds with Layer Caching

**What it does:** Separates the build into 4 stages:
- Base: Dependencies (rarely changes)
- DuckDB Builder: Builds DuckDB once per version
- Extension Builder: Builds only your extension code
- Packager: Creates final output

**Impact:**
- DuckDB build is cached per version (saves 20-25 minutes on subsequent builds)
- Dependency installation cached indefinitely
- Only extension code rebuilds when you make changes

## 2. ccache Integration

**What it does:** Caches compiled C++ object files across builds

**Impact:**
- Incremental compilation: Only changed files recompile
- 70-80% faster C++ compilation on subsequent builds
- Persistent across container runs via cache mounts

**Configuration:**
```dockerfile
ENV CCACHE_DIR=/cache/ccache
ENV CCACHE_COMPRESS=1
ENV CCACHE_MAXSIZE=2G
```

## 3. Docker BuildKit Cache Mounts

**What it does:** Persists ccache between Docker builds using BuildKit's cache mount feature

**Impact:**
- ccache persists even when container is destroyed
- Accumulates cache across all builds
- No manual volume management needed

**Usage in Dockerfile:**
```dockerfile
RUN --mount=type=cache,target=/cache/ccache \
    make release -j$(nproc)
```

## 4. Parallel Compilation

**What it does:** Uses all available CPU cores for compilation

**Impact:**
- 4-8x faster compilation on multi-core systems
- Automatically detects CPU count with `$(nproc)`

**Implementation:**
```dockerfile
RUN make release -j$(nproc)
```

## 5. Optimized Layer Ordering

**What it does:** Orders Dockerfile commands to maximize cache hits

**Strategy:**
1. Install dependencies (rarely changes) → cached
2. Build DuckDB (changes per version) → cached per version
3. Copy extension source (changes frequently) → last layer
4. Build extension → only rebuilds when code changes

**Impact:**
- Minimizes unnecessary rebuilds
- Docker reuses cached layers whenever possible

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Stage 1: Base (ubuntu + dependencies)                   │
│ Cached: Until dependencies change                       │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Stage 2: DuckDB Builder                                 │
│ - Clones DuckDB at specific version                     │
│ - Builds with ccache + parallel builds                  │
│ Cached: Per DuckDB version (v1.4.2, v1.4.1, etc)       │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Stage 3: Extension Builder                              │
│ - Copies pre-built DuckDB from Stage 2 (fast!)         │
│ - Copies extension source code                          │
│ - Builds extension with ccache + parallel               │
│ Cached: Only when extension code unchanged              │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Stage 4: Packager                                       │
│ - Extracts binary                                        │
│ - Compresses to .gz                                      │
│ - Creates output scripts                                 │
└─────────────────────────────────────────────────────────┘
```

## Comparison: Original vs Optimized

### Original Approach (Dockerfile.local)
```dockerfile
# Install deps
COPY . /build/
# Initialize submodules
# Build DuckDB from source
# Build extension
```

**Problems:**
- Everything rebuilds when any file changes
- No compilation caching
- Single-stage means no layer reuse
- Sequential compilation (not using all cores)

### Optimized Approach (Dockerfile.local.optimized)
```dockerfile
Stage 1: Base (deps) ━━━━━━━━━━━━━━┓
Stage 2: DuckDB ━━━━━━━━━━━━━━━━━━┫ Cached!
Stage 3: Extension (with ccache) ━━┛
Stage 4: Package
```

**Benefits:**
- Stages 1-2 cached across builds
- ccache speeds up Stage 3
- Parallel compilation on all stages
- Only extension code triggers rebuild

## Cache Management

### View Docker Cache
```bash
docker system df -v
```

### Clear Docker Cache (if needed)
```bash
# Clear all build cache
docker builder prune -a

# Clear only old cache (keep recent)
docker builder prune --filter "until=24h"
```

### Monitor ccache Statistics
The build script shows ccache stats at the end of each build.

## Troubleshooting

### Build Fails with "cache mount not supported"
**Solution:** Ensure Docker BuildKit is enabled:
```bash
export DOCKER_BUILDKIT=1
```

### Very slow first build
**Expected:** First build must download and compile everything. Subsequent builds will be much faster.

### Cache not working
**Solution:** Force rebuild to recreate cache:
```bash
SKIP_CACHE=1 ./build_extension_docker_local_optimized.sh
```

### Out of disk space
**Solution:** ccache can grow large. Clear old cache:
```bash
docker builder prune -a
```

## Advanced Usage

### Build with Custom DuckDB Branch
```bash
# Modify Dockerfile.local.optimized line 33 to:
# git checkout ${DUCKDB_VERSION} || git checkout -b ${DUCKDB_VERSION} origin/${DUCKDB_VERSION}

# Then build:
./build_extension_docker_local_optimized.sh my-custom-branch
```

### Increase ccache Size
Edit `Dockerfile.local.optimized`:
```dockerfile
ENV CCACHE_MAXSIZE=5G  # Increase from 2G to 5G
```

### Build for Multiple Versions in Parallel
```bash
./build_extension_docker_local_optimized.sh v1.4.2 ./output_142 &
./build_extension_docker_local_optimized.sh v1.4.1 ./output_141 &
wait
```

## Best Practices

1. **First Build:** Expect 25-30 minutes for initial build with cold cache
2. **Subsequent Builds:** Should complete in 2-5 minutes with warm cache
3. **Different DuckDB Versions:** Each version maintains its own cache layer
4. **Code Changes:** Only changed files recompile thanks to ccache
5. **Clean Builds:** Use `SKIP_CACHE=1` only when troubleshooting

## Metrics to Monitor

- **First build time:** Should be similar to original (~25-30 min)
- **Second build time:** Should be 85-90% faster (~3-5 min)
- **Code-only change build:** Should be 92-95% faster (~2-3 min)
- **Disk usage:** Monitor with `docker system df`

If you're not seeing these improvements, check that BuildKit is enabled and review the troubleshooting section.
