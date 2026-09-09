"""Task 4.0k / ADR-023: complete research artifact integrity, never approval."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "verify_generation_artifact.py"
SPEC = importlib.util.spec_from_file_location("verify_generation_artifact", SCRIPT)
VERIFIER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFIER)


class GenerationArtifactIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "artifact"
        self.root.mkdir()
        self.manifest_path = self.base / "manifest.json"
        self.files = {"weights/part.bin": b"research weights", "tokenizer.json": b"{}"}
        for name, content in self.files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        self.manifest = {
            "schemaVersion": 1,
            "files": [self.entry(name, content) for name, content in self.files.items()],
        }

    @staticmethod
    def entry(path, content):
        return {
            "path": path,
            "sha256": hashlib.sha256(content).hexdigest(),
            "sizeBytes": len(content),
        }

    def write_manifest(self):
        self.manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")

    def verify(self):
        self.write_manifest()
        return VERIFIER.verify_artifact(self.root, self.manifest_path)

    def assert_rejected(self):
        with self.assertRaises(VERIFIER.IntegrityError):
            self.verify()

    def test_AC1_complete_nested_tree_verifies_without_granting_approval(self):
        result = self.verify()
        self.assertTrue(result["passed"])
        self.assertEqual(result["scope"], "file-integrity-only")
        self.assertIs(result["approvalGranted"], False)
        self.assertEqual(result["verifiedFiles"], 2)
        self.assertEqual(result["totalBytes"], sum(map(len, self.files.values())))

    def test_AC1_zero_byte_file_is_verified(self):
        (self.root / "NOTICE").write_bytes(b"")
        self.manifest["files"].append(self.entry("NOTICE", b""))
        self.assertEqual(self.verify()["verifiedFiles"], 3)

    def test_AC1_unvalidated_metadata_never_grants_approval(self):
        self.manifest["approvalGranted"] = True
        self.manifest["sourceRevision"] = "not-verified-by-this-tool"
        self.assertIs(self.verify()["approvalGranted"], False)

    def test_AC1_new_file_added_during_hashing_is_rejected(self):
        original_hash = VERIFIER._hash_file

        def hash_then_add(*arguments):
            result = original_hash(*arguments)
            (self.root / "late-extra").write_bytes(b"new unlisted runtime file")
            return result

        with mock.patch.object(VERIFIER, "_hash_file", side_effect=hash_then_add):
            self.assert_rejected()

    def test_AC1_file_changed_after_hashing_is_rejected(self):
        original_hash = VERIFIER._hash_file

        def hash_then_change(descriptor, name, metadata):
            result = original_hash(descriptor, name, metadata)
            (self.root / name).write_bytes(b"replaced after hash")
            return result

        with mock.patch.object(VERIFIER, "_hash_file", side_effect=hash_then_change):
            self.assert_rejected()

    def test_AC1_missing_file_rejects_incomplete_tree(self):
        (self.root / "tokenizer.json").unlink()
        self.assert_rejected()

    def test_AC1_unlisted_file_rejects_partial_manifest(self):
        (self.root / ".extra-config").write_bytes(b"hidden files also count")
        self.assert_rejected()

    def test_AC1_same_size_corruption_fails_hash_check(self):
        (self.root / "tokenizer.json").write_bytes(b"[]")
        self.assert_rejected()

    def test_AC1_wrong_declared_size_fails(self):
        self.manifest["files"][0]["sizeBytes"] += 1
        self.assert_rejected()

    def test_AC1_noncanonical_and_escaping_paths_fail(self):
        for path in ("", ".", "..", "../escape", "/absolute", "a/../b", "a/./b",
                     "a//b", "a/", "./a", "a\\b", "C:/absolute", "C:relative",
                     "a\x00b", "a\nb"):
            with self.subTest(path=path):
                self.manifest["files"][0]["path"] = path
                self.assert_rejected()

    def test_AC1_duplicate_paths_fail(self):
        self.manifest["files"].append(dict(self.manifest["files"][0]))
        self.assert_rejected()

    def test_AC1_symlink_file_cannot_substitute_verified_bytes(self):
        target = self.base / "outside-tokenizer.json"
        target.write_bytes(b"{}")
        path = self.root / "tokenizer.json"
        path.unlink()
        path.symlink_to(target)
        self.assert_rejected()

    def test_AC1_symlink_directory_is_rejected_even_if_unlisted(self):
        (self.root / "external-directory").symlink_to(self.base, target_is_directory=True)
        self.assert_rejected()

    def test_AC1_dangling_symlink_is_rejected(self):
        (self.root / "dangling").symlink_to(self.base / "missing")
        self.assert_rejected()

    def test_AC1_symlink_root_is_rejected(self):
        linked_root = self.base / "linked-root"
        linked_root.symlink_to(self.root, target_is_directory=True)
        self.root = linked_root
        self.assert_rejected()

    def test_AC1_manifest_must_stay_outside_artifact_root(self):
        self.manifest_path = self.root / "manifest.json"
        self.assert_rejected()

    def test_AC1_symlink_manifest_is_rejected(self):
        self.write_manifest()
        linked_manifest = self.base / "linked-manifest.json"
        linked_manifest.symlink_to(self.manifest_path)
        with self.assertRaises(VERIFIER.IntegrityError):
            VERIFIER.verify_artifact(self.root, linked_manifest)

    def test_AC1_manifest_hardlink_inside_root_is_rejected(self):
        self.write_manifest()
        linked = self.root / "embedded-manifest.json"
        os.link(self.manifest_path, linked)
        with self.assertRaises(VERIFIER.IntegrityError):
            VERIFIER.verify_artifact(self.root, self.manifest_path)

    def test_AC1_special_file_is_rejected_without_opening_it(self):
        os.mkfifo(self.root / "pipe")
        self.assert_rejected()

    def test_AC1_empty_manifest_cannot_claim_artifact_verification(self):
        self.manifest["files"] = []
        self.assert_rejected()

    def test_AC1_invalid_manifest_schema_and_field_types_fail(self):
        invalid = [None, [], {}, {"schemaVersion": 2, "files": []},
                   {"schemaVersion": True, "files": self.manifest["files"]},
                   {"schemaVersion": 1, "files": {}},
                   {"schemaVersion": 1, "files": [None]}]
        for value in invalid:
            with self.subTest(value=value):
                self.manifest = value
                self.assert_rejected()

    def test_AC1_invalid_file_fields_fail(self):
        for key, value in (("sha256", "a" * 63), ("sha256", "g" * 64),
                           ("sha256", "A" * 64), ("sha256", None),
                           ("sizeBytes", True), ("sizeBytes", -1),
                           ("sizeBytes", 2.0), ("path", 1)):
            with self.subTest(key=key, value=value):
                original = self.manifest["files"][0][key]
                self.manifest["files"][0][key] = value
                self.assert_rejected()
                self.manifest["files"][0][key] = original

    def test_AC1_missing_required_file_fields_fail(self):
        for key in ("path", "sha256", "sizeBytes"):
            with self.subTest(key=key):
                original = self.manifest["files"][0].pop(key)
                self.assert_rejected()
                self.manifest["files"][0][key] = original

    def test_AC1_duplicate_json_keys_fail(self):
        self.manifest_path.write_text('{"schemaVersion":2,"schemaVersion":1,"files":[]}',
                                      encoding="utf-8")
        with self.assertRaises(VERIFIER.IntegrityError):
            VERIFIER.verify_artifact(self.root, self.manifest_path)

    def test_AC1_malformed_json_and_missing_manifest_fail(self):
        for content in (b"{", b"\xff"):
            with self.subTest(content=content):
                self.manifest_path.write_bytes(content)
                with self.assertRaises(VERIFIER.IntegrityError):
                    VERIFIER.verify_artifact(self.root, self.manifest_path)
        self.manifest_path.unlink()
        with self.assertRaises(VERIFIER.IntegrityError):
            VERIFIER.verify_artifact(self.root, self.manifest_path)

    def test_AC1_missing_or_regular_file_root_fails(self):
        for root in (self.base / "missing", self.root / "tokenizer.json"):
            with self.subTest(root=root):
                self.write_manifest()
                with self.assertRaises(VERIFIER.IntegrityError):
                    VERIFIER.verify_artifact(root, self.manifest_path)

    def test_AC1_cli_exit_status_and_machine_readable_scope(self):
        self.write_manifest()
        command = [sys.executable, str(SCRIPT), "--root", str(self.root),
                   "--manifest", str(self.manifest_path)]
        success = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(success.returncode, 0, success.stderr)
        self.assertIs(json.loads(success.stdout)["approvalGranted"], False)
        (self.root / "extra.bin").write_bytes(b"extra")
        failure = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(failure.returncode, 1, failure.stderr)
        result = json.loads(failure.stdout)
        self.assertFalse(result["passed"])
        self.assertIs(result["approvalGranted"], False)
        self.assertTrue(result["errors"])


if __name__ == "__main__":
    unittest.main()
