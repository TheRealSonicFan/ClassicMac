#!/usr/bin/env python3
"""Stage official Homebrew dylibs compatible with macOS 15.

The release build is host-native. Prefer exact-version official bottles when
Homebrew publishes a compatible macOS 15-era bottle. When current Intel
formulae no longer publish Intel bottles, use the installed official Homebrew
source build only after independently verifying its architecture and Mach-O
minimum OS version.

Run after dylibbundler and before signing. Homebrew itself is never changed.
Bottle downloads are content addressed. --library supports preparing an empty
Frameworks directory for verification.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request

PREFIX = None
SYSTEM = ("/usr/lib/", "/System/Library/")
BOTTLE_TAGS = {
    "arm64": ("arm64_sequoia",),
    "x86_64": ("sequoia", "sonoma"),
}
OCI_ARCH = {
    "arm64": "arm64",
    "x86_64": "amd64",
}


class NoCompatibleBottle(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with open(path, "rb") as stream:
        result = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
        return result.hexdigest()


def sha(value):
    require(isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value), "Invalid SHA256")
    return value


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


def homebrew_prefix():
    return PREFIX if PREFIX is not None else Path(run("brew", "--prefix").strip())


def bottle_tags(arch):
    require(arch in BOTTLE_TAGS, "Unsupported Homebrew architecture: " + str(arch))
    return BOTTLE_TAGS[arch]


class Registry:
    def __init__(self):
        self.tokens = {}

    def open(self, url):
        parsed = urllib.parse.urlparse(url)
        require(parsed.scheme == "https" and parsed.hostname in {"formulae.brew.sh", "ghcr.io", "raw.githubusercontent.com"}, "Unexpected source URL: " + url)
        headers = {"User-Agent": "ClassicMac-release-libraries/1"}
        if parsed.hostname == "ghcr.io":
            match = re.fullmatch(r"/v2/(homebrew/core/[a-z0-9_./-]+)/(?:blobs|manifests)/[^/]+", parsed.path)
            require(match is not None, "Unexpected GHCR repository URL")
            repo = match[1]
            if repo not in self.tokens:
                token_url = "https://ghcr.io/token?" + urllib.parse.urlencode({"service": "ghcr.io", "scope": "repository:" + repo + ":pull"})
                with urllib.request.urlopen(token_url, timeout=60) as response:
                    self.tokens[repo] = json.load(response)["token"]
            headers.update(Authorization="Bearer " + self.tokens[repo], Accept="application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json")
        return urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60)

    def document(self, url, expected=None):
        with self.open(url) as response:
            data = response.read()
            actual = hashlib.sha256(data).hexdigest()
            if expected:
                require(actual == sha(expected), "Source document digest mismatch: " + url)
            header = response.headers.get("Docker-Content-Digest")
            if header:
                require(header == "sha256:" + actual, "Registry digest mismatch: " + url)
        return json.loads(data), actual


def origin(name):
    require(Path(name).name == name and name.endswith(".dylib"), "Expected a dylib basename: " + name)
    prefix = homebrew_prefix()
    original = prefix / "lib" / name
    real = original.resolve(strict=True)
    relative = real.relative_to((prefix / "Cellar").resolve())
    require(len(relative.parts) >= 4 and relative.parts[2] == "lib", "Library is not in a Homebrew keg: " + str(real))
    formula, keg = relative.parts[:2]
    receipt_path = prefix / "Cellar" / formula / keg / "INSTALL_RECEIPT.json"
    receipt = json.loads(receipt_path.read_text())
    source = receipt.get("source", {})
    version = source.get("versions", {}).get("stable")
    arch = receipt.get("arch")
    require(arch in BOTTLE_TAGS, "Unsupported Homebrew architecture for " + formula + ": " + str(arch))
    require(source.get("tap") == "homebrew/core" and source.get("spec") == "stable", "Expected official stable receipt for " + formula)
    require(isinstance(version, str), "Missing installed version for " + formula)
    revision = 0
    if keg != version:
        require(keg.startswith(version + "_") and keg[len(version) + 1:].isdigit(), "Receipt/version mismatch for " + formula)
        revision = int(keg[len(version) + 1:])
    return {"formula": formula, "keg": keg, "version": version, "revision": revision,
            "arch": arch, "homebrew_prefix": str(prefix),
            "local_path": str(real), "receipt_sha256": digest(receipt_path),
            "receipt_tap_git_head": source.get("tap_git_head")}


def formula_api(registry, installed):
    formula = installed["formula"]
    api_url = "https://formulae.brew.sh/api/formula/" + urllib.parse.quote(formula) + ".json"
    api, api_hash = registry.document(api_url)
    require(api.get("full_name") == formula and api.get("tap") == "homebrew/core", "Formula API identity mismatch")
    current = api.get("versions", {}).get("stable") == installed["version"] and api.get("revision") == installed["revision"]
    return api_url, api, api_hash, current


def bottle_source(registry, installed):
    formula, keg = installed["formula"], installed["keg"]
    tags = bottle_tags(installed["arch"])
    api_url, api, api_hash, current = formula_api(registry, installed)
    if current:
        stable = api["bottle"]["stable"]
        files = stable["files"]
        tag = next((candidate for candidate in tags if candidate in files), None)
        if tag is None:
            raise NoCompatibleBottle("Missing compatible macOS bottle for " + formula + " (" + ", ".join(tags) + ")")
        bottle = files[tag]
        commit = api.get("tap_git_head")
        require(isinstance(commit, str) and re.fullmatch(r"[a-f0-9]{40}", commit), "Missing pinned formula commit")
        source_url = "https://raw.githubusercontent.com/Homebrew/homebrew-core/" + commit + "/" + api["ruby_source_path"]
        return {"url": bottle["url"], "sha256": sha(bottle["sha256"]), "formula_source_url": source_url,
                "formula_commit": commit, "metadata_url": api_url, "metadata_sha256": api_hash,
                "resolution": "exact-formula-api", "bottle_rebuild": stable.get("rebuild", 0),
                "bottle_tag": tag}

    # API-installed receipts can omit tap_git_head. An exact official registry
    # version index carries the historical source commit and platform digest.
    repo = formula.replace("@", "/")
    index_url = "https://ghcr.io/v2/homebrew/core/" + repo + "/manifests/" + keg
    index, index_hash = registry.document(index_url)
    annotations = index.get("annotations", {})
    require(annotations.get("com.github.package.type") == "homebrew_bottle" and
            annotations.get("org.opencontainers.image.title") == formula and
            annotations.get("org.opencontainers.image.version") == keg and
            annotations.get("org.opencontainers.image.ref.name") == keg,
            "Official registry formula/version/revision mismatch for " + formula)
    commit = annotations.get("org.opencontainers.image.revision", "")
    require(re.fullmatch(r"[a-f0-9]{40}", commit), "Missing historical formula commit")
    source_url = annotations.get("org.opencontainers.image.source", "")
    require(source_url.startswith("https://github.com/homebrew/homebrew-core/blob/" + commit + "/Formula/"), "Unexpected historical formula source")
    if installed["receipt_tap_git_head"]:
        require(commit == installed["receipt_tap_git_head"], "Receipt/historical formula commit mismatch")
    match = None
    tag = None
    for candidate in tags:
        matches = [m for m in index.get("manifests", [])
                   if m.get("annotations", {}).get("org.opencontainers.image.ref.name") == keg + "." + candidate]
        require(len(matches) <= 1, "Ambiguous bottle for " + formula + " (" + candidate + ")")
        if matches:
            match = matches[0]
            tag = candidate
            break
    if match is None:
        raise NoCompatibleBottle("Missing compatible macOS bottle for " + formula + " (" + ", ".join(tags) + ")")
    require(match.get("platform", {}).get("os") == "darwin" and
            match["platform"].get("architecture") == OCI_ARCH[installed["arch"]],
            "Wrong bottle platform")
    checksum = sha(match["annotations"]["sh.brew.bottle.digest"])
    manifest_hash = sha(match["digest"].removeprefix("sha256:"))
    manifest_url = "https://ghcr.io/v2/homebrew/core/" + repo + "/manifests/sha256:" + manifest_hash
    manifest, _ = registry.document(manifest_url, manifest_hash)
    require(any(layer.get("digest") == "sha256:" + checksum for layer in manifest.get("layers", [])), "Bottle layer digest does not match platform manifest")
    return {"url": "https://ghcr.io/v2/homebrew/core/" + repo + "/blobs/sha256:" + checksum,
            "sha256": checksum, "formula_source_url": source_url, "formula_commit": commit,
            "metadata_url": "https://ghcr.io/v2/homebrew/core/" + repo + "/manifests/sha256:" + index_hash,
            "metadata_sha256": index_hash, "platform_manifest_url": manifest_url,
            "resolution": "exact-historical-registry", "bottle_rebuild": 0,
            "bottle_tag": tag}


def local_build_source(registry, installed):
    """Describe the installed official Homebrew source build.

    Homebrew is reducing Intel bottle coverage for current formulae. When an
    exact compatible bottle does not exist, a native source build on the
    release host is acceptable only after the copied Mach-O is independently
    verified below for architecture and a macOS minimum no newer than 15.0.
    """
    api_url, api, api_hash, current = formula_api(registry, installed)
    require(current, "No compatible bottle and installed formula is not current: " + installed["formula"])
    commit = api.get("tap_git_head")
    require(isinstance(commit, str) and re.fullmatch(r"[a-f0-9]{40}", commit),
            "Missing pinned formula commit for local build")
    if installed.get("receipt_tap_git_head"):
        require(commit == installed["receipt_tap_git_head"],
                "Receipt/current formula commit mismatch for local build")
    source_url = "https://raw.githubusercontent.com/Homebrew/homebrew-core/" + commit + "/" + api["ruby_source_path"]
    return {"formula_source_url": source_url, "formula_commit": commit,
            "metadata_url": api_url, "metadata_sha256": api_hash,
            "resolution": "verified-local-homebrew-build", "bottle_rebuild": None,
            "bottle_tag": None}


def release_source(registry, installed):
    try:
        return bottle_source(registry, installed)
    except NoCompatibleBottle:
        return local_build_source(registry, installed)


def cached_bottle(registry, source, cache):
    expected = sha(source["sha256"])
    destination = cache / (expected + ".tar.gz")
    if destination.exists():
        require(destination.is_file() and not destination.is_symlink(), "Invalid cache entry")
        require(digest(destination) == expected, "Cached bottle SHA256 mismatch: " + str(destination))
        return destination
    cache.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".bottle-", dir=cache)
    try:
        with os.fdopen(fd, "wb") as output, registry.open(source["url"]) as response:
            shutil.copyfileobj(response, output)
        require(digest(temporary) == expected, "Downloaded bottle SHA256 mismatch")
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return destination


def regular_member(archive, member_name, keg_root):
    """Resolve archive aliases without materializing symlinks on the host."""
    seen = set()
    while True:
        require(member_name.startswith(keg_root + "/") and member_name not in seen, "Unsafe or cyclic bottle alias")
        seen.add(member_name)
        matches = [m for m in archive.getmembers() if m.name == member_name]
        require(len(matches) == 1, "Missing or ambiguous bottle member: " + member_name)
        member = matches[0]
        if member.isfile():
            require(member.size <= 128 * 1024 * 1024, "Unexpectedly large dylib")
            return member
        require(member.issym() or member.islnk(), "Bottle dylib is not a regular file")
        require(not member.linkname.startswith("/"), "Absolute bottle alias")
        base = posixpath.dirname(member_name) if member.issym() else ""
        member_name = posixpath.normpath(posixpath.join(base, member.linkname))


def extract_library(bottle, installed, name, destination):
    root = installed["formula"] + "/" + installed["keg"]
    with tarfile.open(bottle, "r:gz") as archive:
        member = regular_member(archive, root + "/lib/" + name, root)
        require(member.name.startswith(root + "/lib/") and member.name.endswith(".dylib"), "Dylib alias escaped lib directory")
        with archive.extractfile(member) as stream, destination.open("wb") as output:
            shutil.copyfileobj(stream, output)
    destination.chmod(0o755)
    return member.name


def macho(path, expected_arch):
    require(run("/usr/bin/lipo", "-archs", str(path)).split() == [expected_arch],
            "Expected thin " + expected_arch + " dylib: " + str(path))
    commands = run("/usr/bin/otool", "-l", str(path))
    versions = []
    for block in commands.split("Load command ")[1:]:
        if re.search(r"cmd LC_BUILD_VERSION\b", block):
            require(re.search(r"platform (?:1|MACOS)\b", block), "Non-macOS Mach-O platform")
            versions += re.findall(r"\bminos ([0-9.]+)", block)
        elif re.search(r"cmd LC_VERSION_MIN_MACOSX\b", block):
            versions += re.findall(r"\bversion ([0-9.]+)", block)
    require(versions and all(tuple(map(int, (v + ".0.0").split(".")[:3])) <= (15, 0, 0) for v in versions), "Library requires newer than macOS 15: " + str(path) + " " + str(versions))
    identity = run("/usr/bin/otool", "-D", str(path)).splitlines()[1:]
    require(len(identity) == 1, "Expected one dylib identity")
    dependencies = [line.strip().split(" (compatibility version", 1)[0] for line in run("/usr/bin/otool", "-L", str(path)).splitlines()[1:]]
    dependencies = [dep for dep in dependencies if dep != identity[0]]
    rpaths = []
    for block in commands.split("Load command ")[1:]:
        if re.search(r"cmd LC_RPATH\b", block):
            rpaths.extend(re.findall(r"\bpath (.+) \(offset", block))
    return {"minimum_macos": versions, "dependencies": dependencies, "rpaths": rpaths}


def stage(frameworks, cache, names):
    require(frameworks.is_dir() and not frameworks.is_symlink(), "Frameworks must be a real directory")
    names = sorted(set(names or [p.name for p in frameworks.glob("*.dylib")]))
    require(names, "No dylibs selected")
    registry = Registry()
    sources, records, aliases = {}, {}, {}
    installed_by_name = {name: origin(name) for name in names}
    architectures = {item["arch"] for item in installed_by_name.values()}
    require(len(architectures) == 1, "Release libraries span multiple architectures")
    target_arch = next(iter(architectures))
    canonical = {item["local_path"]: name for name, item in installed_by_name.items()}
    with tempfile.TemporaryDirectory(prefix=".release-libraries-", dir=frameworks.parent) as temporary:
        pending = list(names)
        staging = Path(temporary)
        while pending:
            name = pending.pop(0)
            if name in records:
                continue
            installed = installed_by_name[name]
            key = (installed["formula"], installed["keg"])
            if key not in sources:
                source = release_source(registry, installed)
                bottle = None
                if source["resolution"] != "verified-local-homebrew-build":
                    bottle = cached_bottle(registry, source, cache)
                    detail = source["bottle_tag"]
                else:
                    detail = "local source build"
                sources[key] = source, bottle
                print("Verified " + installed["formula"] + " " + installed["keg"] + " " + detail, flush=True)
            source, bottle = sources[key]
            path = staging / name
            if bottle is None:
                shutil.copy2(installed["local_path"], path)
                path.chmod(0o755)
                member = None
            else:
                member = extract_library(bottle, installed, name, path)
            info = macho(path, target_arch)
            record = {**installed, "name": name, "bottle": source, "archive_member": member,
                      "extracted_sha256": digest(path), **info}
            records[name] = record
            for dependency in info["dependencies"]:
                if dependency.startswith(SYSTEM):
                    continue
                dep_name = PurePosixPath(dependency).name
                require(dep_name.endswith(".dylib"), "Unexpected dependency: " + dependency)
                if dep_name not in installed_by_name:
                    dep_origin = origin(dep_name)
                    require(dep_origin["arch"] == target_arch,
                            "Dependency architecture mismatch for " + dep_name)
                    known = canonical.get(dep_origin["local_path"])
                    if known:
                        aliases[dep_name] = known
                    else:
                        installed_by_name[dep_name] = dep_origin
                        canonical[dep_origin["local_path"]] = dep_name
                        pending.append(dep_name)

        for name, record in records.items():
            path = staging / name
            # Signing is performed by the outer release transaction after edits.
            subprocess.run(["/usr/bin/codesign", "--remove-signature", str(path)], check=False, capture_output=True)
            edits = ["/usr/bin/install_name_tool", "-id", "@rpath/" + name]
            for dependency in record["dependencies"]:
                if dependency.startswith(SYSTEM):
                    continue
                target = PurePosixPath(dependency).name
                target = target if target in records else aliases.get(target)
                require(target in records, "Unresolved dependency: " + dependency)
                edits += ["-change", dependency, "@loader_path/" + target]
            for rpath in set(record["rpaths"]):
                edits += ["-delete_rpath", rpath]
            run(*edits, str(path))
            final = macho(path, target_arch)
            require(not final["rpaths"], "Unexpected remaining rpath")
            for dependency in final["dependencies"]:
                require(dependency.startswith(SYSTEM) or (dependency.startswith("@loader_path/") and dependency.removeprefix("@loader_path/") in records), "Non-bundled dependency: " + dependency)
            record.update(final_dependencies=final["dependencies"], final_sha256=digest(path))

        provenance = {"schema_version": 3, "architecture": target_arch,
                      "bottle_tags": sorted({record["bottle"]["bottle_tag"] for record in records.values()
                                             if record["bottle"]["bottle_tag"] is not None}),
                      "source_resolutions": sorted({record["bottle"]["resolution"] for record in records.values()}),
                      "maximum_macos": "15.0",
                      "libraries": [records[name] for name in sorted(records)]}
        (staging / "release-libraries.json").write_text(json.dumps(provenance, indent=2) + "\n")
        # All verification precedes mutation of the caller's already-staged bundle.
        for name in sorted(records):
            os.replace(staging / name, frameworks / name)
        os.replace(staging / "release-libraries.json", frameworks / "release-libraries.json")
    print("Staged " + str(len(records)) + " verified macOS 15 libraries in " + str(frameworks))
    return provenance


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frameworks", required=True, type=Path)
    parser.add_argument("--cache", required=True, type=Path)
    parser.add_argument("--library", action="append", help="Dylib basename (repeat to populate an empty directory)")
    args = parser.parse_args()
    try:
        stage(args.frameworks.absolute(), args.cache.absolute(), args.library)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError, tarfile.TarError) as error:
        print("Release library staging failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
