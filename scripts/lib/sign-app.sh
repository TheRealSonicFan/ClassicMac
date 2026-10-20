# shellcheck shell=bash
#
# sign-app.sh - code-sign an assembled ClassicMac.app, inner items first.
# Shared by scripts/bundle-qemu.sh (one architecture) and
# scripts/make-universal-app.sh (arm64 + x86_64), so both produce the same
# signature layout, hardened runtime and JIT entitlements for notarization.
#
# Usage: classicmac_sign_app APP ENTITLEMENTS
#
# Uses the Developer ID Application certificate when one is present in the
# keychain (required for notarization / distribution); falls back to ad-hoc
# signing otherwise. Override with SIGN_IDENTITY=<identity or "-">. Callers
# must define log() and die().

classicmac_sign_app() {
  local app="$1" entitlements="$2"
  local quadra_app="$app/Contents/Helpers/Quadra 800.app"
  local ppc_app="$app/Contents/Helpers/Power Mac G4.app"
  local copland_app="$app/Contents/Helpers/Power Mac 7500.app"
  local identity="${SIGN_IDENTITY:-}"
  local timestamp_flag

  if [ -z "$identity" ]; then
    identity="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')"
  fi
  if [ -z "$identity" ]; then
    identity="-"
  fi

  # Bundled files carry no extended attributes. QEMU's macOS build attaches a
  # Finder icon (Rez resource fork + SetFile FinderInfo) to qemu-system-*, and
  # codesign rejects both as "resource fork, Finder information, or similar
  # detritus"; the helper apps use MachineIcon.icns instead.
  xattr -cr "$app"

  # Developer ID signatures need a secure timestamp for notarization; ad-hoc
  # signatures cannot get one.
  timestamp_flag="--timestamp"
  if [ "$identity" = "-" ]; then
    timestamp_flag="--timestamp=none"
    log "Code signing (ad-hoc)"
  else
    log "Code signing (identity: $identity)"
  fi

  find "$quadra_app/Contents/Frameworks" "$ppc_app/Contents/Frameworks" -name '*.dylib' -print0 | while IFS= read -r -d '' lib; do
    codesign --force --sign "$identity" "$timestamp_flag" "$lib"
  done

  # qemu-img is not the helper bundle's main executable, so it needs its own
  # signature (no JIT entitlements required). All executables get the hardened
  # runtime, which notarization requires.
  codesign --force --sign "$identity" "$timestamp_flag" \
    --options runtime \
    "$quadra_app/Contents/MacOS/qemu-img"

  # Sign the helper apps as bundles, then the outer app. Signing a bundle
  # (re-)signs its main executable - the qemu-system binary - so the JIT
  # entitlements MUST be supplied here or this pass would strip them, leaving a
  # hardened-runtime binary that cannot map its JIT buffer ("allocate ... bytes
  # for jit buffer: Invalid argument" at launch).
  codesign --force --sign "$identity" "$timestamp_flag" \
    --options runtime --entitlements "$entitlements" \
    "$quadra_app"
  codesign --force --sign "$identity" "$timestamp_flag" \
    --options runtime --entitlements "$entitlements" \
    "$ppc_app"

  codesign --force --sign "$identity" "$timestamp_flag" --options runtime "$copland_app"
  codesign --force --sign "$identity" "$timestamp_flag" --options runtime "$app/Contents/MacOS/ClassicMac"

  # Sign the whole bundle last.
  codesign --force --sign "$identity" "$timestamp_flag" --options runtime "$app"

  log "Verifying bundle signature"
  codesign --verify --deep --strict --verbose=2 "$app" || die "Bundle failed signature verification."
}
