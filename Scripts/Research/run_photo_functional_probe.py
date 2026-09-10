#!/usr/bin/env python3
"""Bound and verify native 4.0l functional/cancellation research executions."""

import argparse
import hashlib
import json
import os
import shutil
import signal
import subprocess
import time
from pathlib import Path

import psutil

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'PinnedModels/photo-understanding-evaluation'
MODEL = BASE / 'smolvlm-256m'


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def verify():
    source = json.loads((ROOT / 'docs/05-planning/4.0l-source-verification.json').read_text())
    for entry in source['files']:
        assert sha(MODEL / 'source' / entry['path']) == entry['sha256']
    conversion = json.loads((ROOT / 'docs/05-planning/4.0l-coreml-conversion-2.json').read_text())
    for package in conversion['packages']:
        for entry in package['files']:
            assert sha(MODEL / 'conversion-2' / (package['name'] + '.mlpackage') / entry['path']) == entry['sha256']
    compiled = ROOT / 'docs/05-planning/4.0l-compiled-models.json'
    if compiled.exists():
        for entry in json.loads(compiled.read_text())['files']:
            assert sha(ROOT / entry['path']) == entry['sha256']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['generate', 'cancel-after-vision'], required=True)
    parser.add_argument('--compiled', action='store_true')
    args = parser.parse_args()
    verify()
    label = args.mode + ('-compiled' if args.compiled else '')
    run = MODEL / ('functional-' + label)
    run.mkdir(exist_ok=False)
    scratch = run / 'scratch'
    scratch.mkdir()
    result_path = ROOT / ('docs/05-planning/4.0l-functional-' + label + '.json')
    resources_path = result_path.with_name(result_path.stem + '-resources.json')
    assert not result_path.exists() and not resources_path.exists()
    started = time.monotonic()
    peak = maxdisk = 0
    reason = None
    with (run / 'output.log').open('x') as output:
        command = [str(MODEL / 'photo-functional-probe'), str(MODEL / ('compiled-v1' if args.compiled else 'conversion-2')),
            str(MODEL / 'source/tokenizer.json'), str(result_path), args.mode]
        if args.compiled:
            command.append('--compiled')
        process = subprocess.Popen(command, stdout=output,
            stderr=subprocess.STDOUT, start_new_session=True, env=dict(os.environ, TMPDIR=str(scratch)))
        try:
            owner = psutil.Process(process.pid)
            while process.poll() is None:
                try:
                    rss = sum(p.memory_info().rss for p in [owner] + owner.children(recursive=True) if p.is_running())
                except psutil.NoSuchProcess:
                    rss = 0
                disk = sum(p.stat().st_size for p in BASE.rglob('*') if p.is_file())
                disk += sum(p.stat().st_size for p in Path('/tmp/echo-photo-swift-cache').rglob('*') if p.is_file())
                peak, maxdisk = max(peak, rss), max(maxdisk, disk)
                if rss > 8_000_000_000 or disk > 3_000_000_000 or time.monotonic() - started > 1800:
                    reason = 'research resource bound exceeded'
                    raise RuntimeError(reason)
                time.sleep(0.5)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            record = {'mode': args.mode, 'exitCode': process.returncode, 'stopReason': reason,
                'elapsedSeconds': time.monotonic() - started, 'sampledProcessTreeRSSPeakBytes': peak,
                'sampledResearchDiskPeakBytes': maxdisk, 'pollIntervalSeconds': 0.5,
                'executableSHA256': sha(MODEL / 'photo-functional-probe'),
                'sources': {p.name: sha(p) for p in [ROOT / 'Scripts/Research' / name for name in
                    ['PhotoFunctionalProbe.swift', 'PhotoTokenizer.swift', 'PhotoImagePreprocessor.swift', 'GenerationMemory.swift']]},
                'log': (run / 'output.log').read_text()[-16000:], 'productionApproval': 'pending'}
            verify()
            record['sourceAndPackageIntegrityBeforeAfter'] = True
            if not any(scratch.rglob('*')):
                scratch.rmdir()
            resources_path.write_text(json.dumps(record, indent=2) + '\n')
            print(json.dumps(record), flush=True)


if __name__ == '__main__':
    main()
