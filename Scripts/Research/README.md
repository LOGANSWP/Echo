# Task 4.0k native research probes

## Task 4.0l photo-understanding screening

`photo_understanding_probe.py` is an offline host-only candidate screen. It verifies
the pinned source inventory, renders controlled non-personal images in memory,
and records actual model output, token counts, EOS, timing and host memory.
It does not save media or prove real PhotoKit/product acceptance.

The first screen found content and language failures. The user then clarified
that functional closure takes priority over precision. Continue native research
with the same authorized candidate; retain quality findings separately. Its
source was removed at the earlier checkpoint, so restore and verify the exact
authorized inventory before running again. Keep one source copy within 3 GB. The exact source snapshots
for both experiment versions are embedded in
`docs/05-planning/4.0l-screening-results.json`; the same file retains all results.
See `docs/05-planning/4.0l-screening-review.md` for the verdict and scope.

### Native functional checkpoint

The same authorized source has now been restored and verified. Use
`convert_photo_research.py --attempt 2` as the recorded conversion configuration;
its exclusive output guard prevents overwriting the existing successful run.
`prepare_photo_native_probe.py` freezes analytic-circle token/oracle inputs.
`PhotoNativeProbe.swift` plus `GenerationMemory.swift` compile under Swift 6
complete concurrency checking and warnings-as-errors. The native probe performs
image inference and token decoding itself; prompts are pretokenized, so this is
not a complete production tokenizer or PhotoKit runtime. Both complete outputs
match the CPU reference. See `docs/05-planning/4.0l-functional-research-review.md`.

### Native inputs and generation bridge

`PhotoTokenizer.swift` and `PhotoImagePreprocessor.swift` remove pretokenized
input dependence. Their probes cover 103 tokenizer references, four budget
rejections, 12 image cases and three invalid-image rejections. The fixed vocabulary
omits some byte symbols; unsupported bytes reject instead of silently disappearing.
`PhotoFunctionalProbe.swift` runs native image decoding, tokenization and actual
Core ML inference; `run_photo_functional_probe.py` bounds resources and verifies
source, converted and compiled identities. Existing run folders reject overwrite.
`photo_generation_bridge.py` consumes actual caption results in the existing
native structured generator, with all four bilingual/source checks passing.
English paragraph repetition remains a quality finding.
See `docs/05-planning/4.0l-native-input-review.md` and the pending local-App artifact
packet. These results do not establish production PhotoKit, shared-process memory,
or final quality/release qualification.

## Task 4.0k probes

These command-line programs implement the bounded research experiments in
ADR-023. They are outside the Echo target and App Bundle. No model, runtime,
distribution, quality, or device approval is granted by their results.

The exact Qwen3-0.6B tokenizer and context1024 int8 Core ML package live in the
ignored `PinnedModels/offline-generation-evaluation/` tree. The Python controller
verifies complete source/package manifests and executable/source identities
before and after a run. It does not perform model inference: the child process
uses Swift, Foundation, Darwin, and Core ML only.

Run from the repository root using the installed Xcode toolchain:

```sh
xcrun swiftc -swift-version 6 -O -parse-as-library \
  -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path /tmp/echo-generation-swift-cache \
  Scripts/Research/GenerationTokenizer.swift \
  Scripts/Research/GenerationTokenizerProbe.swift \
  -o PinnedModels/offline-generation-evaluation/generation-tokenizer-probe

python3 Scripts/tests/test_generation_tokenizer_probe.py \
  PinnedModels/offline-generation-evaluation/generation-tokenizer-probe

xcrun swiftc -swift-version 6 -O -parse-as-library \
  -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path /tmp/echo-generation-swift-cache \
  Scripts/Research/GenerationEnvelopeGrammar.swift \
  Scripts/Research/GenerationBudget.swift \
  Scripts/Research/GenerationGrammarProbe.swift \
  -o PinnedModels/offline-generation-evaluation/generation-grammar-probe

python3 Scripts/tests/test_generation_swift_grammar.py \
  PinnedModels/offline-generation-evaluation/generation-grammar-probe

xcrun swiftc -swift-version 6 -O -parse-as-library \
  -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path /tmp/echo-generation-swift-cache \
  Scripts/Research/GenerationTokenizer.swift \
  Scripts/Research/GenerationEnvelopeGrammar.swift \
  Scripts/Research/GenerationBudget.swift \
  Scripts/Research/GenerationMemory.swift \
  Scripts/Research/GenerationNativeProbe.swift \
  -o PinnedModels/offline-generation-evaluation/generation-native-probe

python3 Scripts/evaluate_native_generation.py \
  --output PinnedModels/offline-generation-evaluation/qwen3-0.6b/native-run-NEW.json
```

Choose a new output name for every execution. Existing input, JSONL, stderr, and
report files are never overwritten. To inject actual Task cancellation after
the first real prediction returns, append `--mode cancel-after-first-prediction`.
The expected failure has no generated-case or completion record. This does not
measure cancellation while a GPU operation is in flight.

The full native experiment keeps the existing observations-v1 prompt and
grammar-v1 language. Every request reserves 256 output tokens in context1024
before model loading, owns a fresh MLState, and predicts sequentially. It checks
the monotonic position, cancellation and 60-second deadline before/after each
prediction; grammar selection also checks cancellation/deadline. EOS is legal
only after a complete envelope. There is no prediction after EOS or after the
last allowed output token. A 600-second parent deadline bounds the process.

Darwin kernel historical physical-footprint peaks are checked after loading and
each prediction against the research ceiling of 1.5 billion bytes. Samples are
recorded before token selection; they are not post-exit lifetime measurements.
Mac RSS, Mac physical footprint, full Echo coexistence, and device memory are
different evidence scopes. None substitutes for the required iPhone/App gate.

The controller retains truncation/failure as evidence. A completed research run
does not mean its text passed content or language quality. No generated text is
published into Echo; no fallback, retry, hierarchy, queue, permission, deletion,
or production provider behavior is implemented by this CLI.
