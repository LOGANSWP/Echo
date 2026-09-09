"""Task 4.0k / ADR-023: model-free constrained-decoding boundary tests."""

import importlib.util
import json
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("generation_json_grammar", ROOT / "Scripts/generation_json_grammar.py")
grammar = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(grammar)
SOURCE = "10000000-0000-4000-8000-000000000001"
OTHER = "10000000-0000-4000-8000-000000000002"
UNKNOWN = "10000000-0000-4000-8000-000000000003"
PREFIX = b'{"schemaVersion":1,"paragraphs":[{"text":"'
SUFFIX = b'","sourceMemoryIDs":[]}]}'


def envelope(text="A tile.", ids=None, count=1):
    return json.dumps({"schemaVersion": 1, "paragraphs": [
        {"text": text, "sourceMemoryIDs": [] if ids is None else ids}
    ] * count}, ensure_ascii=False).encode()


class JSONGrammarTests(unittest.TestCase):
    def setUp(self):
        self.rule = grammar.EnvelopeGrammar([SOURCE, OTHER])

    def test_AC2_full_envelope_prefixes_and_no_source(self):
        raw = envelope(ids=[SOURCE, OTHER], count=2)
        self.assertEqual(self.rule.status(raw), "complete")
        self.assertEqual(self.rule.status(envelope()), "complete")
        for index in range(len(raw)):
            self.assertNotEqual(self.rule.status(raw[:index]), "invalid", index)
        for bad in (envelope(count=0), envelope(count=3), envelope(ids=[SOURCE] * 5),
                    envelope().replace(b'"schemaVersion": 1', b'"schemaVersion": 2'),
                    envelope() + b'.', b'```json\n' + envelope() + b'\n```',
                    envelope() + b'{}', envelope().replace(b'"schemaVersion": 1', b'"schemaVersion": 1,"schemaVersion": 1'),
                    PREFIX + b'A tile."},{"sourceMemoryIDs":[]}]}', envelope(text="")):
            with self.subTest(bad=bad):
                self.assertEqual(self.rule.status(bad), "invalid")

    def test_AC2_same_prefix_id_is_model_choice_not_auto_binding(self):
        self.assertEqual(self.rule.status(envelope(ids=[SOURCE])), "complete")
        self.assertEqual(self.rule.status(envelope(ids=[OTHER])), "complete")
        self.assertEqual(self.rule.status(envelope(ids=[UNKNOWN])), "invalid")
        common = envelope(ids=[SOURCE]).split(SOURCE.encode())[0] + SOURCE[:-1].encode()
        self.assertEqual(self.rule.status(common), "prefix")
        self.assertNotEqual(self.rule.status(common + b'2'), "invalid")
        self.assertEqual(self.rule.status(common + b'3'), "invalid")

    def test_AC2_utf8_multitoken_boundaries_are_strict(self):
        for text in ("蓝色", "🙂", "é", "e\u0301"):
            raw = PREFIX + text.encode() + SUFFIX
            for index in range(len(raw)):
                self.assertNotEqual(self.rule.status(raw[:index]), "invalid", (text, index))
            self.assertEqual(self.rule.status(raw), "complete")
        for invalid in (b'\x80', b'\xc0\xaf', b'\xed\xa0\x80', b'\xf4\x90\x80\x80', b'\xe4"'):
            self.assertEqual(self.rule.status(PREFIX + invalid), "invalid")

    def test_AC2_json_escapes_and_surrogate_pairs(self):
        for literal in (rb'a\"b', rb'a\\b', rb'a\nb', rb'\u84dd', rb'\uD83D\uDE42'):
            raw = PREFIX + literal + SUFFIX
            self.assertEqual(self.rule.status(raw), "complete")
            for index in range(len(raw)):
                self.assertNotEqual(self.rule.status(raw[:index]), "invalid", index)
        for literal in (rb'\x20', rb'\uD800x', rb'\uDC00', b'a\nb', b'\x00'):
            self.assertEqual(self.rule.status(PREFIX + literal + SUFFIX), "invalid")
        self.assertEqual(self.rule.status(PREFIX + b'\\'), "prefix")
        self.assertEqual(self.rule.status(PREFIX + rb'\uD83D'), "prefix")

    def test_AC2_eos_requires_complete_object_and_unknown_tokens_fail(self):
        tokens = {0: PREFIX, 1: '蓝'.encode()[:1], 2: '蓝'.encode()[1:], 3: SUFFIX, 4: b'.', 5: b' '}
        selector = grammar.TokenGrammar(self.rule, tokens, {9})
        self.assertFalse(selector.allows(9))
        self.assertFalse(selector.allows(100))
        for token in (0, 1, 2):
            selector.accept(token)
            self.assertFalse(selector.allows(9))
        selector.accept(3)
        self.assertTrue(selector.allows(9))
        self.assertFalse(selector.allows(4))
        self.assertFalse(selector.allows(5))
        self.assertEqual(selector.choose([5, 4, 9]), 9)
        selector.accept(9)
        self.assertFalse(selector.allows(9))
        self.assertEqual(selector.output_bytes, PREFIX + '蓝'.encode() + SUFFIX)

    def test_AC2_descending_choice_never_invents_a_token(self):
        selector = grammar.TokenGrammar(self.rule, {0: b'```', 1: PREFIX}, {9})
        self.assertEqual(selector.choose([100, 9, 0, 1]), 1)
        self.assertEqual(selector.output_bytes, b'')
        with self.assertRaises(grammar.NoAllowedToken):
            selector.choose([100, 9, 0])

    def test_AC2_rejected_candidate_does_not_corrupt_utf8_prefix(self):
        selector = grammar.TokenGrammar(self.rule, {0: PREFIX + b'\xe4', 1: b'"', 2: b'\xb8\xad'}, {9})
        selector.accept(0)
        self.assertEqual(selector.choose([1, 9, 2]), 2)
        self.assertEqual(selector.output_bytes, PREFIX + b'\xe4')
        selector.accept(2)
        self.assertEqual(selector.output_bytes, PREFIX + '中'.encode())

    def test_AC1_byte_bpe_mapping_excludes_every_added_token(self):
        document = {"model": {"type": "BPE", "vocab": {"a": 0, "Ġ": 1, "ä": 2, "½": 3, "ł": 4}},
                    "decoder": {"type": "ByteLevel"},
                    "added_tokens": [{"id": 5, "content": "<think>", "special": False}]}
        mapping = grammar.byte_bpe_tokens(document)
        self.assertEqual(mapping[1], b' ')
        self.assertEqual(mapping[2] + mapping[3] + mapping[4], '你'.encode())
        self.assertNotIn(5, mapping)
        self.assertNotIn(6, mapping)
        document["decoder"] = {"type": "WordPiece"}
        with self.assertRaises(ValueError):
            grammar.byte_bpe_tokens(document)

    def test_AC1_grammar_identity_is_deterministic_and_request_scoped(self):
        self.assertEqual(self.rule.sha256, grammar.EnvelopeGrammar([OTHER, SOURCE]).sha256)
        self.assertNotEqual(self.rule.sha256, grammar.EnvelopeGrammar([SOURCE]).sha256)
        with self.assertRaises(ValueError):
            grammar.EnvelopeGrammar(["not-an-id"])

    def test_AC2_actual_suffix_sync_is_idempotent_and_never_repairs(self):
        selector = grammar.TokenGrammar(self.rule, {0: PREFIX, 1: b'A', 2: SUFFIX}, {9})
        processor = grammar.GrammarLogitsProcessor(selector, 100)
        processor.synchronize([0, 1])
        processor.synchronize([0, 1])
        self.assertEqual(selector.output_bytes, PREFIX + b'A')
        self.assertFalse(processor.evidence()['grammarComplete'])
        with self.assertRaises(ValueError):
            processor.synchronize([0, 2])
        processor.synchronize([0, 1, 2, 9])
        self.assertTrue(processor.evidence()['grammarEOSAccepted'])

    def test_AC2_long_reference_whitespace_has_bounded_matching(self):
        prefix = PREFIX + b'A","sourceMemoryIDs":[' + b' ' * 4096
        self.assertEqual(self.rule.status(prefix), "prefix")
        self.assertEqual(self.rule.status(prefix + b']}]}'), "complete")
        self.assertEqual(self.rule.status(prefix + b'X'), "invalid")

    def test_AC1_decode_profiles_leave_default_generation_unmodified(self):
        spec = importlib.util.spec_from_file_location('harness', ROOT / 'Scripts/evaluate_generation_candidate.py')
        harness = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(harness)
        self.assertIsNone(harness.make_decoder('unconstrained', None, None, None, None, None))
        with self.assertRaises(ValueError):
            harness.make_decoder('invalid', None, None, None, None, None)
        with self.assertRaises(ValueError):
            harness.make_decoder('grammar-v1', None, 'not-qwen', {9}, None, 100)
        tokenizer = SimpleNamespace(backend_tokenizer=SimpleNamespace(to_str=lambda: json.dumps({
            'model': {'type': 'BPE', 'vocab': {'a': 0}}, 'decoder': {'type': 'ByteLevel'},
            'added_tokens': [{'id': 9, 'content': '<eos>', 'special': True}]})))
        with patch.dict(sys.modules, {'generation_json_grammar': grammar}):
            processor = harness.make_decoder('grammar-v1', tokenizer, 'qwen3', [9],
                                             {'sources': [{'memoryID': SOURCE}]}, 100)
        self.assertEqual(processor.selector.eos_ids, {9})
        self.assertEqual(harness.stop_reason(256, 0, [9]), 'output_token_limit')
        self.assertEqual(harness.stop_reason(256, 9, [9]), 'eos')
        self.assertEqual(harness.stop_reason(0, None, [9]), 'generation_stopped')


if __name__ == "__main__":
    unittest.main()
