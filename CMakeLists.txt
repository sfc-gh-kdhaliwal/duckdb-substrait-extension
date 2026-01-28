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
# Link protobuf and abseil using $<TARGET_FILE:> generator expressions
# ============================================================================
# CMake's export system requires all target_link_libraries dependencies to be
# exportable. FetchContent-built libraries are NOT in the export set.
#
# Solution: Use $<TARGET_FILE:target> generator expressions to get library file
# paths. This breaks the CMake target dependency graph while still:
# 1. Using the correct library files (auto-discovered from targets)
# 2. Automatically handling library locations across platforms
# 3. Getting transitive dependencies resolved correctly
#
# The key insight: $<TARGET_FILE:target> is evaluated at generate-time to produce
# a plain file path string. CMake does NOT track this as a target dependency
# for export purposes.

# ============================================================================
# Helper function: Recursively collect all library files from target deps
# ============================================================================
# This handles both direct and transitive abseil dependencies by walking the
# INTERFACE_LINK_LIBRARIES and LINK_LIBRARIES properties of each target.

function(get_real_target target out_var)
    if(NOT TARGET ${target})
        set(${out_var} "" PARENT_SCOPE)
        return()
    endif()
    get_target_property(_aliased ${target} ALIASED_TARGET)
    if(_aliased)
        set(${out_var} ${_aliased} PARENT_SCOPE)
    else()
        set(${out_var} ${target} PARENT_SCOPE)
    endif()
endfunction()

function(collect_target_files seed_targets out_var)
    set(_result "")
    set(_visited "")
    set(_queue ${seed_targets})
    
    while(_queue)
        list(POP_FRONT _queue _current)
        
        # Skip if already visited or not a target
        if(_current IN_LIST _visited)
            continue()
        endif()
        list(APPEND _visited ${_current})
        
        # Resolve alias to real target
        get_real_target(${_current} _real)
        if(NOT _real)
            continue()
        endif()
        
        # Get target type
        get_target_property(_type ${_real} TYPE)
        
        # If it's a real library (not INTERFACE), add its file path
        if(_type STREQUAL "STATIC_LIBRARY" OR _type STREQUAL "SHARED_LIBRARY" OR _type STREQUAL "MODULE_LIBRARY")
            list(APPEND _result "$<TARGET_FILE:${_current}>")
        endif()
        
        # Queue dependencies from INTERFACE_LINK_LIBRARIES
        get_target_property(_iface_deps ${_real} INTERFACE_LINK_LIBRARIES)
        if(_iface_deps)
            foreach(_dep IN LISTS _iface_deps)
                if(TARGET ${_dep})
                    list(APPEND _queue ${_dep})
                endif()
            endforeach()
        endif()
        
        # Queue dependencies from LINK_LIBRARIES (non-interface)
        get_target_property(_link_deps ${_real} LINK_LIBRARIES)
        if(_link_deps)
            foreach(_dep IN LISTS _link_deps)
                if(TARGET ${_dep})
                    list(APPEND _queue ${_dep})
                endif()
            endforeach()
        endif()
    endwhile()
    
    list(REMOVE_DUPLICATES _result)
    set(${out_var} ${_result} PARENT_SCOPE)
endfunction()

# ============================================================================
# Collect all protobuf and abseil library files
# ============================================================================
# Start with protobuf's libprotobuf and utf8_validity, plus all abseil targets
# that protobuf declares it needs (${protobuf_ABSL_USED_TARGETS})

set(_seed_targets libprotobuf utf8_validity ${protobuf_ABSL_USED_TARGETS})
collect_target_files("${_seed_targets}" PROTOBUF_ABSEIL_LIBS)

message(STATUS "Collected ${CMAKE_MATCH_COUNT} protobuf/abseil libraries via TARGET_FILE resolution")

# Ensure build order - protobuf (and transitively abseil) must be built first
add_dependencies(${EXTENSION_NAME} libprotobuf)

# On macOS, abseil's time_zone library requires CoreFoundation
if(APPLE)
    find_library(COREFOUNDATION_LIBRARY CoreFoundation REQUIRED)
    set(PLATFORM_LIBS ${COREFOUNDATION_LIBRARY})
else()
    set(PLATFORM_LIBS "")
endif()

# Link using $<TARGET_FILE:> expressions - breaks CMake target graph for exports
target_link_libraries(${EXTENSION_NAME} PRIVATE 
    ${PROTOBUF_ABSEIL_LIBS}
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
  
  # Ensure loadable extension waits for protobuf build
  add_dependencies(${TARGET_NAME}_loadable_extension libprotobuf)
  
  # Link protobuf and abseil libraries using the same TARGET_FILE approach
  target_link_libraries(${TARGET_NAME}_loadable_extension
      ${PROTOBUF_ABSEIL_LIBS}
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
