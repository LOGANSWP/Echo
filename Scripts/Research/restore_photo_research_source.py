#!/usr/bin/env python3
"""Restore the already authorized Task 4.0l source; no Hub cache or overwrite."""

import hashlib
import json
import shutil
import subprocess
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'PinnedModels/photo-understanding-evaluation'
SOURCE = RESEARCH / 'smolvlm-256m/source'
INVENTORY = ROOT / 'docs/05-planning/4.0l-candidate-inventory.json'
INVENTORY_HASH = 'd341144801c6dc27a08b959c796dad69d41b08b470184171786c90a217c82d72'
LIMIT = 3_000_000_000


def usage():
    return sum(p.stat().st_size for p in RESEARCH.rglob('*') if p.is_file())


def verify(path, item):
    digest = hashlib.sha256()
    blob = hashlib.sha1(f'blob {item["sizeBytes"]}\0'.encode())
    size = 0
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            size += len(chunk)
            digest.update(chunk)
            blob.update(chunk)
    expected = item['upstreamLfsSha256'] or item['gitBlobId']
    actual = digest.hexdigest() if item['upstreamLfsSha256'] else blob.hexdigest()
    if size != item['sizeBytes'] or actual != expected:
        raise ValueError('Fixed source identity mismatch: ' + item['path'])
    return {'path': item['path'], 'sizeBytes': size, 'sha256': digest.hexdigest()}


def main():
    raw = INVENTORY.read_bytes()
    if hashlib.sha256(raw).hexdigest() != INVENTORY_HASH:
        raise ValueError('Authorized inventory changed')
    candidate = next(c for c in json.loads(raw)['candidates']
                     if c['repository'] == 'HuggingFaceTB/SmolVLM-256M-Instruct')
    authorization = json.loads((ROOT / 'docs/05-planning/4.0l-research-authorization.json').read_text())
    assert authorization['inventorySha256'] == INVENTORY_HASH
    assert authorization['revision'] == candidate['revision']
    assert sum(f['sizeBytes'] for f in candidate['rootFiles']) == authorization['approvedDownloadBytes']
    subprocess.run(['git', 'check-ignore', '-q', str(SOURCE / 'model.safetensors')], cwd=ROOT, check=True)
    SOURCE.mkdir(parents=True, exist_ok=True)
    report_path = ROOT / 'docs/05-planning/4.0l-source-restoration.json'
    if report_path.exists():
        raise FileExistsError('Restoration already recorded; verify instead of redownloading')
    started = time.monotonic()
    results = []
    for item in candidate['rootFiles']:
        if Path(item['path']).name != item['path']:
            raise ValueError('Only authorized root files are supported')
        target = SOURCE / item['path']
        if target.is_symlink():
            raise ValueError('Refusing source symlink')
        if target.exists():
            results.append(verify(target, item))
            continue
        if usage() + item['sizeBytes'] > LIMIT or shutil.disk_usage(ROOT).free < 20_000_000_000:
            raise RuntimeError('Research disk cap or free-space reserve reached')
        partial = target.with_name(target.name + '.partial')
        # Exclusive creation prevents deleting another run's temporary file.
        stream = partial.open('xb')
        try:
            with stream, urllib.request.urlopen(item['url'], timeout=60) as response:
                count = 0
                while chunk := response.read(1024 * 1024):
                    count += len(chunk)
                    if count > item['sizeBytes'] or time.monotonic() - started > 1800:
                        raise RuntimeError('Download exceeded frozen size/time bound')
                    stream.write(chunk)
            result = verify(partial, item)
            partial.rename(target)
            results.append(result)
            print('verified ' + item['path'], flush=True)
        finally:
            if partial.exists():
                partial.unlink()
    report = {'taskId': '4.0l', 'restoredAt': datetime.now(timezone.utc).isoformat(),
              'reason': 'Continue existing authorized functional research after user priority clarification',
              'repository': candidate['repository'], 'revision': candidate['revision'],
              'inventorySha256': INVENTORY_HASH, 'files': results,
              'researchBytes': usage(), 'freeBytes': shutil.disk_usage(ROOT).free,
              'productionApproval': 'pending', 'elapsedSeconds': time.monotonic() - started}
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ('researchBytes', 'freeBytes', 'elapsedSeconds')}))


if __name__ == '__main__':
    main()
