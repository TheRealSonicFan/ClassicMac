#!/usr/bin/env bash
#
# make-intel-dmg.sh - Package the Intel-only (x86_64) ClassicMac.app into a
# drag-to-Applications disk image for Macs without a Developer ID / notary
# setup. The image carries the app, an Applications link, the ad-hoc signing
# script recipients run once (scripts/adhoc-sign-classicmac.sh) and a short
# READ ME. For a Developer ID signed and notarized image use scripts/make-dmg.sh.
#
# Typical flow on an Intel Mac:
#   scripts/build-qemu.sh && scripts/build-copland.sh && scripts/build-guest-cd.sh
#   DIST_DIR=dist/x86_64 scripts/bundle-qemu.sh
#   scripts/make-intel-dmg.sh
#
# Environment overrides: DIST_DIR (default dist/x86_64, holding ClassicMac.app),
# DIST_NAME (default ClassicMac-<version>-intel) and DMG_VOLUME_NAME (default
# ClassicMac). Idempotent: the image is rebuilt from scratch on every run.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist/x86_64}"
APP="$DIST_DIR/ClassicMac.app"
SIGN_SCRIPT="$ROOT_DIR/scripts/adhoc-sign-classicmac.sh"
VOLNAME="${DMG_VOLUME_NAME:-ClassicMac}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$APP" ] || die "$APP not found. Run DIST_DIR=$DIST_DIR scripts/bundle-qemu.sh on an Intel Mac first."
[ -f "$SIGN_SCRIPT" ] || die "Missing $SIGN_SCRIPT"

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
DIST_NAME="${DIST_NAME:-ClassicMac-$VERSION-intel}"
DMG="$DIST_DIR/$DIST_NAME.dmg"
STAGING="$DIST_DIR/dmg-staging-intel"

log "Checking that every executable is Intel (x86_64) only"
python3 "$ROOT_DIR/scripts/universal-app.py" verify "$APP" --expect-archs x86_64 || \
  die "$APP is not an Intel-only build"
codesign --verify --deep --strict "$APP" || die "$APP has an invalid signature; re-run scripts/bundle-qemu.sh"
for helper in "Quadra 800" "Power Mac G4"; do
  codesign -d --entitlements - "$APP/Contents/Helpers/$helper.app" 2>/dev/null | \
    grep -q 'com.apple.security.cs.allow-jit' || die "$helper lacks the JIT entitlement"
done

log "Assembling DMG staging folder"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/ClassicMac.app"
ln -s /Applications "$STAGING/Applications"
cp "$SIGN_SCRIPT" "$STAGING/adhoc-sign-classicmac.sh"
chmod 755 "$STAGING/adhoc-sign-classicmac.sh"
cat > "$STAGING/READ ME FIRST.txt" <<TEXT
ClassicMac $VERSION for Intel Macs (x86_64)
==========================================

This build runs natively on Intel Macs with macOS 15 or newer. It is not an
Apple Silicon build. It is ad-hoc signed, not Developer ID signed or
notarized, so macOS blocks it until it is signed on your Mac:

1. Drag ClassicMac to Applications.
2. Open Terminal and run:

     bash "/Volumes/$VOLNAME/adhoc-sign-classicmac.sh"

   (For a copy outside Applications, add its path:
     bash "/Volumes/$VOLNAME/adhoc-sign-classicmac.sh" /path/to/ClassicMac.app)

3. Open ClassicMac from Applications.

The script removes the download quarantine, re-signs the app ad-hoc with the
JIT entitlements its emulators need, and verifies the result. Run it again
after copying ClassicMac to another Mac.

ClassicMac is by Austin McChord and contributors:
https://github.com/amcchord/ClassicMac
TEXT

log "Creating $DMG"
rm -f "$DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

log "Verifying the disk image"
hdiutil verify "$DMG" >/dev/null || die "hdiutil verify failed for $DMG"
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

log "Done. Intel-only disk image: $DMG"
printf '    SHA-256: %s\n' "$(awk '{ print $1 }' "$DMG.sha256")"
