#!/usr/bin/env python3
"""Exercise final archive validation without signing keys or personal data."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("archives", Path(__file__).with_name("verify-release-archives.py"))
archives = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archives)


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="keepclose-archives-")
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.app = self.folder / "KeepClose-macOS.zip"
        self.cli = self.folder / "keepclose-cli-macOS.zip"
        with zipfile.ZipFile(self.app, "w") as archive:
            info = {"CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "4", "CFBundleExecutable": "SocialManager"}
            archive.writestr("KeepClose.app/Contents/Info.plist", plistlib.dumps(info))
            archive.writestr("KeepClose.app/Contents/MacOS/SocialManager", b"fictional executable")
        with zipfile.ZipFile(self.cli, "w") as archive:
            archive.writestr("keepclose", b"fictional CLI")

    def test_valid_distinct_archives(self):
        archives.verify(self.folder, "0.2.0", "4")

    def test_cli_overwriting_app_is_rejected(self):
        self.app.write_bytes(self.cli.read_bytes())
        with self.assertRaises(ValueError):
            archives.verify(self.folder, "0.2.0", "4")

    def test_same_file_is_rejected(self):
        self.cli.unlink()
        self.cli.symlink_to(self.app.name)
        with self.assertRaises(ValueError):
            archives.verify(self.folder, "0.2.0", "4")

    def test_wrong_version_is_rejected(self):
        with self.assertRaises(ValueError):
            archives.verify(self.folder, "0.3.0", "4")

    def test_missing_cli_is_rejected(self):
        with zipfile.ZipFile(self.cli, "w") as archive:
            archive.writestr("other", b"wrong contents")
        with self.assertRaises(KeyError):
            archives.verify(self.folder, "0.2.0", "4")


if __name__ == "__main__":
    unittest.main()
