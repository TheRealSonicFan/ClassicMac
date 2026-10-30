#!/usr/bin/env python3
"""Merge a thin arm64 and a thin x86_64 ClassicMac.app into one universal app.

Both inputs come from scripts/bundle-qemu.sh, one per architecture, built from
the same source revision. The merge is strict, so a universal app is exactly
the union of the two releases:

* every Mach-O present in both trees must be thin arm64 in the first and thin
  x86_64 in the second; the slices are combined with lipo;
* every other file must be byte-identical, except release-libraries.json
  provenance (combined per architecture) and the host-generated application
  icon (Assets.car / AppIcon.icns: the arm64 copy is kept);
* a file may be present in only one tree when it is a dylib in a helper's
  Contents/Frameworks (each architecture's Homebrew dependency closure may
  differ); only that architecture's executables reference it;
* code signatures and stapled tickets are dropped; scripts/sign-app.sh signs
  the merged result.

The output directory must not exist yet. Nothing is signed here.
"""
from __future__ import annotations

import argparse
import filecmp
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys

ARCHS = ("arm64", "x86_64")
MACHO_MAGICS = {
    bytes.fromhex("cffaedfe"), bytes.fromhex("cefaedfe"),  # thin, little-endian
    bytes.fromhex("feedfacf"), bytes.fromhex("feedface"),
    bytes.fromhex("cafebabe"), bytes.fromhex("cafebabf"),  # fat
}
# Regenerated on every bundle by sips/iconutil/actool on the build host, so
# they may differ between two otherwise identical builds.
HOST_GENERATED = {"Contents/Resources/AppIcon.icns", "Contents/Resources/Assets.car"}
PROVENANCE = "release-libraries.json"
SKIPPED_DIRS = {"_CodeSignature"}
SKIPPED_FILES = {".DS_Store"}


class MergeError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise MergeError(message)


def is_macho(path):
    with open(path, "rb") as stream:
        return stream.read(4) in MACHO_MAGICS


def archs(path):
    result = subprocess.run(["/usr/bin/lipo", "-archs", str(path)], text=True, capture_output=True)
    require(result.returncode == 0, "lipo cannot read " + str(path) + ": " + result.stderr.strip())
    return result.stdout.split()


def skipped(relative):
    parts = PurePosixPath(relative).parts
    if any(part in SKIPPED_DIRS for part in parts) or parts[-1] in SKIPPED_FILES:
        return True
    # A stapled notarization ticket: Contents/CodeResources of any bundle.
    return parts[-1] == "CodeResources" and len(parts) >= 2 and parts[-2] == "Contents"


def inventory(root):
    """Relative POSIX paths of directories, symlinks and regular files."""
    dirs, links, files = set(), {}, set()
    for current, dirnames, filenames in os.walk(root, followlinks=False):
        base = Path(current)
        for name in list(dirnames):
            path = base / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                dirnames.remove(name)
                if not skipped(relative):
                    links[relative] = os.readlink(path)
            elif skipped(relative):
                dirnames.remove(name)
            else:
                dirs.add(relative)
        for name in filenames:
            path = base / name
            relative = path.relative_to(root).as_posix()
            if skipped(relative):
                continue
            if path.is_symlink():
                links[relative] = os.readlink(path)
            else:
                require(path.is_file(), "Unsupported file type: " + str(path))
                files.add(relative)
    return dirs, links, files


def framework_dylib(relative):
    parts = PurePosixPath(relative).parts
    return (len(parts) == 6 and parts[0] == "Contents" and parts[1] == "Helpers"
            and parts[2].endswith(".app") and parts[3] == "Contents"
            and parts[4] == "Frameworks" and parts[5].endswith(".dylib"))


def merged_provenance(primary, secondary):
    documents = {}
    for arch, path in zip(ARCHS, (primary, secondary)):
        document = json.loads(Path(path).read_text())
        recorded = document.get("architecture", "arm64" if "libraries" in document else None)
        require(recorded in (None, arch), path.as_posix() + " describes " + str(recorded) + ", expected " + arch)
        documents[arch] = document
    return {"schema_version": 1, "universal": True, "architectures": documents}


def merge(primary, secondary, output):
    """Merge PRIMARY (arm64) and SECONDARY (x86_64) into OUTPUT."""
    primary, secondary, output = Path(primary), Path(secondary), Path(output)
    for app in (primary, secondary):
        require((app / "Contents/Info.plist").is_file(), "Not an application bundle: " + str(app))
    require(not output.exists(), "Output already exists: " + str(output))
    dirs_a, links_a, files_a = inventory(primary)
    dirs_b, links_b, files_b = inventory(secondary)
    require(links_a == links_b, "Symbolic links differ between the two apps")
    require(not (set(links_a) & (files_b | dirs_b)) and not (set(links_b) & (files_a | dirs_a)),
            "A path is a link in one app and a file or directory in the other")

    report = {"lipo": [], "single": [], "host_generated": [], "provenance": []}
    output.mkdir(parents=True)
    for relative in sorted(dirs_a | dirs_b):
        (output / relative).mkdir(parents=True, exist_ok=True)
    for relative, target in sorted(links_a.items()):
        (output / relative).parent.mkdir(parents=True, exist_ok=True)
        os.symlink(target, output / relative)

    for relative in sorted(files_a | files_b):
        a, b, out = primary / relative, secondary / relative, output / relative
        out.parent.mkdir(parents=True, exist_ok=True)
        if relative not in files_b or relative not in files_a:
            source, arch = (a, ARCHS[0]) if relative in files_a else (b, ARCHS[1])
            require(framework_dylib(relative) and is_macho(source),
                    relative + " exists only in the " + arch + " app")
            require(archs(source) == [arch], relative + " is not a thin " + arch + " dylib")
            shutil.copy2(source, out)
            report["single"].append(relative + " (" + arch + ")")
            continue
        macho_a, macho_b = is_macho(a), is_macho(b)
        require(macho_a == macho_b, relative + " is Mach-O in only one app")
        if macho_a:
            require(archs(a) == [ARCHS[0]], relative + " is not thin " + ARCHS[0] + " in the first app")
            require(archs(b) == [ARCHS[1]], relative + " is not thin " + ARCHS[1] + " in the second app")
            subprocess.run(["/usr/bin/lipo", "-create", str(a), str(b), "-output", str(out)],
                           check=True, capture_output=True)
            os.chmod(out, a.stat().st_mode & 0o7777)
            report["lipo"].append(relative)
        elif filecmp.cmp(a, b, shallow=False):
            shutil.copy2(a, out)
        elif PurePosixPath(relative).name == PROVENANCE:
            out.write_text(json.dumps(merged_provenance(a, b), indent=2) + "\n")
            os.chmod(out, a.stat().st_mode & 0o7777)
            report["provenance"].append(relative)
        elif relative in HOST_GENERATED:
            shutil.copy2(a, out)
            report["host_generated"].append(relative)
        else:
            raise MergeError(relative + " differs between the arm64 and x86_64 apps")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("arm64_app", type=Path)
    parser.add_argument("x86_64_app", type=Path)
    parser.add_argument("output_app", type=Path)
    args = parser.parse_args()
    try:
        report = merge(args.arm64_app, args.x86_64_app, args.output_app)
    except (MergeError, OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print("Universal merge failed: " + str(error), file=sys.stderr)
        return 1
    print("Combined " + str(len(report["lipo"])) + " Mach-O files into arm64 + x86_64 binaries")
    for relative in report["single"]:
        print("Single-architecture dependency: " + relative)
    for relative in report["provenance"]:
        print("Combined runtime library provenance: " + relative)
    for relative in report["host_generated"]:
        print("Host-generated icon differs; kept the arm64 copy: " + relative)
    return 0


if __name__ == "__main__":
    sys.exit(main())
