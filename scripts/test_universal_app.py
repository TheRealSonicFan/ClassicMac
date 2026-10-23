#!/usr/bin/env python3
"""Tests for scripts/universal-app.py with tiny cross-compiled Mach-O fixtures.

clang builds both arm64 and x86_64 binaries from either kind of Mac, so these
run on Apple Silicon and Intel alike. No signing, network or app build needed.
"""
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("universal_app", Path(__file__).with_name("universal-app.py"))
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

CLANG = shutil.which("clang")


def quiet(*_):
    pass


@unittest.skipUnless(CLANG, "clang is required")
class UniversalAppTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())
        (self.folder / "main.c").write_text("int demo(void); int main(void) { return demo(); }\n")
        (self.folder / "lib.c").write_text("int demo(void) { return 0; }\n")
        (self.folder / "plain.c").write_text("int main(void) { return 0; }\n")

    def tearDown(self):
        shutil.rmtree(self.folder)

    def cc(self, arch, *args):
        subprocess.run([CLANG, "-arch", arch, "-mmacosx-version-min=15.0", *args], check=True,
                       cwd=self.folder, capture_output=True)

    def app(self, arch, library, provenance, resource=b"same"):
        """A ClassicMac-shaped bundle: main app, one helper linked to a bundled dylib."""
        app = self.folder / arch / "ClassicMac.app"
        contents = app / "Contents"
        helper = contents / "Helpers/Power Mac G4.app/Contents"
        for directory in (contents / "MacOS", contents / "Resources", helper / "MacOS",
                          helper / "Frameworks", helper / "Resources"):
            directory.mkdir(parents=True)
        info = {"CFBundleIdentifier": "com.classicmac.emulator", "CFBundleShortVersionString": "4.4.0",
                "CFBundleVersion": "4.4.0", "CFBundleExecutable": "ClassicMac", "LSMinimumSystemVersion": "15.0"}
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        (helper / "Info.plist").write_bytes(plistlib.dumps({**info, "CFBundleExecutable": "qemu-system-ppc"}))
        self.cc(arch, "plain.c", "-o", str(contents / "MacOS/ClassicMac"))
        self.cc(arch, "-dynamiclib", "lib.c", "-install_name", "@rpath/" + library,
                "-o", str(helper / "Frameworks" / library))
        self.cc(arch, "main.c", str(helper / "Frameworks" / library),
                "-Wl,-rpath,@executable_path/../Frameworks", "-o", str(helper / "MacOS/qemu-system-ppc"))
        (helper / "Resources/release-libraries.json").write_text(json.dumps(provenance))
        (contents / "Resources/data.bin").write_bytes(resource)
        (contents / "Resources/link").symlink_to("data.bin")
        return app

    def test_merge_joins_slices_keeps_arch_only_libraries_and_combines_provenance(self):
        arm = self.app("arm64", "libdemo.1.dylib", {"architecture": "arm64"})
        x86 = self.app("x86_64", "libdemo.2.dylib", {"architecture": "x86_64"})
        out = self.folder / "universal/ClassicMac.app"
        notes = tool.merge(arm, x86, out, log=quiet)
        self.assertEqual(tool.archs(out / "Contents/MacOS/ClassicMac"), ["arm64", "x86_64"])
        helper = out / "Contents/Helpers/Power Mac G4.app/Contents"
        self.assertEqual(tool.archs(helper / "MacOS/qemu-system-ppc"), ["arm64", "x86_64"])
        self.assertEqual(tool.archs(helper / "Frameworks/libdemo.1.dylib"), ["arm64"])
        self.assertEqual(tool.archs(helper / "Frameworks/libdemo.2.dylib"), ["x86_64"])
        self.assertEqual(len([n for n in notes if "-only library" in n]), 2)
        combined = json.loads((helper / "Resources/release-libraries.json").read_text())
        self.assertEqual(combined["architectures"]["x86_64"], {"architecture": "x86_64"})
        self.assertEqual((out / "Contents/Resources/link").readlink(), Path("data.bin"))
        self.assertEqual(tool.verify(out, "arm64 x86_64", log=quiet), ["arm64", "x86_64"])

    def test_thin_app_verifies_against_its_own_architecture(self):
        arm = self.app("arm64", "libdemo.dylib", {})
        self.assertEqual(tool.verify(arm, log=quiet), ["arm64"])
        with self.assertRaisesRegex(tool.MergeError, "expected arm64 x86_64"):
            tool.verify(arm, "arm64 x86_64", log=quiet)

    def test_verify_detects_a_dependency_missing_an_architecture(self):
        arm = self.app("arm64", "libdemo.dylib", {})
        x86 = self.app("x86_64", "libdemo.dylib", {})
        out = self.folder / "universal/ClassicMac.app"
        tool.merge(arm, x86, out, log=quiet)
        library = out / "Contents/Helpers/Power Mac G4.app/Contents/Frameworks/libdemo.dylib"
        shutil.copy2(arm / "Contents/Helpers/Power Mac G4.app/Contents/Frameworks/libdemo.dylib", library)
        with self.assertRaisesRegex(tool.MergeError, r"\[x86_64\]: libdemo.dylib lacks x86_64"):
            tool.verify(out, log=quiet)

    def test_differing_resources_fail_unless_allowed(self):
        arm = self.app("arm64", "libdemo.dylib", {}, resource=b"one")
        x86 = self.app("x86_64", "libdemo.dylib", {}, resource=b"two")
        out = self.folder / "universal/ClassicMac.app"
        with self.assertRaisesRegex(tool.MergeError, "data.bin: differs"):
            tool.merge(arm, x86, out, log=quiet)
        self.assertFalse(out.exists(), "a failed merge leaves no partial app")
        tool.merge(arm, x86, out, allow_resource_diff=True, log=quiet)
        self.assertEqual((out / "Contents/Resources/data.bin").read_bytes(), b"one")

    def test_inputs_must_be_thin_apps_of_their_role_and_same_version(self):
        arm = self.app("arm64", "libdemo.dylib", {})
        x86 = self.app("x86_64", "libdemo.dylib", {})
        with self.assertRaisesRegex(tool.MergeError, "expected a thin arm64 app"):
            tool.merge(x86, arm, self.folder / "out.app", log=quiet)
        plist = x86 / "Contents/Info.plist"
        plist.write_bytes(plistlib.dumps({**plistlib.loads(plist.read_bytes()), "CFBundleVersion": "4.4.1"}))
        with self.assertRaisesRegex(tool.MergeError, "identity/version differs"):
            tool.merge(arm, x86, self.folder / "out.app", log=quiet)

    def test_equivalent_plists_with_different_serialization_merge(self):
        arm = self.app("arm64", "libdemo.dylib", {})
        x86 = self.app("x86_64", "libdemo.dylib", {})
        plist = x86 / "Contents/Info.plist"
        plist.write_bytes(plistlib.dumps(plistlib.loads(plist.read_bytes()), sort_keys=False, fmt=plistlib.FMT_BINARY))
        tool.merge(arm, x86, self.folder / "out.app", log=quiet)

    def test_code_outside_frameworks_must_exist_in_both_apps(self):
        arm = self.app("arm64", "libdemo.dylib", {})
        x86 = self.app("x86_64", "libdemo.dylib", {})
        (x86 / "Contents/MacOS/qemu-img").write_bytes((x86 / "Contents/MacOS/ClassicMac").read_bytes())
        with self.assertRaisesRegex(tool.MergeError, "only in the x86_64 app: Contents/MacOS/qemu-img"):
            tool.merge(arm, x86, self.folder / "out.app", log=quiet)


if __name__ == "__main__":
    unittest.main()
