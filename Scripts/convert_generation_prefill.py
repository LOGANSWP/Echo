#!/usr/bin/env python3
"""Task 4.0k: local batched-prefill experiment; never modifies an App bundle.

Uses the pinned source and INT8 channel settings with FP16 KV, context 1024.
The original artifact approval does not qualify this derived computation graph.
"""
import argparse
import hashlib
import json
from pathlib import Path

import convert_generation_candidate as original


def quantized_identity(model):
    """Compare all compressed tensors by value, independent of blob offsets."""
    from coremltools.converters.mil.frontend.milproto.load import load
    spec = model.get_spec()
    program = load(spec, spec.specificationVersion, file_weights_dir=model.weights_dir)
    return sorted(tuple((name, str(value.val.shape), str(value.val.dtype),
                         hashlib.sha256(value.val.tobytes()).hexdigest())
                        for name, value in op.inputs.items())
                  for op in program.functions['main'].operations
                  if op.op_type == 'constexpr_blockwise_shift_scale')


def build_wrapper(official, context=1024):
    import torch
    import torch.nn.functional as functional
    previous = original.CONTEXT
    original.CONTEXT = context
    try:
        base = original.build_wrapper(official)
    finally:
        original.CONTEXT = previous

    class PrefillQwen(type(base)):
        def repeat_kv(self, tensor):
            return tensor[:, :, None, :, :].expand(
                1, self.kv_heads, self.groups, context, self.head_dim
            ).reshape(1, self.heads, context, self.head_dim)

        def forward(self, token_id, position, valid_count=None):
            hidden = self.embedding(token_id)
            cosine = functional.embedding(position.long(), self.rope_cos).reshape(1, 1, -1, self.head_dim)
            sine = functional.embedding(position.long(), self.rope_sin).reshape(1, 1, -1, self.head_dim)
            write = (position[:, None] == self.cache_positions[None, :]).float()
            if valid_count is not None:
                active = torch.arange(token_id.shape[1]) < valid_count
                write = write * active[:, None].float()
            keep = (1 - write.sum(dim=0)).reshape(1, 1, context, 1).half()
            # Keep the mask tensor-shaped: scalar branches in Core ML select can
            # infer a scalar result even when its condition has flexible shape.
            attention_mask = (self.cache_positions[None, :] > position[:, None]).float() * -10000.
            for index, layer in enumerate(self.layers):
                residual = hidden
                normalized = layer.input_layernorm(hidden)
                attention = layer.self_attn
                query = attention.q_proj(normalized).reshape(1, -1, self.heads, self.head_dim).transpose(1, 2)
                key = attention.k_proj(normalized).reshape(1, -1, self.kv_heads, self.head_dim).transpose(1, 2)
                value = attention.v_proj(normalized).reshape(1, -1, self.kv_heads, self.head_dim).transpose(1, 2)
                query = self.rotate(attention.q_norm(query), cosine, sine)
                key = self.rotate(attention.k_norm(key), cosine, sine)
                key_cache = getattr(self, f'key_cache_{index}')
                value_cache = getattr(self, f'value_cache_{index}')
                key_cache.mul_(keep)
                key_cache.add_(torch.matmul(write.T, key).half())
                value_cache.mul_(keep)
                value_cache.add_(torch.matmul(write.T, value).half())
                scores = torch.matmul(query, self.repeat_kv(key_cache.float()).transpose(2, 3)) * self.head_dim ** -0.5
                probabilities = torch.softmax(scores + attention_mask, dim=-1, dtype=torch.float32)
                attended = torch.matmul(probabilities, self.repeat_kv(value_cache.float())).transpose(1, 2)
                attended = attended.reshape(1, -1, self.heads * self.head_dim)
                hidden = residual + attention.o_proj(attended)
                hidden = hidden + layer.mlp(layer.post_attention_layernorm(hidden))
            selected = hidden[:, -1:, :] if valid_count is None else torch.index_select(hidden, 1, valid_count.long()-1)
            return self.lm_head(self.norm(selected)).reshape(1, -1)

    original.CONTEXT = context
    try:
        return PrefillQwen().eval()
    finally:
        original.CONTEXT = previous


def convert(output, fixed_batch=4):
    import os
    os.environ.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', TOKENIZERS_PARALLELISM='false')
    if output.exists() or output.with_suffix('.evidence.json').exists():
        raise FileExistsError(output)
    import prepare_generation_resources as resources
    resources.prepare(resources.ROOT / 'Echo/Resources/Models/OfflineGeneration.bundle', True)
    inventory = json.loads((resources.PACKET / 'artifact-inventory.json').read_text())
    source_artifact = next(item for item in inventory['artifacts'] if item['group'] == 'source')
    if (resources.ROOT / source_artifact['rootPath'] != original.SOURCE
            or resources.digest(original.SOURCE_MANIFEST) != source_artifact['manifestSHA256']):
        raise ValueError('Source identity differs from the frozen approval packet')
    original.verify_source_identity({})
    import torch
    import numpy as np
    import coremltools as ct
    from transformers import AutoModelForCausalLM
    from coremltools.optimize.coreml import OptimizationConfig, OpLinearQuantizerConfig, linear_quantize_weights
    torch.set_num_threads(4)
    torch.set_grad_enabled(False)
    model = AutoModelForCausalLM.from_pretrained(original.SOURCE, local_files_only=True,
        dtype=torch.float32, attn_implementation='eager').eval()
    wrapper = build_wrapper(model)
    trace_ids = [151644, 8948, 198, 2610][:fixed_batch] if fixed_batch else [151644, 8948]
    trace_args = (torch.tensor([trace_ids], dtype=torch.int32), torch.arange(len(trace_ids), dtype=torch.int32))
    if fixed_batch:
        trace_args += (torch.tensor([fixed_batch], dtype=torch.int32),)
    traced = torch.jit.trace(wrapper, trace_args, check_trace=False)
    wrapper.reset()
    sequence = fixed_batch or ct.RangeDim(lower_bound=1, upper_bound=16, default=1, symbol='sequence')
    inputs = [ct.TensorType(name='token_id', shape=(1, sequence), dtype=np.int32),
              ct.TensorType(name='position', shape=(sequence,), dtype=np.int32)]
    if fixed_batch:
        inputs.append(ct.TensorType(name='valid_count', shape=(1,), dtype=np.int32))
    states = [ct.StateType(wrapped_type=ct.TensorType(shape=tuple(buffer.shape), dtype=np.float16), name=name)
              for name, buffer in wrapper.state_buffers()]
    converted = ct.convert(traced, convert_to='mlprogram', minimum_deployment_target=ct.target.iOS18,
        inputs=inputs, states=states,
        outputs=[ct.TensorType(name='logits', dtype=np.float32)], skip_model_load=True,
        compute_precision=ct.precision.FLOAT16)
    compressed = linear_quantize_weights(converted, OptimizationConfig(global_config=OpLinearQuantizerConfig(
        dtype='int8', mode='linear_symmetric', granularity='per_channel', weight_threshold=2048)))
    import prepare_generation_resources as resources
    import verify_generation_artifact as verifier
    from convert_generation_simulator import promote_rms
    inventory = json.loads((resources.PACKET / 'artifact-inventory.json').read_text())
    artifact = next(item for item in inventory['artifacts'] if item['group'] == 'converted')
    manifest = resources.ROOT / artifact['manifestPath']
    if resources.digest(manifest) != artifact['manifestSHA256']:
        raise ValueError('Pinned conversion manifest changed')
    pinned_path = resources.ROOT / artifact['rootPath']
    verifier.verify_artifact(pinned_path, manifest)
    pinned = ct.models.MLModel(str(pinned_path), skip_model_load=True)
    expected = quantized_identity(pinned)
    if len(expected) != 199 or quantized_identity(compressed) != expected:
        raise ValueError('Prefill conversion changed approved quantized tensors')
    derived, evidence = promote_rms(compressed)
    original.verify_source_identity({})
    derived.save(str(output))
    evidence.update(fixedBatchSize=fixed_batch, quantizedTensorCount=199,
                    quantizedTensorIdentity=hashlib.sha256(repr(expected).encode()).hexdigest())
    output.with_suffix('.evidence.json').write_text(json.dumps(evidence, indent=2)+'\n')
    print('Saved research-only graph', output, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--fixed-batch', type=int, choices=[4], default=4)
    args = parser.parse_args()
    convert(args.output, args.fixed_batch)
