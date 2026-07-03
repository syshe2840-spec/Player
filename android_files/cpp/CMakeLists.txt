cmake_minimum_required(VERSION 3.22.1)
project("vezoo")

# Pure C — بدون dependency خارجی
add_library(vezoo SHARED vezoo.c vezoo_jni.c)

find_library(log-lib log)
target_link_libraries(vezoo ${log-lib})

target_include_directories(vezoo PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
set_target_properties(vezoo PROPERTIES C_STANDARD 99)

# ── AI v2 — whisper.cpp بومی (کتابخانه جداگانه، libvezoo_whisper.so) ──
# اضافه‌شده به‌صورت additive؛ تارگت vezoo بالا دست‌نخورده می‌ماند
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/whisper_v2/CMakeLists.txt")
    add_subdirectory(whisper_v2)
endif()
