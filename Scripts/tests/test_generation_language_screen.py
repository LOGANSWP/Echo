"""Task 4.0k / SYN-001 AC-4/5: research language and retry boundaries."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import generation_language_screen as screen


class GenerationLanguageScreenTests(unittest.TestCase):
    def test_AC4_uuid_only_is_not_language(self):
        self.assertEqual(screen.prose_sample('10000000-0000-4000-8000-000000000001'), '')
        self.assertEqual(screen.prose_sample('The boat stayed upright.'), 'The boat stayed upright.')

    def test_AC4_duplicate_keys_and_empty_envelope_rejected_before_detection(self):
        for raw in ('{"schemaVersion":1,"schemaVersion":1,"paragraphs":[]}',
                    '{"schemaVersion":1,"paragraphs":[]}'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                screen.body_samples(raw, set())

    def test_AC4_low_confidence_wrong_language_and_traditional_script_fail(self):
        good = {'hasLetters': True, 'dominantLanguage': 'en', 'confidence': .99,
                'simplificationChanged': False}
        self.assertTrue(screen.matches(good, 'en-US'))
        self.assertFalse(screen.matches({**good, 'confidence': .89}, 'en-US'))
        self.assertFalse(screen.matches(good, 'zh-Hans'))
        self.assertFalse(screen.matches({**good, 'dominantLanguage': 'zh-Hant',
                                        'simplificationChanged': True}, 'zh-Hans'))
        self.assertFalse(screen.matches({**good, 'hasLetters': False}, 'en-US'))
        self.assertFalse(screen.matches(good, 'fr-FR'))

    def test_AC5_first_success_does_not_retry(self):
        calls = []
        result = screen.align_once(lambda retry: calls.append(retry) or 'good',
                                   lambda raw: {'schemaValid': True, 'languageMatched': True})
        self.assertEqual(calls, [False])
        self.assertEqual(result['outcome'], 'validated_language_screen')

    def test_AC5_second_failure_is_typed_fallback_no_third_call(self):
        calls = []
        result = screen.align_once(lambda retry: calls.append(retry) or 'wrong',
                                   lambda raw: {'schemaValid': True, 'languageMatched': False})
        self.assertEqual(calls, [False, True])
        self.assertEqual(result['outcome'], 'language_fallback')
        self.assertNotIn('generatedOutput', result)

    def test_AC5_retry_success_reassessed(self):
        outputs = iter(['wrong', 'good'])
        result = screen.align_once(lambda retry: next(outputs),
                                   lambda raw: {'schemaValid': True, 'languageMatched': raw == 'good'})
        self.assertEqual(len(result['attempts']), 2)
        self.assertEqual(result['generatedOutput'], 'good')

    def test_AC5_malformed_retry_is_failure_without_repair(self):
        for first_valid in (True, False):
            calls = []
            def assess(raw):
                return {'schemaValid': first_valid and len(calls) == 1, 'languageMatched': False}
            result = screen.align_once(lambda retry: calls.append(retry) or '{}', assess)
            self.assertEqual(len(calls), 2 if first_valid else 1)
            self.assertEqual(result['outcome'], 'schema_failure')

    def test_AC5_cancellation_or_runtime_failure_does_not_retry(self):
        calls = []
        def generate(retry):
            calls.append(retry)
            raise InterruptedError('cancelled')
        with self.assertRaises(InterruptedError):
            screen.align_once(generate, lambda raw: self.fail('must not assess'))
        self.assertEqual(calls, [False])


if __name__ == '__main__':
    unittest.main()
