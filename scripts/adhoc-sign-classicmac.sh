#!/bin/bash
#
# adhoc-sign-classicmac.sh - Prepare this Intel (x86_64) build of ClassicMac
# to run on another Mac by re-signing it ad-hoc on that Mac.
#
# This build is not signed with an Apple Developer ID or notarized, so after
# it is downloaded or copied from another Mac, Gatekeeper refuses to open it
# ("ClassicMac is damaged" / "cannot be opened"). This script, run once on the
# Mac that will use ClassicMac:
#
#   1. removes the download quarantine and Finder metadata from the app,
#   2. re-signs every component ad-hoc, inner items first, with the hardened
#      runtime, and gives the two emulators the JIT entitlements QEMU's TCG
#      needs (exactly as ClassicMac's own build does), and
#   3. verifies the signature.
#
# It is self-contained: it needs only macOS's built-in tools (codesign, xattr,
# lipo) and no Xcode, Homebrew or ClassicMac source checkout.
#
# Usage (Terminal):
#   1. Drag ClassicMac from the disk image to Applications.
#   2. bash "/Volumes/ClassicMac/adhoc-sign-classicmac.sh"
#      or, for a copy elsewhere:
#      bash adhoc-sign-classicmac.sh /path/to/ClassicMac.app
#   3. Open ClassicMac normally.
#
# Run it from Terminal with "bash" as shown: a script copied from a download
# is itself quarantined and macOS may refuse to double-click it.

set -euo pipefail

APP="${1:-/Applications/ClassicMac.app}"
APP="${APP%/}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
for tool in codesign xattr lipo sw_vers mktemp; do
  command -v "$tool" >/dev/null 2>&1 || die "Required macOS tool not found: $tool"
done

[ -d "$APP" ] || die "ClassicMac.app not found at: $APP
Drag ClassicMac from the disk image to Applications first, or pass its path:
  bash $0 /path/to/ClassicMac.app"
APP="$(cd "$APP" && pwd)"

CONTENTS="$APP/Contents"
MAIN="$CONTENTS/MacOS/ClassicMac"
HELPERS="$CONTENTS/Helpers"
QUADRA_APP="$HELPERS/Quadra 800.app"
PPC_APP="$HELPERS/Power Mac G4.app"
COPLAND_APP="$HELPERS/Power Mac 7500.app"
for required in "$MAIN" "$QUADRA_APP/Contents/MacOS/qemu-system-m68k" \
  "$QUADRA_APP/Contents/MacOS/qemu-img" "$PPC_APP/Contents/MacOS/qemu-system-ppc" \
  "$COPLAND_APP/Contents/MacOS/dingusppc"; do
  [ -f "$required" ] || die "This does not look like a complete ClassicMac.app (missing ${required#"$APP"/})"
done

MOUNT_POINT="$(df -P "$APP" | awk 'NR == 2 { for (i = 6; i <= NF; i++) printf "%s%s", $i, (i < NF ? " " : "") }')"
if mount | grep -F " on $MOUNT_POINT (" | grep -q 'read-only'; then
  die "$APP is on a read-only volume (the disk image?). Drag ClassicMac to Applications first, then run this script again."
fi
[ -w "$CONTENTS" ] && [ -w "$APP" ] || \
  die "No write permission for $APP. Run again with: sudo bash $0 \"$APP\""

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 15 ] 2>/dev/null || \
  die "ClassicMac needs macOS 15 or newer (this Mac runs $(sw_vers -productVersion))."

APP_ARCHS="$(lipo -archs "$MAIN")"
HOST_ARCH="$(uname -m)"
if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
  HOST_ARCH="arm64"
fi
case " $APP_ARCHS " in
  *" $HOST_ARCH "*) ;;
  *)
    printf '\nWARNING: This ClassicMac build is for %s Macs; this Mac is %s.\n' "$APP_ARCHS" "$HOST_ARCH" >&2
    if [ "$HOST_ARCH" = "arm64" ]; then
      printf '         It can only run through Rosetta 2, much more slowly. Use the\n' >&2
      printf '         official Apple Silicon release of ClassicMac on this Mac instead.\n' >&2
    fi
    ;;
esac

if pgrep -f "$APP/Contents/" >/dev/null 2>&1; then
  die "ClassicMac (or one of its Macs) is running. Quit it, then run this script again."
fi

# ---------------------------------------------------------------------------
# 1. Remove quarantine and Finder metadata (codesign refuses resource forks
#    and Finder information inside a bundle).
# ---------------------------------------------------------------------------
log "Removing download quarantine and Finder metadata from $APP"
xattr -cr "$APP"

# ---------------------------------------------------------------------------
# 2. Ad-hoc signing, inner items first, then outward.
# ---------------------------------------------------------------------------
WORK_DIR="$(mktemp -d -t classicmac-sign)"
trap 'rm -rf "$WORK_DIR"' EXIT
ENTITLEMENTS="$WORK_DIR/qemu.entitlements"
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- QEMU's TCG uses a just-in-time translator; under the hardened runtime
	     it needs the JIT entitlement to map writable/executable memory. -->
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
	<true/>
	<!-- Allow the emulators to load their bundled dynamic libraries. -->
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
</dict>
</plist>
PLIST

sign() { codesign --force --sign - --timestamp=none "$@"; }

log "Signing bundled libraries"
find "$QUADRA_APP/Contents/Frameworks" "$PPC_APP/Contents/Frameworks" -name '*.dylib' -print0 2>/dev/null | \
  while IFS= read -r -d '' lib; do
    sign "$lib"
  done

log "Signing the emulators (with JIT entitlements) and the app"
# qemu-img is not its helper's main executable, so it is signed on its own.
sign --options runtime "$QUADRA_APP/Contents/MacOS/qemu-img"
# Signing a helper bundle re-signs its main executable (qemu-system-*); the
# JIT entitlements must be supplied here or QEMU cannot allocate its JIT
# buffer at launch.
sign --options runtime --entitlements "$ENTITLEMENTS" "$QUADRA_APP"
sign --options runtime --entitlements "$ENTITLEMENTS" "$PPC_APP"
sign --options runtime "$COPLAND_APP"
sign --options runtime "$MAIN"
sign --options runtime "$APP"

# ---------------------------------------------------------------------------
# 3. Verify
# ---------------------------------------------------------------------------
log "Verifying the signature"
codesign --verify --deep --strict "$APP" || die "Signature verification failed."
for helper in "$QUADRA_APP" "$PPC_APP"; do
  codesign -d --entitlements - "$helper" 2>/dev/null | grep -q 'com.apple.security.cs.allow-jit' || \
    die "JIT entitlement missing from $(basename "$helper")"
done
if [ "$(uname -m)" = "x86_64" ]; then
  "$PPC_APP/Contents/MacOS/qemu-system-ppc" --version >/dev/null 2>&1 || \
    die "The Power Mac emulator does not start on this Mac."
fi

log "Done. ClassicMac is signed for this Mac (ad-hoc, $APP_ARCHS)."
printf '    Open it from %s as usual.\n' "$(dirname "$APP")"
printf '    (Gatekeeper still reports it as not notarized; that is expected for an\n'
printf '    ad-hoc signed app and does not stop it from opening once signed here.)\n'
