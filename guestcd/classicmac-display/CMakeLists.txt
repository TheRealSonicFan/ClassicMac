# ClassicMac Display: a background-only classic Mac OS PowerPC (CFM)
# application that puts Mac OS's screen at the size ClassicMac chose for the
# emulated ATI Radeon. Derived from RetroBoot Display (MIT). Built with
# Retro68's PowerPC toolchain (see build.sh).
cmake_minimum_required(VERSION 3.10)
project(ClassicMacDisplay C)

if(NOT CMAKE_SYSTEM_NAME MATCHES "^RetroPPC$")
    message(FATAL_ERROR "Configure with Retro68's PowerPC toolchain file "
                        "(powerpc-apple-macos/cmake/retroppc.toolchain.cmake).")
endif()

set(CMAKE_C_STANDARD 99)
add_compile_options(-O2 -Wall -Wno-multichar -ffunction-sections)

add_application(ClassicMacDisplay
    TYPE appe CREATOR CMds
    FILES display.c display.r)
target_link_libraries(ClassicMacDisplay DisplayLib NameRegistryLib)
set_target_properties(ClassicMacDisplay PROPERTIES LINK_FLAGS "-Wl,-gc-sections")
