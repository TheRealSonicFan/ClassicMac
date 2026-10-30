#!/usr/bin/env python3
"""Tests for merge-universal-app.py with tiny compiled arm64/x86_64 bundles."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("merge_universal", Path(__file__).with_name("merge-universal-app.py"))
merge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merge)

HELPER = "Contents/Helpers/Power Mac G4.app/Contents"


@unittest.skipUnless(shutil.which("clang") and Path("/usr/bin/lipo").exists(), "needs clang and lipo")
class MergeUniversalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tools = tempfile.TemporaryDirectory()
        source = Path(cls.tools.name) / "main.c"
        source.write_text("int main(void) { return 0; }\n")
        cls.binaries = {}
        for arch in merge.ARCHS:
            output = Path(cls.tools.name) / ("main-" + arch)
            subprocess.run(["clang", "-arch", arch, "-mmacosx-version-min=15.0", str(source), "-o", str(output)],
                           check=True, capture_output=True)
            cls.binaries[arch] = output

    @classmethod
    def tearDownClass(cls):
        cls.tools.cleanup()

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.apps = {arch: self.app(arch) for arch in merge.ARCHS}

    def app(self, arch):
        app = self.root / arch / "ClassicMac.app"
        for relative in ("Contents/MacOS/ClassicMac", HELPER + "/MacOS/qemu-system-ppc",
                         HELPER + "/Frameworks/libglib-2.0.0.dylib"):
            path = app / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self.binaries[arch], path)
        (app / "Contents/Info.plist").write_text("<plist/>\n")
        (app / "Contents/Resources").mkdir()
        (app / "Contents/Resources/Quadra800.rom").write_bytes(b"rom")
        (app / "Contents/Resources/AppIcon.icns").write_bytes(arch.encode())
        (app / "Contents/_CodeSignature").mkdir()
        (app / "Contents/_CodeSignature/CodeResources").write_text(arch)
        (app / "Contents/CodeResources").write_text("stapled ticket " + arch)
        (app / HELPER / "Resources").mkdir(parents=True)
        provenance = {"schema_version": 1, "libraries": []}
        if arch == "x86_64":
            provenance["architecture"] = "x86_64"
        (app / HELPER / "Resources/release-libraries.json").write_text(json.dumps(provenance))
        return app

    def run_merge(self):
        output = self.root / "out/ClassicMac.app"
        return merge.merge(self.apps["arm64"], self.apps["x86_64"], output), output

    def test_merges_executables_resources_and_provenance(self):
        report, output = self.run_merge()
        for relative in ("Contents/MacOS/ClassicMac", HELPER + "/MacOS/qemu-system-ppc",
                         HELPER + "/Frameworks/libglib-2.0.0.dylib"):
            self.assertEqual(sorted(merge.archs(output / relative)), ["arm64", "x86_64"])
            self.assertTrue(os.access(output / relative, os.X_OK))
        self.assertEqual((output / "Contents/Resources/Quadra800.rom").read_bytes(), b"rom")
        self.assertEqual((output / "Contents/Resources/AppIcon.icns").read_bytes(), b"arm64")
        self.assertFalse((output / "Contents/_CodeSignature").exists())
        self.assertFalse((output / "Contents/CodeResources").exists())
        document = json.loads((output / HELPER / "Resources/release-libraries.json").read_text())
        self.assertTrue(document["universal"])
        self.assertEqual(sorted(document["architectures"]), ["arm64", "x86_64"])
        self.assertEqual(len(report["lipo"]), 3)

    def test_single_architecture_framework_dylib_is_kept_thin(self):
        shutil.copy2(self.binaries["x86_64"], self.apps["x86_64"] / HELPER / "Frameworks/libintl.8.dylib")
        report, output = self.run_merge()
        self.assertEqual(merge.archs(output / HELPER / "Frameworks/libintl.8.dylib"), ["x86_64"])
        self.assertEqual(report["single"], [HELPER + "/Frameworks/libintl.8.dylib (x86_64)"])

    def test_rejects_other_single_architecture_files(self):
        (self.apps["arm64"] / "Contents/Resources/extra.txt").write_text("only arm64")
        with self.assertRaisesRegex(merge.MergeError, "exists only in the arm64 app"):
            self.run_merge()

    def test_rejects_differing_resources(self):
        (self.apps["x86_64"] / "Contents/Info.plist").write_text("<plist>different</plist>\n")
        with self.assertRaisesRegex(merge.MergeError, "Info.plist differs"):
            self.run_merge()

    def test_rejects_swapped_or_fat_inputs(self):
        with self.assertRaisesRegex(merge.MergeError, "not thin arm64"):
            merge.merge(self.apps["x86_64"], self.apps["arm64"], self.root / "swapped.app")

    def test_rejects_mislabelled_provenance(self):
        (self.apps["x86_64"] / HELPER / "Resources/release-libraries.json").write_text(
            json.dumps({"schema_version": 1, "libraries": [], "architecture": "arm64"}))
        with self.assertRaisesRegex(merge.MergeError, "expected x86_64"):
            self.run_merge()

    def test_refuses_existing_output(self):
        (self.root / "out/ClassicMac.app").mkdir(parents=True)
        with self.assertRaisesRegex(merge.MergeError, "already exists"):
            self.run_merge()


if __name__ == "__main__":
    unittest.main()
