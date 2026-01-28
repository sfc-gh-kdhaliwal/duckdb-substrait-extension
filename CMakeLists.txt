cmake_minimum_required(VERSION 3.5...3.29)

# Set extension name here
set(TARGET_NAME substrait)

set(EXTENSION_NAME ${TARGET_NAME}_extension)
project(${TARGET_NAME})

# Include external dependencies (protobuf via FetchContent)
include(cmake/dependencies.cmake)

include_directories(src/include)

# ============================================================================
# Protobuf Generation - Generate .pb.cc/.pb.h files at build time
# ============================================================================
set(PROTO_DIR ${CMAKE_CURRENT_SOURCE_DIR}/substrait/proto)
set(PROTO_FILES
    ${PROTO_DIR}/substrait/algebra.proto
    ${PROTO_DIR}/substrait/capabilities.proto
    ${PROTO_DIR}/substrait/extended_expression.proto
    ${PROTO_DIR}/substrait/function.proto
    ${PROTO_DIR}/substrait/parameterized_types.proto
    ${PROTO_DIR}/substrait/plan.proto
    ${PROTO_DIR}/substrait/type.proto
    ${PROTO_DIR}/substrait/type_expressions.proto
    ${PROTO_DIR}/substrait/extensions/extensions.proto
)

set(PROTO_OUT_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated)

# Ensure the output directory exists (protoc doesn't create it automatically)
file(MAKE_DIRECTORY ${PROTO_OUT_DIR})
file(MAKE_DIRECTORY ${PROTO_OUT_DIR}/substrait)
file(MAKE_DIRECTORY ${PROTO_OUT_DIR}/substrait/extensions)

# Create OBJECT library for proto files (Ninja-safe parallel compilation)
add_library(substrait_proto OBJECT ${PROTO_FILES})
target_link_libraries(substrait_proto PRIVATE protobuf::libprotobuf)
target_include_directories(substrait_proto 
    PUBLIC ${PROTO_OUT_DIR} ${protobuf_SOURCE_DIR}/src)

# Ensure proto library uses C++17 (required by protobuf/abseil)
set_target_properties(substrait_proto PROPERTIES 
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

# Generate C++ code from .proto files
protobuf_generate(
    TARGET substrait_proto
    LANGUAGE cpp
    IMPORT_DIRS ${PROTO_DIR} ${protobuf_SOURCE_DIR}/src
    PROTOC_OUT_DIR ${PROTO_OUT_DIR}
)

# ============================================================================
# Extension Library
# ============================================================================
set(EXTENSION_SOURCES
    src/to_substrait.cpp
    src/from_substrait_ast.cpp
    src/substrait_extension.cpp
    src/custom_extensions.cpp
    src/custom_extensions_generated.cpp)

# Include proto object files directly using $<TARGET_OBJECTS:>
# This includes the compiled .o files without creating a CMake target dependency
add_library(${EXTENSION_NAME} STATIC 
    ${EXTENSION_SOURCES}
    $<TARGET_OBJECTS:substrait_proto>
)

# Ensure extension uses C++17 (required by protobuf/abseil headers)
set_target_properties(${EXTENSION_NAME} PROPERTIES 
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

# Include generated headers, protobuf headers, and abseil headers
# Abseil headers are required because protobuf headers include them
target_include_directories(${EXTENSION_NAME} PRIVATE 
    ${PROTO_OUT_DIR} 
    ${protobuf_SOURCE_DIR}/src
    ${abseil_SOURCE_DIR}
)

# ============================================================================
# Link protobuf and abseil using file paths (Delta extension pattern)
# ============================================================================
# CMake's export system requires all target_link_libraries dependencies to be
# exportable. FetchContent-built libraries are NOT in the export set.
#
# Solution: Link to the protobuf/abseil static libraries using FILE PATHs (strings),
# not CMake targets. This is the same pattern used by the delta extension
# for linking to delta-kernel-rs. CMake doesn't track string paths as target
# dependencies, so no export issues arise.

# Ensure protobuf is built first
add_dependencies(${EXTENSION_NAME} libprotobuf)

# Determine library suffix based on platform
if(WIN32)
    set(LIB_SUFFIX ".lib")
else()
    set(LIB_SUFFIX ".a")
endif()

# Set base paths for libraries
set(PROTOBUF_BUILD_DIR "${CMAKE_BINARY_DIR}/_deps/protobuf-build")
set(ABSEIL_BUILD_DIR "${CMAKE_BINARY_DIR}/_deps/abseil-build")

# Protobuf library
set(PROTOBUF_LIB_PATH "${PROTOBUF_BUILD_DIR}/libprotobuf${LIB_SUFFIX}")

# Abseil libraries required by protobuf (order matters due to dependencies)
# These are needed because protobuf 29.x uses abseil internally
set(ABSEIL_LIBS
    # Status (required by protobuf's json functions)
    "${ABSEIL_BUILD_DIR}/absl/status/libabsl_status${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/status/libabsl_statusor${LIB_SUFFIX}"
    # Strings and Cord (heavily used by protobuf)
    "${ABSEIL_BUILD_DIR}/absl/strings/libabsl_strings${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/strings/libabsl_strings_internal${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/strings/libabsl_str_format_internal${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/strings/libabsl_string_view${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/strings/libabsl_cord${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/strings/libabsl_cord_internal${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/strings/libabsl_cordz_functions${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/strings/libabsl_cordz_handle${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/strings/libabsl_cordz_info${LIB_SUFFIX}"
    # Synchronization (Mutex, etc.)
    "${ABSEIL_BUILD_DIR}/absl/synchronization/libabsl_synchronization${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/synchronization/libabsl_graphcycles_internal${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/synchronization/libabsl_kernel_timeout_internal${LIB_SUFFIX}"
    # Containers (raw_hash_set used by protobuf)
    "${ABSEIL_BUILD_DIR}/absl/container/libabsl_raw_hash_set${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/container/libabsl_hashtablez_sampler${LIB_SUFFIX}"
    # Hash
    "${ABSEIL_BUILD_DIR}/absl/hash/libabsl_hash${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/hash/libabsl_city${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/hash/libabsl_low_level_hash${LIB_SUFFIX}"
    # Time
    "${ABSEIL_BUILD_DIR}/absl/time/libabsl_time${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/time/libabsl_time_zone${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/time/libabsl_civil_time${LIB_SUFFIX}"
    # CRC (used by Cord)
    "${ABSEIL_BUILD_DIR}/absl/crc/libabsl_crc32c${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/crc/libabsl_crc_cord_state${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/crc/libabsl_crc_internal${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/crc/libabsl_crc_cpu_detect${LIB_SUFFIX}"
    # Debugging/Profiling
    "${ABSEIL_BUILD_DIR}/absl/debugging/libabsl_stacktrace${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/debugging/libabsl_symbolize${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/debugging/libabsl_debugging_internal${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/debugging/libabsl_demangle_internal${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/debugging/libabsl_demangle_rust${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/debugging/libabsl_decode_rust_punycode${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/debugging/libabsl_utf8_for_code_point${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/debugging/libabsl_examine_stack${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/debugging/libabsl_leak_check${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/profiling/libabsl_exponential_biased${LIB_SUFFIX}"
    # Base types
    "${ABSEIL_BUILD_DIR}/absl/types/libabsl_bad_optional_access${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/types/libabsl_bad_variant_access${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/numeric/libabsl_int128${LIB_SUFFIX}"
    # Log (required by protobuf for CHECK/LOG macros)
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_log_internal_message${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_log_internal_check_op${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_log_internal_conditions${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_log_internal_nullguard${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_log_internal_format${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_log_internal_globals${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_log_internal_proto${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_log_internal_log_sink_set${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_log_internal_fnmatch${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_log_entry${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_log_globals${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_log_initialize${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_log_sink${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_die_if_null${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/log/libabsl_vlog_config_internal${LIB_SUFFIX}"
    # Flags (used by some logging functions)
    "${ABSEIL_BUILD_DIR}/absl/flags/libabsl_flags_internal${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/flags/libabsl_flags_reflection${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/flags/libabsl_flags_config${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/flags/libabsl_flags_program_name${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/flags/libabsl_flags_commandlineflag${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/flags/libabsl_flags_commandlineflag_internal${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/flags/libabsl_flags_marshalling${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/flags/libabsl_flags_private_handle_accessor${LIB_SUFFIX}"
    # Base (commonly used)
    "${ABSEIL_BUILD_DIR}/absl/base/libabsl_base${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/base/libabsl_raw_logging_internal${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/base/libabsl_spinlock_wait${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/base/libabsl_throw_delegate${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/base/libabsl_strerror${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/base/libabsl_log_severity${LIB_SUFFIX}"
    "${ABSEIL_BUILD_DIR}/absl/base/libabsl_malloc_internal${LIB_SUFFIX}"
)

# UTF8 validity library (part of protobuf, used for string validation)
set(UTF8_VALIDITY_LIB "${PROTOBUF_BUILD_DIR}/third_party/utf8_range/libutf8_validity${LIB_SUFFIX}")

# On macOS, abseil's time_zone library requires CoreFoundation
if(APPLE)
    find_library(COREFOUNDATION_LIBRARY CoreFoundation REQUIRED)
    set(PLATFORM_LIBS ${COREFOUNDATION_LIBRARY})
else()
    set(PLATFORM_LIBS "")
endif()

# Link using file path strings (not CMake targets) - avoids export dependency
target_link_libraries(${EXTENSION_NAME} PRIVATE 
    "${PROTOBUF_LIB_PATH}"
    "${UTF8_VALIDITY_LIB}"
    ${ABSEIL_LIBS}
    ${PLATFORM_LIBS}
)

set(PARAMETERS "-warnings")
if(COMMAND build_loadable_extension)
  build_loadable_extension(${TARGET_NAME} ${PARAMETERS} ${EXTENSION_SOURCES})
  
  # Add protobuf objects to the loadable extension
  target_sources(${TARGET_NAME}_loadable_extension PRIVATE $<TARGET_OBJECTS:substrait_proto>)
  
  # Configure includes and libraries for the loadable extension
  target_include_directories(${TARGET_NAME}_loadable_extension PRIVATE 
      ${PROTO_OUT_DIR} 
      ${protobuf_SOURCE_DIR}/src
      ${abseil_SOURCE_DIR}
  )
  
  # Link protobuf and abseil libraries to the loadable extension (plain signature to match DuckDB)
  target_link_libraries(${TARGET_NAME}_loadable_extension
      "${PROTOBUF_LIB_PATH}"
      "${UTF8_VALIDITY_LIB}"
      ${ABSEIL_LIBS}
      ${PLATFORM_LIBS}
  )
  
  # Ensure C++17 for the loadable extension
  set_target_properties(${TARGET_NAME}_loadable_extension PROPERTIES 
      CXX_STANDARD 17
      CXX_STANDARD_REQUIRED ON
  )
  
  if(DEFINED ENV{SKIP_SUBSTRAIT_C_TESTS})
    message(STATUS "Skipping substrait c tests")
  else()
    add_subdirectory("test/c")
  endif()
endif()

# Install with export - required because DuckDB links substrait_extension
# into duckdb_static which is exported
install(
  TARGETS ${EXTENSION_NAME}
  EXPORT "${DUCKDB_EXPORT_SET}"
  LIBRARY DESTINATION "${INSTALL_LIB_DIR}"
  ARCHIVE DESTINATION "${INSTALL_LIB_DIR}")
