#!/usr/bin/env bash
#
# make-dmg.sh - Package dist/ClassicMac.app into a drag-to-Applications DMG.
#
# By default this is the public-release path: require a Developer ID Application
# identity, notarize/staple the app when needed, then sign/notarize/staple the
# DMG. For community/local builds without an Apple Developer certificate, set
# SIGN_IDENTITY=- to create an explicitly ad-hoc signed, non-notarized DMG.
#
# Typical release flow:
#   scripts/bundle-qemu.sh
#   scripts/make-dmg.sh
#
# Ad-hoc flow:
#   SIGN_IDENTITY=- scripts/bundle-qemu.sh
#   SIGN_IDENTITY=- scripts/make-dmg.sh
#
# Idempotent: the DMG is rebuilt from scratch on every run.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/dist/ClassicMac.app"
DMG="$ROOT_DIR/dist/ClassicMac.dmg"
STAGING="$ROOT_DIR/dist/dmg-staging"
VOLNAME="ClassicMac"
PROFILE="${NOTARY_PROFILE:-classicmac-notary}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$APP" ] || die "dist/ClassicMac.app not found. Run scripts/bundle-qemu.sh first."

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')"
fi
if [ -z "$SIGN_IDENTITY" ]; then
  die "No Developer ID Application certificate found. For an ad-hoc, non-notarized DMG use: SIGN_IDENTITY=- ./scripts/make-dmg.sh"
fi

ADHOC_SIGNING=0
if [ "$SIGN_IDENTITY" = "-" ]; then
  ADHOC_SIGNING=1
  log "Ad-hoc DMG mode: notarization, stapling, and Gatekeeper trust checks will be skipped"
else
  # Notary credentials: use an explicitly supplied API key first, then the
  # keychain profile, then Apple ID credentials. This keeps automation from
  # depending on an unlocked login keychain.
  if [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ]; then
    NOTARY_AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID")
    if [ -n "${NOTARY_ISSUER_ID:-}" ]; then
      NOTARY_AUTH+=(--issuer "$NOTARY_ISSUER_ID")
    fi
    xcrun notarytool history "${NOTARY_AUTH[@]}" >/dev/null 2>&1 || \
      die "The supplied NOTARY_KEY credentials were rejected by Apple."
  else
    NOTARY_AUTH=(--keychain-profile "$PROFILE")
    if ! xcrun notarytool history "${NOTARY_AUTH[@]}" >/dev/null 2>&1; then
      if [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
        log "Keychain profile '$PROFILE' unavailable; using NOTARY_* Apple ID credentials"
        NOTARY_AUTH=(--apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD")
      else
        die "No usable notary credentials. Set NOTARY_KEY and NOTARY_KEY_ID (plus NOTARY_ISSUER_ID for a Team API Key), unlock or recreate keychain profile '$PROFILE', or set NOTARY_APPLE_ID, NOTARY_TEAM_ID and NOTARY_PASSWORD."
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 1. Validate the app before packaging
# ---------------------------------------------------------------------------
if [ "$ADHOC_SIGNING" -eq 1 ]; then
  log "Verifying ad-hoc app signature"
  codesign --verify --deep --strict --verbose=2 "$APP" || \
    die "The app's existing ad-hoc signature is invalid. Re-run scripts/bundle-qemu.sh."
else
  if xcrun stapler validate "$APP" >/dev/null 2>&1; then
    log "App already has a stapled notarization ticket"
  else
    log "App not stapled yet; running scripts/notarize.sh"
    bash "$ROOT_DIR/scripts/notarize.sh"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Build the DMG (app + Applications symlink)
# ---------------------------------------------------------------------------
log "Assembling DMG staging folder"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/ClassicMac.app"
ln -s /Applications "$STAGING/Applications"

log "Creating $DMG"
rm -f "$DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

# ---------------------------------------------------------------------------
# 3. Sign the DMG; notarize/staple only Developer ID releases
# ---------------------------------------------------------------------------
log "Signing DMG"
if [ "$ADHOC_SIGNING" -eq 1 ]; then
  codesign --force --sign - --timestamp=none "$DMG"
else
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

  log "Submitting DMG to Apple notary service (this can take a few minutes)"
  SUBMIT_OUTPUT="$(xcrun notarytool submit "$DMG" "${NOTARY_AUTH[@]}" --wait 2>&1 | tee /dev/stderr)"

  SUBMISSION_ID="$(printf '%s\n' "$SUBMIT_OUTPUT" | awk '/^  id:/{print $2; exit}')"
  STATUS="$(printf '%s\n' "$SUBMIT_OUTPUT" | awk '/^  status:/{print $2}' | tail -1)"

  if [ "$STATUS" != "Accepted" ]; then
    log "Notarization failed (status: ${STATUS:-unknown}). Fetching log:"
    if [ -n "$SUBMISSION_ID" ]; then
      xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_AUTH[@]}" || true
    fi
    die "DMG notarization was not accepted."
  fi

  log "Stapling notarization ticket to the DMG"
  xcrun stapler staple "$DMG"
fi

# ---------------------------------------------------------------------------
# 4. Verify
# ---------------------------------------------------------------------------
log "Verifying DMG"
hdiutil verify "$DMG" >/dev/null || die "Disk image verification failed."
codesign --verify --verbose=2 "$DMG" || die "DMG code signature verification failed."

if [ "$ADHOC_SIGNING" -eq 1 ]; then
  log "Done. Ad-hoc disk image: $DMG"
  log "This DMG is not notarized; downloaded copies require local trust/self-signing steps documented in README.md."
else
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || die "Gatekeeper rejected the DMG."
  xcrun stapler validate "$DMG" || die "Stapled ticket failed validation."
  log "Done. Distributable disk image: $DMG"
fi
