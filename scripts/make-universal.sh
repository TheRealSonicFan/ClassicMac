#!/usr/bin/env bash
#
# make-universal.sh - Merge an arm64 and an x86_64 ClassicMac.app into one
# universal ClassicMac.app that runs natively on Apple Silicon and Intel Macs.
#
# Build each architecture with the normal scripts first, from the same commit,
# version and Tools CD, into separate DIST_DIRs. On an Apple Silicon Mac the
# x86_64 app can be built in a Rosetta shell against the x86_64 Homebrew in
# /usr/local (Copland can also be cross-built with CLASSICMAC_ARCH):
#
#   # arm64 (native shell, /opt/homebrew/bin first in PATH)
#   scripts/build-qemu.sh && scripts/build-copland.sh
#   DIST_DIR=dist/arm64 scripts/bundle-qemu.sh
#   # x86_64 (Intel Mac, or: arch -x86_64 /bin/bash with /usr/local/bin first)
#   scripts/build-qemu.sh && scripts/build-copland.sh
#   DIST_DIR=dist/x86_64 scripts/bundle-qemu.sh
#   # merge, sign, then notarize and package as usual
#   scripts/make-universal.sh dist/arm64/ClassicMac.app dist/x86_64/ClassicMac.app
#   DIST_DIR=dist/universal scripts/make-dmg.sh
#
# The merged app is signed with scripts/sign-app.sh, exactly like a
# single-architecture app (Developer ID when available, else ad-hoc; override
# with SIGN_IDENTITY), and verified per architecture before it is promoted to
# DIST_DIR/ClassicMac.app (default dist/universal).
#
# Environment: DIST_DIR, SIGN_IDENTITY, UNIVERSAL_ALLOW_RESOURCE_DIFF=1 (take
# the arm64 copy of non-code files that differ between the inputs, e.g. an
# Assets.car compiled by a different Xcode, instead of failing).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist/universal}"
FINAL_APP="$DIST_DIR/ClassicMac.app"

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[ "$#" -eq 2 ] || die "Usage: $0 ARM64/ClassicMac.app X86_64/ClassicMac.app"
ARM_APP="$(cd "$1" && pwd)"
X86_APP="$(cd "$2" && pwd)"
[ "$ARM_APP" != "$X86_APP" ] || die "The two inputs are the same app"

mkdir -p "$DIST_DIR"
STAGE_DIR="$(mktemp -d "$DIST_DIR/.make-universal.stage.XXXXXX")"
PREVIOUS_APP=""
cleanup() {
  local status=$?
  trap - EXIT
  if [ -n "$PREVIOUS_APP" ] && [ -e "$PREVIOUS_APP" ] && [ ! -e "$FINAL_APP" ]; then
    mv "$PREVIOUS_APP" "$FINAL_APP"
  fi
  case "$STAGE_DIR" in
    "$DIST_DIR"/.make-universal.stage.*) rm -rf -- "$STAGE_DIR" ;;
  esac
  exit "$status"
}
trap cleanup EXIT

APP="$STAGE_DIR/ClassicMac.app"
MERGE_ARGS=()
[ "${UNIVERSAL_ALLOW_RESOURCE_DIFF:-0}" != "1" ] || MERGE_ARGS+=(--allow-resource-diff)

log "Merging $ARM_APP (arm64) and $X86_APP (x86_64)"
python3 "$ROOT_DIR/scripts/universal-app.py" merge \
  "$ARM_APP" "$X86_APP" "$APP" "${MERGE_ARGS[@]+"${MERGE_ARGS[@]}"}" || \
  die "Merge failed"

bash "$ROOT_DIR/scripts/sign-app.sh" "$APP" || die "Signing failed"

log "Verifying both architectures"
python3 "$ROOT_DIR/scripts/universal-app.py" verify "$APP" --expect-archs "arm64 x86_64" || \
  die "Universal app verification failed"

log "Promoting verified universal app to $FINAL_APP"
if [ -e "$FINAL_APP" ]; then
  PREVIOUS_APP="$STAGE_DIR/Previous-ClassicMac.app"
  mv "$FINAL_APP" "$PREVIOUS_APP"
fi
mv "$APP" "$FINAL_APP" || die "Failed to promote $FINAL_APP"

log "Done. Built: $FINAL_APP ($(lipo -archs "$FINAL_APP/Contents/MacOS/ClassicMac"))"
