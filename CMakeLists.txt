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

# Create OBJECT library for proto files (Ninja-safe parallel compilation)
add_library(substrait_proto OBJECT ${PROTO_FILES})
target_link_libraries(substrait_proto PUBLIC protobuf::libprotobuf)
target_include_directories(substrait_proto 
    PUBLIC ${PROTO_OUT_DIR} ${protobuf_SOURCE_DIR}/src)

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

add_library(${EXTENSION_NAME} STATIC ${EXTENSION_SOURCES})

# Link against substrait proto library and protobuf
target_link_libraries(${EXTENSION_NAME} PUBLIC substrait_proto protobuf::libprotobuf)

# Include generated headers and protobuf headers
target_include_directories(${EXTENSION_NAME} PRIVATE ${PROTO_OUT_DIR} ${protobuf_SOURCE_DIR}/src)

set(PARAMETERS "-warnings")
if(COMMAND build_loadable_extension)
  build_loadable_extension(${TARGET_NAME} ${PARAMETERS} ${EXTENSION_SOURCES})
  target_link_libraries(${TARGET_NAME} PUBLIC substrait_proto)
  
  if(DEFINED ENV{SKIP_SUBSTRAIT_C_TESTS})
    message(STATUS "Skipping substrait c tests")
  else()
    add_subdirectory("test/c")
  endif()
endif()

install(
  TARGETS ${EXTENSION_NAME}
  EXPORT "${DUCKDB_EXPORT_SET}"
  LIBRARY DESTINATION "${INSTALL_LIB_DIR}"
  ARCHIVE DESTINATION "${INSTALL_LIB_DIR}")
