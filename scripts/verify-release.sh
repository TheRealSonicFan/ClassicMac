#!/usr/bin/env bash
#
# verify-release.sh - Verify the exact ClassicMac application or DMG that will
# be handed to a tester. Developer ID releases validate notarization/Gatekeeper;
# SIGN_IDENTITY=- explicitly selects verification of an ad-hoc, non-notarized
# artifact while retaining structural, signature, architecture, entitlement,
# runtime-library, and feature checks.
#
# Usage:
#   scripts/verify-release.sh [app-or-dmg] [short-version] [build-version]
#
# Examples:
#   scripts/verify-release.sh dist/ClassicMac.app 3.2.1 3.2.1
#   scripts/verify-release.sh dist/ClassicMac.dmg 3.2.1 3.2.1
#   SIGN_IDENTITY=- scripts/verify-release.sh dist/ClassicMac.dmg 3.2.1 3.2.1

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-$ROOT_DIR/dist/ClassicMac.dmg}"
EXPECTED_VERSION="${2:-${APP_VERSION:-}}"
EXPECTED_BUILD="${3:-${APP_BUILD_VERSION:-}}"
SKIP_REPO_FRESHNESS="${VERIFY_RELEASE_SKIP_REPO_FRESHNESS:-0}"
VERIFY_ADHOC=0
if [ "${SIGN_IDENTITY:-}" = "-" ]; then
  VERIFY_ADHOC=1
fi
MOUNT_ROOT=""
ATTACH_DEVICE=""

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [ -n "$ATTACH_DEVICE" ]; then
    diskutil eject "$ATTACH_DEVICE" >/dev/null 2>&1 || true
  fi
  if [ -n "$MOUNT_ROOT" ] && [ -d "$MOUNT_ROOT" ]; then
    rmdir "$MOUNT_ROOT" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

for tool in cmp codesign file hdiutil lipo plutil shasum spctl strings xcrun; do
  command -v "$tool" >/dev/null 2>&1 || die "Required tool not found: $tool"
done
[ -e "$TARGET" ] || die "Release target not found: $TARGET"

APP="$TARGET"
VERIFY_NOTARIZATION=0
EXPECTED_ARCH="${CLASSICMAC_ARCH:-$(uname -m)}"
case "$EXPECTED_ARCH" in
  arm64|x86_64) ;;
  *) die "Unsupported release architecture: $EXPECTED_ARCH" ;;
esac
case "$TARGET" in
  *.dmg)
    log "Verifying DMG structure and code signature"
    hdiutil verify "$TARGET" >/dev/null || die "Disk image verification failed."
    codesign --verify --verbose=2 "$TARGET" || die "DMG code signature verification failed."

    if [ "$VERIFY_ADHOC" -eq 1 ]; then
      log "Ad-hoc release mode: skipping notarization and Gatekeeper trust checks"
    else
      VERIFY_NOTARIZATION=1
      log "Validating the DMG notarization ticket and Gatekeeper policy"
      xcrun stapler validate "$TARGET"
      spctl --assess --type open --context context:primary-signature \
        --verbose=2 "$TARGET"
    fi

    MOUNT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/classicmac-release.XXXXXX")"
    ATTACH_OUTPUT="$(diskutil image attach --readOnly --nobrowse \
      --mountPoint "$MOUNT_ROOT" "$TARGET")"
    ATTACH_DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk 'NR == 1 { print $1 }')"
    [ -n "$ATTACH_DEVICE" ] || die "Could not determine the attached DMG device"
    APP="$MOUNT_ROOT/ClassicMac.app"
    [ -d "$APP" ] || die "ClassicMac.app is missing from the DMG root"
    ;;
  *.app)
    [ -d "$APP" ] || die "Application bundle not found: $APP"
    ;;
  *)
    die "Expected a ClassicMac .app or .dmg target"
    ;;
esac

PLIST="$APP/Contents/Info.plist"
MAIN_APP="$APP/Contents/MacOS/ClassicMac"
PPC_HELPER="$APP/Contents/Helpers/Power Mac G4.app"
PPC_QEMU="$PPC_HELPER/Contents/MacOS/qemu-system-ppc"
QUADRA_HELPER="$APP/Contents/Helpers/Quadra 800.app"
QUADRA_QEMU="$QUADRA_HELPER/Contents/MacOS/qemu-system-m68k"
COPLAND_HELPER="$APP/Contents/Helpers/Power Mac 7500.app"
COPLAND_ENGINE="$COPLAND_HELPER/Contents/MacOS/dingusppc"
PPC_NDRV="$APP/Contents/Resources/qemu/pc-bios/qemu_vga.ndrv"
TOOLS_CD="$APP/Contents/Resources/ClassicMacTools.iso"
VNC_KEYMAP="$APP/Contents/Resources/qemu/pc-bios/keymaps/en-us"
BROWSER_INDEX="$APP/Contents/Resources/Browser/index.html"
BROWSER_RFB="$APP/Contents/Resources/Browser/novnc/core/rfb.js"
BROWSER_SCALE="$APP/Contents/Resources/Browser/pixel-scale.js"
BROWSER_LICENSE="$APP/Contents/Resources/Licenses/noVNC-MPL-2.0.txt"
PAKO_LICENSE="$APP/Contents/Resources/Licenses/pako-MIT.txt"

for required in "$COPLAND_HELPER/Contents/Info.plist" "$COPLAND_ENGINE" "$PLIST" "$MAIN_APP" "$PPC_HELPER/Contents/Info.plist" \
  "$QUADRA_HELPER/Contents/Info.plist" "$PPC_QEMU" "$QUADRA_QEMU" \
  "$PPC_NDRV" "$TOOLS_CD" "$VNC_KEYMAP" "$BROWSER_INDEX" "$BROWSER_SCALE" \
  "$BROWSER_RFB" "$BROWSER_LICENSE" "$PAKO_LICENSE"; do
  [ -e "$required" ] || die "Required release component is missing: $required"
done
[ -s "$TOOLS_CD" ] || die "Bundled ClassicMac Tools CD is empty"
if [ "$SKIP_REPO_FRESHNESS" != "1" ] && \
   [ -f "$ROOT_DIR/dist/ClassicMacTools.iso" ]; then
  cmp -s "$ROOT_DIR/dist/ClassicMacTools.iso" "$TOOLS_CD" || \
    die "Bundled Tools CD differs from the freshly built dist image"
fi
if [ "$SKIP_REPO_FRESHNESS" != "1" ] && \
   [ -f "$ROOT_DIR/ppcvid/qemu_vga.ndrv" ]; then
  cmp -s "$ROOT_DIR/ppcvid/qemu_vga.ndrv" "$PPC_NDRV" || \
    die "Bundled Power Mac NDRV differs from the freshly built driver"
fi
if [ -f "$ROOT_DIR/ppcvid/qemu_vga.ndrv.gxmetal-protocol.sha256" ]; then
  CURRENT_PROTOCOL_SHA="$(shasum -a 256 \
    "$ROOT_DIR/gxmetal/protocol/gxmetal_protocol.h" | awk '{ print $1 }')"
  NDRV_PROTOCOL_SHA="$(sed -n '1p' \
    "$ROOT_DIR/ppcvid/qemu_vga.ndrv.gxmetal-protocol.sha256")"
  [ "$NDRV_PROTOCOL_SHA" = "$CURRENT_PROTOCOL_SHA" ] || \
    die "Power Mac NDRV was built for a different GXMetal protocol"
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw "$PLIST")"
HELPER_VERSION="$(plutil -extract CFBundleShortVersionString raw \
  "$PPC_HELPER/Contents/Info.plist")"
HELPER_BUILD="$(plutil -extract CFBundleVersion raw \
  "$PPC_HELPER/Contents/Info.plist")"

[ -z "$EXPECTED_VERSION" ] || [ "$VERSION" = "$EXPECTED_VERSION" ] || \
  die "Expected version $EXPECTED_VERSION, found $VERSION"
[ -z "$EXPECTED_BUILD" ] || [ "$BUILD" = "$EXPECTED_BUILD" ] || \
  die "Expected build $EXPECTED_BUILD, found $BUILD"
[ "$HELPER_VERSION" = "$VERSION" ] || \
  die "Power Mac helper version $HELPER_VERSION does not match app version $VERSION"
[ "$HELPER_BUILD" = "$BUILD" ] || \
  die "Power Mac helper build $HELPER_BUILD does not match app build $BUILD"

if [ "$VERIFY_ADHOC" -eq 1 ]; then
  log "Verifying ad-hoc signatures and hardened runtime"
else
  log "Verifying Developer ID signatures and hardened runtime"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
for signed_item in "$APP" "$PPC_HELPER" "$QUADRA_HELPER"; do
  SIGNING_INFO="$(codesign -dvvv "$signed_item" 2>&1)"
  if [ "$VERIFY_ADHOC" -eq 1 ]; then
    printf '%s\n' "$SIGNING_INFO" | grep -q '^Signature=adhoc' || \
      die "Ad-hoc signature missing from $signed_item"
  else
    printf '%s\n' "$SIGNING_INFO" | grep -q \
      '^Authority=Developer ID Application:' || \
      die "Developer ID Application signature missing from $signed_item"
    printf '%s\n' "$SIGNING_INFO" | grep -q '^TeamIdentifier=' || \
      die "Signing team identifier missing from $signed_item"
  fi
  printf '%s\n' "$SIGNING_INFO" | grep -q 'flags=.*runtime' || \
    die "Hardened runtime is missing from $signed_item"
done

for qemu_helper in "$PPC_HELPER" "$QUADRA_HELPER"; do
  ENTITLEMENTS_INFO="$(codesign -d --entitlements :- "$qemu_helper" 2>/dev/null || true)"
  for entitlement in com.apple.security.cs.allow-jit \
                     com.apple.security.cs.allow-unsigned-executable-memory \
                     com.apple.security.cs.disable-library-validation; do
    printf '%s\n' "$ENTITLEMENTS_INFO" | grep -q "<key>$entitlement</key>" || \
      die "Required QEMU JIT entitlement $entitlement is missing from $qemu_helper"
  done
done

if [ "$VERIFY_NOTARIZATION" -eq 1 ]; then
  log "Validating the stapled app ticket and executable Gatekeeper policy"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
fi

log "Verifying native macOS executable architecture ($EXPECTED_ARCH)"
for native_executable in "$MAIN_APP" "$PPC_QEMU" "$QUADRA_QEMU" "$COPLAND_ENGINE"; do
  ARCHS="$(lipo -archs "$native_executable")"
  [ "$ARCHS" = "$EXPECTED_ARCH" ] || \
    die "$(basename "$native_executable") architecture is '$ARCHS', expected '$EXPECTED_ARCH'"
done

log "Verifying the bundled GXMetal-capable Power Mac executable"
DEVICE_HELP="$("$PPC_QEMU" -device VGA,help 2>&1)"
for property in gxmetal untracked-vram packed-lowbpp hardware-cursor host-resize; do
  printf '%s\n' "$DEVICE_HELP" | grep -q "$property" || \
    die "Bundled Power Mac QEMU lacks VGA.$property"
done
for qemu in "$PPC_QEMU" "$QUADRA_QEMU"; do
  DISPLAY_HELP="$("$qemu" -display help 2>&1 || true)"
  printf '%s\n' "$DISPLAY_HELP" | grep -qx 'cocoa' || \
    die "Bundled $(basename "$qemu") lacks the native Cocoa display"

  VNC_HELP="$("$qemu" -vnc help 2>&1 || true)"
  printf '%s\n' "$VNC_HELP" | grep -q 'vnc options' || \
    die "Bundled $(basename "$qemu") lacks the optional VNC display"
  printf '%s\n' "$VNC_HELP" | grep -q 'websocket=' || \
    die "Bundled $(basename "$qemu") lacks VNC-over-WebSocket support"

  QEMU_STRINGS="$(strings "$qemu")"
  for option in swap-opt-cmd right-click-ctrl scroll-keys; do
    grep -Fq "$option" <<< "$QEMU_STRINGS" || \
      die "Bundled $(basename "$qemu") lacks Cocoa option $option"
  done
  if [[ "$VERSION" == 3.* ]]; then
    for marker in classicmac-media com.classicmac.paste-text com.classicmac.media; do
      grep -Fq "$marker" <<< "$QEMU_STRINGS" || \
        die "Bundled $(basename "$qemu") lacks ClassicMac 3 media/text bridge $marker"
    done
  fi
done
if [[ "$VERSION" == 3.* ]]; then
  strings "$PPC_QEMU" | grep -F 'gxmetal-status' >/dev/null || \
    die "Bundled Power Mac QEMU lacks live GXMetal status"
  for action in /actions/paste-text /actions/media; do
    grep -Fq "$action" "$APP/Contents/Resources/Browser/viewer.js" || \
      die "Bundled browser controls lack $action"
  done
  log "Checking every packaged runtime library supports macOS 15"
  python3 - "$APP" "$EXPECTED_ARCH" <<'PY'
from pathlib import Path
import re
import subprocess
import sys
app = Path(sys.argv[1])
expected_arch = sys.argv[2]
for helper in (app / "Contents/Helpers").glob("*.app"):
    frameworks = helper / "Contents/Frameworks"
    if not (helper / "Contents/Resources/release-libraries.json").is_file():
        sys.exit(f"Missing runtime library provenance: {helper.name}")
    for library in list(frameworks.glob("*.dylib")) + list((helper / "Contents/MacOS").iterdir()):
        archs = subprocess.check_output(["lipo", "-archs", str(library)], text=True).split()
        if archs != [expected_arch]:
            sys.exit(f"Runtime library architecture mismatch: {library.name}: {archs}")
        info = subprocess.check_output(["otool", "-l", str(library)], text=True)
        minimums = re.findall(r"\bminos ([0-9.]+)", info)
        if not minimums or any(tuple(map(int, (v + ".0.0").split(".")[:3])) > (15, 0, 0) for v in minimums):
            sys.exit(f"Runtime library needs newer than macOS 15: {library.name}")
        deps = subprocess.check_output(["otool", "-L", str(library)], text=True)
        if "/opt/homebrew" in deps or "@@HOMEBREW" in deps or "/usr/local" in deps:
            sys.exit(f"Unbundled runtime dependency: {library.name}")
print(f"All packaged runtime libraries are {expected_arch} and target macOS 15 or earlier.")
PY
fi
grep -q 'pseudoEncodingQEMUPointerTypeChange' "$BROWSER_RFB" || \
  die "Bundled browser client lacks QEMU relative-pointer support"
grep -q 'Math.floor(fit)' "$BROWSER_SCALE" || \
  die "Bundled browser client lacks whole-number display scaling"
if otool -L "$PPC_QEMU" | grep -Eq '/opt/homebrew|/usr/local'; then
  die "Bundled Power Mac QEMU still references a package-manager library"
fi

log "Release verification passed"
if [ "$VERIFY_ADHOC" -eq 1 ]; then
  printf '    Signing:       ad-hoc (not notarized)\n'
else
  printf '    Signing:       Developer ID\n'
fi
printf '    Version:       %s (%s)\n' "$VERSION" "$BUILD"
printf '    Tools CD SHA:  %s\n' "$(shasum -a 256 "$TOOLS_CD" | awk '{ print $1 }')"
printf '    Power NDRV SHA: %s\n' "$(shasum -a 256 "$PPC_NDRV" | awk '{ print $1 }')"
if [ -f "$TARGET" ]; then
  printf '    Target SHA:    %s\n' "$(shasum -a 256 "$TARGET" | awk '{ print $1 }')"
else
  printf '    Power Mac SHA: %s\n' "$(shasum -a 256 "$PPC_QEMU" | awk '{ print $1 }')"
fi
