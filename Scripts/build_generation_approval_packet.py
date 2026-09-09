#!/usr/bin/env python3
"""4.0k: assemble an unapproved, reviewable model/resource and legal packet.

No weights are copied into docs or the App. Installed Python metadata describes
the current research tool environment, not an attestation of historical wheels.
"""
import argparse
import hashlib
import importlib.metadata as metadata
import json
from pathlib import Path
import platform
import subprocess
import uuid

from generation_approval_inventory import dependency_graph, is_license_document
from verify_generation_artifact import verify_artifact

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT/'PinnedModels/offline-generation-evaluation'
MODEL = BASE/'qwen3-0.6b'
REVISION = 'c1899de289a04d12100db370d81485cdf75e47ca'


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1_048_576), b''):
            value.update(block)
    return value.hexdigest()


def write_json(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def properties(**values):
    return [{'name': 'echo:' + key, 'value': str(value)} for key, value in values.items()]


def observed_package(name):
    dist = metadata.distribution(name)
    return {'version': dist.version, 'requires': dist.requires or []}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.relative_to(ROOT/'docs/05-planning')
    output.mkdir()
    legal_dir = output/'licenses'
    legal_dir.mkdir()
    components, dependencies, legal_records = [], [], []
    roots = ['coremltools', 'torch', 'transformers[chat-template]', 'tokenizers', 'safetensors', 'numpy', 'regex']
    graph = dependency_graph(roots, observed_package)
    for name, package in graph.items():
        dist = metadata.distribution(name)
        version = package['version']
        ref = 'pkg:pypi/' + name + '@' + version
        evidence = []
        metadata_digests = []
        for item in dist.files or []:
            path = Path(dist.locate_file(item))
            if '..' in Path(str(item)).parts or path.is_symlink() or not path.is_file():
                continue
            if Path(str(item)).name in ('METADATA', 'WHEEL', 'RECORD'):
                metadata_digests.append({'path': str(item), 'sha256': digest(path)})
            if not is_license_document(str(item)):
                continue
            target = legal_dir/(name + '-' + digest(path)[:12] + '-' + path.name)
            if not target.exists():
                with target.open('xb') as stream:
                    stream.write(path.read_bytes())
            evidence.append({'sourcePath': str(item), 'packetPath': str(target.relative_to(output)),
                             'sha256': digest(target), 'sizeBytes': target.stat().st_size})
        if name == 'tokenizers' and not evidence:
            path = BASE/'legal-reference/tokenizers-0.22.2-LICENSE'
            assert digest(path) == 'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4'
            target = legal_dir/'tokenizers-0.22.2-upstream-LICENSE'
            target.write_bytes(path.read_bytes())
            evidence.append({'sourceURL': 'https://raw.githubusercontent.com/huggingface/tokenizers/v0.22.2/LICENSE',
                             'packetPath': str(target.relative_to(output)), 'sha256': digest(target),
                             'sizeBytes': target.stat().st_size, 'scope': 'upstream tag reference; absent from installed wheel'})
        expression = dist.metadata.get('License-Expression')
        license_field = dist.metadata.get('License') or ''
        legal_records.append({'name': name, 'version': version, 'declaredLicenseExpression': expression,
            'licenseMetadataSHA256': hashlib.sha256(license_field.encode()).hexdigest(),
            'licenseClassifiers': [c for c in dist.metadata.get_all('Classifier', []) if c.startswith('License ::')],
            'files': evidence, 'installedMetadataDigests': metadata_digests,
            'legalApproval': 'pending', 'packagingScope': 'research_tool_only_not_app'})
        components.append({'type': 'library', 'bom-ref': ref, 'name': name, 'version': version, 'purl': ref,
            'description': 'Current installed research tool dependency; not linked or shipped by the native runtime.',
            'properties': properties(scope='research-tool-only', selectedExtras=','.join(package['selectedExtras']),
                                     licenseEvidence='licenses-index.json', legalApproval='pending')})
        dependencies.append({'ref': ref, 'dependsOn': ['pkg:pypi/' + child + '@' + graph[child]['version']
                                                       for child in package['dependencies']]})
    write_json(output/'licenses-index.json', {'schemaVersion': 1, 'productionApproval': 'not_granted',
        'scope': 'Current installed tool dependency metadata and preserved legal texts, not historical wheel attestation or App SBOM.',
        'pythonVersion': platform.python_version(), 'components': legal_records})
    artifact_groups = [
        ('source', MODEL/'source', ROOT/'docs/05-planning/4.0k-qwen3-source-manifest.json'),
        ('converted', MODEL/'conversion-context1024-int8-channel/Qwen06BContext1024Int8Channel.mlpackage', MODEL/'context1024-int8-manifest.json'),
        ('compiled', MODEL/'approval-compiled-v1/Qwen06BContext1024Int8Channel.mlmodelc', ROOT/'docs/05-planning/4.0k-qwen3-int8-compiled-manifest.json')]
    inventory, artifacts = [], []
    for group, directory, manifest in artifact_groups:
        checked = verify_artifact(directory, manifest)
        content = json.loads(manifest.read_text())
        artifacts.append({'group': group, 'rootPath': str(directory.relative_to(ROOT)),
            'manifestPath': str(manifest.relative_to(ROOT)), 'manifestSHA256': digest(manifest), 'integrity': checked})
        for file in content['files']:
            path = directory/file['path']
            inventory.append({'group': group, 'path': str(path.relative_to(ROOT)), 'relativePath': file['path'],
                              'sizeBytes': path.stat().st_size, 'sha256': digest(path)})
        ref = 'echo:qwen3-0.6b:' + group
        components.append({'type': 'machine-learning-model', 'bom-ref': ref, 'name': 'Qwen3-0.6B ' + group,
            'version': REVISION + ('-context1024-int8-channel-v1' if group != 'source' else ''),
            'licenses': [{'license': {'id': 'Apache-2.0'}}],
            'properties': properties(scope='unapproved-candidate', completeFileInventory='artifact-inventory.json',
                manifestPath=str(manifest.relative_to(ROOT)), manifestSHA256=digest(manifest),
                licenseClaim='upstream declaration only; legal disposition pending')})
        dependencies.append({'ref': ref, 'dependsOn': []})
    source_license = MODEL/'source/LICENSE'
    (legal_dir/'Qwen3-0.6B-LICENSE').write_bytes(source_license.read_bytes())
    write_json(output/'artifact-inventory.json', {'schemaVersion': 1, 'productionApproval': 'not_granted',
        'artifacts': artifacts, 'files': inventory})
    swift_files = ['GenerationTokenizer.swift', 'GenerationEnvelopeGrammar.swift', 'GenerationBudget.swift',
                   'GenerationMemory.swift', 'GenerationNativeProbe.swift', 'GenerationCoreMLProbe.swift', 'GenerationLanguageProbe.swift']
    lineage_paths = [ROOT/'Scripts/Research'/n for n in swift_files] + [
        ROOT/'Scripts/convert_generation_candidate.py', MODEL/'convert-context1024.py', MODEL/'quantize-context1024-int8.py',
        MODEL/'conversion-context1024/report.json', MODEL/'conversion-context1024-int8-channel/report.json',
        MODEL/'approval-compiled-v1/compile-control.json', MODEL/'approval-compiled-v1/native-validation.json',
        BASE/'generation-native-probe', BASE/'generation-compiled-coreml-probe', BASE/'generation-language-probe',
        ROOT/'Scripts/build_generation_approval_packet.py', ROOT/'Scripts/generation_approval_inventory.py']
    lineage = [{'path': str(p.relative_to(ROOT)), 'sizeBytes': p.stat().st_size, 'sha256': digest(p)} for p in lineage_paths]
    dylibs = subprocess.check_output(['otool', '-L', str(BASE/'generation-native-probe')], text=True)
    link_libraries = [line.strip().split(' (')[0] for line in dylibs.splitlines()[1:]]
    if any(not p.startswith(('/usr/lib/', '/System/Library/')) for p in link_libraries):
        raise ValueError('Unexpected non-system native library')
    write_json(output/'runtime-lineage.json', {'schemaVersion': 1, 'productionApproval': 'not_granted',
        'files': lineage, 'nativeDirectLibraries': link_libraries,
        'toolchain': {'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
                     'swift': subprocess.check_output(['xcrun', 'swiftc', '--version'], text=True).strip(),
                     'coremlcompiler': subprocess.check_output(['xcrun', 'coremlcompiler', 'version'], text=True).strip()},
        'historicalDependencyLimit': 'Top-level conversion versions and script/report identities were captured earlier; this current transitive inventory cannot retroactively attest every historical wheel.',
        'path': 'Official pinned safetensors -> fixed first-party Qwen3 conversion -> context1024 FP16 -> per-channel int8 -> Xcode iOS18 compatibility compilation -> native direct-load reference probe',
        'productionRuntime': 'Proposed system Core ML + first-party Swift tokenizer/runtime, no Python or third-party inference library in App.',
        'releaseBuild': 'Not built; exact final App bundle/compiler output hashes require the later release gate.'})
    for framework in ['CoreML', 'Foundation', 'NaturalLanguage', 'Swift']:
        ref = 'echo:system:' + framework
        components.append({'type': 'framework', 'bom-ref': ref, 'name': 'Apple ' + framework,
            'version': 'Xcode 26.5 SDK; deployment proposal iOS 18+',
            'properties': properties(scope='system-provided-runtime', redistribution='not-copied-as-third-party-package',
                                     license='Apple SDK/system terms; approver review required')})
        dependencies.append({'ref': ref, 'dependsOn': []})
    components.append({'type': 'library', 'bom-ref': 'echo:first-party:runtime', 'name': 'Echo Swift generation research runtime',
        'version': '4.0k-native-v1', 'properties': properties(scope='first-party-prototype', sourceIdentity='runtime-lineage.json')})
    dependencies.append({'ref': 'echo:first-party:runtime', 'dependsOn': ['echo:system:' + x for x in ['CoreML', 'Foundation', 'NaturalLanguage', 'Swift']]})
    bom = {'$schema': 'http://cyclonedx.org/schema/bom-1.6.schema.json', 'bomFormat': 'CycloneDX', 'specVersion': '1.6',
           'serialNumber': 'urn:uuid:' + str(uuid.uuid4()), 'version': 1,
           'metadata': {'component': {'type': 'application', 'bom-ref': 'echo:approval-packet', 'name': 'Echo 4.0k candidate approval packet', 'version': '1'},
                        'properties': properties(productionApproval='not-granted', scope='candidate-and-current-research-tool-environment',
                          completeness='Explicit component graph; not a final App SBOM or exhaustive embedded-native third-party decomposition. Preserve package NOTICE texts for nested attributions.')},
           'components': components, 'dependencies': [{'ref': 'echo:approval-packet', 'dependsOn': [c['bom-ref'] for c in components]}] + dependencies,
           'compositions': [{'aggregate': 'incomplete', 'assemblies': ['echo:approval-packet']}]}
    write_json(output/'SBOM.cdx.json', bom)
    resources = [dict(row, destination='Qwen06BContext1024Int8Channel.mlmodelc/' + row['relativePath'])
                 for row in inventory if row['group'] == 'compiled']
    for name in ['tokenizer.json', 'tokenizer_config.json', 'config.json', 'generation_config.json', 'LICENSE']:
        p = MODEL/'source'/name
        resources.append({'path': str(p.relative_to(ROOT)), 'destination': 'Qwen3Tokenizer/' + name,
                          'sizeBytes': p.stat().st_size, 'sha256': digest(p)})
    write_json(output/'candidate-resources.json', {'schemaVersion': 1, 'productionApproval': 'not_granted',
        'scope': 'Exact candidate runtime model/tokenizer/config/license resources before first-party config/NOTICE and final App compilation.',
        'files': resources, 'totalBytes': sum(x['sizeBytes'] for x in resources)})
    print(json.dumps({'output': str(output.relative_to(ROOT)), 'researchToolComponents': len(graph),
                      'sbomComponents': len(components), 'candidateResourceBytes': sum(x['sizeBytes'] for x in resources)}))


if __name__ == '__main__':
    main()
