#!/usr/bin/env bash
#
# make-intel-dmg.sh - Package an Intel-only (thin x86_64) ClassicMac.app into
# a distributable disk image for Macs without a Developer ID signature:
#
#   ClassicMac.app                    the Intel app (ad-hoc signed)
#   Applications                      drag target
#   Ad-hoc Sign ClassicMac.command    scripts/adhoc-sign-classicmac.sh
#   Read Me First.txt                 installation steps
#
# Every executable and bundled library must be thin x86_64: this image is for
# Intel Macs only. Build the app on an Intel Mac first:
#   APP_VERSION=4.6.1 APP_BUILD_VERSION=4.6.1 DIST_DIR="$PWD/dist-x86_64" ./scripts/bundle-qemu.sh
#   DIST_DIR="$PWD/dist-x86_64" ./scripts/make-intel-dmg.sh
#
# For a Developer ID signed, notarized release use scripts/make-dmg.sh.
#
# Environment overrides: DIST_DIR (default dist/, holding ClassicMac.app),
# DIST_NAME (default ClassicMac-<version>-x86_64; the image is
# DIST_DIR/DIST_NAME.dmg) and DMG_VOLUME_NAME (default "ClassicMac Intel").

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP="$DIST_DIR/ClassicMac.app"
SIGN_SCRIPT="$ROOT_DIR/scripts/adhoc-sign-classicmac.sh"
VOLNAME="${DMG_VOLUME_NAME:-ClassicMac Intel}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$APP" ] || die "$APP not found. Run scripts/bundle-qemu.sh on an Intel Mac first."
[ -f "$SIGN_SCRIPT" ] || die "scripts/adhoc-sign-classicmac.sh is missing."
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
DIST_NAME="${DIST_NAME:-ClassicMac-$VERSION-x86_64}"
DMG="$DIST_DIR/$DIST_NAME.dmg"
STAGING="$DIST_DIR/.intel-dmg-staging"
MOUNT=""

cleanup() {
  [ -z "$MOUNT" ] || hdiutil detach -quiet "$MOUNT" >/dev/null 2>&1 || true
  rm -rf "$STAGING"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1. The app must be Intel-only and correctly signed
# ---------------------------------------------------------------------------
log "Checking that every Mach-O file in ClassicMac $VERSION is thin x86_64"
MACHO_COUNT=0
while IFS= read -r -d '' file; do
  if archs="$(lipo -archs "$file" 2>/dev/null)"; then
    [ "$archs" = "x86_64" ] || die "${file#"$APP"/} is $archs, not thin x86_64"
    MACHO_COUNT=$((MACHO_COUNT + 1))
  fi
done < <(find "$APP/Contents/MacOS" "$APP/Contents/Helpers" -type f -print0)
[ "$MACHO_COUNT" -ge 5 ] || die "Expected the app and engine executables, found $MACHO_COUNT Mach-O files"
printf '    OK  %d Mach-O files, all x86_64\n' "$MACHO_COUNT"

log "Verifying the app signature and JIT entitlements"
codesign --verify --deep --strict "$APP" || die "ClassicMac.app is not validly signed; rebuild it with scripts/bundle-qemu.sh."
for helper in "Quadra 800" "Power Mac G4"; do
  codesign -d --entitlements - --xml "$APP/Contents/Helpers/$helper.app" 2>/dev/null |
    grep -q 'com.apple.security.cs.allow-jit' || die "$helper.app lacks the JIT entitlement."
done

# ---------------------------------------------------------------------------
# 2. Stage the image contents
# ---------------------------------------------------------------------------
log "Assembling the disk image contents"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/ClassicMac.app"
ln -s /Applications "$STAGING/Applications"
cp "$SIGN_SCRIPT" "$STAGING/Ad-hoc Sign ClassicMac.command"
chmod 755 "$STAGING/Ad-hoc Sign ClassicMac.command"
cat > "$STAGING/Read Me First.txt" <<README
ClassicMac $VERSION for Intel Macs (x86_64)
==========================================

This build runs on Intel Macs with macOS 15 or newer. It is not an Apple
Silicon build. It is ad-hoc signed (not Developer ID signed or notarized),
so prepare it once with the included script:

1. Drag ClassicMac to the Applications folder.

2. Run the ad-hoc signing script. Open Terminal (Applications > Utilities)
   and enter:

       bash "/Volumes/$VOLNAME/Ad-hoc Sign ClassicMac.command"

   (Double-clicking "Ad-hoc Sign ClassicMac.command" also works if macOS
   allows it; when it is blocked, use the Terminal command above.)

   The script removes the download quarantine from
   /Applications/ClassicMac.app, re-signs it ad-hoc for this Mac with the
   JIT entitlements the emulator needs, and verifies the result. To prepare
   a copy elsewhere, give its path:

       bash "/Volumes/$VOLNAME/Ad-hoc Sign ClassicMac.command" ~/Desktop/ClassicMac.app

3. Open ClassicMac from Applications.

Run the script again after replacing or updating the app.

Source and documentation: https://github.com/amcchord/ClassicMac
README

# ---------------------------------------------------------------------------
# 3. Create and check the image
# ---------------------------------------------------------------------------
log "Creating $DMG"
rm -f "$DMG"
hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
hdiutil verify -quiet "$DMG" || die "hdiutil could not verify $DMG"

log "Checking the image contents"
MOUNT="$(mktemp -d "${TMPDIR:-/tmp}/classicmac-intel-dmg.XXXXXX")"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$MOUNT" "$DMG"
for entry in ClassicMac.app Applications "Ad-hoc Sign ClassicMac.command" "Read Me First.txt"; do
  [ -e "$MOUNT/$entry" ] || die "$entry is missing from the image"
done
[ -x "$MOUNT/Ad-hoc Sign ClassicMac.command" ] || die "The signing script is not executable in the image"
codesign --verify --deep --strict "$MOUNT/ClassicMac.app" || die "The app in the image does not verify"
[ "$(lipo -archs "$MOUNT/ClassicMac.app/Contents/MacOS/ClassicMac")" = "x86_64" ] || die "The app in the image is not x86_64"
hdiutil detach -quiet "$MOUNT"
rmdir "$MOUNT" 2>/dev/null || true
MOUNT=""

log "Done. Intel disk image: $DMG"
printf '    SHA-256: %s\n' "$(shasum -a 256 "$DMG" | awk '{ print $1 }')"
