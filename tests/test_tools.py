from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.audit_repository import audit
from tools.prepare_assets import find_input, validate_mod


class PrepareAssetsTests(unittest.TestCase):
    def test_find_input_is_case_insensitive(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            expected = root / "presenta.trk"
            expected.write_bytes(b"test")
            self.assertEqual(find_input(root, "PRESENTA.TRK"), expected)

    def test_find_input_rejects_missing_file(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            with self.assertRaises(FileNotFoundError):
                find_input(Path(name), "PRESENTA.TRK")

    def test_validate_mod_rejects_non_module(self) -> None:
        with self.assertRaises(ValueError):
            validate_mod(b"not a module", "bad.trk")


class RepositoryAuditTests(unittest.TestCase):
    def test_audit_rejects_original_asset_extension(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "PRESENTA.TRK").write_bytes(b"not real game data")
            self.assertTrue(audit(root))

    def test_audit_allows_redistributable_binaries(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "dist").mkdir()
            (root / "dist" / "PRE2GUS.COM").write_bytes(b"launcher")
            (root / "dist" / "INSTALL.COM").write_bytes(b"installer")
            self.assertEqual(audit(root), [])

    def test_audit_rejects_unapproved_com_binary(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "GAME.COM").write_bytes(b"not redistributable")
            self.assertTrue(audit(root))


if __name__ == "__main__":
    unittest.main()
