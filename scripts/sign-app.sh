#!/usr/bin/env bash
#
# sign-app.sh - Code-sign an assembled ClassicMac.app, inner items first, then
# outward. Shared by scripts/bundle-qemu.sh (single-architecture apps) and
# scripts/make-universal.sh (arm64 + x86_64 apps), so every release is signed
# the same way regardless of the architectures it contains.
#
# Usage: scripts/sign-app.sh path/to/ClassicMac.app
#
# Uses the Developer ID Application certificate when one is present in the
# keychain (required for notarization / distribution); falls back to ad-hoc
# signing otherwise. Override with SIGN_IDENTITY=<identity or "-">.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS="$ROOT_DIR/scripts/qemu.entitlements"

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

APP="${1:-}"
[ -n "$APP" ] && [ -d "$APP" ] || die "Usage: $0 path/to/ClassicMac.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
HELPERS_DIR="$CONTENTS/Helpers"
QUADRA_APP="$HELPERS_DIR/Quadra 800.app"
PPC_APP="$HELPERS_DIR/Power Mac G4.app"
COPLAND_APP="$HELPERS_DIR/Power Mac 7500.app"
for required in "$MACOS_DIR/ClassicMac" "$QUADRA_APP" "$PPC_APP" "$COPLAND_APP" "$ENTITLEMENTS"; do
  [ -e "$required" ] || die "Missing $required"
done

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')"
fi
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="-"
fi

# Developer ID signatures need a secure timestamp for notarization; ad-hoc
# signatures cannot get one.
TIMESTAMP_FLAG="--timestamp"
if [ "$SIGN_IDENTITY" = "-" ]; then
  TIMESTAMP_FLAG="--timestamp=none"
  log "Code signing (ad-hoc)"
else
  log "Code signing (identity: $SIGN_IDENTITY)"
fi

# QEMU's build (scripts/entitlement.sh) gives each qemu-system binary an icon
# resource fork and a custom-icon Finder flag. Depending on the build volume
# and copy path those attributes reach the bundle, and codesign then refuses
# it ("resource fork, Finder information, or similar detritus not allowed").
# The helper apps carry their own icon, so drop Finder metadata before signing.
xattr -cr "$APP"

find "$QUADRA_APP/Contents/Frameworks" "$PPC_APP/Contents/Frameworks" -name '*.dylib' -print0 | while IFS= read -r -d '' lib; do
  codesign --force --sign "$SIGN_IDENTITY" "$TIMESTAMP_FLAG" "$lib"
done

# qemu-img is not the helper bundle's main executable, so it needs its own
# signature (no JIT entitlements required). All executables get the hardened
# runtime, which notarization requires.
codesign --force --sign "$SIGN_IDENTITY" "$TIMESTAMP_FLAG" \
  --options runtime \
  "$QUADRA_APP/Contents/MacOS/qemu-img"

# Sign the helper apps as bundles, then the outer app. Signing a bundle
# (re-)signs its main executable - the qemu-system binary - so the JIT
# entitlements MUST be supplied here or this pass would strip them, leaving a
# hardened-runtime binary that cannot map its JIT buffer ("allocate ... bytes
# for jit buffer: Invalid argument" at launch).
codesign --force --sign "$SIGN_IDENTITY" "$TIMESTAMP_FLAG" \
  --options runtime --entitlements "$ENTITLEMENTS" \
  "$QUADRA_APP"
codesign --force --sign "$SIGN_IDENTITY" "$TIMESTAMP_FLAG" \
  --options runtime --entitlements "$ENTITLEMENTS" \
  "$PPC_APP"

codesign --force --sign "$SIGN_IDENTITY" "$TIMESTAMP_FLAG" --options runtime "$COPLAND_APP"
codesign --force --sign "$SIGN_IDENTITY" "$TIMESTAMP_FLAG" --options runtime "$MACOS_DIR/ClassicMac"

# Sign the whole bundle last.
codesign --force --sign "$SIGN_IDENTITY" "$TIMESTAMP_FLAG" --options runtime "$APP"

log "Verifying bundle signature"
codesign --verify --deep --strict --verbose=2 "$APP" || die "Bundle failed signature verification."
