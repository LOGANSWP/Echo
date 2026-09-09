#!/usr/bin/env python3
"""Task 4.0k / SYN-001 AC-4/5: bounded, research-only language measurements.

Uses the real macOS NaturalLanguage framework via an explicit local probe binary.
No model calls in this CLI. Old reports remain immutable. Per-paragraph language
and ICU script signals are development diagnostics, not formal language quality.
Only UUID metadata is removed; no guessed names/quotes are silently discarded.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import re
import subprocess
from pathlib import Path

from evaluate_generation_candidate import AtomicReportWriter, validate_output, validate_cases

UUID_PATTERN = re.compile(r'(?<![\w-])[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}(?![\w-])', re.I)


def prose_sample(text):
    return UUID_PATTERN.sub('', text).strip()


def strict_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key')
        result[key] = value
    return result


def body_samples(raw, allowed_ids):
    validation = validate_output(raw, allowed_ids)
    if not validation['jsonSchemaValid'] or validation['emptyOutput']:
        raise ValueError('invalid or empty envelope')
    document = json.loads(raw, object_pairs_hook=strict_object)
    return [prose_sample(paragraph['text']) for paragraph in document['paragraphs']]


def matches(measurement, preferred):
    language = measurement.get('dominantLanguage')
    confidence = measurement.get('confidence', 0)
    if not measurement.get('hasLetters') or not math.isfinite(confidence) or confidence < .9:
        return False
    if preferred == 'en-US':
        return language == 'en'
    if preferred == 'zh-Hans':
        return language in ('zh-Hans', 'zh-Hant') and measurement.get('simplificationChanged') is False
    return False


def run_probe(binary, samples):
    payload = json.dumps(samples, ensure_ascii=False).encode()
    if len(samples) > 256 or len(payload) > 1_048_576:
        raise ValueError('probe input exceeds research budget')
    process = subprocess.run([str(binary.resolve())], input=payload, capture_output=True,
                             check=True, timeout=30)
    result = json.loads(process.stdout)
    if result.get('schemaVersion') != 1 or len(result.get('measurements', [])) != len(samples):
        raise ValueError('unexpected probe result')
    return result


def assess(raw, allowed_ids, preferred, binary):
    try:
        samples = body_samples(raw, allowed_ids)
    except ValueError as error:
        return {'schemaValid': False, 'languageMatched': False, 'error': str(error)}
    # Whole JSON is only a comparator for the old implementation, never the gate.
    measured = run_probe(binary, [raw, '\n'.join(samples)] + samples)
    body = measured['measurements'][2:]
    return {'schemaValid': True, 'languageMatched': bool(body) and all(matches(x, preferred) for x in body),
            'samplePolicy': 'paragraphs_minus_UUIDs_no_guessed_quote_or_name_exclusions_v1',
            'wholeEnvelope': measured['measurements'][0],
            'joinedBody': measured['measurements'][1], 'paragraphs': body,
            'operatingSystem': measured['operatingSystem'], 'formalQualityApproval': False}


def align_once(generate, assess_output):
    """One logical call: schema failure never repaired; at most one language retry.

    The caller must enforce a shared execution deadline/call budget and re-render
    the same source inputs and allow-list. Exceptions including cancellation are
    propagated, never converted to a successful fallback or an extra model call.
    """
    attempts = []
    for is_retry in (False, True):
        output = generate(is_retry)
        measurement = assess_output(output)
        attempts.append({'isLanguageRetry': is_retry, 'assessment': measurement})
        if not measurement['schemaValid']:
            return {'outcome': 'schema_failure', 'attempts': attempts}
        if measurement['languageMatched']:
            return {'outcome': 'validated_language_screen', 'attempts': attempts, 'generatedOutput': output}
    return {'outcome': 'language_fallback', 'attempts': attempts}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ('review-index', 'cases', 'probe', 'probe-source', 'output'):
        parser.add_argument('--' + field, type=Path, required=True)
    args = parser.parse_args()
    cases = {c['id']: c for c in validate_cases(json.loads(args.cases.read_text()))}
    root = Path(__file__).resolve().parents[1]
    files = [Path(__file__), root/'Scripts/evaluate_generation_candidate.py', args.review_index,
             args.cases, args.probe, args.probe_source]
    identities = {str(p.resolve()): digest(p) for p in files}
    writer = AtomicReportWriter(args.output)
    report = {'schemaVersion': 1, 'evidenceKind': 'research_host_language_measurements',
              'formalLanguageGate': 'not_evaluated', 'productionApproval': 'not_granted',
              'fileIdentities': identities, 'status': 'running', 'evidenceValid': False, 'runs': []}
    writer.save(report)
    try:
        for run in json.loads(args.review_index.read_text())['runs']:
            path = root/run['reportPath']
            if digest(path) != run['reportSHA256']:
                raise ValueError('original screen report identity changed')
            identities[str(path.resolve())] = run['reportSHA256']
            measured = {'reportPath': run['reportPath'], 'reportSHA256': run['reportSHA256'], 'results': []}
            rows = json.loads(path.read_text())['results']
            if len(rows) != len(cases) or {r['caseID'] for r in rows} != set(cases):
                raise ValueError('case coverage differs from frozen dataset')
            for row in rows:
                case = cases[row['caseID']]
                result = assess(row.get('decodedOutput', ''), {s['memoryID'] for s in case['sources']},
                                case['preferredLanguage'], args.probe)
                measured['results'].append({'caseID': case['id'], **result})
            measured['caseCount'] = len(rows)
            measured['validSchemaCount'] = sum(r['schemaValid'] for r in measured['results'])
            measured['matchedCount'] = sum(r['languageMatched'] for r in measured['results'])
            report['runs'].append(measured)
            writer.save(report)
        report['status'] = 'completed'
    finally:
        report['evidenceValid'] = report['status'] == 'completed' and all(
            digest(Path(p)) == h for p, h in identities.items())
        writer.save(report)


if __name__ == '__main__':
    main()
