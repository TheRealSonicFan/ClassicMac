#!/usr/bin/env bash
#
# make-adhoc-dmg.sh - Package an ad-hoc signed dist/ClassicMac.app (built by
# scripts/bundle-qemu.sh without a Developer ID certificate) into a
# drag-to-Applications disk image for testers on other Macs.
#
# Unlike scripts/make-dmg.sh this needs no Developer ID certificate and no
# notary credentials, and the result is NOT notarized: Gatekeeper blocks it
# on other Macs until its quarantine flag is removed. The image therefore also
# carries scripts/open-adhoc-build.sh (as "Open ClassicMac.sh") and a short
# "Read Me First.txt" that explains how to install it.
#
# Usage:
#   scripts/make-adhoc-dmg.sh
#
# Environment overrides: DIST_DIR (default dist/, holding ClassicMac.app),
# DIST_NAME (default ClassicMac-<version>-<arch>: DIST_DIR/DIST_NAME.dmg) and
# DMG_VOLUME_NAME (default ClassicMac).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP="$DIST_DIR/ClassicMac.app"
VOLNAME="${DMG_VOLUME_NAME:-ClassicMac}"
OPEN_SCRIPT="$ROOT_DIR/scripts/open-adhoc-build.sh"

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$APP" ] || die "$APP not found. Run scripts/bundle-qemu.sh first."
[ -f "$OPEN_SCRIPT" ] || die "scripts/open-adhoc-build.sh is missing."

log "Verifying $APP"
codesign --verify --deep --strict "$APP" || die "ClassicMac.app's signature does not verify; re-run scripts/bundle-qemu.sh."
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/ClassicMac")"
ARCH_NAME="$(printf '%s\n' "$ARCHS" | tr ' ' '-')"
DIST_NAME="${DIST_NAME:-ClassicMac-$VERSION-$ARCH_NAME}"
DMG="$DIST_DIR/$DIST_NAME.dmg"
STAGING="$DIST_DIR/adhoc-dmg-staging"
if codesign -dvv "$APP" 2>&1 | grep -q '^Authority=Developer ID Application'; then
  log "NOTE: this app is Developer ID signed; scripts/make-dmg.sh produces a notarized DMG instead."
fi
printf '    Version: %s  Architectures: %s\n' "$VERSION" "$ARCHS"

log "Assembling the disk image contents"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/ClassicMac.app"
ln -s /Applications "$STAGING/Applications"
cp "$OPEN_SCRIPT" "$STAGING/Open ClassicMac.sh"
chmod 755 "$STAGING/Open ClassicMac.sh"
cat > "$STAGING/Read Me First.txt" <<EOF
ClassicMac $VERSION for Intel Macs ($ARCHS), macOS 15 or newer

This build is ad-hoc signed and not notarized by Apple, so macOS blocks it
when it was downloaded from the internet. To install and open it, run in
Terminal, with this disk image open:

    bash "/Volumes/$VOLNAME/Open ClassicMac.sh"

The script copies ClassicMac to /Applications, removes the download
quarantine flag, checks its ad-hoc signature (re-signing it ad hoc if
needed) and opens it. Add --dest ~/Applications to install it elsewhere.

Without the script: drag ClassicMac to Applications, then Control-click
ClassicMac in Applications and choose Open, or open it once and click
"Open Anyway" in System Settings > Privacy & Security.

Derived from https://github.com/amcchord/ClassicMac
EOF

log "Creating $DMG"
rm -f "$DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
hdiutil verify "$DMG" >/dev/null || die "hdiutil could not verify $DMG"

log "Done. Ad-hoc signed disk image (not notarized): $DMG"
printf '    SHA-256: %s\n' "$(shasum -a 256 "$DMG" | awk '{ print $1 }')"
