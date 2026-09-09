#!/usr/bin/env python3
"""Task 4.0k / ADR-023: research-only local Core ML structured generation.

Uses synthetic frozen cases, a complete package manifest and pinned tokenizer.
No App integration, automatic quality approval or network. Optional host language
screen permits at most one fresh, full-envelope retry per selected logical call.
Run under an external process deadline; atomic per-case evidence survives timeout.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import time
from pathlib import Path


def validate_context(input_count: int, output_count: int, context: int) -> None:
    if min(input_count, output_count, context) <= 0 or input_count + output_count > context:
        raise ValueError("Full rendered prompt plus reserved output exceeds context")


def decode_request(predict, state, prompt_ids, selector, eos_ids, output_limit, context):
    """Sequential forced prefill and greedy constrained generation, never overlap state."""
    validate_context(len(prompt_ids), output_limit, context)
    prefix = list(prompt_ids)
    for position, token in enumerate(prefix):
        logits = predict(token, position, state)
    generated = []
    for index in range(output_limit):
        token = selector(prefix, logits)
        generated.append(token)
        prefix.append(token)
        if token in eos_ids or index + 1 == output_limit:
            break
        logits = predict(token, len(prefix) - 1, state)
    return generated


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1048576), b''): h.update(block)
    return h.hexdigest()


def prepare_language_retry(tokenizer, case, evaluator):
    messages = evaluator.build_profile_messages(case, 'observations-v1')
    language = 'English' if case['preferredLanguage'] == 'en-US' else 'Simplified Chinese'
    messages[0]['content'] += (
        f' Language validation failed. Regenerate the complete JSON report in {language}. '
        'Each text field must contain natural-language observations, never only identifiers. '
        'Put record IDs only in sourceMemoryIDs. Translate ordinary words into the requested '
        'language. Preserve the same recorded facts and supporting references.'
    )
    kwargs = {'add_generation_prompt': True, 'enable_thinking': False}
    inputs = tokenizer.apply_chat_template(messages, tokenize=True, return_tensors='pt',
                                          return_dict=True, **kwargs)
    return inputs, {'messages': messages,
                    'renderedPrompt': tokenizer.apply_chat_template(messages, tokenize=False, **kwargs),
                    'inputTokens': int(inputs['input_ids'].shape[-1])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('package', 'package-manifest', 'source', 'source-manifest', 'cases', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--context', type=int, required=True)
    parser.add_argument('--language-probe', type=Path)
    parser.add_argument('--probe-source', type=Path)
    parser.add_argument('--case-id', action='append', default=[])
    args = parser.parse_args()
    if bool(args.language_probe) != bool(args.probe_source):
        parser.error('--language-probe and --probe-source must be supplied together')
    os.environ.update({'HF_HUB_OFFLINE':'1', 'TRANSFORMERS_OFFLINE':'1',
                       'HF_HUB_DISABLE_TELEMETRY':'1', 'DO_NOT_TRACK':'1',
                       'TOKENIZERS_PARALLELISM':'false'})
    import evaluate_generation_candidate as evaluator
    import generation_json_grammar as grammar
    import verify_generation_artifact as verifier
    import generation_language_screen as language_screen
    writer = evaluator.AtomicReportWriter(args.output)
    report = {'schemaVersion':1, 'evidenceKind':'research_coreml_generation', 'status':'running',
              'productionApproval':'not_granted', 'formalLanguageGate':'not_evaluated',
              'promptProfile':'observations-v1', 'decodeProfile':'grammar-v1',
              'configuration':{'contextTokens':args.context, 'maxNewTokens':256,
                               'computeUnits':'CPU_AND_GPU', 'modelCompute':'float16',
                               'greedy':True, 'languageRetries':0},
              'results':[], 'evidenceValid':False}
    started = time.monotonic()
    identity_files = [Path(__file__), Path(evaluator.__file__), Path(grammar.__file__),
                      Path(verifier.__file__), args.package_manifest, args.source_manifest, args.cases]
    if args.language_probe:
        identity_files += [args.language_probe, args.probe_source, Path(language_screen.__file__)]
        report['configuration']['languageRetries'] = 1
        report['configuration']['languageScreen'] = 'macOS_NaturalLanguage_paragraph_v1'
    report['configuration']['selectedCaseIDs'] = args.case_id
    identities = {str(p.resolve()):digest(p) for p in identity_files}
    report['fileIdentities']=identities
    writer.save(report)
    try:
        report['packageIntegrity']=verifier.verify_artifact(args.package,args.package_manifest)
        report['sourceIntegrity']=verifier.verify_artifact(args.source,args.source_manifest)
        manifest=json.loads(args.package_manifest.read_text())
        if manifest['configuration']['context'] != args.context:
            raise ValueError('Manifest context differs from requested context')
        cases=evaluator.validate_cases(json.loads(args.cases.read_text()))
        if args.case_id:
            if len(set(args.case_id)) != len(args.case_id) or not set(args.case_id) <= {c['id'] for c in cases}:
                raise ValueError('unknown or duplicate selected case ID')
            cases = [c for c in cases if c['id'] in args.case_id]
        evaluator.validate_profiles('observations-v1','grammar-v1',cases)
        import coremltools as ct
        import numpy as np
        import torch
        import transformers
        from transformers import AutoTokenizer
        torch.set_num_threads(4)
        tokenizer=AutoTokenizer.from_pretrained(str(args.source),local_files_only=True,trust_remote_code=False)
        generation_config=json.loads((args.source/'generation_config.json').read_text())
        eos_ids=generation_config['eos_token_id']
        eos_ids=[eos_ids] if isinstance(eos_ids,int) else eos_ids
        load_start=time.monotonic()
        model=ct.models.MLModel(str(args.package),compute_units=ct.ComputeUnit.CPU_AND_GPU)
        spec=model.get_spec()
        buffers=spec.description.state
        if len(buffers)!=56 or any(list(x.type.stateType.arrayType.shape)!=[1,8,args.context,128] for x in buffers):
            raise ValueError('Unexpected Qwen3 state shapes')
        report['runtime']={'coremltools':ct.__version__,'transformers':transformers.__version__,
                           'torch':torch.__version__,'numpy':np.__version__,
                           'loadSeconds':time.monotonic()-load_start,'hostOnly':True}
        writer.save(report)
        def predict(token,position,state):
            return model.predict({'token_id':np.array([[token]],dtype=np.int32),
                                  'position':np.array([position],dtype=np.int32)},state=state)['logits']
        for case in cases:
            case_start=time.monotonic()
            row={'caseID':case['id'],'preferredLanguage':case['preferredLanguage']}
            processor=None
            try:
                attempts=[]
                def generate(is_retry):
                    nonlocal processor
                    attempt_started=time.monotonic()
                    inputs,prompt=(prepare_language_retry(tokenizer,case,evaluator) if is_retry else
                                   evaluator.prepare_prompt(tokenizer,case,'observations-v1'))
                    ids=inputs['input_ids'][0].tolist()
                    validate_context(len(ids),256,args.context)
                    processor=evaluator.make_decoder('grammar-v1',tokenizer,'qwen3',eos_ids,case,len(ids))
                    def select(prefix,logits):
                        return int(processor(torch.tensor([prefix]),torch.from_numpy(logits.copy())).argmax())
                    generated=decode_request(predict,model.make_state(),ids,select,eos_ids,256,args.context)
                    processor.synchronize(generated)
                    attempt={**prompt,'isLanguageRetry':is_retry,'outputTokens':len(generated),
                             'rawOutput':tokenizer.decode(generated,skip_special_tokens=False),
                             'decodedOutput':tokenizer.decode(generated,skip_special_tokens=True),
                             'stopReason':evaluator.stop_reason(len(generated),generated[-1],eos_ids),
                             'elapsedSeconds':time.monotonic()-attempt_started,**processor.evidence()}
                    attempts.append(attempt)
                    # Persist before language assessment or a second model call can fail.
                    report['activeCase']={'caseID':case['id'],'modelAttempts':attempts}
                    writer.save(report)
                    return attempt['decodedOutput']
                allowed={s['memoryID'] for s in case['sources']}
                if args.language_probe:
                    row['languageAlignment']=language_screen.align_once(generate,lambda raw:
                        language_screen.assess(raw,allowed,case['preferredLanguage'],args.language_probe))
                    row.update({'status':row['languageAlignment']['outcome'],'modelAttempts':attempts})
                    if 'generatedOutput' in row['languageAlignment']:
                        row['decodedOutput']=row['languageAlignment'].pop('generatedOutput')
                else:
                    row['decodedOutput']=generate(False)
                    row.update(attempts[0]);row['status']='generated'
                row['validation']=evaluator.validate_output(row.get('decodedOutput',''),allowed)
            except Exception as error:
                row.update({'status':'rejected','error':str(error)})
                if attempts:
                    row['modelAttempts']=attempts
            if processor: row.update(processor.evidence())
            row['elapsedSeconds']=time.monotonic()-case_start
            report['results'].append(row)
            report.pop('activeCase',None)
            writer.save(report)
            print(case['id'],row['status'],round(row['elapsedSeconds'],2),flush=True)
        report['status']='completed'
    except Exception as error:
        report.update({'status':'failed','error':str(error)})
        raise
    finally:
        report['elapsedSeconds']=time.monotonic()-started
        try:
            report['postPackageIntegrity']=verifier.verify_artifact(args.package,args.package_manifest)
            report['postSourceIntegrity']=verifier.verify_artifact(args.source,args.source_manifest)
            unchanged=all(digest(Path(p))==h for p,h in identities.items())
            report['evidenceValid']=report['status']=='completed' and unchanged
            report['identityUnchanged']=unchanged
        except Exception as error:
            report['evidenceValid']=False;report['identityError']=str(error)
        writer.save(report)


if __name__ == '__main__':
    main()
