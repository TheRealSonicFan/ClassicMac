#!/usr/bin/env bash
# Reproducible native Copland engine. No guest disks or Apple ROMs are fetched.
# CLASSICMAC_ARCH (arm64 or x86_64, default: this host's) selects the target
# architecture; CMake cross-compiles the other one from either kind of Mac.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ROOT_DIR/vendor/dingusppc"
SDL="$ROOT_DIR/vendor/SDL2"
ENGINE_COMMIT=8dcac6fb160adfd8860c2252fba321d412b2c8a6
SDL_COMMIT=5d249570393f7a37e037abf22cd6012a4cc56a71
TARGET_ARCH="${CLASSICMAC_ARCH:-$(uname -m)}"
case "$TARGET_ARCH" in
    arm64|x86_64) ;;
    *) echo "Unsupported CLASSICMAC_ARCH: $TARGET_ARCH (expected arm64 or x86_64)" >&2; exit 1 ;;
esac
for tool in git cmake ninja; do command -v "$tool" >/dev/null; done
mkdir -p "$ROOT_DIR/vendor"
if [ ! -d "$ENGINE/.git" ] && [ ! -f "$ENGINE/SOURCE-REVISION" ]; then
    git clone --branch copland-boot https://github.com/mist64/dingusppc.git "$ENGINE"
    git -C "$ENGINE" checkout "$ENGINE_COMMIT"
fi
if [ -d "$ENGINE/.git" ]; then
    [ "$(git -C "$ENGINE" rev-parse HEAD)" = "$ENGINE_COMMIT" ] || { echo "Unexpected DingusPPC revision" >&2; exit 1; }
    git -C "$ENGINE" submodule update --init --recursive
else
    [ "$(cat "$ENGINE/SOURCE-REVISION")" = "$ENGINE_COMMIT" ]
fi
if [ ! -d "$SDL/.git" ] && [ ! -f "$SDL/SOURCE-REVISION" ]; then
    git clone --branch release-2.32.10 --depth 1 https://github.com/libsdl-org/SDL.git "$SDL"
fi
if [ -d "$SDL/.git" ]; then
    [ "$(git -C "$SDL" rev-parse HEAD)" = "$SDL_COMMIT" ] || { echo "Unexpected SDL2 revision" >&2; exit 1; }
else
    [ "$(cat "$SDL/SOURCE-REVISION")" = "$SDL_COMMIT" ]
fi
# Exported corresponding-source archives already contain the applied patches.
if [ -d "$ENGINE/.git" ]; then
for patch in rtc.patch host-integration.patch clock-state.patch keyboard-input.patch; do
    if [ "$patch" = rtc.patch ] && git -C "$ENGINE" apply --reverse --check "$ROOT_DIR/copland/clock-state.patch" 2>/dev/null; then
        : # clock-state.patch modifies two lines added by rtc.patch.
    elif git -C "$ENGINE" apply --reverse --check "$ROOT_DIR/copland/$patch" 2>/dev/null; then
        : # Already applied.
    else
        git -C "$ENGINE" apply --check "$ROOT_DIR/copland/$patch"
        git -C "$ENGINE" apply "$ROOT_DIR/copland/$patch"
    fi
done
fi
cp "$ROOT_DIR/copland/chario_copland.h" "$ENGINE/devices/serial/chario_copland.h"
cp "$ROOT_DIR/copland/host_control.h" "$ENGINE/core/classicmac_control.h"
cp "$ROOT_DIR/copland/clock_state.h" "$ENGINE/devices/common/classicmac_clock.h"
cp "$ROOT_DIR/copland/soundserver_silent.cpp" "$ENGINE/devices/sound/soundserver_cubeb.cpp"
# CMake caches per-architecture probes (SDL's CPU feature checks among them),
# so a tree configured for the other architecture is rebuilt from clean.
for tree in "$SDL/build" "$SDL/install" "$ENGINE/build"; do
    if [ -d "$tree" ] && [ "$(cat "$tree/classicmac-arch" 2>/dev/null || true)" != "$TARGET_ARCH" ]; then
        rm -rf "$tree"
    fi
done
cmake -S "$SDL" -B "$SDL/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_OSX_ARCHITECTURES="$TARGET_ARCH" \
    -DSDL_SHARED=OFF -DSDL_STATIC=ON \
    -DSDL_TEST=OFF -DSDL_TESTS=OFF -DCMAKE_INSTALL_PREFIX="$SDL/install"
cmake --build "$SDL/build" -j "$(sysctl -n hw.ncpu)"
cmake --install "$SDL/build"
printf '%s\n' "$TARGET_ARCH" > "$SDL/build/classicmac-arch"
printf '%s\n' "$TARGET_ARCH" > "$SDL/install/classicmac-arch"
cmake -S "$ENGINE" -B "$ENGINE/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_OSX_ARCHITECTURES="$TARGET_ARCH" \
    -DSDL2_DIR="$SDL/install/lib/cmake/SDL2" \
    -DBUILD_SHARED_LIBS=OFF
cmake --build "$ENGINE/build" -j "$(sysctl -n hw.ncpu)"
ENGINE_BIN="$ENGINE/build/bin/dingusppc.app/Contents/MacOS/dingusppc"
[ "$(lipo -archs "$ENGINE_BIN")" = "$TARGET_ARCH" ] || {
    echo "dingusppc is built for '$(lipo -archs "$ENGINE_BIN")', expected $TARGET_ARCH" >&2; exit 1; }
printf '%s\n' "$TARGET_ARCH" > "$ENGINE/build/classicmac-arch"
"${CXX:-c++}" -std=c++17 -I"$ENGINE" "$ROOT_DIR/copland/test_serial.cpp" -o "$ENGINE/build/test-copland-serial"
"$ENGINE/build/test-copland-serial"
"${CXX:-c++}" -std=c++17 "$ROOT_DIR/copland/test_clock.cpp" -o "$ENGINE/build/test-copland-clock"
"$ENGINE/build/test-copland-clock"
