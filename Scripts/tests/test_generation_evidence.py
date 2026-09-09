"""Task 4.0k / ADR-023: model-free source identity and interruption evidence tests."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "generation_evidence_harness", ROOT / "Scripts/evaluate_generation_candidate.py"
)
harness = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(harness)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class FakeProcess:
    """Exercise the parent event loop without importing or loading an ML runtime."""

    def __init__(self, on_start=None):
        self.on_start = on_start
        self.started = False
        self.alive = False
        self.terminated = False

    def start(self):
        self.started = True
        self.alive = True
        if self.on_start:
            self.on_start()

    def is_alive(self):
        return self.alive

    def terminate(self):
        self.terminated = True
        self.alive = False

    def kill(self):
        self.alive = False

    def join(self, timeout=None):
        pass


class FakeSender:
    def close(self):
        pass


class FakeContext:
    def __init__(self, events, before_poll=None, on_start=None):
        self.events = list(events)
        self.received = 0
        self.before_poll = before_poll
        self.process = FakeProcess(on_start)

    def Pipe(self, duplex):
        return self, FakeSender()

    def Process(self, **options):
        return self.process

    def poll(self, timeout):
        if self.before_poll:
            self.before_poll(self.received)
        if self.events and isinstance(self.events[0], BaseException):
            raise self.events.pop(0)
        return bool(self.events)

    def recv(self):
        self.received += 1
        return self.events.pop(0)

    def close(self):
        pass


class GenerationEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.model = self.directory / "source"
        self.model.mkdir()
        for name, content in {
            "config.json": b'{"model_type":"qwen2"}',
            "model.safetensors": b"synthetic test bytes; never loaded as model weights",
            "tokenizer.json": b'{"version":"1.0"}',
            "tokenizer_config.json": b'{"chat_template":"synthetic template"}',
            "generation_config.json": b'{"eos_token_id":1}',
        }.items():
            (self.model / name).write_bytes(content)
        self.manifest = self.directory / "source-manifest.json"
        self.manifest.write_text(json.dumps({
            "schemaVersion": 1, "upstreamRevision": "research-only-fixed-revision",
            "files": [{"path": path.name, "sha256": digest(path), "sizeBytes": path.stat().st_size}
                      for path in sorted(self.model.iterdir())],
        }))
        self.cases = self.directory / "cases.json"
        suite = json.loads((ROOT / "EchoTests/TestData/Generation/4.0k-screen-v1.json").read_text())
        suite["cases"] = suite["cases"][:2]
        self.case_ids = [case["id"] for case in suite["cases"]]
        self.cases.write_text(json.dumps(suite))
        self.output = self.directory / "result.json"
        self.code = self.directory / "code"
        self.code.mkdir()
        for name in ("evaluate_generation_candidate.py", "generation_json_grammar.py",
                     "verify_generation_artifact.py"):
            (self.code / name).write_bytes((ROOT / "Scripts" / name).read_bytes())
        self.loaded = {"type": "loaded", "loadSeconds": 0.01,
                       "torchVersion": "synthetic-test", "transformersVersion": "synthetic-test"}
        self.case_events = [{"type": "case", "result": {
            "caseID": case_id, "status": "generated", "decodedOutput": "synthetic test output",
        }} for case_id in self.case_ids]

    def invoke(self, context, *, manifest=True, decode_profile="unconstrained", timeout="1"):
        arguments = ["evaluate_generation_candidate.py", "--model-dir", str(self.model),
                     "--cases", str(self.cases), "--output", str(self.output),
                     "--timeout", timeout, "--decode-profile", decode_profile]
        if manifest:
            arguments.extend(["--manifest", str(self.manifest)])
        with patch.object(sys, "argv", arguments), \
                patch.object(harness, "__file__", str(self.code / "evaluate_generation_candidate.py")), \
                patch.object(harness.multiprocessing, "get_context", return_value=context):
            return harness.main()

    def completed_context(self, **options):
        return FakeContext([self.loaded, *self.case_events, {"type": "complete"}], **options)

    def read_report(self):
        return json.loads(self.output.read_text())

    def test_AC1_manifest_is_explicitly_required_before_starting_worker(self):
        context = self.completed_context()
        with self.assertRaises(SystemExit) as failure:
            self.invoke(context, manifest=False)
        self.assertEqual(failure.exception.code, 2)
        self.assertFalse(context.process.started)
        self.assertFalse(self.output.exists())

    def test_AC1_unlisted_or_changed_source_file_prevents_worker_start(self):
        for target in (self.model / "unlisted.json", self.model / "model.safetensors"):
            with self.subTest(target=target.name):
                original = target.read_bytes() if target.exists() else None
                target.write_bytes(b"changed source bytes")
                context = self.completed_context()
                try:
                    with self.assertRaises((ValueError, SystemExit)):
                        self.invoke(context)
                    self.assertFalse(context.process.started)
                    self.assertFalse(self.output.exists())
                finally:
                    if original is None:
                        target.unlink()
                    else:
                        target.write_bytes(original)

    def test_AC1_initial_report_binds_full_source_manifest_and_frozen_inputs(self):
        def check_before_start():
            report = self.read_report()
            identity = report["evidenceIdentity"]
            self.assertEqual(identity["sourceManifest"]["sha256"], digest(self.manifest))
            self.assertEqual(identity["sourceFiles"], json.loads(self.manifest.read_text())["files"])
            self.assertEqual(identity["modelConfigSHA256"], digest(self.model / "config.json"))
            self.assertEqual(identity["caseFileSHA256"], digest(self.cases))
            self.assertEqual(identity["scriptSHA256"], digest(self.code / "evaluate_generation_candidate.py"))
            self.assertEqual(identity["grammarModuleSHA256"], digest(self.code / "generation_json_grammar.py"))
            self.assertEqual(identity["verifierModuleSHA256"], digest(self.code / "verify_generation_artifact.py"))
            self.assertFalse(report["evidenceValid"])
            self.assertEqual(report["productionApproval"], "not_granted")

        context = self.completed_context(on_start=check_before_start)
        self.assertEqual(self.invoke(context, decode_profile="grammar-v1"), 0)
        report = self.read_report()
        self.assertEqual(report["evidenceIntegrity"]["status"], "unchanged")
        self.assertTrue(report["evidenceValid"])
        self.assertEqual(report["formalLanguageGate"], "not_evaluated")
        self.assertEqual(report["factualReview"], "pending_human_review")

    def test_AC1_each_identity_change_invalidates_completed_evidence_without_rebinding(self):
        targets = [self.model / name for name in ("model.safetensors", "tokenizer.json", "config.json")]
        targets += [self.manifest, self.cases,
                    self.code / "evaluate_generation_candidate.py",
                    self.code / "generation_json_grammar.py", self.code / "verify_generation_artifact.py"]
        for target in targets:
            with self.subTest(target=target.name):
                original = target.read_bytes()
                before = {}

                def change_after_first_result(received):
                    if received == 2:
                        before.update(self.read_report()["evidenceIdentity"])
                        target.write_bytes(original + b"\n")

                context = self.completed_context(before_poll=change_after_first_result)
                try:
                    self.assertNotEqual(self.invoke(context, decode_profile="grammar-v1"), 0)
                    report = self.read_report()
                    self.assertEqual(report["evidenceIdentity"], before)
                    self.assertEqual(report["evidenceIntegrity"]["status"], "changed")
                    self.assertFalse(report["evidenceValid"])
                    self.assertEqual(len(report["results"]), 2)
                finally:
                    target.write_bytes(original)
                    if self.output.exists():
                        self.output.unlink()

    def test_AC1_existing_output_is_preserved_and_worker_never_starts(self):
        original = b'{"historicalReport":"must remain unchanged"}\n'
        self.output.write_bytes(original)
        context = self.completed_context()
        with self.assertRaises((FileExistsError, ValueError, SystemExit)):
            self.invoke(context)
        self.assertEqual(self.output.read_bytes(), original)
        self.assertFalse(context.process.started)

    def test_AC1_new_valid_manifest_cannot_rebind_a_running_evaluation(self):
        frozen = {}

        def replace_source_and_manifest(received):
            if received == 2:
                frozen.update(self.read_report()["evidenceIdentity"])
                changed = self.model / "model.safetensors"
                changed.write_bytes(b"different synthetic weight bytes")
                manifest = json.loads(self.manifest.read_text())
                for entry in manifest["files"]:
                    if entry["path"] == changed.name:
                        entry.update(sha256=digest(changed), sizeBytes=changed.stat().st_size)
                self.manifest.write_text(json.dumps(manifest))

        context = self.completed_context(before_poll=replace_source_and_manifest)
        self.assertNotEqual(self.invoke(context), 0)
        report = self.read_report()
        self.assertEqual(report["evidenceIdentity"], frozen)
        self.assertEqual(report["evidenceIntegrity"]["status"], "changed")
        self.assertFalse(report["evidenceValid"])

    def test_AC1_loaded_and_case_events_are_saved_as_readable_progress_snapshots(self):
        observed = []

        def inspect_before_next_event(received):
            report = self.read_report()
            self.assertEqual(report["status"], "running")
            if received >= 1:
                self.assertEqual(report["runtime"]["loadSeconds"], 0.01)
            if received >= 2:
                self.assertEqual(report["results"][0]["caseID"], self.case_ids[0])
            observed.append(received)

        context = self.completed_context(before_poll=inspect_before_next_event)
        self.assertEqual(self.invoke(context), 0)
        self.assertEqual(observed, [0, 1, 2, 3])
        self.assertEqual(self.read_report()["notCompletedCaseIDs"], [])

    def test_AC1_completed_worker_can_release_resources_before_forced_termination(self):
        context = self.completed_context()
        with patch.object(context.process, "join", side_effect=lambda timeout: setattr(context.process, "alive", False)):
            self.assertEqual(self.invoke(context), 0)
        self.assertFalse(context.process.terminated)

    def test_AC1_keyboard_interrupt_preserves_completed_case_and_stops_worker(self):
        context = FakeContext([self.loaded, self.case_events[0], KeyboardInterrupt()])
        self.assertNotEqual(self.invoke(context), 0)
        report = self.read_report()
        self.assertEqual(report["status"], "interrupted")
        self.assertEqual([result["caseID"] for result in report["results"]], self.case_ids[:1])
        self.assertEqual(report["notCompletedCaseIDs"], self.case_ids[1:])
        self.assertFalse(report["evidenceValid"])
        self.assertTrue(context.process.terminated)

    def test_AC1_parent_exception_preserves_completed_case_and_error_terminal(self):
        context = FakeContext([self.loaded, self.case_events[0], RuntimeError("synthetic parent failure")])
        self.assertNotEqual(self.invoke(context), 0)
        report = self.read_report()
        self.assertEqual(report["status"], "error")
        self.assertIn("synthetic parent failure", report["error"])
        self.assertEqual([result["caseID"] for result in report["results"]], self.case_ids[:1])
        self.assertEqual(report["notCompletedCaseIDs"], self.case_ids[1:])
        self.assertTrue(context.process.terminated)

    def test_AC1_failed_atomic_progress_replace_preserves_readable_prior_snapshot(self):
        replace = harness.os.replace
        observed = []

        def fail_one_case_replace(source, target):
            next_report = json.loads(Path(source).read_text())
            if next_report["status"] == "running" and next_report["results"] and not observed:
                observed.append(self.read_report())
                raise OSError("synthetic atomic replacement failure")
            return replace(source, target)

        context = self.completed_context()
        with patch.object(harness.os, "replace", side_effect=fail_one_case_replace):
            self.assertNotEqual(self.invoke(context), 0)
        self.assertEqual(len(observed), 1)
        self.assertEqual(observed[0]["runtime"]["loadSeconds"], 0.01)
        self.assertEqual(observed[0]["results"], [])
        report = self.read_report()
        self.assertEqual(report["status"], "error")
        self.assertIn("synthetic atomic replacement failure", report["error"])
        self.assertEqual([result["caseID"] for result in report["results"]], self.case_ids[:1])
        self.assertTrue(context.process.terminated)

    def test_AC1_hard_timeout_preserves_partial_progress_and_stops_worker(self):
        clock = [0.0]

        def expire_after_first_case(received):
            if received == 2:
                clock[0] = 2.0

        context = FakeContext([self.loaded, self.case_events[0]], before_poll=expire_after_first_case)
        with patch.object(harness.time, "monotonic", side_effect=lambda: clock[0]):
            self.assertNotEqual(self.invoke(context), 0)
        report = self.read_report()
        self.assertEqual(report["status"], "timeout")
        self.assertEqual([result["caseID"] for result in report["results"]], self.case_ids[:1])
        self.assertEqual(report["notCompletedCaseIDs"], self.case_ids[1:])
        self.assertFalse(report["evidenceValid"])
        self.assertTrue(context.process.terminated)


if __name__ == "__main__":
    unittest.main()
