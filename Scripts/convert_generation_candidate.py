#!/usr/bin/env python3
"""Research-only Qwen3-0.6B iOS 18 stateful Core ML smoke conversion.

Spec: ADR-023; task 4.0k. This does not approve a model or modify an App bundle.
One configuration: context 128, batch/sequence 1, FP16 KV, FP16 Core ML compute.
Prefill deliberately consumes one token per call; this is not a throughput test.
The official local Transformers implementation is the numerical oracle.
"""

import argparse
import gc
import hashlib
import json
import os
import platform
import sys
import time
import traceback
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "PinnedModels/offline-generation-evaluation/qwen3-0.6b"
SOURCE = BASE / "source"
OUTPUT = BASE / "conversion"
PACKAGE = OUTPUT / "Qwen06BContext128Stateful.mlpackage"
SOURCE_MANIFEST = ROOT / "docs/05-planning/4.0k-qwen3-source-manifest.json"
REPOSITORY = "Qwen/Qwen3-0.6B"
REVISION = "c1899de289a04d12100db370d81485cdf75e47ca"
CONTEXT = 128
STEPS = 3
# Fixed before execution; numerical smoke limits are not production quality gates.
LIMITS = {
    "torch_vs_official": {"max_abs": 0.03, "rmse": 0.005, "cosine_min": 0.99999},
    "coreml_vs_official": {"max_abs": 0.20, "rmse": 0.03, "cosine_min": 0.9999},
}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def log(message):
    print(message, flush=True)


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def verify_source_identity(report):
    """Bind the fixed candidate identity to an external complete-file manifest."""
    import verify_generation_artifact

    report["converter_sha256"] = digest(Path(__file__).resolve())
    report["source_manifest_path"] = str(SOURCE_MANIFEST)
    report["source_integrity"] = {
        "scope": "file-integrity-only", "approvalGranted": False, "passed": False}
    try:
        manifest_bytes = SOURCE_MANIFEST.read_bytes()
        manifest_hash = hashlib.sha256(manifest_bytes).hexdigest()
        report["source_manifest_sha256"] = manifest_hash
        document = json.loads(manifest_bytes)
        if (not isinstance(document, dict) or document.get("repository") != REPOSITORY
                or document.get("revision") != REVISION):
            raise verify_generation_artifact.IntegrityError(
                "Manifest repository/revision does not match the fixed Qwen3-0.6B candidate")
        result = verify_generation_artifact.verify_artifact(SOURCE, SOURCE_MANIFEST)
        if digest(SOURCE_MANIFEST) != manifest_hash:
            raise verify_generation_artifact.IntegrityError("Source manifest changed during verification")
        if result.get("passed") is not True:
            raise verify_generation_artifact.IntegrityError("Source integrity verification did not pass")
        report["source_integrity"] = result
        report["source_repository"] = document["repository"]
        report["source_revision"] = document["revision"]
        # These are verified manifest values, never freshly re-baselined source hashes.
        report["source_files"] = [{"path": entry["path"], "bytes": entry["sizeBytes"],
                                   "sha256": entry["sha256"]} for entry in document["files"]]
    except Exception as error:
        report["source_integrity"]["error"] = str(error)
        raise


def metrics(actual, expected, limits):
    import numpy as np
    left = np.asarray(actual, dtype=np.float64).reshape(-1)
    right = np.asarray(expected, dtype=np.float64).reshape(-1)
    if left.shape != right.shape or not np.isfinite(left).all() or not np.isfinite(right).all():
        return {"passed": False, "error": "shape mismatch or non-finite logits"}
    delta = left - right
    result = {
        "max_abs": float(np.max(np.abs(delta))),
        "rmse": float(np.sqrt(np.mean(delta * delta))),
        "cosine": float(np.dot(left, right) / (np.linalg.norm(left) * np.linalg.norm(right))),
        "actual_top1": int(left.argmax()),
        "expected_top1": int(right.argmax()),
    }
    result["top1_equal"] = result["actual_top1"] == result["expected_top1"]
    result["passed"] = bool(result["max_abs"] <= limits["max_abs"]
                            and result["rmse"] <= limits["rmse"]
                            and result["cosine"] >= limits["cosine_min"]
                            and result["top1_equal"])
    return result


def build_wrapper(official):
    import torch
    import torch.nn.functional as functional
    from torch import nn

    class SingleTokenStatefulQwen(nn.Module):
        """Fixed-context causal GQA; no sliding window or altered RoPE scheme."""

        def __init__(self):
            super().__init__()
            cfg = official.config
            self.hidden = cfg.hidden_size
            self.heads = cfg.num_attention_heads
            self.kv_heads = cfg.num_key_value_heads
            self.head_dim = cfg.head_dim
            self.groups = self.heads // self.kv_heads
            # Reuse loaded modules and the same tied embedding parameter.
            self.embedding = official.model.embed_tokens
            self.layers = official.model.layers
            self.norm = official.model.norm
            self.lm_head = official.lm_head
            positions = torch.arange(CONTEXT, dtype=torch.float32)
            frequency = 1.0 / (cfg.rope_theta ** (
                torch.arange(0, self.head_dim, 2, dtype=torch.float32) / self.head_dim))
            angles = positions[:, None] * frequency[None, :]
            angles = torch.cat((angles, angles), dim=-1)
            self.register_buffer("rope_cos", torch.cos(angles))
            self.register_buffer("rope_sin", torch.sin(angles))
            self.register_buffer("cache_positions", torch.arange(CONTEXT, dtype=torch.int32))
            for index in range(len(self.layers)):
                for prefix in ("key", "value"):
                    self.register_buffer(f"{prefix}_cache_{index}", torch.zeros(
                        (1, self.kv_heads, CONTEXT, self.head_dim), dtype=torch.float16))

        def state_buffers(self):
            return [(name, buffer) for name, buffer in self.named_buffers()
                    if name.startswith(("key_cache_", "value_cache_"))]

        def reset(self):
            for _, buffer in self.state_buffers():
                buffer.zero_()

        def rotate(self, tensor, cosine, sine):
            half = self.head_dim // 2
            rotated = torch.cat((-tensor[..., half:], tensor[..., :half]), dim=-1)
            return tensor * cosine + rotated * sine

        def repeat_kv(self, tensor):
            return tensor[:, :, None, :, :].expand(
                1, self.kv_heads, self.groups, CONTEXT, self.head_dim
            ).reshape(1, self.heads, CONTEXT, self.head_dim)

        def forward(self, token_id, position):
            # The caller enforces monotonic positions and 0 <= position < 128.
            hidden = self.embedding(token_id)
            cosine = functional.embedding(position.to(torch.int64), self.rope_cos).reshape(
                1, 1, 1, self.head_dim)
            sine = functional.embedding(position.to(torch.int64), self.rope_sin).reshape(
                1, 1, 1, self.head_dim)
            write_mask = (self.cache_positions == position).reshape(1, 1, CONTEXT, 1).half()
            keep_mask = 1.0 - write_mask
            # -1e4 is finite in FP16 and underflows masked softmax probabilities to zero.
            attention_mask = torch.where(self.cache_positions <= position, 0.0, -10000.0)
            attention_mask = attention_mask.reshape(1, 1, 1, CONTEXT)
            for index, layer in enumerate(self.layers):
                residual = hidden
                normalized = layer.input_layernorm(hidden)
                attention = layer.self_attn
                query = attention.q_proj(normalized).reshape(
                    1, 1, self.heads, self.head_dim).transpose(1, 2)
                key = attention.k_proj(normalized).reshape(
                    1, 1, self.kv_heads, self.head_dim).transpose(1, 2)
                value = attention.v_proj(normalized).reshape(
                    1, 1, self.kv_heads, self.head_dim).transpose(1, 2)
                query = attention.q_norm(query)
                key = attention.k_norm(key)
                query = self.rotate(query, cosine, sine)
                key = self.rotate(key, cosine, sine)
                key_cache = getattr(self, f"key_cache_{index}")
                value_cache = getattr(self, f"value_cache_{index}")
                # Explicit buffer mutation is translated to Core ML StateType updates.
                key_cache.mul_(keep_mask)
                key_cache.add_(key.half() * write_mask)
                value_cache.mul_(keep_mask)
                value_cache.add_(value.half() * write_mask)
                keys = self.repeat_kv(key_cache.float())
                values = self.repeat_kv(value_cache.float())
                scores = torch.matmul(query, keys.transpose(2, 3)) * (self.head_dim ** -0.5)
                probabilities = torch.softmax(scores + attention_mask, dim=-1, dtype=torch.float32)
                attended = torch.matmul(probabilities, values).transpose(1, 2).reshape(1, 1, self.heads * self.head_dim)
                hidden = residual + attention.o_proj(attended)
                hidden = hidden + layer.mlp(layer.post_attention_layernorm(hidden))
            return self.lm_head(self.norm(hidden)).reshape(1, -1)

    return SingleTokenStatefulQwen().eval()


def convert(report, report_path):
    if PACKAGE.exists():
        raise FileExistsError(f"Refusing to overwrite existing package: {PACKAGE}")
    # Fail closed before importing any ML framework or loading model weights.
    try:
        verify_source_identity(report)
    finally:
        write_json(report_path, report)

    import coremltools as ct
    import numpy as np
    import torch
    import transformers
    from transformers import AutoModelForCausalLM, AutoTokenizer

    torch.set_num_threads(4)
    torch.set_grad_enabled(False)
    configuration = json.loads((SOURCE / "config.json").read_text())
    required = {"model_type": "qwen3", "hidden_size": 1024, "num_hidden_layers": 28,
                "num_attention_heads": 16, "num_key_value_heads": 8,
                "head_dim": 128, "intermediate_size": 3072, "attention_bias": False,
                "vocab_size": 151936, "rope_theta": 1000000.0,
                "tie_word_embeddings": True, "use_sliding_window": False}
    for key, expected in required.items():
        if configuration.get(key) != expected:
            raise ValueError(f"Unsupported configuration {key}: {configuration.get(key)}")
    if configuration.get("rope_scaling") is not None:
        raise ValueError("Only the pinned model's default RoPE is supported")
    report["tool_versions"] = {"torch": torch.__version__, "transformers": transformers.__version__,
                               "coremltools": ct.__version__, "numpy": np.__version__}
    write_json(report_path, report)
    log("Loading only the pinned local checkpoint in FP32 for oracle and shared-weight wrapper")
    started = time.monotonic()
    official = AutoModelForCausalLM.from_pretrained(
        str(SOURCE), local_files_only=True, trust_remote_code=False,
        use_safetensors=True, dtype=torch.float32, attn_implementation="eager").eval()
    if official.lm_head.weight.data_ptr() != official.model.embed_tokens.weight.data_ptr():
        raise ValueError("Pinned tied embedding was not preserved")
    tokenizer = AutoTokenizer.from_pretrained(str(SOURCE), local_files_only=True, trust_remote_code=False)
    wrapper = build_wrapper(official)
    report["load_seconds"] = time.monotonic() - started
    report["state_count"] = len(wrapper.state_buffers())
    report["state_bytes"] = sum(t.numel() * t.element_size() for _, t in wrapper.state_buffers())
    cases = []
    reference_logits = {}
    for case_index, prompt in enumerate(("Complete briefly: The sky is", "请简短回答：天空是什么颜色？")):
        ids = tokenizer.apply_chat_template([{"role": "user", "content": prompt}],
                                            tokenize=True, add_generation_prompt=True, enable_thinking=False)
        if len(ids) + STEPS >= CONTEXT:
            raise ValueError("Smoke prompt exceeds the fixed context")
        wrapper.reset()
        case = {"id": f"smoke-{case_index + 1}", "prompt": prompt, "prompt_tokens": len(ids),
                "consumed_token_ids": list(ids), "comparisons": []}
        custom = None
        for position, token in enumerate(ids):
            custom = wrapper(torch.tensor([[token]], dtype=torch.int32),
                             torch.tensor([position], dtype=torch.int32)).float().numpy()
        for step in range(STEPS + 1):
            oracle = official(input_ids=torch.tensor([ids]), use_cache=False, logits_to_keep=1)
            expected = oracle.logits[:, -1, :].float().numpy()
            key = f"case{case_index}_step{step}"
            reference_logits[key] = expected.copy()
            comparison = metrics(custom, expected, LIMITS["torch_vs_official"])
            comparison.update({"step": step, "position": len(ids) - 1, "reference_key": key})
            case["comparisons"].append(comparison)
            log(f"Torch {case['id']} step {step}: {comparison}")
            if step < STEPS:
                token = int(expected.argmax())
                ids.append(token)
                case["consumed_token_ids"].append(token)
                custom = wrapper(torch.tensor([[token]], dtype=torch.int32),
                                 torch.tensor([len(ids) - 1], dtype=torch.int32)).float().numpy()
        case["oracle_generated_text"] = tokenizer.decode(ids[case["prompt_tokens"]:])
        cases.append(case)
    report["torch_cases"] = cases
    report["torch_numerical_pass"] = all(c["passed"] for case in cases for c in case["comparisons"])
    np.savez(OUTPUT / "oracle_logits.npz", **reference_logits)
    write_json(report_path, report)
    if not report["torch_numerical_pass"]:
        raise RuntimeError("Custom Torch stateful graph failed fixed official-model parity limits")
    wrapper.reset()
    log(f"Tracing one-token graph with all {len(wrapper.state_buffers())} FP16 KV buffers")
    traced = torch.jit.trace(wrapper, (torch.tensor([[151644]], dtype=torch.int32),
                                     torch.tensor([0], dtype=torch.int32)), check_trace=False)
    wrapper.reset()
    states = [ct.StateType(wrapped_type=ct.TensorType(shape=tuple(buffer.shape), dtype=np.float16), name=name)
              for name, buffer in wrapper.state_buffers()]
    started = time.monotonic()
    log("Converting research-only iOS18 MLProgram, FP16 compute, skip_model_load=True")
    model = ct.convert(traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
                       inputs=[ct.TensorType(name="token_id", shape=(1, 1), dtype=np.int32),
                               ct.TensorType(name="position", shape=(1,), dtype=np.int32)],
                       states=states, outputs=[ct.TensorType(name="logits", dtype=np.float32)],
                       compute_precision=ct.precision.FLOAT16, skip_model_load=True)
    model.short_description = "Unapproved 4.0k research smoke: Qwen0.6B, context128, single-token stateful"
    model.user_defined_metadata["researchOnly"] = "true"
    model.user_defined_metadata["sourceRevision"] = REVISION
    model.user_defined_metadata["minimumTarget"] = "iOS18"
    model.user_defined_metadata["productionApproval"] = "pending"
    model.save(str(PACKAGE))
    report["conversion_seconds"] = time.monotonic() - started
    report["conversion_status"] = "converted_not_device_qualified"
    report["package_files"] = [{"path": str(p.relative_to(PACKAGE)), "bytes": p.stat().st_size,
                                "sha256": digest(p)} for p in sorted(PACKAGE.rglob("*")) if p.is_file()]
    write_json(report_path, report)
    del model, traced, wrapper, official, tokenizer, reference_logits
    gc.collect()


def predict(report, report_path):
    import coremltools as ct
    import numpy as np

    if not PACKAGE.exists() or not report.get("torch_numerical_pass"):
        raise RuntimeError("A converted package and passing Torch oracle comparison are required")
    reference = np.load(OUTPUT / "oracle_logits.npz", allow_pickle=False)
    log("Loading research package on host Mac with CPU_AND_GPU; this is not iPhone evidence")
    started = time.monotonic()
    model = ct.models.MLModel(str(PACKAGE), compute_units=ct.ComputeUnit.CPU_AND_GPU)
    report["host_load_seconds"] = time.monotonic() - started
    results = []
    for case in report["torch_cases"]:
        state = model.make_state()
        by_position = {entry["position"]: entry for entry in case["comparisons"]}
        row = {"id": case["id"], "comparisons": [], "predictions": 0}
        started = time.monotonic()
        for position, token in enumerate(case["consumed_token_ids"]):
            output = model.predict({"token_id": np.array([[token]], dtype=np.int32),
                                    "position": np.array([position], dtype=np.int32)}, state=state)
            row["predictions"] += 1
            if position in by_position:
                recorded = by_position[position]
                comparison = metrics(output["logits"], reference[recorded["reference_key"]],
                                     LIMITS["coreml_vs_official"])
                comparison.update({"step": recorded["step"], "position": position})
                row["comparisons"].append(comparison)
                log(f"Core ML {case['id']} position {position}: {comparison}")
        row["elapsed_seconds"] = time.monotonic() - started
        results.append(row)
        report["coreml_cases"] = results
        write_json(report_path, report)
    report["coreml_numerical_pass"] = all(c["passed"] for case in results for c in case["comparisons"])
    report["prediction_status"] = "host_smoke_passed" if report["coreml_numerical_pass"] else "host_numerical_failure"
    write_json(report_path, report)
    if not report["coreml_numerical_pass"]:
        raise RuntimeError("Core ML logits failed fixed numerical smoke limits; thresholds unchanged")


def prepare_stage(stage):
    """Claim new evidence before importing ML or modifying any existing run."""
    report_path = OUTPUT / "report.json"
    if stage == "predict":
        report = json.loads(report_path.read_text())
        if (report.get("conversion_status") != "converted_not_device_qualified"
                or not report.get("torch_numerical_pass") or not PACKAGE.exists()
                or not (OUTPUT / "oracle_logits.npz").is_file()):
            raise RuntimeError("Predict requires the existing completed conversion and oracle evidence")
        # Each host/XPC retry has independent evidence. Never rewrite conversion or
        # previous prediction reports, including after a failed prediction.
        report_path = OUTPUT / f"prediction-report-{uuid.uuid4().hex}.json"
        with report_path.open("x") as stream:
            stream.write("{}\n")
    else:
        # Partial outputs and failed runs are evidence too. This check precedes
        # mkdir, scratch creation, report writes and all heavy-library imports.
        if OUTPUT.exists() and (not OUTPUT.is_dir() or any(OUTPUT.iterdir())):
            raise FileExistsError(f"Refusing to overwrite existing conversion run evidence: {OUTPUT}")
        OUTPUT.mkdir(parents=True, exist_ok=True)
        # Exclusive claim also prevents two converter invocations from racing
        # through an initially empty directory. A failed attempt retains its claim.
        with (OUTPUT / ".conversion-claimed").open("x") as stream:
            stream.write(f"{time.time()}\n")
        report = {"schema_version": 1, "research_only": True, "production_approval": "pending",
                  "expected_source_identity": {"repository": REPOSITORY, "revision": REVISION},
                  "context": CONTEXT, "batch": 1, "sequence": 1,
                  "kv_dtype": "float16", "coreml_compute_precision": "float16",
                  "host_compute_units": "CPU_AND_GPU", "limits_fixed_before_execution": LIMITS,
                  "host": {"platform": platform.platform(), "python": sys.version},
                  "limitations": ["No iPhone, iOS execution or simulator validation", "No 4096-token prefill",
                                   "No production latency, memory, language or provenance qualification",
                                   "Only short forced-prefix multistep next-token logits comparisons"]}
    report.setdefault("attempts", []).append({"stage": stage, "started_at_unix": time.time()})
    write_json(report_path, report)
    return report, report_path


def run_stage(stage):
    report, report_path = prepare_stage(stage)
    # Keep compiler/cache scratch inside the single authorized research directory.
    scratch = OUTPUT / "scratch"
    scratch.mkdir(exist_ok=True)
    os.environ["TMPDIR"] = str(scratch)
    try:
        if stage == "convert":
            convert(report, report_path)
        else:
            predict(report, report_path)
        report["attempts"][-1]["status"] = "finished"
    except Exception as error:
        report["attempts"][-1].update({"status": "failed", "error_type": type(error).__name__,
                                      "error": str(error), "traceback": traceback.format_exc()})
        raise
    finally:
        report["attempts"][-1]["ended_at_unix"] = time.time()
        write_json(report_path, report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=("convert", "predict", "all"), default="convert")
    args = parser.parse_args()
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["TOKENIZERS_PARALLELISM"] = "false"
    if args.stage in ("convert", "all"):
        run_stage("convert")
    if args.stage in ("predict", "all"):
        run_stage("predict")


if __name__ == "__main__":
    main()
