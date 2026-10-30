#!/bin/bash
#
# adhoc-sign-classicmac.sh - Prepare the Intel (x86_64) ClassicMac build to
# run on this Mac. The Intel DMG ships ad-hoc signed (no Developer ID, not
# notarized), so macOS quarantines a downloaded copy and Gatekeeper refuses to
# open it. This script, which needs nothing but macOS itself:
#
#   1. removes the download quarantine and other extended attributes,
#   2. re-signs every component ad-hoc with the hardened runtime, giving the
#      emulator helpers the JIT entitlements QEMU's TCG needs, and
#   3. verifies the signature.
#
# The DMG carries this script as "Ad-hoc Sign ClassicMac.command".
#
# Usage:
#   bash adhoc-sign-classicmac.sh [path/to/ClassicMac.app] [--open]
#
# Without a path it signs /Applications/ClassicMac.app (drag the app there
# from the DMG first). --open launches ClassicMac afterwards. Run it again
# after replacing or updating the app.

set -euo pipefail

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

APP=""
OPEN_AFTER=0
for argument in "$@"; do
  case "$argument" in
    --open) OPEN_AFTER=1 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) [ -z "$APP" ] || die "Give one application path."; APP="$argument" ;;
  esac
done
if [ -z "$APP" ]; then
  APP="/Applications/ClassicMac.app"
  [ -d "$APP" ] || die "ClassicMac.app is not in /Applications. Drag it there from the disk image first, or give its path: bash \"$0\" /path/to/ClassicMac.app"
fi
APP="$(cd "$APP" 2>/dev/null && pwd)" || die "Application not found: $APP"

CONTENTS="$APP/Contents"
MAIN="$CONTENTS/MacOS/ClassicMac"
HELPERS="$CONTENTS/Helpers"
QUADRA_APP="$HELPERS/Quadra 800.app"
PPC_APP="$HELPERS/Power Mac G4.app"
COPLAND_APP="$HELPERS/Power Mac 7500.app"
for required in "$CONTENTS/Info.plist" "$MAIN" "$QUADRA_APP/Contents/MacOS/qemu-system-m68k" \
                "$QUADRA_APP/Contents/MacOS/qemu-img" "$PPC_APP/Contents/MacOS/qemu-system-ppc" \
                "$COPLAND_APP/Contents/MacOS/dingusppc"; do
  [ -e "$required" ] || die "This does not look like a complete ClassicMac.app (missing ${required#"$APP"/})."
done

# --- Compatibility checks --------------------------------------------------
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS/Info.plist" 2>/dev/null || echo unknown)"
ARCHS="$(lipo -archs "$MAIN")"
case " $ARCHS " in
  *" x86_64 "*) ;;
  *) die "This ClassicMac ($ARCHS) is not an Intel build; this script is for the Intel (x86_64) DMG." ;;
esac
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 15 ] || die "ClassicMac needs macOS 15 or newer (this Mac runs $(sw_vers -productVersion))."
if [ "$(uname -m)" != "x86_64" ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" != "1" ]; then
  printf '\nNOTE: This Mac is not an Intel Mac. The Intel build would run only under\n'
  printf '      Rosetta 2, much more slowly; use an Apple Silicon build of ClassicMac instead.\n'
fi

# The app must be writable: a mounted disk image is read-only. Probe with a
# real write (mount-point matching is unreliable: / is the sealed read-only
# system volume and /Applications reaches the data volume via a firmlink).
PROBE="$CONTENTS/.classicmac-write-test.$$"
if WRITE_ERROR="$(LC_ALL=C /bin/bash -c ': > "$1" && rm -f "$1"' _ "$PROBE" 2>&1)"; then
  :
else
  case "$WRITE_ERROR" in
    *"Read-only file system"*)
      die "$APP is on a read-only disk image. Drag ClassicMac to Applications first, then run this script again." ;;
    *)
      die "No permission to modify $APP. Run: sudo bash \"$0\" \"$APP\"" ;;
  esac
fi
if [ ! -w "$MAIN" ]; then
  die "No permission to modify $APP. Run: sudo bash \"$0\" \"$APP\""
fi
if pgrep -f "$APP/Contents/" >/dev/null 2>&1; then
  die "ClassicMac is running. Quit it (and any running Mac) first."
fi

log "Preparing ClassicMac $VERSION ($ARCHS) at $APP"

# --- 1. Quarantine and other extended attributes ---------------------------
# codesign also rejects files that carry a resource fork or Finder info.
xattr -cr "$APP"

# --- 2. Ad-hoc signature, inner items first --------------------------------
ENTITLEMENTS="$(mktemp -t classicmac-entitlements)"
trap 'rm -f "$ENTITLEMENTS"' EXIT
cat > "$ENTITLEMENTS" <<'PLIST'
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

sign() { codesign --force --sign - --timestamp=none "$@" 2>&1 | grep -v 'replacing existing signature' || true; }

log "Signing bundled libraries"
find "$QUADRA_APP/Contents/Frameworks" "$PPC_APP/Contents/Frameworks" -name '*.dylib' -type f -print0 2>/dev/null |
  while IFS= read -r -d '' library; do sign "$library"; done

log "Signing the emulator helpers"
sign --options runtime "$QUADRA_APP/Contents/MacOS/qemu-img"
# Signing a helper bundle re-signs its qemu-system executable: the JIT
# entitlements must be given here, or QEMU cannot allocate its JIT buffer.
sign --options runtime --entitlements "$ENTITLEMENTS" "$QUADRA_APP"
sign --options runtime --entitlements "$ENTITLEMENTS" "$PPC_APP"
sign --options runtime "$COPLAND_APP"

log "Signing ClassicMac"
sign --options runtime "$MAIN"
sign --options runtime "$APP"

# --- 3. Verify -------------------------------------------------------------
log "Verifying"
codesign --verify --deep --strict "$APP" || die "The signature did not verify."
for helper in "$QUADRA_APP" "$PPC_APP"; do
  codesign -d --entitlements - --xml "$helper" 2>/dev/null | grep -q 'com.apple.security.cs.allow-jit' ||
    die "$(basename "$helper") lacks the JIT entitlement."
done
if xattr -r "$APP" 2>/dev/null | grep -q 'com.apple.quarantine'; then
  die "The quarantine attribute is still present."
fi
"$PPC_APP/Contents/MacOS/qemu-system-ppc" --version >/dev/null 2>&1 ||
  die "The Power Mac engine does not start on this Mac."
printf '    OK  ad-hoc signed, hardened runtime, JIT entitlements, quarantine removed\n'

log "Done. ClassicMac is ready to open."
if [ "$OPEN_AFTER" -eq 1 ]; then
  open "$APP"
fi
