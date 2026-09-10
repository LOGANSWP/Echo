#!/usr/bin/env python3
"""4.0l: isolate FP16 CPU execution using the existing pinned source, outside Echo.

This exports only a FLOAT32-compute decoder with unchanged FP16 KV storage.
It does not replace the approved artifact or grant production approval.
"""

import hashlib
import json
import os
from pathlib import Path
import time

os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["TOKENIZERS_PARALLELISM"] = "false"

from convert_photo_research import SOURCE, wrappers
from photo_understanding_probe import verify_source


def main():
    import coremltools as ct
    import numpy as np
    import torch
    from transformers import AutoModelForImageTextToText

    verify_source()
    output = SOURCE.parent / "cpu-decoder-diagnostic"
    output.mkdir(exist_ok=False)
    torch.set_num_threads(4)
    torch.set_grad_enabled(False)
    model = AutoModelForImageTextToText.from_pretrained(
        str(SOURCE), local_files_only=True, trust_remote_code=False,
        dtype=torch.float32, attn_implementation="eager").eval()
    _, decoder = wrappers(model)
    example = (torch.tensor([[1]], dtype=torch.int32), torch.tensor([0], dtype=torch.int32),
               torch.zeros(1, 1, 576))
    decoder.reset()
    reference = decoder(*example).numpy().copy()
    decoder.reset()
    traced = torch.jit.trace(decoder, example, check_trace=False)
    decoder.reset()
    started = time.monotonic()
    converted = ct.convert(
        traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
        compute_precision=ct.precision.FLOAT32, skip_model_load=True,
        inputs=[ct.TensorType(name="token_id", shape=(1, 1), dtype=np.int32),
                ct.TensorType(name="position", shape=(1,), dtype=np.int32),
                ct.TensorType(name="image_embedding", shape=(1, 1, 576), dtype=np.float32)],
        outputs=[ct.TensorType(name="logits", dtype=np.float32)],
        states=[ct.StateType(name=name, wrapped_type=ct.TensorType(shape=tuple(buffer.shape), dtype=np.float16))
                for name, buffer in decoder.states()])
    converted.user_defined_metadata["researchOnly"] = "true"
    converted.user_defined_metadata["productionApproval"] = "pending"
    package = output / "SmolDecoder1024.mlpackage"
    converted.save(str(package))
    np.save(output / "first-token-oracle.npy", reference)
    files = []
    for path in sorted(output.rglob("*")):
        if path.is_file():
            with path.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            files.append({"path": str(path.relative_to(output)), "bytes": path.stat().st_size, "sha256": digest})
    (output / "manifest.json").write_text(json.dumps({
        "scope": "research only; CPU precision diagnosis; no artifact replacement approval",
        "computePrecision": "FLOAT32", "kvPrecision": "FLOAT16", "seconds": time.monotonic() - started,
        "files": files,
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
