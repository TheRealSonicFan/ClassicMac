#!/usr/bin/env python3
"""Failure-boundary tests for release library staging; no network or Homebrew writes."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_libraries", Path(__file__).with_name("bundle-release-libraries.py"))
lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lib)


class ReleaseLibraryTests(unittest.TestCase):
    def setUp(self):
        # The original tests describe the arm64 release; pin it so they pass on
        # either host architecture.
        lib.configure("arm64")
        self.addCleanup(lib.configure, lib.host_arch() if lib.host_arch() in lib.PLATFORMS else "arm64")

    def archive(self, target):
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode="w") as archive:
            regular = tarfile.TarInfo("demo/1.0/lib/libdemo.1.dylib")
            regular.size = 5
            archive.addfile(regular, io.BytesIO(b"dylib"))
            alias = tarfile.TarInfo("demo/1.0/lib/libdemo.dylib")
            alias.type = tarfile.SYMTYPE
            alias.linkname = target
            archive.addfile(alias)
        stream.seek(0)
        return tarfile.open(fileobj=stream, mode="r")

    def test_resolves_alias_to_only_regular_library(self):
        with self.archive("libdemo.1.dylib") as archive:
            member = lib.regular_member(archive, "demo/1.0/lib/libdemo.dylib", "demo/1.0")
            self.assertEqual(archive.extractfile(member).read(), b"dylib")

    def test_rejects_escape_absolute_and_cyclic_aliases(self):
        for target in ("../../../outside", "/tmp/outside", "libdemo.dylib"):
            with self.subTest(target=target), self.archive(target) as archive:
                with self.assertRaises(ValueError):
                    lib.regular_member(archive, "demo/1.0/lib/libdemo.dylib", "demo/1.0")

    def test_corrupt_cache_fails_without_network_or_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            checksum = hashlib.sha256(b"expected").hexdigest()
            path = Path(folder) / (checksum + ".tar.gz")
            path.write_bytes(b"corrupt")
            with self.assertRaisesRegex(ValueError, "Cached bottle SHA256 mismatch"):
                lib.cached_bottle(None, {"sha256": checksum}, Path(folder))
            self.assertEqual(path.read_bytes(), b"corrupt")

    def test_bad_download_is_never_cached(self):
        class Registry:
            def open(self, url):
                return io.BytesIO(b"corrupt")
        with tempfile.TemporaryDirectory() as folder:
            checksum = hashlib.sha256(b"expected").hexdigest()
            with self.assertRaisesRegex(ValueError, "Downloaded bottle SHA256 mismatch"):
                lib.cached_bottle(Registry(), {"sha256": checksum, "url": "unused"}, Path(folder))
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_receipt_version_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(lib, "PREFIX", Path(folder)):
            prefix = Path(folder)
            keg = prefix / "Cellar/demo/1.0"
            (keg / "lib").mkdir(parents=True)
            (keg / "lib/libdemo.dylib").write_bytes(b"dylib")
            (prefix / "lib").mkdir()
            (prefix / "lib/libdemo.dylib").symlink_to(keg / "lib/libdemo.dylib")
            (keg / "INSTALL_RECEIPT.json").write_text(json.dumps({"arch": "arm64", "source": {"tap": "homebrew/core", "spec": "stable", "versions": {"stable": "2.0"}}}))
            with self.assertRaisesRegex(ValueError, "Receipt/version mismatch"):
                lib.origin("libdemo.dylib")

    def test_historical_registry_cannot_upgrade_version(self):
        class Registry:
            def document(self, url, expected=None):
                if "formulae.brew.sh" in url:
                    return {"full_name": "demo", "tap": "homebrew/core", "versions": {"stable": "2.0"}, "revision": 0}, "0" * 64
                return {"annotations": {"com.github.package.type": "homebrew_bottle", "org.opencontainers.image.title": "demo", "org.opencontainers.image.version": "2.0", "org.opencontainers.image.ref.name": "2.0"}}, "0" * 64
        with self.assertRaisesRegex(ValueError, "formula/version/revision mismatch"):
            lib.bottle_source(Registry(), {"formula": "demo", "keg": "1.0", "version": "1.0", "revision": 0})

    def test_newer_macos_binary_is_rejected(self):
        def output(*args):
            if args[0].endswith("lipo"):
                return "arm64\n"
            return "Load command 0\n cmd LC_BUILD_VERSION\n platform MACOS\n minos 26.0\n"
        with patch.object(lib, "run", side_effect=output), self.assertRaisesRegex(ValueError, "newer than macOS 15"):
            lib.macho(Path("unused"))

    def test_stage_verification_failure_keeps_original_files(self):
        with tempfile.TemporaryDirectory() as folder:
            frameworks = Path(folder) / "Frameworks"
            frameworks.mkdir()
            original = frameworks / "libdemo.dylib"
            original.write_bytes(b"original")
            installed = {"formula": "demo", "keg": "1.0", "local_path": "/brew/libdemo.dylib"}
            with patch.object(lib, "origin", return_value=installed), patch.object(lib, "bottle_source", side_effect=ValueError("no exact bottle")):
                with self.assertRaisesRegex(ValueError, "no exact bottle"):
                    lib.stage(frameworks, Path(folder) / "cache", None)
            self.assertEqual(original.read_bytes(), b"original")
            self.assertEqual([p.name for p in Path(folder).iterdir()], ["Frameworks"])


class ArchitectureTests(unittest.TestCase):
    """Bottle selection for each Mach-O architecture; no network access."""

    def tearDown(self):
        lib.configure(lib.host_arch() if lib.host_arch() in lib.PLATFORMS else "arm64")

    @staticmethod
    def api_registry(files):
        class Registry:
            def document(self, url, expected=None):
                return {"full_name": "demo", "tap": "homebrew/core", "versions": {"stable": "1.0"},
                        "revision": 0, "tap_git_head": "a" * 40, "ruby_source_path": "Formula/d/demo.rb",
                        "bottle": {"stable": {"rebuild": 0, "files": files}}}, "0" * 64
        return Registry()

    @staticmethod
    def installed():
        return {"formula": "demo", "keg": "1.0", "version": "1.0", "revision": 0, "receipt_tap_git_head": None}

    def bottle(self, name):
        return {"url": "https://ghcr.io/v2/homebrew/core/demo/blobs/sha256:" + name * 64, "sha256": name * 64}

    def test_platform_table(self):
        lib.configure("arm64")
        self.assertEqual((lib.TAGS, lib.REGISTRY_ARCH, lib.PREFIX), (("arm64_sequoia",), "arm64", Path("/opt/homebrew")))
        lib.configure("x86_64")
        self.assertEqual(lib.TAG, "sequoia")
        self.assertEqual((lib.REGISTRY_ARCH, lib.PREFIX), ("amd64", Path("/usr/local")))
        lib.configure("x86_64", "/opt/intel-brew")
        self.assertEqual(lib.PREFIX, Path("/opt/intel-brew"))
        with self.assertRaisesRegex(ValueError, "Unsupported architecture"):
            lib.configure("ppc")

    def test_arm64_uses_only_arm64_sequoia(self):
        lib.configure("arm64")
        files = {"arm64_sonoma": self.bottle("b"), "sequoia": self.bottle("c")}
        with self.assertRaises(lib.NoBottle):
            lib.bottle_source(self.api_registry(files), self.installed())
        files["arm64_sequoia"] = self.bottle("a")
        self.assertEqual(lib.bottle_source(self.api_registry(files), self.installed())["tag"], "arm64_sequoia")

    def test_x86_64_prefers_newest_macos15_compatible_intel_bottle(self):
        lib.configure("x86_64")
        files = {"arm64_sequoia": self.bottle("a"), "ventura": self.bottle("c"), "sonoma": self.bottle("b"),
                 "tahoe": self.bottle("d")}
        source = lib.bottle_source(self.api_registry(files), self.installed())
        self.assertEqual((source["tag"], source["sha256"]), ("sonoma", "b" * 64))

    def test_x86_64_historical_registry_requires_amd64(self):
        lib.configure("x86_64")

        def registry(architecture):
            class Registry:
                def document(self, url, expected=None):
                    if "formulae.brew.sh" in url:
                        return {"full_name": "demo", "tap": "homebrew/core", "versions": {"stable": "2.0"}, "revision": 0}, "0" * 64
                    return {"annotations": {"com.github.package.type": "homebrew_bottle", "org.opencontainers.image.title": "demo",
                                            "org.opencontainers.image.version": "1.0", "org.opencontainers.image.ref.name": "1.0",
                                            "org.opencontainers.image.revision": "a" * 40,
                                            "org.opencontainers.image.source": "https://github.com/homebrew/homebrew-core/blob/" + "a" * 40 + "/Formula/d/demo.rb"},
                            "manifests": [{"annotations": {"org.opencontainers.image.ref.name": "1.0.sonoma"},
                                           "platform": {"os": "darwin", "architecture": architecture}}]}, "0" * 64
            return Registry()

        with self.assertRaisesRegex(ValueError, "Wrong bottle platform"):
            lib.bottle_source(registry("arm64"), self.installed())

    def test_missing_intel_bottle_raises_no_bottle(self):
        lib.configure("x86_64")
        with self.assertRaises(lib.NoBottle):
            lib.bottle_source(self.api_registry({"arm64_sequoia": self.bottle("a")}), self.installed())

    def test_thin_architecture_is_enforced(self):
        lib.configure("x86_64")

        def output(*args):
            if args[0].endswith("lipo"):
                return "arm64\n"
            return "Load command 0\n cmd LC_BUILD_VERSION\n platform MACOS\n minos 15.0\n"
        with patch.object(lib, "run", side_effect=output), self.assertRaisesRegex(ValueError, "Expected thin x86_64 dylib"):
            lib.macho(Path("unused"))

    def test_receipt_architecture_must_match(self):
        with tempfile.TemporaryDirectory() as folder:
            lib.configure("x86_64", folder)
            prefix = Path(folder)
            keg = prefix / "Cellar/demo/1.0"
            (keg / "lib").mkdir(parents=True)
            (keg / "lib/libdemo.dylib").write_bytes(b"dylib")
            (prefix / "lib").mkdir()
            (prefix / "lib/libdemo.dylib").symlink_to(keg / "lib/libdemo.dylib")
            (keg / "INSTALL_RECEIPT.json").write_text(json.dumps({"arch": "arm64", "source": {"tap": "homebrew/core", "spec": "stable", "versions": {"stable": "1.0"}}}))
            with self.assertRaisesRegex(ValueError, "Expected official stable x86_64 receipt"):
                lib.origin("libdemo.dylib")

    def test_no_bottle_uses_installed_keg_only_when_allowed(self):
        with tempfile.TemporaryDirectory() as folder:
            lib.configure("x86_64", Path(folder) / "brew")
            keg = Path(folder) / "brew/Cellar/demo/1.0"
            (keg / "lib").mkdir(parents=True)
            (keg / "lib/libdemo.1.dylib").write_bytes(b"installed")
            (keg / "INSTALL_RECEIPT.json").write_text(json.dumps({"poured_from_bottle": False}))
            frameworks = Path(folder) / "Frameworks"
            frameworks.mkdir()
            (frameworks / "libdemo.1.dylib").write_bytes(b"dylibbundler")
            installed = {"formula": "demo", "keg": "1.0", "version": "1.0", "revision": 0,
                         "local_path": str((keg / "lib/libdemo.1.dylib").resolve())}
            info = {"minimum_macos": ["15.0"], "dependencies": ["/usr/lib/libSystem.B.dylib"], "rpaths": []}
            missing = lib.NoBottle("No macOS 15-compatible x86_64 bottle for demo 1.0")
            with patch.object(lib, "origin", return_value=installed), \
                 patch.object(lib, "bottle_source", side_effect=missing), \
                 patch.object(lib, "macho", return_value=info), \
                 patch.object(lib, "run", return_value=""), \
                 patch.object(lib.subprocess, "run"):
                with self.assertRaises(lib.NoBottle):
                    lib.stage(frameworks, Path(folder) / "cache", None, allow_local=False)
                self.assertEqual((frameworks / "libdemo.1.dylib").read_bytes(), b"dylibbundler")
                provenance = lib.stage(frameworks, Path(folder) / "cache", None)
            record = provenance["libraries"][0]
            self.assertEqual(provenance["architecture"], "x86_64")
            self.assertEqual(record["bottle"]["resolution"], "verified-local-keg")
            self.assertFalse(record["bottle"]["poured_from_bottle"])
            self.assertEqual(record["archive_member"], "demo/1.0/lib/libdemo.1.dylib")
            self.assertEqual((frameworks / "libdemo.1.dylib").read_bytes(), b"installed")
            self.assertFalse((Path(folder) / "cache").exists())


if __name__ == "__main__":
    unittest.main()
