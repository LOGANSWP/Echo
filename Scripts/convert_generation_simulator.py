#!/usr/bin/env python3
"""Derive Debug simulator RMS-FP32 graph from the exact approved local INT8 graph.

Task 4.0k; ADR-023 simulator supplement. Offline developer tooling only.
Does not alter the approval packet or approve device/release use.
"""

import argparse
import json
from pathlib import Path

import prepare_generation_resources as resources
import verify_generation_artifact


def convert(output):
    if output.exists():
        raise ValueError("Refusing to overwrite a model package")
    resources.prepare(resources.ROOT / "Echo/Resources/Models/OfflineGeneration.bundle", True)
    inventory = json.loads((resources.PACKET / "artifact-inventory.json").read_text())
    artifact = next(item for item in inventory["artifacts"] if item["group"] == "converted")
    manifest = resources.ROOT / artifact["manifestPath"]
    if resources.digest(manifest) != artifact["manifestSHA256"]:
        raise ValueError("Converted source manifest changed")
    source = resources.ROOT / artifact["rootPath"]
    verify_generation_artifact.verify_artifact(source, manifest)

    import coremltools as ct
    model = ct.models.MLModel(str(source), skip_model_load=True)
    derived, evidence = promote_rms(model)
    derived.save(str(output))
    return evidence


def promote_rms(model):
    """Preserve quantized bytes while promoting only RMS accumulation."""
    import coremltools as ct
    import numpy as np
    from coremltools.converters.mil import Builder as mb
    from coremltools.converters.mil.frontend.milproto.load import load

    spec = model.get_spec()
    program = load(spec, spec.specificationVersion, file_weights_dir=model.weights_dir)
    function = program.functions["main"]
    count = 0

    def child(value, kind):
        matches = [op for op in value.child_ops if op.op_type == kind]
        if len(matches) != 1:
            raise ValueError("Unexpected RMS graph topology")
        return matches[0]

    for op in list(function.operations):
        if op.op_type != "pow" or not np.all(op.y.val == 2):
            continue
        mean = child(op.outputs[0], "reduce_mean")
        add = child(mean.outputs[0], "add")
        rsqrt = child(add.outputs[0], "rsqrt")
        mul = child(rsqrt.outputs[0], "mul")
        if mul.x is not op.x and mul.y is not op.x:
            raise ValueError("Unexpected RMS normalization input")
        epsilon = add.y if add.x is mean.outputs[0] else add.x
        with function:
            value = mb.cast(x=op.x, dtype="fp32", before_op=op)
            square = mb.mul(x=value, y=value, before_op=op)
            variance = mb.reduce_mean(x=square, axes=mean.axes.val,
                                      keep_dims=mean.keep_dims.val, before_op=op)
            inverse = mb.rsqrt(x=mb.add(x=variance, y=np.float32(epsilon.val), before_op=op),
                               before_op=op)
            result = mb.cast(x=mb.mul(x=value, y=inverse, before_op=op), dtype="fp16", before_op=op)
        function.replace_uses_of_var_after_op(mul, mul.outputs[0], result)
        function.remove_ops([mul, rsqrt, add, mean, op])
        count += 1
    if count != 113:
        raise ValueError("Pinned graph must contain exactly 113 RMS normalizations")
    derived = ct.convert(program, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
                         compute_precision=ct.precision.FLOAT32, skip_model_load=True)
    # Rehydrating MIL does not preserve flexible-input range metadata by itself.
    derived_spec = derived.get_spec()
    for target, source_input in zip(derived_spec.description.input, spec.description.input):
        if target.name != source_input.name:
            raise ValueError("RMS transformation changed input identity")
        target.CopyFrom(source_input)
    derived = ct.models.MLModel(derived_spec, weights_dir=derived.weights_dir, skip_model_load=True)
    expected_weights = resources.digest(Path(model.weights_dir) / "weight.bin")
    actual_weights = resources.digest(Path(derived.weights_dir) / "weight.bin")
    if expected_weights != actual_weights:
        raise ValueError("RMS transformation changed quantized weights")
    return derived, {"rmsNormalizations": count, "weightsSHA256": actual_weights,
                     "scope": "debug-simulator-engineering-only", "releaseApproved": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(convert(args.output), indent=2))
