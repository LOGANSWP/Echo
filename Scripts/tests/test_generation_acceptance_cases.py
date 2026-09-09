"""4.0k: freeze source-only model inputs and separate factual review annotations."""
import sys
import unittest
from collections import Counter
from pathlib import Path
from uuid import UUID

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from generate_generation_acceptance_cases import build_suite, model_case
from evaluate_generation_candidate import build_profile_messages


class AcceptanceCasesTests(unittest.TestCase):
    def test_counts_and_semantic_clusters_are_explicit(self):
        suite = build_suite()
        self.assertEqual(len(suite['cases']), 400)
        self.assertEqual(Counter(c['preferredLanguage'] for c in suite['cases']), {'en-US': 200, 'zh-Hans': 200})
        self.assertEqual(len({c['scenarioID'] for c in suite['cases']}), 20)
        self.assertEqual(len({c['id'] for c in suite['cases']}), 400)
        self.assertFalse(suite['independentIdenticallyDistributed'])

    def test_identifiers_annotations_and_source_languages(self):
        seen = set()
        for case in build_suite()['cases']:
            allowed = {s['memoryID'] for s in case['sources']}
            self.assertEqual(len(allowed), len(case['sources']))
            self.assertFalse(allowed & seen)
            seen.update(allowed)
            self.assertTrue(all(str(UUID(x)) == x for x in allowed))
            self.assertTrue(all(f['sourceMemoryID'] in allowed for f in case['expectedFacts']))
            self.assertTrue(case['expectedFacts'])
            self.assertEqual(len(case['sourceLanguages']), len(case['sources']))

    def test_annotations_are_not_model_input(self):
        for case in build_suite()['cases']:
            projected = model_case(case)
            self.assertNotIn('expectedFacts', projected)
            self.assertTrue(all(set(s) == {'memoryID', 'sourceType', 'text'} for s in projected['sources']))
            messages = build_profile_messages(projected, 'observations-v1')
            self.assertNotIn('humanReviewChecks', messages[1]['content'])
            self.assertNotIn('expectedFacts', messages[1]['content'])
            self.assertNotIn('<|im_start|>', messages[1]['content'])

    def test_generation_is_repeatable_and_not_old_screen_reuse(self):
        self.assertEqual(build_suite(), build_suite())
        for case in build_suite()['cases']:
            self.assertTrue(case['id'].startswith('acceptance-v1-'))
            self.assertFalse(case['previouslyExecuted'])


if __name__ == '__main__':
    unittest.main()
