# Builds the library in ../src, which Flutter bundles with the app.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "btox_call_media")
project(${PROJECT_NAME} LANGUAGES C CXX)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

set(btox_call_media_bundled_libraries
  $<TARGET_FILE:btox_call_media>
  PARENT_SCOPE
)
