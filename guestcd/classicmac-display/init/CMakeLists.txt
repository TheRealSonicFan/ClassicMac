# ClassicMac Display (startup extension): the 68k INIT variant of ClassicMac
# Display, which sets the Mac OS screen size for the emulated ATI Radeon while
# the extensions load. Derived from RetroBoot Display (MIT). Built with
# Retro68's 68k toolchain as a flat code resource (see ../build.sh).
cmake_minimum_required(VERSION 3.10)
project(ClassicMacDisplayInit C)

if(NOT CMAKE_SYSTEM_NAME MATCHES "^Retro68$")
    message(FATAL_ERROR "Configure with Retro68's 68k toolchain file "
                        "(m68k-apple-macos/cmake/retro68.toolchain.cmake).")
endif()

set(CMAKE_C_STANDARD 99)
add_compile_options(-Os -Wall -Wno-multichar -ffunction-sections
    --param=min-pagesize=0)          # low-memory globals (0x928...) are real addresses

# Step 1: the code as a flat piece of 68k code (no CODE/jump table)
add_executable(ClassicMacDisplayInit displayinit.c)
set_target_properties(ClassicMacDisplayInit PROPERTIES
    OUTPUT_NAME ClassicMacDisplayInit.flt
    LINK_FLAGS "-Wl,--mac-flat -Wl,-gc-sections")

# Step 2: Rez wraps it in 'INIT' 128 (MacBinary output, type INIT)
add_custom_command(
    OUTPUT ClassicMacDisplayInit.bin
    COMMAND ${REZ} -I${REZ_INCLUDE_PATH}
                   ${CMAKE_CURRENT_SOURCE_DIR}/displayinit.r
                   -o ClassicMacDisplayInit.bin
                   -t INIT -c CMds
    DEPENDS ClassicMacDisplayInit displayinit.r)
add_custom_target(ClassicMacDisplayInit_INIT ALL DEPENDS ClassicMacDisplayInit.bin)
