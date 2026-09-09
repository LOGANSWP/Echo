#!/usr/bin/env python3
"""4.0k: stdlib controller for the full Swift research process; no App approval.

The model process itself uses only Swift and system frameworks. Input messages
are the frozen observations-v1 profile; they contain synthetic source records.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

import evaluate_generation_candidate as evaluator
import verify_generation_artifact as verifier

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT/'PinnedModels/offline-generation-evaluation'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_records(records, ids, exit_code, mode):
    if mode == 'cancel-after-first-prediction':
        if (exit_code != 1 or len(records) != 2 or records[0].get('kind') != 'loaded'
                or records[1].get('kind') != 'failure'
                or records[1].get('reason') != 'CancellationError()'):
            raise ValueError('Cancellation did not fail before any case/completion publication')
        return True
    if (exit_code != 0 or len(records) != len(ids) + 2 or records[0].get('kind') != 'loaded'
            or records[-1].get('kind') != 'completed'):
        raise ValueError('Native execution incomplete')
    for row, case_id in zip(records[1:-1], ids):
        if row.get('kind') != 'case' or row.get('id') != case_id:
            raise ValueError('Native execution case order/identity mismatch')
        prompt, output = row.get('inputTokenIDs', []), row.get('outputTokenIDs', [])
        if (not prompt or not output or len(prompt) + 256 > 1024 or len(output) > 256
                or any(type(t) is not int or not 0 <= t < 151936 for t in prompt)
                or any(type(t) is not int or not (0 <= t < 151643 or t in (151643, 151645)) for t in output)
                or any(t in (151643, 151645) for t in output[:-1])
                or row.get('predictionCalls') != len(prompt) + len(output) - 1):
            raise ValueError('Token/prediction budget or identity violation')
        ended = output[-1] in (151643, 151645)
        if ((ended and row.get('stopReason') != 'eos')
                or (not ended and (row.get('stopReason') != 'max_new_tokens' or len(output) != 256))):
            raise ValueError('Unsupported stopping claim')
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mode', choices=['generate', 'cancel-after-first-prediction'], default='generate')
    args = parser.parse_args()
    output = args.output.resolve()
    writer = evaluator.AtomicReportWriter(output)
    source = BASE/'qwen3-0.6b/source'
    package = BASE/'qwen3-0.6b/conversion-context1024-int8-channel/Qwen06BContext1024Int8Channel.mlpackage'
    source_manifest = ROOT/'docs/05-planning/4.0k-qwen3-source-manifest.json'
    package_manifest = BASE/'qwen3-0.6b/context1024-int8-manifest.json'
    binary = BASE/'generation-native-probe'
    frozen = ROOT/'EchoTests/TestData/Generation/4.0k-screen-v1.json'
    cases = evaluator.validate_cases(json.loads(frozen.read_text()))
    if args.mode != 'generate':
        cases = cases[:1]
    payload = {'schemaVersion': 1, 'context': 1024, 'outputLimit': 256, 'cases': [
        {'id': c['id'], 'messages': evaluator.build_profile_messages(c, 'observations-v1'),
         'allowedIDs': [s['memoryID'] for s in c['sources']]} for c in cases]}
    input_path = output.with_suffix('.input.json')
    raw_path = output.with_suffix('.jsonl')
    error_path = output.with_suffix('.stderr.txt')
    with input_path.open('x') as stream:
        json.dump(payload, stream, ensure_ascii=False, indent=2)
    paths = [Path(__file__).resolve(), Path(evaluator.__file__).resolve(), Path(verifier.__file__).resolve(),
             source_manifest, package_manifest, binary, frozen, input_path]
    paths += [ROOT/'Scripts/Research'/name for name in (
        'GenerationTokenizer.swift', 'GenerationEnvelopeGrammar.swift', 'GenerationBudget.swift',
        'GenerationMemory.swift', 'GenerationNativeProbe.swift')]
    identities = {str(p.relative_to(ROOT)): digest(p) for p in paths}
    archive = BASE/'tool-archive'
    archive.mkdir(exist_ok=True)
    for path in paths:
        if path.suffix in ('.swift', '.py'):
            target = archive/(digest(path) + '-' + path.name)
            if not target.exists():
                with target.open('xb') as stream:
                    stream.write(path.read_bytes())
    report = {'schemaVersion': 1, 'taskID': '4.0k', 'evidenceKind': 'research_native_generation_control',
              'productionApproval': 'not_granted', 'status': 'running', 'evidenceValid': False,
              'fileIdentities': identities, 'mode': args.mode, 'timeoutSeconds': 600,
              'rawPath': str(raw_path.relative_to(ROOT)), 'inputPath': str(input_path.relative_to(ROOT)),
              'caseIDs': [c['id'] for c in cases]}
    writer.save(report)
    started = time.monotonic()
    try:
        report['sourceIntegrity'] = verifier.verify_artifact(source, source_manifest)
        report['packageIntegrity'] = verifier.verify_artifact(package, package_manifest)
        writer.save(report)
        with raw_path.open('xb') as stdout, error_path.open('xb') as stderr:
            process = subprocess.run([str(binary), str(package), str(source/'tokenizer.json'),
                str(input_path), args.mode], stdout=stdout, stderr=stderr, timeout=600)
        report['exitCode'] = process.returncode
        records = [json.loads(line) for line in raw_path.read_text().splitlines()]
        report['records'] = records
        report['checksPassed'] = validate_records(records, report['caseIDs'], process.returncode, args.mode)
        if args.mode == 'generate':
            report['outputValidation'] = [evaluator.validate_output(row.get('decodedOutput') or '',
                {s['memoryID'] for s in case['sources']}) for row, case in zip(records[1:-1], cases)]
        report['status'] = 'completed'
    except Exception as error:
        report.update(status='failed', error=str(error))
    finally:
        report['elapsedSeconds'] = time.monotonic() - started
        try:
            report['postSourceIntegrity'] = verifier.verify_artifact(source, source_manifest)
            report['postPackageIntegrity'] = verifier.verify_artifact(package, package_manifest)
            report['identityUnchanged'] = all(digest(ROOT/p) == sha for p, sha in identities.items())
            report['evidenceValid'] = report['identityUnchanged']
            if raw_path.exists():
                report['rawSHA256'] = digest(raw_path)
        except Exception as error:
            report.update(evidenceValid=False, integrityError=str(error))
        writer.save(report)
    print(json.dumps({k: report.get(k) for k in ('status', 'evidenceValid', 'elapsedSeconds', 'error')}))
    if report['status'] != 'completed' or not report['evidenceValid']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
