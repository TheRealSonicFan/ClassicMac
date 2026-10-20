#!/usr/bin/env bash
#
# make-universal-app.sh - Merge an arm64 (Apple Silicon) and an x86_64 (Intel)
# ClassicMac.app built from the same source by scripts/bundle-qemu.sh into one
# universal ClassicMac.app, then code-sign it exactly like bundle-qemu.sh.
#
# Every Mach-O file present in both apps (the app, the QEMU and Copland
# engines, qemu-img and the bundled libraries) becomes a two-slice universal
# binary with lipo. A library only one architecture uses stays a thin file;
# dyld only loads it for that slice. Every other file must be byte-identical in
# both apps, except each helper's release-libraries.json, whose two
# provenance records are combined, and the compiled icon catalog Assets.car:
# actool output is not reproducible byte for byte even on one Mac, so the
# arm64 app's copy (architecture-independent data from the same
# Resources/AppIcon.icon) is used. Existing signatures and stapled tickets are
# discarded: the merged app is re-signed and must be notarized again
# (scripts/notarize.sh, scripts/make-dmg.sh).
#
# Usage:
#   scripts/make-universal-app.sh ARM64_APP X86_64_APP
#
# Typical flow (each architecture built natively, or x86_64 under Rosetta 2
# from a second checkout with CLASSICMAC_ARCH=x86_64):
#   DIST_DIR=dist/arm64  scripts/bundle-qemu.sh          # on Apple Silicon
#   DIST_DIR=dist/x86_64 scripts/bundle-qemu.sh          # on Intel
#   scripts/make-universal-app.sh dist/arm64/ClassicMac.app dist/x86_64/ClassicMac.app
#   scripts/make-dmg.sh
#   EXPECTED_ARCHS="arm64 x86_64" scripts/verify-release.sh dist/ClassicMac.dmg
#
# Environment overrides: DIST_DIR (default dist/; the result is always
# DIST_DIR/ClassicMac.app) and SIGN_IDENTITY (as in bundle-qemu.sh).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/macos-arch.sh
. "$ROOT_DIR/scripts/lib/macos-arch.sh"
# shellcheck source=lib/sign-app.sh
. "$ROOT_DIR/scripts/lib/sign-app.sh"
ENTITLEMENTS="$ROOT_DIR/scripts/qemu.entitlements"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
FINAL_APP="$DIST_DIR/ClassicMac.app"
LOCK_DIR="$DIST_DIR/.make-universal-app.lock"
STAGE_DIR=""
PREVIOUS_APP=""
LOCK_HELD=0

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[ "$#" -eq 2 ] || die "Usage: $(basename "$0") ARM64_APP X86_64_APP"
ARM64_APP="$(cd "$1" 2>/dev/null && pwd)" || die "arm64 app not found: $1"
X86_64_APP="$(cd "$2" 2>/dev/null && pwd)" || die "x86_64 app not found: $2"
for tool in lipo codesign plutil python3; do
  command -v "$tool" >/dev/null 2>&1 || die "Required tool not found: $tool"
done

# ---------------------------------------------------------------------------
# 0. Both inputs are complete single-architecture builds of the same version
# ---------------------------------------------------------------------------
check_input() {
  local app="$1" arch="$2" executable
  [ -f "$app/Contents/Info.plist" ] || die "$app is not an application bundle"
  for executable in "MacOS/ClassicMac" \
                    "Helpers/Power Mac G4.app/Contents/MacOS/qemu-system-ppc" \
                    "Helpers/Quadra 800.app/Contents/MacOS/qemu-system-m68k" \
                    "Helpers/Quadra 800.app/Contents/MacOS/qemu-img" \
                    "Helpers/Power Mac 7500.app/Contents/MacOS/dingusppc"; do
    [ -f "$app/Contents/$executable" ] || die "$app lacks Contents/$executable"
    classicmac_require_archs "$app/Contents/$executable" "$arch"
  done
}
check_input "$ARM64_APP" arm64
check_input "$X86_64_APP" x86_64
for key in CFBundleShortVersionString CFBundleVersion CFBundleIdentifier; do
  ARM64_VALUE="$(plutil -extract "$key" raw "$ARM64_APP/Contents/Info.plist")"
  X86_64_VALUE="$(plutil -extract "$key" raw "$X86_64_APP/Contents/Info.plist")"
  [ "$ARM64_VALUE" = "$X86_64_VALUE" ] || \
    die "$key differs: arm64 app has $ARM64_VALUE, x86_64 app has $X86_64_VALUE"
done
log "Merging ClassicMac $(plutil -extract CFBundleShortVersionString raw "$ARM64_APP/Contents/Info.plist") (arm64 + x86_64)"

# ---------------------------------------------------------------------------
# 1. Transactional staging, as in bundle-qemu.sh
# ---------------------------------------------------------------------------
cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  set +e
  if [ -n "$PREVIOUS_APP" ] && [ -e "$PREVIOUS_APP" ] && [ ! -e "$FINAL_APP" ]; then
    mv "$PREVIOUS_APP" "$FINAL_APP"
  fi
  if [ -n "$STAGE_DIR" ]; then
    case "$STAGE_DIR" in
      "$DIST_DIR"/.make-universal-app.stage.*) rm -rf -- "$STAGE_DIR" ;;
      *) printf '\nWARNING: Refusing to clean unexpected staging path: %s\n' "$STAGE_DIR" >&2 ;;
    esac
  fi
  if [ "$LOCK_HELD" -eq 1 ]; then
    rm -f -- "$LOCK_DIR/owner"
    rmdir -- "$LOCK_DIR" 2>/dev/null
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$DIST_DIR"
DIST_DIR="$(cd "$DIST_DIR" && pwd)"
FINAL_APP="$DIST_DIR/ClassicMac.app"
LOCK_DIR="$DIST_DIR/.make-universal-app.lock"
case "$FINAL_APP" in
  "$ARM64_APP"|"$X86_64_APP") die "The output $FINAL_APP must differ from both inputs (set DIST_DIR)" ;;
esac
mkdir "$LOCK_DIR" 2>/dev/null || die "Another make-universal-app.sh invocation holds $LOCK_DIR."
LOCK_HELD=1
printf '%s\n' "$$" > "$LOCK_DIR/owner"
STAGE_DIR="$(mktemp -d "$DIST_DIR/.make-universal-app.stage.XXXXXX")"
APP="$STAGE_DIR/ClassicMac.app"

# ---------------------------------------------------------------------------
# 2. Merge the two bundles file by file
# ---------------------------------------------------------------------------
log "Combining architecture slices"
python3 - "$ARM64_APP" "$X86_64_APP" "$APP" <<'PY'
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys

arm64, x86_64, output = (Path(p) for p in sys.argv[1:4])
MACHO = (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf")
# Architecture-independent build outputs that are not byte-reproducible.
NONREPRODUCIBLE = {"Contents/Resources/Assets.car"}

def skipped(relative):
    # Signatures and stapled tickets are regenerated for the merged app.
    parts = PurePosixPath(relative).parts
    return "_CodeSignature" in parts or (parts[-1] == "CodeResources" and len(parts) > 1 and parts[-2] == "Contents")

def entries(root):
    found = {}
    for directory, folders, files in os.walk(root):
        for name in sorted(folders + files):
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            if skipped(relative):
                continue
            if path.is_symlink():
                found[relative] = ("link", os.readlink(path))
            elif path.is_dir():
                found[relative] = ("dir", None)
            else:
                found[relative] = ("file", None)
    return found

def is_macho(path):
    with open(path, "rb") as stream:
        return stream.read(4) in MACHO

def archs(path):
    return set(subprocess.check_output(["lipo", "-archs", str(path)], text=True).split())

def is_provenance(relative):
    parts = PurePosixPath(relative).parts
    return parts[-1] == "release-libraries.json" and len(parts) == 6 and parts[1] == "Helpers" and parts[-2] == "Resources"

a, b = entries(arm64), entries(x86_64)
problems, universal, thin = [], 0, []
output.mkdir(parents=True)
for relative in sorted(set(a) | set(b)):
    kind_a, kind_b = a.get(relative, (None, None))[0], b.get(relative, (None, None))[0]
    source_a, source_b, target = arm64 / relative, x86_64 / relative, output / relative
    if kind_a and kind_b and kind_a != kind_b:
        problems.append(relative + ": file type differs between architectures")
        continue
    kind = kind_a or kind_b
    if kind == "dir":
        target.mkdir(parents=True, exist_ok=True)
        continue
    target.parent.mkdir(parents=True, exist_ok=True)
    if kind == "link":
        if kind_a and kind_b and a[relative][1] != b[relative][1]:
            problems.append(relative + ": symlink targets differ")
            continue
        os.symlink((a.get(relative) or b.get(relative))[1], target)
        continue
    if kind_a and kind_b:
        macho_a, macho_b = is_macho(source_a), is_macho(source_b)
        if macho_a and macho_b:
            if archs(source_a) & archs(source_b):
                problems.append(relative + ": both inputs contain the same architecture")
                continue
            subprocess.run(["lipo", "-create", str(source_a), str(source_b), "-output", str(target)], check=True)
            os.chmod(target, source_a.stat().st_mode & 0o7777)
            universal += 1
        elif source_a.read_bytes() == source_b.read_bytes():
            shutil.copy2(source_a, target)
        elif relative in NONREPRODUCIBLE:
            shutil.copy2(source_a, target)
            print("Using the arm64 app's " + relative + " (not byte-reproducible)")
        elif is_provenance(relative):
            merged = {"schema_version": 1, "universal": True, "architectures": {
                "arm64": json.loads(source_a.read_text()), "x86_64": json.loads(source_b.read_text())}}
            target.write_text(json.dumps(merged, indent=2) + "\n")
        else:
            problems.append(relative + ": differs between the arm64 and x86_64 apps")
        continue
    source, arch = (source_a, "arm64") if kind_a else (source_b, "x86_64")
    if is_macho(source):
        # Needed by one slice only (for example a library linked by only one
        # architecture's Homebrew build); dyld never loads it for the other.
        shutil.copy2(source, target)
        thin.append(relative + " (" + arch + " only)")
    else:
        problems.append(relative + ": only present in the " + arch + " app")

if problems:
    sys.exit("Cannot merge the apps:\n  " + "\n  ".join(problems))
print(f"Created {universal} universal Mach-O files")
for item in thin:
    print("Kept single-architecture file " + item)
PY

# ---------------------------------------------------------------------------
# 3. Sign (inner items first) and verify, as in bundle-qemu.sh
# ---------------------------------------------------------------------------
classicmac_sign_app "$APP" "$ENTITLEMENTS"
classicmac_require_archs "$APP/Contents/MacOS/ClassicMac" arm64 x86_64

log "Promoting verified universal app to $FINAL_APP"
if [ -e "$FINAL_APP" ]; then
  PREVIOUS_APP="$STAGE_DIR/Previous-ClassicMac.app"
  mv "$FINAL_APP" "$PREVIOUS_APP"
fi
mv "$APP" "$FINAL_APP" || die "Failed to promote the universal app to $FINAL_APP"

log "Done. Built universal app: $FINAL_APP"
