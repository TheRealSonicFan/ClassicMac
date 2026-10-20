#!/usr/bin/env bash
#
# open-adhoc-build.sh - Install and open the ad-hoc signed (not notarized)
# Intel ClassicMac build on another Mac.
#
# The Intel build is ad-hoc signed: it carries a valid code signature, hardened
# runtime and QEMU JIT entitlements, but no Developer ID and no Apple
# notarization ticket. A downloaded copy is quarantined, so Gatekeeper refuses
# to open it ("cannot be opened because the developer cannot be verified").
# This script:
#
#   1. checks that this Mac is an Intel Mac running macOS 15 or newer;
#   2. removes the quarantine flag from the DMG (or app) you downloaded;
#   3. copies ClassicMac.app from the DMG to /Applications (or --dest DIR);
#   4. verifies the app's ad-hoc signature, and re-signs it ad hoc (inner
#      code first, JIT entitlements on the emulator helpers) only if the
#      signature is missing or broken, or when --resign is given;
#   5. opens ClassicMac (unless --no-open).
#
# Usage:
#   bash open-adhoc-build.sh [--dest DIR] [--resign] [--no-open] [PATH]
#
# PATH is ClassicMac-<version>-x86_64.dmg or an already copied ClassicMac.app.
# Without PATH, the ClassicMac.app next to this script is installed; that is
# how the "Open ClassicMac.sh" copy inside the disk image works:
#   bash "/Volumes/ClassicMac/Open ClassicMac.sh"
# Run it with "bash" so the script itself is not subject to Gatekeeper.
# Only remove quarantine from builds you obtained from a source you trust.

set -euo pipefail

DEST="/Applications"
RESIGN=0
OPEN_APP=1
TARGET=""
MOUNT_POINT=""

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed -n 's/^# \{0,1\}//p'
  exit "${1:-0}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dest) [ "$#" -ge 2 ] || die "--dest needs a directory"; DEST="$2"; shift 2 ;;
    --resign) RESIGN=1; shift ;;
    --no-open) OPEN_APP=0; shift ;;
    -h|--help) usage 0 ;;
    -*) die "Unknown option: $1" ;;
    *) [ -z "$TARGET" ] || die "Give only one DMG or app"; TARGET="$1"; shift ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$TARGET" ]; then
  [ -d "$SCRIPT_DIR/ClassicMac.app" ] || usage 1
fi
[ -z "$TARGET" ] || [ -e "$TARGET" ] || die "Not found: $TARGET"

cleanup() {
  if [ -n "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1. This build runs on Intel Macs with macOS 15 or newer
# ---------------------------------------------------------------------------
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ]; then
  die "This is the Intel-only (x86_64) ClassicMac build and this Mac has Apple Silicon. Use the official Apple Silicon release from https://github.com/amcchord/ClassicMac/releases instead."
fi
[ "$(uname -m)" = "x86_64" ] || die "This build needs an Intel (x86_64) Mac; this Mac reports $(uname -m)."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 15 ] 2>/dev/null || die "ClassicMac needs macOS 15 or newer; this Mac runs $(sw_vers -productVersion)."

# ---------------------------------------------------------------------------
# 2-3. Clear quarantine and install the app
# ---------------------------------------------------------------------------
install_app() {
  local source="$1"
  mkdir -p "$DEST" || die "Cannot create $DEST"
  APP="$(cd "$DEST" && pwd)/ClassicMac.app"
  [ "$(cd "$source" && pwd)" != "$APP" ] || return 0
  if [ -e "$APP" ]; then
    pgrep -f "$APP/Contents/MacOS/ClassicMac" >/dev/null 2>&1 && \
      die "ClassicMac is running from $APP. Quit it, then run this script again."
    log "Replacing the existing $APP"
    rm -rf "$APP" || die "Cannot replace $APP (try --dest ~/Applications)"
  fi
  log "Copying ClassicMac.app to $DEST"
  ditto "$source" "$APP" || die "Copy to $DEST failed (try --dest ~/Applications)"
}

case "$TARGET" in
  "")
    install_app "$SCRIPT_DIR/ClassicMac.app"
    ;;
  *.dmg)
    log "Removing the quarantine flag from $(basename "$TARGET")"
    xattr -d com.apple.quarantine "$TARGET" 2>/dev/null || true
    MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/classicmac-dmg.XXXXXX")"
    hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$TARGET" >/dev/null || \
      die "Could not open the disk image $TARGET (if it is already open in Finder, eject it first)"
    [ -d "$MOUNT_POINT/ClassicMac.app" ] || die "ClassicMac.app is missing from the disk image"
    install_app "$MOUNT_POINT/ClassicMac.app"
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
    MOUNT_POINT=""
    ;;
  *.app)
    APP="$(cd "$TARGET" && pwd)"
    ;;
  *)
    die "Expected a ClassicMac .dmg or .app, got: $TARGET"
    ;;
esac

log "Removing the quarantine flag from $APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

ARCHS="$(lipo -archs "$APP/Contents/MacOS/ClassicMac" 2>/dev/null || true)"
case " $ARCHS " in
  *" x86_64 "*) ;;
  *) die "$APP is not an Intel build (architectures: ${ARCHS:-unknown})." ;;
esac

# ---------------------------------------------------------------------------
# 4. Verify the ad-hoc signature; re-sign ad hoc only when needed
# ---------------------------------------------------------------------------
resign_adhoc() {
  local app="$1" entitlements helper
  entitlements="$(mktemp "${TMPDIR:-/tmp}/classicmac-entitlements.XXXXXX")"
  # Same entitlements as scripts/qemu.entitlements: QEMU's TCG translator
  # needs JIT memory under the hardened runtime, and the helpers load their
  # bundled libraries.
  cat > "$entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
	<true/>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
</dict>
</plist>
PLIST
  log "Re-signing ClassicMac ad hoc"
  xattr -cr "$app"
  find "$app/Contents/Helpers" -path '*/Contents/Frameworks/*.dylib' -print0 | \
    while IFS= read -r -d '' lib; do
      codesign --force --sign - --timestamp=none "$lib"
    done
  codesign --force --sign - --timestamp=none --options runtime \
    "$app/Contents/Helpers/Quadra 800.app/Contents/MacOS/qemu-img"
  for helper in "Quadra 800.app" "Power Mac G4.app"; do
    codesign --force --sign - --timestamp=none --options runtime \
      --entitlements "$entitlements" "$app/Contents/Helpers/$helper"
  done
  codesign --force --sign - --timestamp=none --options runtime "$app/Contents/Helpers/Power Mac 7500.app"
  codesign --force --sign - --timestamp=none --options runtime "$app/Contents/MacOS/ClassicMac"
  codesign --force --sign - --timestamp=none --options runtime "$app"
  rm -f "$entitlements"
}

if [ "$RESIGN" -eq 1 ]; then
  resign_adhoc "$APP"
elif ! codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  log "The app's signature is missing or damaged"
  resign_adhoc "$APP"
fi
codesign --verify --deep --strict --verbose=1 "$APP" || die "ClassicMac's signature does not verify"
log "Signature verified (ad hoc, hardened runtime)"

# ---------------------------------------------------------------------------
# 5. Open
# ---------------------------------------------------------------------------
if [ "$OPEN_APP" -eq 1 ]; then
  log "Opening ClassicMac"
  open "$APP"
fi
log "Done. ClassicMac is installed at $APP"
