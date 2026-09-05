"""Exercise the release packager and reject incomplete distributable archives."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]


class PackageAddonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="quickroute-package-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.addon = self.root / "QuickRoute"
        shutil.copytree(ROOT / "QuickRoute", self.addon)

    def package(self):
        return subprocess.run(
            ["bash", str(ROOT / "scripts/package_addon.sh")],
            cwd=self.root,
            env={**os.environ, "VERSION": "package-test"},
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            check=False,
        )

    def test_archive_retains_every_addon_file_and_notice(self):
        result = self.package()
        self.assertEqual(result.returncode, 0, result.stdout)
        with zipfile.ZipFile(self.root / "dist/QuickRoute-package-test.zip") as archive:
            self.assertIsNone(archive.testzip())
            for source in self.addon.rglob("*"):
                if source.is_file():
                    self.assertEqual(archive.read(source.relative_to(self.root).as_posix()), source.read_bytes())
            for notice in ("Licenses/QuickRoute-MIT.txt", "Licenses/AllTheThings-MIT.txt",
                           "ThirdParty/Mapzeroth-LICENSE.txt", "ThirdParty/Mapzeroth-NOTICE.md"):
                self.assertTrue(archive.read("QuickRoute/" + notice))

    def test_missing_xml_blocks_packaging(self):
        (self.addon / "Modules/SettingsHeader.xml").unlink()
        result = self.package()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("SettingsHeader.xml", result.stdout)
        self.assertFalse((self.root / "dist/QuickRoute-package-test.zip").exists())

    def test_missing_upstream_license_blocks_packaging(self):
        (self.addon / "ThirdParty/Mapzeroth-LICENSE.txt").unlink()
        result = self.package()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Required license or source notice missing", result.stdout)
        self.assertFalse((self.root / "dist/QuickRoute-package-test.zip").exists())


if __name__ == "__main__":
    unittest.main()
