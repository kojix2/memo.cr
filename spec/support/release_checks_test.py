import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("release_checks", Path(__file__).parents[2] / "scripts/check-release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseChecksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="memo-release-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "shard.yml").write_text("name: memo\nversion: 0.0.14\n")
        (self.root / "com.github.kojix2.memo.metainfo.xml").write_text(
            '<component><releases><release version="0.0.14"/></releases></component>')
        self.deb = self.root / "memo_0.0.14_amd64.deb"
        self.deb.write_bytes(b"!<arch>\n" + b"debian-binary")
        self.dmg = self.root / "memo_0.0.14_aarch64.dmg"
        self.dmg.write_bytes(b"koly" + bytes(508))
        header = bytearray(132)
        header[:2] = b"MZ"
        struct.pack_into("<I", header, 60, 128)
        header[128:] = b"PE\0\0"
        for suffix in ["ucrt64", "ucrt64_setup"]:
            (self.root / f"memo_0.0.14_{suffix}.exe").write_bytes(header)

    def test_matching_versions_and_all_packages(self):
        self.assertEqual(release.check_version(self.root, "v0.0.14"), "0.0.14")
        release.check_artifacts(self.root, "0.0.14")
        self.assertEqual(len((self.root / "SHA256SUMS").read_text().splitlines()), 4)

    def test_tag_and_metadata_must_match(self):
        with self.assertRaises(ValueError):
            release.check_version(self.root, "v0.0.15")
        (self.root / "com.github.kojix2.memo.metainfo.xml").write_text(
            '<component><releases><release version="0.0.6"/></releases></component>')
        with self.assertRaises(ValueError):
            release.check_version(self.root)

    def test_each_required_platform_is_mandatory(self):
        for package in list(self.root.glob("*.deb")) + list(self.root.glob("*.exe")) + [self.dmg]:
            data = package.read_bytes()
            package.unlink()
            with self.assertRaises(ValueError):
                release.check_artifacts(self.root, "0.0.14")
            self.assertFalse((self.root / "SHA256SUMS").exists())
            package.write_bytes(data)

    def test_empty_or_wrong_format_cannot_be_published(self):
        for data in [b"", b"<html>download failed</html>"]:
            self.deb.write_bytes(data)
            with self.assertRaises(ValueError):
                release.check_artifacts(self.root, "0.0.14")

    def test_unexpected_version_is_rejected(self):
        (self.root / "memo_0.0.13_amd64.deb").write_bytes(b"!<arch>\n")
        with self.assertRaises(ValueError):
            release.check_artifacts(self.root, "0.0.14")


if __name__ == "__main__":
    unittest.main()
