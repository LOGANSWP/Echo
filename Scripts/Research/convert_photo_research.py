#!/usr/bin/env python3
"""Task 4.0l: fixed SmolVLM vision and stateful decoder research, outside the App.

ADR-025 functional-first research. Oracle: pinned local Transformers implementation.
No quality qualification, personal images, model downloads or production approval.
"""

import argparse
import gc
import hashlib
import json
import os
import shutil
import time
import traceback
from pathlib import Path

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
os.environ['TOKENIZERS_PARALLELISM'] = 'false'

from photo_understanding_probe import ROOT, SOURCE, make_case, verify_source

BASE = SOURCE.parent
OUTPUT = BASE / 'conversion'
CONTEXT = 1024


def digest(path):
    sha = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            sha.update(chunk)
    return sha.hexdigest()


def numerical(actual, expected):
    import numpy as np
    a, b = (np.asarray(v, dtype=np.float64).reshape(-1) for v in (actual, expected))
    assert a.shape == b.shape and np.isfinite(a).all() and np.isfinite(b).all()
    return {'maxAbs': float(np.abs(a-b).max()), 'rmse': float(np.sqrt(np.mean((a-b)**2))),
            'cosine': float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))),
            'actualTop1': int(a.argmax()), 'referenceTop1': int(b.argmax())}


def wrappers(official):
    import torch
    from torch import nn
    from torch.nn import functional as f

    class Vision(nn.Module):
        def __init__(self):
            super().__init__()
            self.vision = official.model.vision_model
            self.connector = official.model.connector

        def forward(self, pixels, position_ids, attention_mask):
            hidden = self.vision.embeddings.patch_embedding(pixels).flatten(2).transpose(1, 2)
            hidden = hidden + self.vision.embeddings.position_embedding(position_ids)
            for layer in self.vision.encoder.layers:
                hidden = layer(hidden, attention_mask)
            return self.connector(self.vision.post_layernorm(hidden))

    class Decoder(nn.Module):
        def __init__(self):
            super().__init__()
            text = official.model.text_model
            self.embedding, self.layers, self.norm = text.embed_tokens, text.layers, text.norm
            self.lm_head = official.lm_head
            cfg = text.config
            assert (cfg.hidden_size, cfg.num_attention_heads, cfg.num_key_value_heads,
                    cfg.num_hidden_layers, cfg.head_dim, cfg.rope_parameters['rope_theta']) == (576, 9, 3, 30, 64, 100000)
            assert cfg.rope_parameters['rope_type'] == 'default'
            frequency = text.rotary_emb.inv_freq.clone()
            angles = torch.arange(CONTEXT).float()[:, None] * frequency[None, :]
            angles = torch.cat((angles, angles), dim=-1)
            self.register_buffer('rope_cos', angles.cos())
            self.register_buffer('rope_sin', angles.sin())
            self.register_buffer('positions', torch.arange(CONTEXT, dtype=torch.int32))
            for i in range(30):
                for name in ('key', 'value'):
                    self.register_buffer(f'{name}_cache_{i}', torch.zeros(1, 3, CONTEXT, 64).half())

        def states(self):
            return [(n, b) for n, b in self.named_buffers() if n.startswith(('key_cache_', 'value_cache_'))]

        def reset(self):
            for _, b in self.states():
                b.zero_()

        def rotate(self, value, cosine, sine):
            return value * cosine + torch.cat((-value[..., 32:], value[..., :32]), dim=-1) * sine

        def repeat(self, value):
            return value[:, :, None, :, :].expand(1, 3, 3, CONTEXT, 64).reshape(1, 9, CONTEXT, 64)

        def forward(self, token_id, position, image_embedding):
            hidden = torch.where((token_id == 49190).reshape(1, 1, 1), image_embedding, self.embedding(token_id))
            cosine = f.embedding(position.long(), self.rope_cos).reshape(1, 1, 1, 64)
            sine = f.embedding(position.long(), self.rope_sin).reshape(1, 1, 1, 64)
            write = (self.positions == position).reshape(1, 1, CONTEXT, 1).half()
            keep = 1 - write
            mask = torch.where(self.positions <= position, 0., -10000.).reshape(1, 1, 1, CONTEXT)
            for i, layer in enumerate(self.layers):
                residual = hidden
                normalized = layer.input_layernorm(hidden)
                attn = layer.self_attn
                q = attn.q_proj(normalized).reshape(1, 1, 9, 64).transpose(1, 2)
                k = attn.k_proj(normalized).reshape(1, 1, 3, 64).transpose(1, 2)
                v = attn.v_proj(normalized).reshape(1, 1, 3, 64).transpose(1, 2)
                q, k = self.rotate(q, cosine, sine), self.rotate(k, cosine, sine)
                keys, values = getattr(self, f'key_cache_{i}'), getattr(self, f'value_cache_{i}')
                keys.mul_(keep).add_(k.half() * write)
                values.mul_(keep).add_(v.half() * write)
                scores = torch.matmul(q, self.repeat(keys.float()).transpose(2, 3)) * (64 ** -0.5)
                probs = torch.softmax(scores + mask, dim=-1, dtype=torch.float32)
                attended = torch.matmul(probs, self.repeat(values.float())).transpose(1, 2).reshape(1, 1, 576)
                hidden = residual + attn.o_proj(attended)
                hidden = hidden + layer.mlp(layer.post_attention_layernorm(hidden))
            return self.lm_head(self.norm(hidden)).reshape(1, 49280)

    return Vision().eval(), Decoder().eval()


def convert(report, save):
    import numpy as np
    import torch
    import coremltools as ct
    import transformers
    from transformers import AutoModelForImageTextToText, AutoProcessor

    report['tools'] = {'torch': torch.__version__, 'transformers': transformers.__version__, 'coremltools': ct.__version__}
    torch.set_num_threads(4)
    torch.set_grad_enabled(False)
    official = AutoModelForImageTextToText.from_pretrained(
        str(SOURCE), local_files_only=True, trust_remote_code=False, dtype=torch.float32, attn_implementation='eager').eval()
    processor = AutoProcessor.from_pretrained(str(SOURCE), local_files_only=True, trust_remote_code=False)
    vision, decoder = wrappers(official)
    positions = torch.arange(1024, dtype=torch.int32).reshape(1, 1024)
    mask = torch.zeros(1, 1, 1, 1024)
    oracle_arrays, cases = {}, []
    for index in (0, 1):
        picture, fact = make_case(index)
        message = [{'role': 'user', 'content': [{'type': 'image'}, {'type': 'text', 'text': 'Describe this image in one short sentence.'}]}]
        prompt = processor.apply_chat_template(message, add_generation_prompt=True, tokenize=False)
        batch = processor(text=prompt, images=[picture], return_tensors='pt', do_image_splitting=False,
                          size={'longest_edge': 512})
        assert batch.pixel_values.shape == (1, 1, 3, 512, 512)
        assert batch.pixel_attention_mask.all()
        pixels = batch.pixel_values[:, 0].float()
        reference_visual = official.model.connector(official.model.vision_model(pixels).last_hidden_state)
        visual = vision(pixels, positions, mask)
        comparison = numerical(visual.numpy(), reference_visual.numpy())
        assert comparison['maxAbs'] < 0.0001, comparison
        ids = batch.input_ids[0].tolist()
        assert ids.count(49190) == 64 and len(ids) <= 768
        case = {'id': index, 'pixelSha256': hashlib.sha256(picture.tobytes()).hexdigest(), 'expectedVisible': fact,
                'prompt': prompt, 'promptTokens': len(ids), 'inputIds': list(ids), 'visionTorch': comparison,
                'comparisons': [], 'consumedIds': list(ids)}
        decoder.reset()
        image_index = 0
        zero = torch.zeros(1, 1, 576)
        for pos, token in enumerate(ids):
            embed = visual[:, image_index:image_index+1] if token == 49190 else zero
            if token == 49190:
                image_index += 1
            predicted = decoder(torch.tensor([[token]], dtype=torch.int32), torch.tensor([pos], dtype=torch.int32), embed)
        for step in range(4):
            output = official(input_ids=torch.tensor([ids]), pixel_values=batch.pixel_values,
                              pixel_attention_mask=batch.pixel_attention_mask, use_cache=False, logits_to_keep=1)
            reference = output.logits[:, -1, :].numpy()
            comparison = numerical(predicted.numpy(), reference)
            assert comparison['cosine'] > 0.99999 and comparison['rmse'] < 0.01, comparison
            assert comparison['actualTop1'] == comparison['referenceTop1'], comparison
            key = f'case{index}_step{step}'
            oracle_arrays[key] = reference.copy()
            case['comparisons'].append({'step': step, 'position': len(ids)-1, 'referenceKey': key, **comparison})
            if step < 3:
                token = int(reference.argmax())
                ids.append(token)
                case['consumedIds'].append(token)
                predicted = decoder(torch.tensor([[token]], dtype=torch.int32), torch.tensor([len(ids)-1], dtype=torch.int32), zero)
        # No pixel or image files: retain compact numerical oracle features and logits only.
        oracle_arrays[f'case{index}_vision'] = reference_visual.numpy()
        case['oraclePrefix'] = processor.tokenizer.decode(ids[case['promptTokens']:])
        cases.append(case)
        print('reference parity ' + json.dumps(case['comparisons'][-1]), flush=True)
    report['cases'], report['torchParityPassed'] = cases, True
    np.savez(OUTPUT / 'oracle.npz', **oracle_arrays)
    save()
    for name, module, example, inputs, outputs, states in (
        ('SmolVision512', vision, (pixels, positions, mask),
         [ct.TensorType(name='pixels', shape=(1, 3, 512, 512), dtype=np.float32),
          ct.TensorType(name='position_ids', shape=(1, 1024), dtype=np.int32),
          ct.TensorType(name='attention_mask', shape=(1, 1, 1, 1024), dtype=np.float32)],
         [ct.TensorType(name='image_embeddings', dtype=np.float32)], []),
        ('SmolDecoder1024', decoder,
         (torch.tensor([[1]], dtype=torch.int32), torch.tensor([0], dtype=torch.int32), zero),
         [ct.TensorType(name='token_id', shape=(1, 1), dtype=np.int32),
          ct.TensorType(name='position', shape=(1,), dtype=np.int32),
          ct.TensorType(name='image_embedding', shape=(1, 1, 576), dtype=np.float32)],
         [ct.TensorType(name='logits', dtype=np.float32)],
         [ct.StateType(name=n, wrapped_type=ct.TensorType(shape=tuple(b.shape), dtype=np.float16)) for n, b in decoder.states()])):
        started = time.monotonic()
        decoder.reset()
        print('converting ' + name, flush=True)
        traced = torch.jit.trace(module, example, check_trace=False)
        decoder.reset()
        model = ct.convert(traced, convert_to='mlprogram', minimum_deployment_target=ct.target.iOS18,
                           inputs=inputs, outputs=outputs, states=states, compute_precision=ct.precision.FLOAT16,
                           skip_model_load=True)
        model.user_defined_metadata['researchOnly'] = 'true'
        model.user_defined_metadata['productionApproval'] = 'pending'
        model.user_defined_metadata['sourceRevision'] = report['source']['revision']
        package = OUTPUT / (name + '.mlpackage')
        model.save(str(package))
        report.setdefault('packages', []).append({'name': name, 'elapsedSeconds': time.monotonic()-started,
            'files': [{'path': str(p.relative_to(package)), 'sizeBytes': p.stat().st_size, 'sha256': digest(p)}
                      for p in sorted(package.rglob('*')) if p.is_file()]})
        save()
        del traced, model
        gc.collect()


def main():
    global OUTPUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--attempt', type=int, default=1, choices=range(1, 10))
    attempt = parser.parse_args().attempt
    suffix = '' if attempt == 1 else f'-{attempt}'
    OUTPUT = BASE / ('conversion' + suffix)
    source = verify_source()
    if OUTPUT.exists():
        raise FileExistsError('Refusing to overwrite a previous conversion')
    if shutil.disk_usage(ROOT).free < 20_000_000_000:
        raise RuntimeError('Free-space reserve unavailable')
    OUTPUT.mkdir()
    scratch = OUTPUT / 'scratch'
    scratch.mkdir()
    os.environ['TMPDIR'] = str(scratch)
    report_path = ROOT / f'docs/05-planning/4.0l-coreml-conversion{suffix}.json'
    if report_path.exists():
        raise FileExistsError('Conversion report already exists')
    report = {'taskId': '4.0l', 'researchOnly': True, 'productionApproval': 'pending',
              'source': {'revision': source['revision'], 'manifestSha256': digest(ROOT / 'docs/05-planning/4.0l-source-verification.json')},
              'converterSha256': digest(Path(__file__)), 'startedAtUnix': time.time(),
              'context': CONTEXT, 'imageTokens': 64, 'kvBytes': 23592960,
              'scope': 'Two controlled square in-memory images; numerical execution parity, not description precision or iOS acceptance'}
    def save():
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    save()
    try:
        convert(report, save)
        report['status'] = 'converted_pending_native_execution'
    except Exception:
        report['status'] = 'failed'
        report['error'] = traceback.format_exc()
        raise
    finally:
        report['endedAtUnix'] = time.time()
        save()


if __name__ == '__main__':
    main()
