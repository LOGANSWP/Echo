"""4.0k: actual Swift prefix-language conformance against frozen grammar-v1."""
import base64
import hashlib
import json
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'Scripts'))
from generation_json_grammar import EnvelopeGrammar


def main():
    ids = ['10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002']
    rule = EnvelopeGrammar(ids)
    texts = ['hello', '中文👩🏽‍💻', '\\uD83D\\uDE00', '\\u4e2d', '\\n\\t\\\\\\"', ' ',
             '', '\\uD800', '\\uDC00', '\\uD800\\u0041', '\\q', '\n', 'a"x']
    documents = [(b'{"schemaVersion":1,"paragraphs":[{"text":"' + t.encode() +
                  b'","sourceMemoryIDs":["' + ids[0].encode() + b'"]}]}') for t in texts]
    for count in range(5):
        documents.append(json.dumps({'schemaVersion':1,'paragraphs':[
            {'text':'x','sourceMemoryIDs':ids[:1]*count}]*max(1,count)}).encode())
    documents += [b'{"schemaVersion":2}', b'{"schemaVersion":1,"paragraphs":[]}',
                  documents[0]+b'x', documents[0]+b' \n',
                  documents[0].replace(ids[0].encode(), b'ffffffff-ffff-4fff-8fff-ffffffffffff')]
    samples = set()
    for data in documents:
        samples.update(data[:i] for i in range(len(data)+1))
    rng = random.Random(40012)
    valid = documents[1]
    for _ in range(512):
        data = bytearray(valid[:rng.randrange(len(valid)+1)])
        if data:
            data[rng.randrange(len(data))] = rng.randrange(256)
        samples.add(bytes(data))
    samples = sorted(samples)
    expected = [rule.status(s) for s in samples]
    payload = {'allowedIDs':ids, 'prefixes':[base64.b64encode(s).decode() for s in samples]}
    result = subprocess.run([str(Path(sys.argv[1]).resolve())], input=json.dumps(payload).encode(),
                            capture_output=True, timeout=30, check=True)
    actual = json.loads(result.stdout)
    assert len(actual['boundaryChecks']) == 12
    assert len(actual['statuses']) == len(expected)
    for raw, want, got in zip(samples, expected, actual['statuses']):
        assert want == got, (raw, want, got)
    record={'schemaVersion':1,'taskID':'4.0k','evidenceKind':'research_swift_grammar_conformance',
            'productionApproval':'not_granted','status':'passed','caseCount':len(samples),
            'randomSeed':40012,'cases':payload,'expected':expected,'actual':actual,
            'fileIdentities':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                for p in [Path(sys.argv[1]).resolve(),Path(__file__).resolve(),
                          ROOT/'Scripts/Research/GenerationEnvelopeGrammar.swift',
                          ROOT/'Scripts/Research/GenerationBudget.swift',
                          ROOT/'Scripts/Research/GenerationGrammarProbe.swift',
                          ROOT/'Scripts/generation_json_grammar.py']}}
    if len(sys.argv)>2:
        with Path(sys.argv[2]).open('x') as f:json.dump(record,f,indent=2)
    print(len(samples),'Swift byte-prefix states match grammar-v1')


if __name__=='__main__':main()
