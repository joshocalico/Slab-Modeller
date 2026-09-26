"""Archive contract tests with synthetic bytes; these do not validate native binaries."""

from pathlib import Path
import runpy
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parent.parent
PACKAGER = runpy.run_path(str(ROOT / "scripts/slab-package"))


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.binaries = self.root / "bin"
        self.required = PACKAGER["required_binaries"](ROOT / "project/addons/slab/slab.gdextension")
        for name in self.required:
            path = self.binaries / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"synthetic library: " + name.encode())
        self.output = self.root / "slab.zip"

    def package(self):
        PACKAGER["package"](ROOT, self.binaries, self.output)

    def test_complete_deterministic_installable_archive(self):
        self.package()
        original = self.output.read_bytes()
        self.package()
        self.assertEqual(original, self.output.read_bytes())
        with zipfile.ZipFile(self.output) as archive:
            names = archive.namelist()
            self.assertEqual(names, sorted(names))
            self.assertTrue(all(name.startswith("addons/slab/") for name in names))
            self.assertIn("addons/slab/plugin.cfg", names)
            self.assertIn("addons/slab/slab.gdextension", names)
            self.assertEqual(archive.read("addons/slab/LICENSE"), (ROOT / "LICENSE").read_bytes())
            actual = {name.removeprefix("addons/slab/bin/") for name in names
                      if name.startswith("addons/slab/bin/")}
            self.assertEqual(self.required, actual)
            self.assertFalse(any(".godot/" in name or name.endswith(".o") for name in names))

    def test_missing_library_does_not_replace_existing_output(self):
        self.output.write_bytes(b"previous release")
        (self.binaries / sorted(self.required)[0]).unlink()
        with self.assertRaisesRegex(ValueError, "Missing libraries"):
            self.package()
        self.assertEqual(self.output.read_bytes(), b"previous release")

    def test_empty_library_rejected(self):
        (self.binaries / sorted(self.required)[0]).write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "Empty library"):
            self.package()
        self.assertFalse(self.output.exists())

    def test_build_debris_rejected(self):
        (self.binaries / "slab.obj").write_bytes(b"object")
        with self.assertRaisesRegex(ValueError, "Unexpected artifacts"):
            self.package()
        self.assertFalse(self.output.exists())

    def test_symlink_rejected(self):
        name = sorted(self.required)[0]
        (self.binaries / name).unlink()
        (self.binaries / name).symlink_to(ROOT / "LICENSE")
        with self.assertRaisesRegex(ValueError, "Symlinks"):
            self.package()


if __name__ == "__main__":
    unittest.main()
