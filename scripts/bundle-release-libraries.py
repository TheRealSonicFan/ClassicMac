#!/usr/bin/env python3
"""Stage exact-version official Homebrew dylibs for macOS 15.

Run after dylibbundler and before signing. Only selected regular dylib members
are extracted; Homebrew itself is never changed. The cache is content addressed.
--library supports preparing an empty Frameworks directory for verification.

--arch selects the Mach-O architecture (default: this process's). arm64 uses
arm64_sequoia bottles from /opt/homebrew, exactly as before. x86_64 uses
/usr/local and the Intel sequoia (or older, macOS 15 compatible) bottles.
Homebrew no longer publishes Intel bottles for most current formulae, so
--allow-local-kegs lets a library without an official bottle come from the
installed keg instead, under the same thin-architecture, macOS 15 minimum,
dependency and provenance checks.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import posixpath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.parse
import urllib.request

# Per-architecture Homebrew conventions: bottle tags (most preferred first, all
# macOS 15 compatible; the minimum-version check below still applies), the
# default prefix, the INSTALL_RECEIPT.json "arch" and the OCI platform name.
ARCHITECTURES = {
    "arm64": {"tags": ("arm64_sequoia",), "prefix": "/opt/homebrew",
              "receipt_arch": "arm64", "oci_arch": "arm64"},
    "x86_64": {"tags": ("sequoia", "sonoma", "ventura"), "prefix": "/usr/local",
               "receipt_arch": "x86_64", "oci_arch": "amd64"},
}

# Module state; configure() switches architecture. The defaults are arm64.
ARCH = "arm64"
TAGS = ARCHITECTURES[ARCH]["tags"]
TAG = TAGS[0]
PREFIX = Path(ARCHITECTURES[ARCH]["prefix"])
ALLOW_LOCAL_KEGS = False
SYSTEM = ("/usr/lib/", "/System/Library/")


class NoOfficialBottle(ValueError):
    """Homebrew publishes no bottle of the installed version for this arch."""


def host_arch():
    machine = platform.machine()
    return {"aarch64": "arm64", "amd64": "x86_64"}.get(machine, machine)


def configure(arch, prefix=None, allow_local_kegs=False):
    global ARCH, TAGS, TAG, PREFIX, ALLOW_LOCAL_KEGS
    require(arch in ARCHITECTURES, "Unsupported architecture: " + str(arch))
    ARCH = arch
    TAGS = ARCHITECTURES[arch]["tags"]
    TAG = TAGS[0]
    PREFIX = Path(prefix or ARCHITECTURES[arch]["prefix"])
    ALLOW_LOCAL_KEGS = bool(allow_local_kegs)


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
    original = PREFIX / "lib" / name
    real = original.resolve(strict=True)
    relative = real.relative_to((PREFIX / "Cellar").resolve())
    require(len(relative.parts) >= 4 and relative.parts[2] == "lib", "Library is not in a Homebrew keg: " + str(real))
    formula, keg = relative.parts[:2]
    receipt_path = PREFIX / "Cellar" / formula / keg / "INSTALL_RECEIPT.json"
    receipt = json.loads(receipt_path.read_text())
    source = receipt.get("source", {})
    version = source.get("versions", {}).get("stable")
    receipt_arch = ARCHITECTURES[ARCH]["receipt_arch"]
    require(source.get("tap") == "homebrew/core" and source.get("spec") == "stable" and receipt.get("arch") == receipt_arch, "Expected official stable " + receipt_arch + " receipt for " + formula)
    require(isinstance(version, str), "Missing installed version for " + formula)
    revision = 0
    if keg != version:
        require(keg.startswith(version + "_") and keg[len(version) + 1:].isdigit(), "Receipt/version mismatch for " + formula)
        revision = int(keg[len(version) + 1:])
    return {"formula": formula, "keg": keg, "version": version, "revision": revision,
            "local_path": str(real), "receipt_sha256": digest(receipt_path),
            "receipt_tap_git_head": source.get("tap_git_head")}


def bottle_source(registry, installed):
    formula, keg = installed["formula"], installed["keg"]
    api_url = "https://formulae.brew.sh/api/formula/" + urllib.parse.quote(formula) + ".json"
    api, api_hash = registry.document(api_url)
    require(api.get("full_name") == formula and api.get("tap") == "homebrew/core", "Formula API identity mismatch")
    current = api.get("versions", {}).get("stable") == installed["version"] and api.get("revision") == installed["revision"]
    if current:
        stable = api.get("bottle", {}).get("stable") or {}
        files = stable.get("files", {})
        tag = next((candidate for candidate in TAGS if candidate in files), None)
        if tag is None:
            raise NoOfficialBottle("No official " + "/".join(TAGS) + " bottle for " + formula + " " + installed["keg"])
        bottle = files[tag]
        commit = api.get("tap_git_head")
        require(isinstance(commit, str) and re.fullmatch(r"[a-f0-9]{40}", commit), "Missing pinned formula commit")
        source_url = "https://raw.githubusercontent.com/Homebrew/homebrew-core/" + commit + "/" + api["ruby_source_path"]
        result = {"url": bottle["url"], "sha256": sha(bottle["sha256"]), "formula_source_url": source_url,
                  "formula_commit": commit, "metadata_url": api_url, "metadata_sha256": api_hash,
                  "resolution": "exact-formula-api", "bottle_rebuild": stable.get("rebuild", 0)}
        if tag != TAG:
            result["bottle_tag"] = tag
        return result

    # API-installed receipts can omit tap_git_head. An exact official registry
    # version index carries the historical source commit and platform digest.
    repo = formula.replace("@", "/")
    index_url = "https://ghcr.io/v2/homebrew/core/" + repo + "/manifests/" + keg
    try:
        index, index_hash = registry.document(index_url)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            raise NoOfficialBottle("No official registry entry for " + formula + " " + keg) from error
        raise
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
    for tag in TAGS:
        matches = [m for m in index.get("manifests", []) if m.get("annotations", {}).get("org.opencontainers.image.ref.name") == keg + "." + tag]
        if matches:
            break
    if not matches:
        raise NoOfficialBottle("Missing " + "/".join(TAGS) + " bottle for " + formula + " " + keg)
    require(len(matches) == 1, "Missing or ambiguous Sequoia bottle for " + formula)
    match = matches[0]
    require(match.get("platform", {}).get("os") == "darwin" and match["platform"].get("architecture") == ARCHITECTURES[ARCH]["oci_arch"], "Wrong bottle platform")
    checksum = sha(match["annotations"]["sh.brew.bottle.digest"])
    manifest_hash = sha(match["digest"].removeprefix("sha256:"))
    manifest_url = "https://ghcr.io/v2/homebrew/core/" + repo + "/manifests/sha256:" + manifest_hash
    manifest, _ = registry.document(manifest_url, manifest_hash)
    require(any(layer.get("digest") == "sha256:" + checksum for layer in manifest.get("layers", [])), "Bottle layer digest does not match platform manifest")
    result = {"url": "https://ghcr.io/v2/homebrew/core/" + repo + "/blobs/sha256:" + checksum,
              "sha256": checksum, "formula_source_url": source_url, "formula_commit": commit,
              "metadata_url": "https://ghcr.io/v2/homebrew/core/" + repo + "/manifests/sha256:" + index_hash,
              "metadata_sha256": index_hash, "platform_manifest_url": manifest_url,
              "resolution": "exact-historical-registry", "bottle_rebuild": 0}
    if tag != TAG:
        result["bottle_tag"] = tag
    return result


def local_keg_source(installed):
    """Provenance for a library taken from the installed keg (no bottle)."""
    receipt_path = PREFIX / "Cellar" / installed["formula"] / installed["keg"] / "INSTALL_RECEIPT.json"
    receipt = json.loads(receipt_path.read_text())
    return {"resolution": "local-keg", "url": None, "sha256": None,
            "homebrew_version": receipt.get("homebrew_version"),
            "built_as_bottle": receipt.get("built_as_bottle"),
            "poured_from_bottle": receipt.get("poured_from_bottle"),
            "compiler": receipt.get("compiler"),
            "formula_commit": installed.get("receipt_tap_git_head")}


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


def copy_local_library(installed, destination):
    """Copy the installed keg's regular dylib (local-keg resolution)."""
    source = Path(installed["local_path"])
    keg_lib = (PREFIX / "Cellar" / installed["formula"] / installed["keg"] / "lib").resolve()
    require(source.is_file() and not source.is_symlink(), "Local keg dylib is not a regular file: " + str(source))
    require(source.parent == keg_lib or keg_lib in source.parents, "Local dylib escaped its keg lib directory: " + str(source))
    require(source.name.endswith(".dylib") and source.stat().st_size <= 128 * 1024 * 1024, "Unexpected local keg dylib: " + str(source))
    shutil.copyfile(source, destination)
    destination.chmod(0o755)
    return str(source)


def macho(path):
    require(run("/usr/bin/lipo", "-archs", str(path)).split() == [ARCH], "Expected thin " + ARCH + " dylib: " + str(path))
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
                try:
                    source = bottle_source(registry, installed)
                except NoOfficialBottle as missing:
                    if not ALLOW_LOCAL_KEGS:
                        raise
                    sources[key] = local_keg_source(installed), None
                    print("Using local " + ARCH + " keg " + installed["formula"] + " " + installed["keg"] + " (" + str(missing) + ")", flush=True)
                else:
                    sources[key] = source, cached_bottle(registry, source, cache)
                    print("Verified " + installed["formula"] + " " + installed["keg"] + " " + source.get("bottle_tag", TAG), flush=True)
            source, bottle = sources[key]
            path = staging / name
            if bottle is None:
                member = copy_local_library(installed, path)
            else:
                member = extract_library(bottle, installed, name, path)
            info = macho(path)
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
            final = macho(path)
            require(not final["rpaths"], "Unexpected remaining rpath")
            for dependency in final["dependencies"]:
                require(dependency.startswith(SYSTEM) or (dependency.startswith("@loader_path/") and dependency.removeprefix("@loader_path/") in records), "Non-bundled dependency: " + dependency)
            record.update(final_dependencies=final["dependencies"], final_sha256=digest(path))

        provenance = {"schema_version": 1, "bottle_tag": TAG, "maximum_macos": "15.0",
                      "libraries": [records[name] for name in sorted(records)]}
        if ARCH != "arm64":
            provenance.update(architecture=ARCH, bottle_tags=list(TAGS), local_kegs_allowed=ALLOW_LOCAL_KEGS)
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
    parser.add_argument("--arch", choices=sorted(ARCHITECTURES), default=None,
                        help="Mach-O architecture of the staged libraries (default: this process's)")
    parser.add_argument("--homebrew-prefix", type=Path, default=None,
                        help="Homebrew prefix for --arch (default: /opt/homebrew for arm64, /usr/local for x86_64)")
    parser.add_argument("--allow-local-kegs", action="store_true",
                        help="Use the installed keg when Homebrew has no official bottle for --arch")
    args = parser.parse_args()
    try:
        configure(args.arch or host_arch(), args.homebrew_prefix, args.allow_local_kegs)
        stage(args.frameworks.absolute(), args.cache.absolute(), args.library)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError, tarfile.TarError) as error:
        print("Release library staging failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
