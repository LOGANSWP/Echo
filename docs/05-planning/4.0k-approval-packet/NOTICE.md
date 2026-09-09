# Candidate attribution and modification notice — NOT RELEASE APPROVED

Qwen3-0.6B model weights, tokenizer vocabulary/merges/configuration and upstream
chat template originate from Qwen/Qwen3-0.6B, revision
`c1899de289a04d12100db370d81485cdf75e47ca`.

Copyright 2024 Alibaba Cloud.

The upstream repository declares Apache License 2.0. Its exact LICENSE is
preserved as `licenses/Qwen3-0.6B-LICENSE`; the source manifest identifies every
upstream file. The complete pinned source tree contains no separate NOTICE.
This is an observation about those source bytes, not a claim of upstream
endorsement or a grant of trademark rights.

The candidate has been modified for Echo research: fixed context1024,
single-token input, explicit position input, 56 FP16 key/value state buffers,
tied embedding/head handling, FP16 Core ML compute, then symmetric per-channel
int8 weight quantization above the recorded size threshold. The resulting
package was compiled using Xcode 26.5 with an iOS 18 compatibility target.
The exact scripts, inputs, outputs and failed/passed numerical checks are
identified in `runtime-lineage.json` and `artifact-inventory.json`.

The native research runtime and byte-BPE implementation are first-party Swift
code. They consume the pinned tokenizer data and explicitly frame the supported
system/user/no-thinking template. Swift, Foundation, NaturalLanguage and Core ML
are provided by the Apple toolchain/system. This packet does not purport to
relicense those frameworks or replace the applicable Apple agreements.

Python/PyTorch/Transformers/Core ML Tools and their dependency graph are research
and conversion tools, not native App runtime dependencies. Their original
license/NOTICE files, including nested third-party notices supplied by the
installed packages, are preserved under `licenses/` and indexed separately.
The tokenizers wheel lacks a local license text; its pinned upstream-version
license is identified explicitly as an upstream reference, not wheel evidence.

This candidate notice is not installed in Echo. Following artifact approval,
the exact upstream license and an appropriate modification/attribution notice
must accompany the actual bundled resources and be rechecked against the final
App SBOM. Existing E5/SigLIP2/Whisper rights and notices are outside this packet.

No model use/distribution sign-off, output-quality approval, device qualification,
or release approval has been recorded by the Agent.
