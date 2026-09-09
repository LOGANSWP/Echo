"""4.0k: native execution evidence must not turn partial output into success."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evaluate_native_generation import validate_records


class NativeEvidenceTests(unittest.TestCase):
    def sample(self):
        return [{'kind': 'loaded'}, {'kind': 'case', 'id': 'x', 'inputTokenIDs': [1, 2],
                 'outputTokenIDs': [3, 151645], 'stopReason': 'eos', 'predictionCalls': 3},
                {'kind': 'completed'}]

    def test_completed_requires_exact_cases_and_prediction_accounting(self):
        self.assertTrue(validate_records(self.sample(), ['x'], 0, 'generate'))
        for field, value in [('predictionCalls', 4), ('outputTokenIDs', [151645, 3]),
                             ('inputTokenIDs', [True]), ('stopReason', 'max_new_tokens')]:
            records = self.sample()
            records[1][field] = value
            with self.assertRaises(ValueError):
                validate_records(records, ['x'], 0, 'generate')

    def test_missing_duplicate_unknown_and_failed_records_are_not_completed(self):
        for records in [self.sample()[:-1], self.sample() + self.sample()[1:2],
                        [{'kind': 'failure', 'reason': 'deadline'}]]:
            with self.assertRaises(ValueError):
                validate_records(records, ['x'], 0, 'generate')
        with self.assertRaises(ValueError):
            validate_records(self.sample(), ['different'], 0, 'generate')
        with self.assertRaises(ValueError):
            validate_records(self.sample(), ['x'], 1, 'generate')

    def test_cancellation_has_no_case_or_completion(self):
        rows = [{'kind': 'loaded'}, {'kind': 'failure', 'reason': 'CancellationError()'}]
        self.assertTrue(validate_records(rows, ['x'], 1, 'cancel-after-first-prediction'))
        for bad in [rows + self.sample()[1:], [{'kind': 'failure', 'reason': 'invalidInput'}]]:
            with self.assertRaises(ValueError):
                validate_records(bad, ['x'], 1, 'cancel-after-first-prediction')


if __name__ == '__main__':
    unittest.main()
