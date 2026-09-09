# SmolVLM-256M candidate notices

This packet describes a pending candidate for local Echo engineering. It does
not authorize external distribution or claim that product acceptance is complete.

## Model origin

- HuggingFaceTB/SmolVLM-256M-Instruct, pinned revision
  `7e3e67edbbed1bf9888184d9df282b700a323964`.
- The pinned model card declares Apache-2.0 and identifies
  `google/siglip-base-patch16-512` and
  `HuggingFaceTB/SmolLM2-135M-Instruct` as its image/text foundations.
- Preserve the pinned model card and `licenses/Apache-2.0.txt` with any locally
  packaged candidate. The upstream SmolVLM root did not contain separate
  LICENSE/NOTICE files; that absence is retained in the fixed inventory.
- Base-model cards are independent, pinned license references retrieved during
  this evaluation. Their revisions are not a claim about unrecorded historical
  training inputs or base checkpoint hashes.

## Echo research modifications

- Converted the pinned safetensors into separate vision/projection and
  single-token stateful decoder Core ML graphs, FP16, context 1024.
- Compiled both graphs for an iOS 18 deployment target using Xcode 26.5.
- Added first-party Swift ByteLevel BPE, trusted image/chat framing, native
  ImageIO orientation/downsampling/neutral padding and bounded state ownership.
- ImageIO preprocessing is an explicitly versioned alternative to the upstream
  Pillow resize path. No upstream accuracy or latency claim is carried over.
- No additional model training, replacement weights or quantization was applied.

## Runtime and tooling

The proposed App runtime links Apple system frameworks and first-party Swift.
Python, PyTorch, Transformers, tokenizers, Pillow and coremltools are host research
tools only. Their installed licenses and notices, including embedded attributions,
are retained under `licenses/` and indexed in `licenses-index.json`.

The native pretokenizer follows the Hugging Face Tokenizers ByteLevel and Digits
definitions and is checked against the pinned installed tokenizer. Reference
source: [ByteLevel](https://github.com/huggingface/tokenizers/blob/v0.22.2/tokenizers/src/pre_tokenizers/byte_level.rs),
[Digits](https://github.com/huggingface/tokenizers/blob/v0.22.2/tokenizers/src/pre_tokenizers/digits.rs).
The upstream Tokenizers Apache-2.0 text is included in the tool license records.

Any later externally distributed App needs its actual final resource inventory,
applicable notices and release review. This candidate packet is not that release.
