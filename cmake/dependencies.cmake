# cmake/dependencies.cmake
# Manages external dependencies for the Substrait extension

include(FetchContent)

# ============================================================================
# Protobuf v3.19.4 - MUST match version used to generate .pb.cc files
# ============================================================================
set(PROTOBUF_VERSION "3.19.4")
set(PROTOBUF_URL "https://github.com/protocolbuffers/protobuf/archive/refs/tags/v${PROTOBUF_VERSION}.tar.gz")
set(PROTOBUF_URL_HASH "SHA256=3bd7828aa5af4b13b99c191e8b1e884ebfa9ad371b0ce264605d347f135d2568")

# Configure protobuf build options BEFORE fetching
set(protobuf_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_PROTOC_BINARIES ON CACHE BOOL "" FORCE)
set(protobuf_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(protobuf_MSVC_STATIC_RUNTIME OFF CACHE BOOL "" FORCE)

# Hide protobuf symbols to avoid conflicts when extension is loaded
set(CMAKE_CXX_VISIBILITY_PRESET hidden CACHE STRING "" FORCE)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON CACHE BOOL "" FORCE)

FetchContent_Declare(protobuf
  URL      ${PROTOBUF_URL}
  URL_HASH ${PROTOBUF_URL_HASH}
  EXCLUDE_FROM_ALL
)

# Manually fetch and patch before adding subdirectory
FetchContent_GetProperties(protobuf)
if(NOT protobuf_POPULATED)
  FetchContent_Populate(protobuf)
  
  # Patch the CMakeLists.txt to work with CMake 3.5+ (required for modern CMake)
  set(_CMAKELISTS "${protobuf_SOURCE_DIR}/cmake/CMakeLists.txt")
  file(READ "${_CMAKELISTS}" _CONTENT)
  string(REPLACE "cmake_minimum_required(VERSION 3.1.3)" 
                 "cmake_minimum_required(VERSION 3.10)"
                 _CONTENT "${_CONTENT}")
  file(WRITE "${_CMAKELISTS}" "${_CONTENT}")
  
  # Now add the cmake subdirectory
  add_subdirectory("${protobuf_SOURCE_DIR}/cmake" "${protobuf_BINARY_DIR}" EXCLUDE_FROM_ALL)
endif()

# Include protobuf_generate() function for later phases (Phase 3)
# Note: protobuf-generate.cmake is only available in newer protobuf versions
# For v3.19.4, we handle protobuf code generation differently
# include(${protobuf_SOURCE_DIR}/cmake/protobuf-generate.cmake)

message(STATUS "Protobuf version: ${PROTOBUF_VERSION}")
message(STATUS "Protobuf source: ${protobuf_SOURCE_DIR}")
