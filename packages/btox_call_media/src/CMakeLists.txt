# The call media library for Linux and Windows. The podspec builds it for
# iOS and macOS.
cmake_minimum_required(VERSION 3.14)

project(btox_call_media_library VERSION 0.1.0 LANGUAGES C CXX)

set(THIRD_PARTY "${CMAKE_CURRENT_SOURCE_DIR}/../third_party")
set(SPEEXDSP "${THIRD_PARTY}/speexdsp")

add_library(btox_call_media SHARED
  audio.c
  "${THIRD_PARTY}/miniaudio/miniaudio.c"
  "${SPEEXDSP}/libspeexdsp/fftwrap.c"
  "${SPEEXDSP}/libspeexdsp/filterbank.c"
  "${SPEEXDSP}/libspeexdsp/kiss_fft.c"
  "${SPEEXDSP}/libspeexdsp/kiss_fftr.c"
  "${SPEEXDSP}/libspeexdsp/mdf.c"
  "${SPEEXDSP}/libspeexdsp/preprocess.c"
)

# tools/prepare-call-media downloads the third-party libraries, and speexdsp/
# holds what their configure scripts would write.
target_include_directories(btox_call_media PRIVATE
  speexdsp
  "${THIRD_PARTY}/miniaudio"
  "${SPEEXDSP}/include"
)

target_compile_definitions(btox_call_media PRIVATE
  HAVE_CONFIG_H
  MA_NO_DECODING
  MA_NO_ENCODING
  MA_NO_ENGINE
  MA_NO_GENERATION
  MA_NO_NODE_GRAPH
  MA_NO_RESOURCE_MANAGER
)

set_target_properties(btox_call_media PROPERTIES
  OUTPUT_NAME "btox_call_media"
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
)

if(WIN32)
  target_sources(btox_call_media PRIVATE camera_mf.cpp nv12.c)
  target_link_libraries(btox_call_media PRIVATE mf mfplat mfreadwrite mfuuid ole32)
else()
  target_sources(btox_call_media PRIVATE camera_v4l2.c)
  # miniaudio loads the sound system's library when it runs.
  target_link_libraries(btox_call_media PRIVATE m ${CMAKE_DL_LIBS} pthread)
endif()
