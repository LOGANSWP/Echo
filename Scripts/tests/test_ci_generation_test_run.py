"""Task 4.0k: CI deferral must reach only the intended test host."""
from copy import deepcopy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_ci_generation_test_run import configured, FLAG


class GenerationTestRunTests(unittest.TestCase):
    def test_AC1_only_test_host_environment_changes_and_original_stays_enabled(self):
        original = {'__xctestrun_metadata__': {'FormatVersion': 2},
                    'CodeCoverageBuildableInfos': [{'IncludeInReport': True}],
                    'TestConfigurations': [{'TestTargets': [
                        {'BlueprintName': 'EchoTests', 'EnvironmentVariables': {'EXISTING': 'keep'},
                         'SkipTestIdentifiers': ['ExistingTest'], 'TestBundlePath': '__TESTROOT__/bundle'},
                        {'BlueprintName': 'EchoUITests', 'EnvironmentVariables': {'EXISTING': 'keep'}}]}]}
        before = deepcopy(original)
        result = configured(original)
        self.assertEqual(original, before)
        target = result['TestConfigurations'][0]['TestTargets'][0]
        self.assertEqual(target['EnvironmentVariables'].pop(FLAG), '1')
        self.assertEqual(result, original)

    def test_AC1_unknown_format_or_ambiguous_target_fails_closed(self):
        for targets in [[], [{'BlueprintName': 'Other'}], [{'BlueprintName': 'EchoTests'}] * 2]:
            with self.assertRaises(ValueError):
                configured({'__xctestrun_metadata__': {'FormatVersion': 2},
                            'TestConfigurations': [{'TestTargets': targets}]})
        with self.assertRaises(ValueError):
            configured({'__xctestrun_metadata__': {'FormatVersion': 1}})


if __name__ == '__main__':
    unittest.main()
