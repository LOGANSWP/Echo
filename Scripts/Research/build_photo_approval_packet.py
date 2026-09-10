#!/usr/bin/env python3
"""4.0l: assemble an unapproved, reviewable model/resource and legal packet.

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
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from generation_approval_inventory import dependency_graph, is_license_document
from verify_generation_artifact import verify_artifact

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT/'PinnedModels/offline-generation-evaluation'
PHOTO = ROOT/'PinnedModels/photo-understanding-evaluation/smolvlm-256m'
MODEL = PHOTO
REVISION = '7e3e67edbbed1bf9888184d9df282b700a323964'


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
    output.mkdir(exist_ok=True)
    legal_dir = output/'licenses'
    legal_dir.mkdir(exist_ok=True)
    components, dependencies, legal_records = [], [], []
    roots = ['coremltools', 'torch', 'transformers[chat-template]', 'tokenizers', 'safetensors', 'numpy', 'regex', 'pillow', 'psutil']
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
    from run_photo_functional_probe import verify
    verify()
    compiled = json.loads((ROOT/'docs/05-planning/4.0l-compiled-models.json').read_text())
    source = json.loads((ROOT/'docs/05-planning/4.0l-source-verification.json').read_text())
    converted = json.loads((ROOT/'docs/05-planning/4.0l-coreml-conversion-2.json').read_text())
    inventory = [dict(row, group='compiled') for row in compiled['files']]
    inventory += [dict(row, path=str((PHOTO/'source'/row['path']).relative_to(ROOT)), group='source') for row in source['files']]
    for package in converted['packages']:
        inventory += [dict(row, path=str((PHOTO/'conversion-2'/(package['name']+'.mlpackage')/row['path']).relative_to(ROOT)), group='converted') for row in package['files']]
    write_json(output/'artifact-inventory.json', {'productionApproval':'pending','files':inventory})
    resources = [dict(row, destination=str(Path(row['path']).relative_to(PHOTO.relative_to(ROOT)/'compiled-v1'))) for row in compiled['files']]
    for name in ['tokenizer.json','tokenizer_config.json','config.json','preprocessor_config.json','processor_config.json','generation_config.json','chat_template.json']:
        path=PHOTO/'source'/name
        resources.append({'path':str(path.relative_to(ROOT)), 'destination':'SmolVLMTokenizer/'+name,'sizeBytes':path.stat().st_size,'sha256':digest(path)})
    for name in ['Apache-2.0.txt','SmolVLM-256M-README.md']:
        path=legal_dir/name
        resources.append({'path':str(path.relative_to(ROOT)),'destination':'SmolVLMLegal/'+name,'sizeBytes':path.stat().st_size,'sha256':digest(path)})
    write_json(output/'candidate-resources.json', {'productionApproval':'pending','files':resources,'totalBytes':sum(r['sizeBytes'] for r in resources)})
    swift_names=['PhotoTokenizer.swift','PhotoImagePreprocessor.swift','PhotoFunctionalProbe.swift','GenerationMemory.swift','PhotoImageProbe.swift','PhotoTokenizerProbe.swift']
    paths=[ROOT/'Scripts/Research'/name for name in swift_names+['convert_photo_research.py','run_photo_functional_probe.py','photo_generation_bridge.py','build_photo_approval_packet.py']]
    paths.append(PHOTO/'photo-functional-probe')
    libs=subprocess.check_output(['otool','-L',str(PHOTO/'photo-functional-probe')],text=True)
    links=[line.strip().split(' (')[0] for line in libs.splitlines()[1:]]
    assert all(link.startswith(('/usr/lib/','/System/Library/')) for link in links)
    write_json(output/'runtime-lineage.json',{'files':[{'path':str(p.relative_to(ROOT)),'sizeBytes':p.stat().st_size,'sha256':digest(p)} for p in paths],
        'nativeLibraries':links,'toolchain':{'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),'swift':subprocess.check_output(['xcrun','swiftc','--version'],text=True).strip()},
        'scope':'Pinned source to two FP16 Core ML graphs to iOS18 compiled models; first-party Swift ImageIO/ByteLevel/stateful decoder prototype. Production adapters and final App SBOM remain to be built.'})
    for name in ['CoreML','Foundation','ImageIO','CoreGraphics','CryptoKit','UniformTypeIdentifiers','Swift']:
        ref='echo:system:'+name
        components.append({'type':'framework','bom-ref':ref,'name':'Apple '+name,'version':'Xcode 26.5 SDK; iOS 18 target', 'properties':properties(scope='system-provided-runtime')})
        dependencies.append({'ref':ref,'dependsOn':[]})
    for group in ['source','converted','compiled']:
        ref='echo:smolvlm-256m:'+group
        components.append({'type':'machine-learning-model','bom-ref':ref,'name':'SmolVLM-256M '+group,'version':REVISION,
            'licenses':[{'license':{'id':'Apache-2.0'}}],'properties':properties(scope='candidate-pending-approval',inventory='artifact-inventory.json',licenseClaim='upstream declaration; human disposition pending')})
        dependencies.append({'ref':ref,'dependsOn':[] if group=='source' else ['echo:smolvlm-256m:'+('source' if group=='converted' else 'converted')]})
    ref='echo:first-party:photo-runtime'
    components.append({'type':'library','bom-ref':ref,'name':'Echo Swift photo-understanding research runtime','version':'4.0l-native-v1','properties':properties(sourceIdentity='runtime-lineage.json')})
    dependencies.append({'ref':ref,'dependsOn':['echo:system:'+name for name in ['CoreML','Foundation','ImageIO','CoreGraphics','CryptoKit','UniformTypeIdentifiers','Swift']]})
    bom={'$schema':'http://cyclonedx.org/schema/bom-1.6.schema.json','bomFormat':'CycloneDX','specVersion':'1.6','version':1,'serialNumber':'urn:uuid:'+str(uuid.uuid4()),
        'metadata':{'component':{'type':'application','bom-ref':'echo:photo-packet','name':'Echo 4.0l candidate packet','version':'1'},'properties':properties(scope='candidate and current research dependencies; not final App SBOM',approval='pending')},
        'components':components,'dependencies':[{'ref':'echo:photo-packet','dependsOn':[c['bom-ref'] for c in components]}]+dependencies,
        'compositions':[{'aggregate':'incomplete','assemblies':['echo:photo-packet']}]}
    write_json(output/'SBOM.cdx.json',bom)
    write_json(output/'approval.json',{'status':'pending','approvedBy':None,'approvedAt':None,'userInstruction':None,'packetManifestSha256':None,
        'scope':'Local App engineering integration of this exact candidate under the functional-first plan; no distribution, release, signing change or final qualification approval.'})
    print(json.dumps({'toolComponents':len(graph),'allComponents':len(components),'candidateResourceBytes':sum(r['sizeBytes'] for r in resources)}))

if __name__=='__main__':
    main()
