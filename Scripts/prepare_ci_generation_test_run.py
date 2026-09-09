#!/usr/bin/env python3
"""Task 4.0k / DEF-79-002: forward the user-approved CI-only deferral to XCTest.

Do not modify the generated original, other test targets or existing exclusions.
Local scheme runs remain enabled. Preserve __TESTROOT__ by writing beside input.
"""
import argparse
from copy import deepcopy
from pathlib import Path
import plistlib

FLAG = 'ECHO_DEFER_GENERATION_ARTIFACT_TESTS'


def configured(document):
    result = deepcopy(document)
    if result.get('__xctestrun_metadata__', {}).get('FormatVersion') != 2:
        raise ValueError('Unsupported xctestrun format')
    targets = [target for config in result.get('TestConfigurations', [])
               for target in config.get('TestTargets', []) if target.get('BlueprintName') == 'EchoTests']
    if len(targets) != 1:
        raise ValueError('Expected exactly one EchoTests target')
    targets[0].setdefault('EnvironmentVariables', {})[FLAG] = '1'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('products', type=Path)
    args = parser.parse_args()
    paths = list(args.products.glob('Echo_Echo_iphonesimulator*.xctestrun'))
    if len(paths) != 1:
        raise ValueError('Expected exactly one generated Echo simulator test run')
    source = paths[0]
    result = configured(plistlib.loads(source.read_bytes()))
    destination = source.parent / 'Echo-CI-GenerationDeferred.xctestrun'
    destination.write_bytes(plistlib.dumps(result))
    print(destination)


if __name__ == '__main__':
    main()
