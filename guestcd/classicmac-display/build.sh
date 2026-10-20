#!/bin/sh
# Build ClassicMac Display with Retro68 and install the MacBinary outputs that
# scripts/build-guest-cd.sh puts on the Tools CD (committed, like the other
# prebuilt guest drivers, so the Tools CD build needs no cross compiler):
#   bin/ClassicMacDisplayInit.bin  " ClassicMac Display Startup", 68k INIT
#   bin/ClassicMacDisplay.bin      "ClassicMac Display", PowerPC appe
#
#   RETRO68_TOOLCHAIN  Retro68-build/toolchain directory (read only; default
#                      vendor/Retro68-build/toolchain of this checkout)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
tc=${RETRO68_TOOLCHAIN:-$root/vendor/Retro68-build/toolchain}
build=${BUILD:-$root/output/classicmac-display-build}
[ -f "$tc/powerpc-apple-macos/cmake/retroppc.toolchain.cmake" ] || {
    echo "Retro68 PowerPC toolchain not found at $tc (set RETRO68_TOOLCHAIN)" >&2; exit 1; }
cmake -S "$here" -B "$build/ppc" \
    -DCMAKE_TOOLCHAIN_FILE="$tc/powerpc-apple-macos/cmake/retroppc.toolchain.cmake" \
    -DCMAKE_BUILD_TYPE=Release
cmake --build "$build/ppc"
cmake -S "$here/init" -B "$build/init" \
    -DCMAKE_TOOLCHAIN_FILE="$tc/m68k-apple-macos/cmake/retro68.toolchain.cmake" \
    -DCMAKE_BUILD_TYPE=Release
cmake --build "$build/init"
mkdir -p "$here/bin"
cp "$build/ppc/ClassicMacDisplay.bin" "$here/bin/ClassicMacDisplay.bin"
cp "$build/init/ClassicMacDisplayInit.bin" "$here/bin/ClassicMacDisplayInit.bin"
shasum -a 256 "$here/bin/ClassicMacDisplay.bin" "$here/bin/ClassicMacDisplayInit.bin"
