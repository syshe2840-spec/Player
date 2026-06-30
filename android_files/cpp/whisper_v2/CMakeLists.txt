# ══════════════════════════════════════════════════════════
#  Vezoo Whisper v2 — کامپایل whisper.cpp بومی روی Android
#  vendored از whisper.cpp v1.9.1 (فقط CPU backend)
# ══════════════════════════════════════════════════════════
cmake_minimum_required(VERSION 3.22.1)
project("vezoo_whisper_v2" C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ── ggml (فقط CPU backend — بک‌اندهای GPU حذف شدن) ──
set(GGML_CPU ON CACHE BOOL "" FORCE)
set(GGML_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GGML_BLAS OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

add_subdirectory(ggml)

# ── whisper.cpp (فقط همین یک فایل + هدرها) ──
add_library(whisper_core STATIC
    src/whisper.cpp
)
target_include_directories(whisper_core PUBLIC
    include
    src
)
target_compile_features(whisper_core PUBLIC cxx_std_17)
target_link_libraries(whisper_core PUBLIC ggml)

find_package(Threads REQUIRED)
target_link_libraries(whisper_core PUBLIC Threads::Threads)

# ── JNI Wrapper ما ──
find_library(LOG_LIB log)

add_library(vezoo_whisper SHARED
    jni_v2.c
)
target_link_libraries(vezoo_whisper PRIVATE whisper_core ggml ${LOG_LIB} android)
target_include_directories(vezoo_whisper PRIVATE include)

if (NOT CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(whisper_core PRIVATE -O3)
    target_compile_options(vezoo_whisper PRIVATE -O3)
endif()
