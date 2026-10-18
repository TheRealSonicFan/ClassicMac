#!/usr/bin/env bash
#
# Rebuild the PowerPC OpenBIOS firmware bundled with ClassicMac
# (screamer/openbios-ppc; build-qemu.sh stages it into pc-bios/).
#
# Source: OpenBIOS e1e703ac ("macio: add awacs/screamer device") plus, in
# order,
#   powermac/openbios-classic-macos-8.patch  ClassicMac's Mac OS 8/9 profile
#   ati/openbios-ati-radeon.patch            the emulated ATI Radeon R100
#                                            (ATY,Rage6p), only for that
#                                            device (from RetroBoot)
# built in the pinned openbios-builder image (Debian 12,
# powerpc-linux-gnu-gcc 12.2.0) with ClassicMac's flags.
#
# OpenBIOS stamps `date +'%b %e %Y %H:%M'` into its banner; a shim makes that
# OPENBIOS_BUILD_DATE so the output is reproducible. OPENBIOS_VERIFY_PINNED=1
# first rebuilds the unmodified 3.x firmware (ClassicMac patch only, its
# recorded date) and refuses to continue unless it is bit-identical to the
# previously shipped binary.
#
# Environment:
#   OPENBIOS_BUILD_DATE     banner date (default: the ClassicMac 4.0 date)
#   OPENBIOS_VERIFY_PINNED  1 = reproduce the 3.x firmware first
#   OPENBIOS_BUILDER_IMAGE  builder image (default: pinned digest)
#   OPENBIOS_OUTPUT         output path (default: screamer/openbios-ppc)
#   OPENBIOS_MAKE_JOBS      make -j value (default 2)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor"
SOURCE_DIR="$VENDOR_DIR/openbios"
PATCH_FILES=(
  "$ROOT_DIR/powermac/openbios-classic-macos-8.patch"
  "$ROOT_DIR/ati/openbios-ati-radeon.patch"
)
OUTPUT_FILE="${OPENBIOS_OUTPUT:-$ROOT_DIR/screamer/openbios-ppc}"
OPENBIOS_REPO="${OPENBIOS_REPO:-https://github.com/openbios/openbios.git}"
OPENBIOS_COMMIT="${OPENBIOS_COMMIT:-e1e703ac0ad615ab0d7edea54db600aaa629bf07}"
# The only tag ClassicMac ever used (master, unchanged since 2024-04-24),
# pinned by digest.
BUILDER_IMAGE="${OPENBIOS_BUILDER_IMAGE:-ghcr.io/openbios/openbios-builder@sha256:bf806644ccff091323dd56a853866ba09301b1a7fcb91e865fdb289499ef8b38}"
BUILD_DATE="${OPENBIOS_BUILD_DATE:-Oct 17 2026 00:00}"
EXTRACFLAGS="-Wno-array-bounds -Wno-address-of-packed-member"
MAKE_JOBS="${OPENBIOS_MAKE_JOBS:-2}"
# ClassicMac 3.x screamer/openbios-ppc (ClassicMac patch only).
PINNED_DATE="Aug 15 2026 10:43"
PINNED_SHA256="cc5bccd2d9482aa74b41930e2f1649af84b945771cdc045349186e586b230abe"
BUILD_SOURCE=""
SHIM_DIR=""

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [ -n "$BUILD_SOURCE" ] && [ -d "$BUILD_SOURCE" ]; then
    git -C "$SOURCE_DIR" worktree remove --force "$BUILD_SOURCE" >/dev/null 2>&1 || true
  fi
  if [ -n "$SHIM_DIR" ] && [ -d "$SHIM_DIR" ]; then
    rm -rf "$SHIM_DIR"
  fi
}
trap cleanup EXIT

command -v docker >/dev/null 2>&1 || die "Docker is required to build OpenBIOS"
for patch in "${PATCH_FILES[@]}"; do
  [ -f "$patch" ] || die "OpenBIOS patch missing: $patch"
done

mkdir -p "$VENDOR_DIR"
if [ ! -d "$SOURCE_DIR/.git" ]; then
  log "Cloning OpenBIOS"
  git clone "$OPENBIOS_REPO" "$SOURCE_DIR"
fi

if ! git -C "$SOURCE_DIR" cat-file -e "$OPENBIOS_COMMIT^{commit}" 2>/dev/null; then
  log "Fetching pinned OpenBIOS revision"
  git -C "$SOURCE_DIR" fetch origin "$OPENBIOS_COMMIT"
fi

# date shim: only the banner format is answered, everything else passes on.
SHIM_DIR="$(mktemp -d "$VENDOR_DIR/openbios-shim.XXXXXX")"
cat > "$SHIM_DIR/date" <<'EOF'
#!/bin/sh
if [ "$*" = "+%b %e %Y %H:%M" ]; then echo "${CLASSICMAC_OPENBIOS_DATE:?}"; exit 0; fi
exec /bin/date "$@"
EOF
chmod 755 "$SHIM_DIR/date"

# build DATE PATCH... ; leaves $BUILD_SOURCE/obj-ppc/openbios-qemu.elf
build() {
  local date="$1"; shift
  if [ -n "$BUILD_SOURCE" ] && [ -d "$BUILD_SOURCE" ]; then
    git -C "$SOURCE_DIR" worktree remove --force "$BUILD_SOURCE" >/dev/null 2>&1 || true
  fi
  BUILD_SOURCE="$(mktemp -d "$VENDOR_DIR/openbios-build.XXXXXX")"
  rmdir "$BUILD_SOURCE"
  git -C "$SOURCE_DIR" worktree add --detach "$BUILD_SOURCE" "$OPENBIOS_COMMIT" >/dev/null
  local patch
  for patch in "$@"; do
    log "Applying $(basename "$patch")"
    git -C "$BUILD_SOURCE" apply "$patch"
  done
  log "Building PowerPC OpenBIOS (banner date: $date)"
  docker run --rm --platform linux/amd64 \
    -e "EXTRACFLAGS=$EXTRACFLAGS" \
    -e "CLASSICMAC_OPENBIOS_DATE=$date" \
    -e "MAKE_JOBS=$MAKE_JOBS" \
    -e "PATH=/classicmac-shim:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    -v "$SHIM_DIR:/classicmac-shim:ro" \
    -v "$BUILD_SOURCE:/src" \
    -w /src \
    "$BUILDER_IMAGE" \
    sh -c 'config/scripts/switch-arch ppc >/dev/null && make -j"$MAKE_JOBS"'
  [ -f "$BUILD_SOURCE/obj-ppc/openbios-qemu.elf" ] || \
    die "OpenBIOS build did not produce obj-ppc/openbios-qemu.elf"
}

if [ "${OPENBIOS_VERIFY_PINNED:-0}" = "1" ]; then
  build "$PINNED_DATE" "${PATCH_FILES[0]}"
  GOT="$(shasum -a 256 "$BUILD_SOURCE/obj-ppc/openbios-qemu.elf" | awk '{ print $1 }')"
  [ "$GOT" = "$PINNED_SHA256" ] || \
    die "Unmodified rebuild is not bit-identical to the 3.x firmware ($GOT)"
  printf '    OK  unmodified rebuild is bit-identical to the 3.x firmware (%s)\n' "$GOT"
fi

build "$BUILD_DATE" "${PATCH_FILES[@]}"
FIRMWARE="$BUILD_SOURCE/obj-ppc/openbios-qemu.elf"
if ! strings "$FIRMWARE" | grep "screamer" >/dev/null; then
  die "Built OpenBIOS is missing Screamer audio support"
fi
if ! strings "$FIRMWARE" | grep "nvram-fetch" >/dev/null; then
  die "Built OpenBIOS is missing classic Mac OS RTAS support"
fi
if ! strings "$FIRMWARE" | grep "ATY,Rage6p" >/dev/null; then
  die "Built OpenBIOS is missing the ATI Radeon (ATY,Rage6p) node"
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
cp "$FIRMWARE" "$OUTPUT_FILE"
log "Updated $OUTPUT_FILE"
printf '    OpenBIOS commit:  %s\n' "$OPENBIOS_COMMIT"
printf '    Builder image:    %s\n' "$BUILDER_IMAGE"
printf '    Banner date:      %s\n' "$BUILD_DATE"
for patch in "${PATCH_FILES[@]}"; do
  printf '    Patch %-34s %s\n' "$(basename "$patch")" \
    "$(shasum -a 256 "$patch" | awk '{ print $1 }')"
done
printf '    openbios-ppc:     %s\n' "$(shasum -a 256 "$OUTPUT_FILE" | awk '{ print $1 }')"
