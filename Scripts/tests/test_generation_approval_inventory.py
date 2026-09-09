"""4.0k: approval inventory must include transitive and optional dependencies."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from generation_approval_inventory import dependency_graph, is_license_document


class ApprovalInventoryTests(unittest.TestCase):
    def graph(self, requirements, packages):
        return dependency_graph(requirements, packages.__getitem__)

    def test_transitive_cycle_and_platform_markers(self):
        packages = {'a': {'version': '1', 'requires': ['b>=2', 'missing; sys_platform == "impossible"']},
                    'b': {'version': '2.1', 'requires': ['a']}}
        result = self.graph(['a'], packages)
        self.assertEqual(set(result), {'a', 'b'})
        self.assertEqual(result['a']['dependencies'], ['b'])

    def test_new_extra_after_initial_visit_expands_dependency(self):
        packages = {'a': {'version': '1', 'requires': ['b', 'c']},
                    'b': {'version': '1', 'requires': ['d; extra == "feature"']},
                    'c': {'version': '1', 'requires': ['b[feature]']},
                    'd': {'version': '1', 'requires': []}}
        result = self.graph(['a'], packages)
        self.assertEqual(set(result), {'a', 'b', 'c', 'd'})
        self.assertEqual(result['b']['dependencies'], ['d'])

    def test_missing_or_incompatible_dependency_rejects(self):
        for packages in ({}, {'a': {'version': '1', 'requires': []}}):
            with self.assertRaises(ValueError):
                self.graph(['a>=2'], packages)

    def test_legal_text_does_not_match_source_or_cache_names(self):
        for path in ['x.dist-info/licenses/LICENSE', 'x/NOTICE.txt', 'x/LICENCE', 'x/COPYING', 'x/LICENSE.BSD']:
            self.assertTrue(is_license_document(path))
        for path in ['packaging/licenses/__init__.py', '../cache/LICENSE.pyc', 'x/_license.py', 'x/LICENSE.so']:
            self.assertFalse(is_license_document(path))


if __name__ == '__main__':
    unittest.main()
