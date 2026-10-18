cmake_minimum_required(VERSION 3.22.1)
project(aether_jni)

add_library(aether SHARED IMPORTED)
set_target_properties(aether PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/${ANDROID_ABI}/libaether.so"
    IMPORTED_NO_SONAME TRUE)

add_library(aether_jni SHARED aether_jni.cpp mix_packet_jni.cpp)
target_link_options(aether_jni PRIVATE
    "-Wl,-z,max-page-size=16384")
# No -z common-page-size: it pads PT_GNU_RELRO to a 16K boundary that can
# overhang its LOAD segment end (RELRO@4K OVERRUN); max-page-size alone
# carries 16K device support.
find_library(log-lib log)
target_link_libraries(aether_jni aether ${log-lib})

# Hev (hev-socks5-tunnel) is built via ndk-build in CI (build.yml) and
# vendored as a prebuilt into jniLibs/ — not via add_subdirectory, so its
# lwIP copy does not share a CMake scope with badvpn's lwIP.
