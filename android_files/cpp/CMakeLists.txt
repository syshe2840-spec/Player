cmake_minimum_required(VERSION 3.22.1)
project("vezoo")

add_library(vezoo SHARED vezoo.c vezoo_jni.c)

find_library(log-lib log)

# OpenSSL که با Android NDK API 28+ میاد
target_link_libraries(vezoo ${log-lib} crypto)

target_include_directories(vezoo PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
