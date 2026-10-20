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
    """Per-architecture Homebrew conventions (arm64 defaults stay unchanged)."""

    def tearDown(self):
        lib.configure("arm64")

    @staticmethod
    def api(files):
        return {"full_name": "demo", "tap": "homebrew/core", "versions": {"stable": "1.0"}, "revision": 0,
                "tap_git_head": "a" * 40, "ruby_source_path": "Formula/d/demo.rb",
                "bottle": {"stable": {"rebuild": 0, "files": files}}}

    def registry(self, files):
        api = self.api(files)

        class Registry:
            def document(self, url, expected=None):
                return api, "0" * 64
        return Registry()

    def bottle(self):
        return {"url": "https://ghcr.io/v2/homebrew/core/demo/blobs/sha256:" + "b" * 64, "sha256": "b" * 64}

    def keg(self, prefix, arch):
        keg = prefix / "Cellar/demo/1.0"
        (keg / "lib").mkdir(parents=True)
        (keg / "lib/libdemo.1.dylib").write_bytes(b"local dylib")
        (prefix / "lib").mkdir()
        (prefix / "lib/libdemo.1.dylib").symlink_to(keg / "lib/libdemo.1.dylib")
        (keg / "INSTALL_RECEIPT.json").write_text(json.dumps({
            "arch": arch, "built_as_bottle": False, "poured_from_bottle": False, "compiler": "clang",
            "source": {"tap": "homebrew/core", "spec": "stable", "versions": {"stable": "1.0"}}}))

    @staticmethod
    def tools(arch, minos="15.0"):
        def output(*args):
            if args[0].endswith("lipo"):
                return arch + "\n"
            if args[0].endswith("install_name_tool"):
                return ""
            if args[1] == "-l":
                return "Load command 0\n cmd LC_BUILD_VERSION\n platform MACOS\n minos " + minos + "\n"
            if args[1] == "-D":
                return args[2] + ":\n@rpath/libdemo.1.dylib\n"
            return args[2] + ":\n\t@rpath/libdemo.1.dylib (compatibility version 1.0.0)\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n"
        return output

    def test_arm64_defaults_are_unchanged(self):
        self.assertEqual((lib.ARCH, lib.TAG, lib.PREFIX, lib.ALLOW_LOCAL_KEGS),
                         ("arm64", "arm64_sequoia", Path("/opt/homebrew"), False))

    def test_x86_64_uses_intel_prefix_tags_and_slices(self):
        lib.configure("x86_64")
        self.assertEqual((lib.TAG, lib.PREFIX), ("sequoia", Path("/usr/local")))
        with patch.object(lib, "run", side_effect=self.tools("arm64")), self.assertRaisesRegex(ValueError, "Expected thin x86_64"):
            lib.macho(Path("unused"))
        with patch.object(lib, "run", side_effect=self.tools("x86_64")):
            self.assertEqual(lib.macho(Path("unused"))["minimum_macos"], ["15.0"])

    def test_unknown_architecture_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Unsupported architecture"):
            lib.configure("ppc")

    def test_receipt_must_match_architecture(self):
        with tempfile.TemporaryDirectory() as folder:
            lib.configure("x86_64", folder)
            self.keg(Path(folder), "arm64")
            with self.assertRaisesRegex(ValueError, "Expected official stable x86_64 receipt"):
                lib.origin("libdemo.1.dylib")

    def test_missing_bottle_tag_is_reported_not_key_error(self):
        installed = {"formula": "demo", "keg": "1.0", "version": "1.0", "revision": 0}
        for arch in ("arm64", "x86_64"):
            with self.subTest(arch=arch):
                lib.configure(arch)
                with self.assertRaises(lib.NoOfficialBottle):
                    lib.bottle_source(self.registry({"arm64_linux": self.bottle()}), installed)

    def test_x86_64_accepts_older_macos_bottle_but_arm64_does_not(self):
        installed = {"formula": "demo", "keg": "1.0", "version": "1.0", "revision": 0}
        lib.configure("x86_64")
        source = lib.bottle_source(self.registry({"sonoma": self.bottle()}), installed)
        self.assertEqual(source["bottle_tag"], "sonoma")
        lib.configure("arm64")
        with self.assertRaises(lib.NoOfficialBottle):
            lib.bottle_source(self.registry({"arm64_sonoma": self.bottle()}), installed)

    def test_local_keg_needs_opt_in_and_is_recorded(self):
        for allowed in (False, True):
            with self.subTest(allowed=allowed), tempfile.TemporaryDirectory() as folder:
                prefix = Path(folder) / "brew"
                prefix.mkdir()
                self.keg(prefix, "x86_64")
                lib.configure("x86_64", prefix, allow_local_kegs=allowed)
                frameworks = Path(folder) / "Frameworks"
                frameworks.mkdir()
                (frameworks / "libdemo.1.dylib").write_bytes(b"dylibbundler copy")
                missing = lib.NoOfficialBottle("no Intel bottle")
                with patch.object(lib, "bottle_source", side_effect=missing), \
                     patch.object(lib, "run", side_effect=self.tools("x86_64")):
                    if not allowed:
                        with self.assertRaisesRegex(ValueError, "no Intel bottle"):
                            lib.stage(frameworks, Path(folder) / "cache", None)
                        self.assertEqual((frameworks / "libdemo.1.dylib").read_bytes(), b"dylibbundler copy")
                        continue
                    provenance = lib.stage(frameworks, Path(folder) / "cache", None)
                self.assertEqual((frameworks / "libdemo.1.dylib").read_bytes(), b"local dylib")
                record = provenance["libraries"][0]
                self.assertEqual(record["bottle"]["resolution"], "local-keg")
                self.assertEqual((provenance["architecture"], provenance["local_kegs_allowed"]), ("x86_64", True))
                self.assertFalse((Path(folder) / "cache").exists())

    def test_local_keg_still_requires_macos_15(self):
        with tempfile.TemporaryDirectory() as folder:
            prefix = Path(folder) / "brew"
            prefix.mkdir()
            self.keg(prefix, "x86_64")
            lib.configure("x86_64", prefix, allow_local_kegs=True)
            frameworks = Path(folder) / "Frameworks"
            frameworks.mkdir()
            (frameworks / "libdemo.1.dylib").write_bytes(b"dylibbundler copy")
            with patch.object(lib, "bottle_source", side_effect=lib.NoOfficialBottle("none")), \
                 patch.object(lib, "run", side_effect=self.tools("x86_64", minos="26.0")):
                with self.assertRaisesRegex(ValueError, "newer than macOS 15"):
                    lib.stage(frameworks, Path(folder) / "cache", None)
            self.assertEqual((frameworks / "libdemo.1.dylib").read_bytes(), b"dylibbundler copy")


if __name__ == "__main__":
    unittest.main()
