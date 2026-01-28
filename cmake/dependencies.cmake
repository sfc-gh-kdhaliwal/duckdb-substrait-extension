# cmake/dependencies.cmake
# Manages external dependencies for the Substrait extension

include(FetchContent)

# ============================================================================
# C++ Standard Override
# ============================================================================
# DuckDB uses C++11, but modern protobuf (22.x+) and abseil require C++14/17.
# We override the C++ standard for our dependencies and extension.
# This is ABI-compatible since we only use DuckDB's C++11-compatible public API.
set(CMAKE_CXX_STANDARD 17 CACHE STRING "" FORCE)
set(CMAKE_CXX_STANDARD_REQUIRED ON CACHE BOOL "" FORCE)

# ============================================================================
# Abseil - Required by modern protobuf
# ============================================================================
set(ABSL_VERSION "20240722.0")  # LTS version compatible with protobuf 29.x
set(ABSL_URL "https://github.com/abseil/abseil-cpp/archive/refs/tags/${ABSL_VERSION}.tar.gz")
set(ABSL_URL_HASH "SHA256=f50e5ac311a81382da7fa75b97310e4b9006474f9560ac46f54a9967f07d4ae3")

set(ABSL_PROPAGATE_CXX_STD ON CACHE BOOL "" FORCE)
set(ABSL_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(ABSL_BUILD_TESTING OFF CACHE BOOL "" FORCE)

FetchContent_Declare(abseil
  URL      ${ABSL_URL}
  URL_HASH ${ABSL_URL_HASH}
  EXCLUDE_FROM_ALL
)

FetchContent_MakeAvailable(abseil)

# ============================================================================
# Protobuf - Modern version with proper CMake integration
# ============================================================================
set(PROTOBUF_VERSION "29.5")
set(PROTOBUF_URL "https://github.com/protocolbuffers/protobuf/archive/refs/tags/v${PROTOBUF_VERSION}.tar.gz")
set(PROTOBUF_URL_HASH "SHA256=955ef3235be41120db4d367be81efe6891c9544b3a71194d80c3055865b26e09")

# Configure protobuf build options BEFORE fetching
set(protobuf_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_CONFORMANCE OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_PROTOBUF_BINARIES ON CACHE BOOL "" FORCE)
set(protobuf_BUILD_PROTOC_BINARIES ON CACHE BOOL "" FORCE)
set(protobuf_BUILD_LIBPROTOC ON CACHE BOOL "" FORCE)
set(protobuf_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(protobuf_INSTALL OFF CACHE BOOL "" FORCE)
set(protobuf_MSVC_STATIC_RUNTIME OFF CACHE BOOL "" FORCE)
set(protobuf_ABSL_PROVIDER "package" CACHE STRING "" FORCE)

# Hide symbols to avoid conflicts when extension is loaded into DuckDB
set(CMAKE_CXX_VISIBILITY_PRESET hidden CACHE STRING "" FORCE)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON CACHE BOOL "" FORCE)

FetchContent_Declare(protobuf
  URL      ${PROTOBUF_URL}
  URL_HASH ${PROTOBUF_URL_HASH}
  EXCLUDE_FROM_ALL
)

FetchContent_MakeAvailable(protobuf)

# Include the protobuf_generate function (provided by modern protobuf)
include(${protobuf_SOURCE_DIR}/cmake/protobuf-generate.cmake)

message(STATUS "Protobuf version: ${PROTOBUF_VERSION}")
message(STATUS "Protobuf source: ${protobuf_SOURCE_DIR}")
