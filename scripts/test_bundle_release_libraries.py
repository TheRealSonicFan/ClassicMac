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
    """x86_64 bottle selection and the local-keg fallback; no network."""

    COMMIT = "a" * 40

    def tearDown(self):
        lib.configure("arm64")

    def api(self, files):
        return {"full_name": "demo", "tap": "homebrew/core", "versions": {"stable": "1.0"}, "revision": 0,
                "tap_git_head": self.COMMIT, "ruby_source_path": "Formula/d/demo.rb",
                "bottle": {"stable": {"rebuild": 0, "files": files}}}

    def bottle(self, name):
        return {"url": "https://ghcr.io/v2/homebrew/core/demo/blobs/sha256:" + name * 64, "sha256": name * 64}

    def test_default_configuration_is_unchanged_arm64(self):
        self.assertEqual((lib.ARCH, lib.TAG, lib.PREFIX, lib.REGISTRY_ARCH), ("arm64", "arm64_sequoia", Path("/opt/homebrew"), "arm64"))

    def test_configure_selects_intel_conventions_and_rejects_unknown(self):
        lib.configure("x86_64")
        self.assertEqual((lib.TAG, lib.PREFIX, lib.REGISTRY_ARCH), ("sequoia", Path("/usr/local"), "amd64"))
        lib.configure("x86_64", Path("/custom"))
        self.assertEqual(lib.PREFIX, Path("/custom"))
        with self.assertRaises(ValueError):
            lib.configure("ppc")
        with self.assertRaises(ValueError):
            lib.configure("arm64", source="anything")

    def test_api_prefers_newest_macos15_compatible_tag_for_architecture(self):
        files = {"arm64_sequoia": self.bottle("1"), "tahoe": self.bottle("2"), "sonoma": self.bottle("3"), "ventura": self.bottle("4")}
        class Registry:
            def document(inner, url, expected=None):
                return self.api(files), "0" * 64
        installed = {"formula": "demo", "keg": "1.0", "version": "1.0", "revision": 0}
        self.assertEqual(lib.bottle_source(Registry(), installed)["bottle_tag"], "arm64_sequoia")
        lib.configure("x86_64")
        source = lib.bottle_source(Registry(), installed)
        self.assertEqual((source["bottle_tag"], source["sha256"]), ("sonoma", "3" * 64))

    def test_api_without_compatible_bottle_is_no_bottle(self):
        class Registry:
            def document(inner, url, expected=None):
                return self.api({"arm64_sequoia": self.bottle("1"), "tahoe": self.bottle("2")}), "0" * 64
        lib.configure("x86_64")
        with self.assertRaises(lib.NoBottle):
            lib.bottle_source(Registry(), {"formula": "demo", "keg": "1.0", "version": "1.0", "revision": 0})

    def test_historical_registry_matches_intel_platform(self):
        layer = "5" * 64
        manifest = "6" * 64
        def entry(tag, arch, digest):
            return {"annotations": {"org.opencontainers.image.ref.name": "1.0." + tag, "sh.brew.bottle.digest": digest},
                    "platform": {"os": "darwin", "architecture": arch}, "digest": "sha256:" + manifest}
        class Registry:
            def document(inner, url, expected=None):
                if "formulae.brew.sh" in url:
                    return {**self.api({}), "versions": {"stable": "2.0"}}, "0" * 64
                if url.endswith("/manifests/1.0"):
                    return {"annotations": {"com.github.package.type": "homebrew_bottle", "org.opencontainers.image.title": "demo",
                                            "org.opencontainers.image.version": "1.0", "org.opencontainers.image.ref.name": "1.0",
                                            "org.opencontainers.image.revision": self.COMMIT,
                                            "org.opencontainers.image.source": "https://github.com/homebrew/homebrew-core/blob/" + self.COMMIT + "/Formula/d/demo.rb"},
                            "manifests": [entry("arm64_sequoia", "arm64", "7" * 64), entry("ventura", "amd64", layer)]}, "0" * 64
                return {"layers": [{"digest": "sha256:" + layer}]}, manifest
        lib.configure("x86_64")
        installed = {"formula": "demo", "keg": "1.0", "version": "1.0", "revision": 0, "receipt_tap_git_head": None}
        source = lib.bottle_source(Registry(), installed)
        self.assertEqual((source["bottle_tag"], source["sha256"]), ("ventura", layer))

    def keg(self, prefix):
        keg_lib = prefix / "Cellar/demo/1.0/lib"
        keg_lib.mkdir(parents=True)
        (keg_lib / "libdemo.dylib").write_bytes(b"local keg")
        return {"formula": "demo", "keg": "1.0", "version": "1.0", "revision": 0,
                "local_path": str((keg_lib / "libdemo.dylib").resolve()), "receipt_sha256": "8" * 64,
                "receipt_tap_git_head": None, "receipt_poured_from_bottle": False}

    def test_auto_uses_verified_local_keg_when_no_bottle_exists(self):
        with tempfile.TemporaryDirectory() as folder:
            prefix = Path(folder) / "brew"
            frameworks = Path(folder) / "Frameworks"
            frameworks.mkdir()
            (frameworks / "libdemo.dylib").write_bytes(b"dylibbundler copy")
            lib.configure("x86_64", prefix, "auto")
            installed = self.keg(prefix)
            info = {"minimum_macos": ["15.0"], "dependencies": [], "rpaths": []}
            with patch.object(lib, "origin", return_value=installed), \
                 patch.object(lib, "bottle_source", side_effect=lib.NoBottle("none")), \
                 patch.object(lib, "macho", return_value=info), patch.object(lib, "run", return_value=""):
                provenance = lib.stage(frameworks, Path(folder) / "cache", None)
            self.assertEqual((frameworks / "libdemo.dylib").read_bytes(), b"local keg")
            self.assertEqual(provenance["architecture"], "x86_64")
            self.assertEqual(provenance["libraries"][0]["bottle"]["resolution"], "local-keg")
            self.assertFalse((Path(folder) / "cache").exists(), "no bottle download for a local keg")

    def test_bottle_policy_refuses_local_keg(self):
        with tempfile.TemporaryDirectory() as folder:
            prefix = Path(folder) / "brew"
            frameworks = Path(folder) / "Frameworks"
            frameworks.mkdir()
            (frameworks / "libdemo.dylib").write_bytes(b"original")
            lib.configure("x86_64", prefix, "bottle")
            installed = self.keg(prefix)
            with patch.object(lib, "origin", return_value=installed), \
                 patch.object(lib, "bottle_source", side_effect=lib.NoBottle("none")):
                with self.assertRaises(lib.NoBottle):
                    lib.stage(frameworks, Path(folder) / "cache", None)
            self.assertEqual((frameworks / "libdemo.dylib").read_bytes(), b"original")

    def test_local_keg_must_be_inside_its_keg(self):
        with tempfile.TemporaryDirectory() as folder:
            prefix = Path(folder) / "brew"
            lib.configure("x86_64", prefix)
            installed = self.keg(prefix)
            outside = Path(folder) / "libdemo.dylib"
            outside.write_bytes(b"elsewhere")
            with self.assertRaisesRegex(ValueError, "escaped its keg"):
                lib.copy_local_library({**installed, "local_path": str(outside)}, "libdemo.dylib", Path(folder) / "out.dylib")

    def test_wrong_architecture_dylib_is_rejected(self):
        lib.configure("x86_64")
        with patch.object(lib, "run", return_value="arm64\n"), self.assertRaisesRegex(ValueError, "thin x86_64"):
            lib.macho(Path("unused"))


if __name__ == "__main__":
    unittest.main()
