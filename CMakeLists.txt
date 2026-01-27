cmake_minimum_required(VERSION 3.5...3.29)

# Set extension name here
set(TARGET_NAME substrait)

set(EXTENSION_NAME ${TARGET_NAME}_extension)
project(${TARGET_NAME})

# Include external dependencies (protobuf via FetchContent)
include(cmake/dependencies.cmake)

include_directories(src/include)

include_directories(third_party/substrait)
include_directories(third_party/)

set(SUBSTRAIT_SOURCES
    third_party/substrait/substrait/algebra.pb.cc
    third_party/substrait/substrait/capabilities.pb.cc
    third_party/substrait/substrait/function.pb.cc
    third_party/substrait/substrait/parameterized_types.pb.cc
    third_party/substrait/substrait/plan.pb.cc
    third_party/substrait/substrait/type.pb.cc
    third_party/substrait/substrait/type_expressions.pb.cc
    third_party/substrait/substrait/extensions/extensions.pb.cc)

set(EXTENSION_SOURCES
    src/to_substrait.cpp
    src/from_substrait_ast.cpp
    src/substrait_extension.cpp
    src/custom_extensions.cpp
    src/custom_extensions_generated.cpp
    ${SUBSTRAIT_SOURCES})

add_library(${EXTENSION_NAME} STATIC ${EXTENSION_SOURCES})

# Link against protobuf library target
target_link_libraries(${EXTENSION_NAME} PUBLIC protobuf::libprotobuf)

# Include protobuf headers
target_include_directories(${EXTENSION_NAME} PRIVATE ${protobuf_SOURCE_DIR}/src)

set(PARAMETERS "-warnings")
build_loadable_extension(${TARGET_NAME} ${PARAMETERS} ${EXTENSION_SOURCES})
if(DEFINED ENV{SKIP_SUBSTRAIT_C_TESTS})
  message(STATUS "Skipping substrait c tests")
else()
  add_subdirectory("test/c")
endif()

install(
  TARGETS ${EXTENSION_NAME}
  EXPORT "${DUCKDB_EXPORT_SET}"
  LIBRARY DESTINATION "${INSTALL_LIB_DIR}"
  ARCHIVE DESTINATION "${INSTALL_LIB_DIR}")
