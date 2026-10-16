cmake_minimum_required(VERSION 3.22.1)
project(kamhost C)

# Engine compiled by Free Pascal (android/build_native.sh)
add_library(kamcore SHARED IMPORTED)
set_target_properties(kamcore PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/arm64-v8a/libkamcore.so)

add_library(kamhost SHARED kamhost.c)
target_link_libraries(kamhost PRIVATE kamcore android log)
target_link_options(kamhost PRIVATE "-Wl,-z,max-page-size=16384")
