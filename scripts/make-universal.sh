#!/usr/bin/env bash
#
# make-universal.sh - Combine an arm64 and an x86_64 ClassicMac.app into one
# universal ClassicMac.app that runs natively on Apple Silicon and Intel Macs.
#
# Build each input with scripts/bundle-qemu.sh from the same revision, one
# per architecture: natively on an Apple Silicon Mac and an Intel Mac, or both
# on one Apple Silicon Mac (the x86_64 engines under `arch -x86_64` with an
# x86_64 Homebrew in /usr/local, in a separate VENDOR_DIR and DIST_DIR). See
# README.md, "Building from source".
#
# Usage:
#   scripts/make-universal.sh ARM64_APP X86_64_APP
#
# The merged app is signed by scripts/sign-app.sh (Developer ID when present,
# SIGN_IDENTITY overrides) and promoted to DIST_DIR/ClassicMac.app, so
# notarize.sh, make-dmg.sh and verify-release.sh then work unchanged; give
# DIST_NAME (for example ClassicMac-4.6.1-universal) to name the zip/DMG.
#
# Environment overrides: DIST_DIR (default dist/), SIGN_IDENTITY.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
FINAL_APP="$DIST_DIR/ClassicMac.app"
STAGE_DIR=""
PREVIOUS_APP=""

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[ "$#" -eq 2 ] || die "Usage: $0 ARM64_APP X86_64_APP"
ARM64_APP="$(cd "$1" && pwd)"
X86_64_APP="$(cd "$2" && pwd)"
for app in "$ARM64_APP" "$X86_64_APP"; do
  [ -f "$app/Contents/Info.plist" ] || die "Not an application bundle: $app"
done
[ "$(lipo -archs "$ARM64_APP/Contents/MacOS/ClassicMac")" = "arm64" ] || \
  die "$ARM64_APP is not a thin arm64 ClassicMac build"
[ "$(lipo -archs "$X86_64_APP/Contents/MacOS/ClassicMac")" = "x86_64" ] || \
  die "$X86_64_APP is not a thin x86_64 ClassicMac build"
case "$FINAL_APP" in
  "$ARM64_APP"|"$X86_64_APP") die "Write the universal app to a DIST_DIR other than the inputs' folders" ;;
esac

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  set +e
  # Restore the previous app if promotion moved it aside but did not finish.
  if [ -n "$PREVIOUS_APP" ] && [ -e "$PREVIOUS_APP" ] && [ ! -e "$FINAL_APP" ]; then
    mv "$PREVIOUS_APP" "$FINAL_APP"
  fi
  case "$STAGE_DIR" in
    "$DIST_DIR"/.make-universal.stage.*) rm -rf -- "$STAGE_DIR" ;;
  esac
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$DIST_DIR"
STAGE_DIR="$(mktemp -d "$DIST_DIR/.make-universal.stage.XXXXXX")"
APP="$STAGE_DIR/ClassicMac.app"

log "Merging $ARM64_APP (arm64) and $X86_64_APP (x86_64)"
python3 "$ROOT_DIR/scripts/merge-universal-app.py" "$ARM64_APP" "$X86_64_APP" "$APP"

bash "$ROOT_DIR/scripts/sign-app.sh" "$APP"

log "Checking that every executable is universal"
for exe in "Contents/MacOS/ClassicMac" \
           "Contents/Helpers/Quadra 800.app/Contents/MacOS/qemu-system-m68k" \
           "Contents/Helpers/Quadra 800.app/Contents/MacOS/qemu-img" \
           "Contents/Helpers/Power Mac G4.app/Contents/MacOS/qemu-system-ppc" \
           "Contents/Helpers/Power Mac 7500.app/Contents/MacOS/dingusppc"; do
  [ "$(lipo -archs "$APP/$exe" | tr ' ' '\n' | sort | xargs)" = "arm64 x86_64" ] || \
    die "$exe is not an arm64 + x86_64 universal binary"
done

log "Promoting universal app to $FINAL_APP"
if [ -e "$FINAL_APP" ]; then
  PREVIOUS_APP="$STAGE_DIR/Previous-ClassicMac.app"
  mv "$FINAL_APP" "$PREVIOUS_APP"
fi
mv "$APP" "$FINAL_APP" || die "Failed to promote the universal app to $FINAL_APP"

log "Done. Universal app: $FINAL_APP"
