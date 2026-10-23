#!/usr/bin/env python3
"""Merge single-architecture ClassicMac apps into a universal app, or verify one.

  universal-app.py merge ARM64_APP X86_64_APP OUTPUT_APP
  universal-app.py verify APP [--expect-archs "arm64 x86_64"]

merge walks both bundles (built by scripts/bundle-qemu.sh from the same
sources and version) and writes OUTPUT_APP unsigned:

* Mach-O files present in both are joined with lipo. Each input slice must be
  thin and of its input's architecture.
* Mach-O files present in only one input are allowed in a helper's
  Contents/Frameworks (Homebrew can ship different library versions for each
  architecture; each slice of the executable references its own file). They
  stay thin; anything else missing from one side is an error.
* Other files must be byte-identical, except each helper's release-library
  provenance (Contents/Resources/release-libraries.json), which is combined
  per architecture. --allow-resource-diff takes the arm64 copy of any other
  differing file and reports it.
* Existing code signatures are discarded; scripts/sign-app.sh signs the result.

verify checks that every executable in Contents/MacOS of the app and its
helpers carries the same architecture set as the main executable (or
--expect-archs), and that for every architecture each executable's bundled
dependency closure resolves to files that contain that architecture.
"""
from __future__ import annotations

import argparse
import filecmp
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import subprocess
import sys

ARCHS = ("arm64", "x86_64")
MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",  # 32-bit
    b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",  # 64-bit
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",  # fat
    b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",  # fat64
}
SKIPPED_NAMES = {"_CodeSignature", ".DS_Store", "CodeResources"}
PROVENANCE = "release-libraries.json"
SYSTEM = ("/usr/lib/", "/System/Library/")
PLIST_KEYS = ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
              "CFBundleExecutable", "LSMinimumSystemVersion")


class MergeError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise MergeError(message)


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


def is_macho(path: Path) -> bool:
    if path.is_symlink() or not path.is_file():
        return False
    with path.open("rb") as stream:
        magic = stream.read(4)
    if magic in (b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
        # Java class files share the fat magic; Mach-O fat headers carry a
        # small architecture count where class files carry a version.
        with path.open("rb") as stream:
            header = stream.read(8)
        count = int.from_bytes(header[4:8], "big" if magic == b"\xca\xfe\xba\xbe" else "little")
        return 0 < count < 32
    return magic in MACHO_MAGICS


def archs(path: Path) -> list[str]:
    return sorted(run("/usr/bin/lipo", "-archs", str(path)).split())


def entries(root: Path) -> dict[str, str]:
    """Relative path -> kind ("dir", "link", "file"), without following links."""
    found = {}
    for current, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [d for d in dirs if d not in SKIPPED_NAMES]
        base = Path(current)
        for name in dirs + files:
            if name in SKIPPED_NAMES:
                continue
            path = base / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                found[relative] = "link"
            elif path.is_dir():
                found[relative] = "dir"
            else:
                found[relative] = "file"
    return found


def in_frameworks(relative: str) -> bool:
    parts = PurePosixPath(relative).parts
    return len(parts) >= 2 and parts[-2] == "Frameworks"


def bundle_info(app: Path) -> dict:
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    return {key: info.get(key) for key in PLIST_KEYS}


def same_plist(a: Path, b: Path) -> bool:
    try:
        return plistlib.loads(a.read_bytes()) == plistlib.loads(b.read_bytes())
    except (plistlib.InvalidFileException, ValueError):
        return False


def merge(arm_app: Path, x86_app: Path, output: Path, allow_resource_diff=False, log=print):
    inputs = {"arm64": arm_app, "x86_64": x86_app}
    for arch, app in inputs.items():
        require((app / "Contents/Info.plist").is_file(), f"Not an app bundle: {app}")
        main = app / "Contents/MacOS" / (bundle_info(app)["CFBundleExecutable"] or "")
        require(main.is_file(), f"Missing main executable in {app}")
        require(archs(main) == [arch], f"{app} is {' '.join(archs(main))}, expected a thin {arch} app")
    require(bundle_info(arm_app) == bundle_info(x86_app),
            f"Bundle identity/version differs: {bundle_info(arm_app)} vs {bundle_info(x86_app)}")
    require(not output.exists(), f"Output already exists: {output}")

    arm_entries, x86_entries = entries(arm_app), entries(x86_app)
    problems, notes = [], []
    output.mkdir(parents=True)
    for relative in sorted(set(arm_entries) | set(x86_entries)):
        kinds = (arm_entries.get(relative), x86_entries.get(relative))
        a, x, out = arm_app / relative, x86_app / relative, output / relative
        if None in kinds:
            present = a if kinds[0] else x
            arch = "arm64" if kinds[0] else "x86_64"
            kind = kinds[0] or kinds[1]
            if kind == "file" and in_frameworks(relative) and is_macho(present):
                require(archs(present) == [arch], f"{relative} is not a thin {arch} library")
                out.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(present, out)
                notes.append(f"{arch}-only library: {relative}")
            elif kind == "dir" and relative.endswith("Frameworks"):
                out.mkdir(parents=True, exist_ok=True)
            else:
                problems.append(f"only in the {arch} app: {relative}")
            continue
        if kinds[0] != kinds[1]:
            problems.append(f"{relative}: {kinds[0]} in arm64 app, {kinds[1]} in x86_64 app")
            continue
        kind = kinds[0]
        if kind == "dir":
            out.mkdir(parents=True, exist_ok=True)
        elif kind == "link":
            if os.readlink(a) != os.readlink(x):
                problems.append(f"{relative}: symlink targets differ")
            else:
                out.parent.mkdir(parents=True, exist_ok=True)
                os.symlink(os.readlink(a), out)
        elif is_macho(a) or is_macho(x):
            if not (is_macho(a) and is_macho(x)):
                problems.append(f"{relative}: Mach-O in only one app")
                continue
            if archs(a) != ["arm64"] or archs(x) != ["x86_64"]:
                problems.append(f"{relative}: slices are {archs(a)} and {archs(x)}, expected arm64 and x86_64")
                continue
            out.parent.mkdir(parents=True, exist_ok=True)
            run("/usr/bin/lipo", "-create", str(a), str(x), "-output", str(out))
            os.chmod(out, a.stat().st_mode & 0o7777)
        elif filecmp.cmp(a, x, shallow=False):
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(a, out)
        elif relative.endswith(".plist") and same_plist(a, x):
            # Same property list serialized differently (e.g. key order).
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(a, out)
        elif PurePosixPath(relative).name == PROVENANCE:
            combined = {"schema_version": 1, "universal": True,
                        "architectures": {"arm64": json.loads(a.read_text()),
                                          "x86_64": json.loads(x.read_text())}}
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(json.dumps(combined, indent=2) + "\n")
            notes.append(f"combined per-architecture provenance: {relative}")
        elif allow_resource_diff:
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(a, out)
            notes.append(f"WARNING: differing resource taken from the arm64 app: {relative}")
        else:
            problems.append(f"{relative}: differs between the apps")
    for note in notes:
        log("    " + note)
    if problems:
        shutil.rmtree(output)
        raise MergeError("The apps cannot be merged:\n  " + "\n  ".join(problems))
    return notes


def dependencies(binary: Path, arch: str) -> list[str]:
    lines = run("/usr/bin/otool", "-arch", arch, "-L", str(binary)).splitlines()[1:]
    deps = [line.strip().split(" (compatibility version", 1)[0] for line in lines if line.strip()]
    identity = run("/usr/bin/otool", "-arch", arch, "-D", str(binary)).splitlines()[1:]
    return [dep for dep in deps if dep not in identity]


def rpaths(binary: Path, arch: str) -> list[str]:
    found, block = [], []
    for line in run("/usr/bin/otool", "-arch", arch, "-l", str(binary)).splitlines():
        line = line.strip()
        if line.startswith("Load command"):
            block = []
        block.append(line)
        if line.startswith("path ") and any(item == "cmd LC_RPATH" for item in block):
            found.append(line[5:].split(" (offset", 1)[0])
    return found


def resolve(dep: str, binary: Path, executable: Path, search: list[str]) -> list[Path]:
    if dep.startswith("@executable_path/"):
        return [executable.parent / dep.removeprefix("@executable_path/")]
    if dep.startswith("@loader_path/"):
        return [binary.parent / dep.removeprefix("@loader_path/")]
    if dep.startswith("@rpath/"):
        tail = dep.removeprefix("@rpath/")
        return [resolve(rpath + "/" + tail, binary, executable, [])[0] for rpath in search]
    return [Path(dep)]


def executables(app: Path) -> list[Path]:
    found = sorted((app / "Contents/MacOS").iterdir())
    helpers = app / "Contents/Helpers"
    if helpers.is_dir():
        for helper in sorted(helpers.glob("*.app")):
            found += sorted((helper / "Contents/MacOS").iterdir())
    return [path for path in found if is_macho(path)]


def verify(app: Path, expect=None, log=print):
    main = app / "Contents/MacOS" / (bundle_info(app)["CFBundleExecutable"] or "")
    require(main.is_file(), f"Missing main executable in {app}")
    wanted = sorted(expect.split()) if expect else archs(main)
    require(wanted and all(arch in ARCHS for arch in wanted), f"Unexpected architectures: {wanted}")
    problems = []
    for executable in executables(app):
        relative = executable.relative_to(app)
        if archs(executable) != wanted:
            problems.append(f"{relative} is {' '.join(archs(executable))}, expected {' '.join(wanted)}")
            continue
        for arch in wanted:
            pending, seen = [executable], set()
            search = rpaths(executable, arch)
            while pending:
                binary = pending.pop()
                if binary in seen:
                    continue
                seen.add(binary)
                for dep in dependencies(binary, arch):
                    if dep.startswith(SYSTEM):
                        continue
                    candidates = [c for c in resolve(dep, binary, executable, search + rpaths(binary, arch))
                                  if c.is_file()]
                    if not candidates:
                        problems.append(f"{relative} [{arch}]: unresolved {dep} (from {binary.name})")
                        continue
                    target = candidates[0].resolve()
                    if not str(target).startswith(str(app.resolve()) + "/"):
                        problems.append(f"{relative} [{arch}]: {dep} is outside the bundle")
                    elif arch not in archs(target):
                        problems.append(f"{relative} [{arch}]: {target.name} lacks {arch}")
                    else:
                        pending.append(target)
    if problems:
        raise MergeError("Architecture verification failed:\n  " + "\n  ".join(problems))
    log(f"    OK  every executable is {' '.join(wanted)} with a complete bundled dependency closure")
    return wanted


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    merge_cmd = commands.add_parser("merge")
    merge_cmd.add_argument("arm64_app", type=Path)
    merge_cmd.add_argument("x86_64_app", type=Path)
    merge_cmd.add_argument("output_app", type=Path)
    merge_cmd.add_argument("--allow-resource-diff", action="store_true")
    verify_cmd = commands.add_parser("verify")
    verify_cmd.add_argument("app", type=Path)
    verify_cmd.add_argument("--expect-archs", default=None)
    args = parser.parse_args()
    try:
        if args.command == "merge":
            merge(args.arm64_app, args.x86_64_app, args.output_app, args.allow_resource_diff)
        else:
            verify(args.app, args.expect_archs)
    except (MergeError, OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
