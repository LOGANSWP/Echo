# Model Provenance Register（模型溯源登记册）

**版本**: 1.1.0
**创建**: 2026-08-06（任务 3F.3）
**最近核对**: 2026-09-07（4.0k 规格评审；文件与既有记录核对，未重跑模型验证）
**维护规则**: 每个捆绑工件必须登记；manifest → bundle → register 计数 100%；哈希全部可验证；未获批模型不得进入打包（ADR-009 决策 2）。

---

## 0. 当前登记核对与证据边界

下表是当前 `Echo/Resources/Models/model-manifest.json` 的 **4 个主模型声明**，不等于本轮已经证明构建产物完整、哈希一致或具有最终分发批准。Tokenizer、配置、权重分片与许可证为各模型的附属工件，不能从主模型计数中省略其验证。

| # | modelId | manifest 的运行时工件 | manifest 声明的 hash / scope | 当前记录状态 |
|---|---------|------------------------|------------------------------|--------------|
| 1 | `e5-multilingual-small-v1` | `MultilingualE5Small.mlpackage` | `af2f01cb…edca11b9`；实际旧校验仅 `Manifest.json` | `pending-approval`；§1 工程暂定；完整权重身份与不可变 revision 待核对 |
| 2 | `whisper-tiny-q5_1-v1` | `whisper-tiny-q5_1.gguf` | `81871056…69c3d7`；单文件 | manifest 为 `pending-approval`，§2 保留 R-5.4 与 3F.3b 批准记录；审批范围与登记状态待对齐 |
| 3 | `siglip2-base-patch32-256-v1` | `SigLIP2BasePatch32.mlmodelc` | `acbc5b87…7ab05c0`；目录 hash scope 未声明 | `pending-evaluation`；§3 及下述检索路由历史审批需按确切工件核对 |
| 4 | `siglip2-text-base-patch32-256-v1` | `SigLIP2TextBasePatch32.mlmodelc` | `3b30a393…11bc971`；仅 `model.mil` | `pending-evaluation`；文本塔见 §3.4；不能以定义文件摘要代表全权重验证 |

**历史记录保留**：2026-08-06 曾记录“三个主工件、计数 100%、`prepare_models.sh --verify-only` 通过”。该结论早于文本塔登记与后续转换，只适用于当时脚本的校验范围，不能作为当前四项 inventory、全部 runtime 文件或新生成式 LLM 的发布证明。

**历史审批保留且不得扩张范围**：`docs/05-planning/photo-text-search-release-evidence-manifest.json` 记录 SigLIP2 双塔检索的分阶段审批；`.omo/evidence/photo-text-search/wp7/final-verdict.json` 的 `step11cRouteEnablement` 与 `.omo/evidence/photo-text-search/EVIDENCE_LEDGER.md` 的 `E-WP7-S18` 记录 2026-08-28 用户 Legal sign-off 与检索路由启用。这些事实不能因通用 manifest 尚为 pending 而被抹除，也不能自动扩张为任意模型或生成式 LLM 的批准。现存记录的 scope、revision、运行时工件摘要与附件必须对应后再同步机器登记；本次规格评审不修改既有批准事实或 manifest。

**4.0k 当前状态**：尚无生成式 LLM 登记项或该工件的批准证据。ADR-009/022 批准的离线方向不等于选定某个工件。候选、证据和人类审批的顺序见技术选型 §3.6；不得凭技术接线成功自行新增 `approved`。

**4.0k 研究材料**：[候选评估与待审批计划](4.0k-generation-evaluation.md) 已列出固定来源、资源估算和真实本地筛选失败。前三款已下载源模型各自的完整 10 文件清单为 [Qwen2.5-0.5B](4.0k-qwen25-source-manifest.json)、[Qwen3-0.6B](4.0k-qwen3-source-manifest.json)、[Qwen2.5-1.5B](4.0k-qwen25-15b-source-manifest.json)；另有 [Qwen3-1.7B 的 12 文件清单](4.0k-qwen3-17b-source-manifest.json)。Qwen3-0.6B 的 [context128 FP16 Core ML 包清单](4.0k-qwen3-coreml-fp16-manifest.json)已形成，Mac 短序列数值对照通过；int4 的数值损失另行记录。均仅在被忽略的研究目录验证，不增加生产 Bundle 模型或生成式分发批准；LFM2 仍只查 metadata。NOTICE/SBOM、正式质量和设备证据仍需各自完成。

**2026-09-08 候选补充**：[4.0k确切工件审批包](4.0k-approval-packet/README.md)已归档编译目录全文件、tokenizer/config、候选NOTICE、当前研究工具与runtime SBOM/lineage及待审预算；编译后必需资源共609,921,113 bytes。明确的工件使用/接线审批请求已提交，但`approval.json`仍pending，不新增生产approved登记。该候选包不代替最终Echo App SBOM、设备质量或发布批准。

### 0.1 完整性校验缺口

- `prepare_models.sh` 当前校验 E5 的 `Manifest.json` 与 tokenizer、Whisper 单文件及 `PinnedModels/` 中的 SigLIP2 转换源；它未按 `model-manifest.json` 遍历全部 `.mlmodelc` 运行时文件，也未验证完整审批附件或 SBOM。`--verify-only` 成功不能独立证明 ADR-009 的完整发布门禁通过。
- E5 只哈希 `Manifest.json`、文本塔只哈希 `model.mil` 均无法覆盖其余权重文件。转换源摘要只能证明来源字节，不能替代转换后工件摘要。
- `Scripts/model_checksums.sha256` 的 SigLIP2 双塔值与 manifest 值不同且缺少共同 scope 说明，另有格式异常行；在统一算法与文件清单前，不得据此宣称相同或损坏，也不得重新生成摘要后自行把当前字节当作获批基线。
- SigLIP2 转换源已在 `prepare_models.sh` 固定为 `94dffa8cb1179de3e03f091dbc3917e5d5a9ae84` 且移至 `PinnedModels/`；§3 的 `main` 与资源目录位置为历史记录。E5 与 Whisper 的当前 manifest 仍使用 `main`，不可笼统宣称所有 revision 已固定。
- 4.0k 必须定义版本化的 hash scope：分别列出固定来源、转换工具链/参数、完整转换输出，以及所有实际运行所需的权重、tokenizer、配置和附属文件。目录工件采用排序后的相对路径、文件字节长度与逐文件 SHA-256 清单（或已记录且同等完整的目录摘要算法），校验缺失、额外文件、内容变更和声明不一致；编译产物的工具链相关差异单独记录，不能伪称跨工具链字节恒等。
- 完整发布验证必须核对 **批准清单 → manifest → 实际 App bundle → 完整文件摘要 → 许可证/NOTICE/SBOM**。`ModelManifestActor` 负责持久化身份元数据，不是批准主体；角色、日期、scope 与证据引用来自可审阅的人类审批记录。

---

## 1. multilingual-e5-small（文本嵌入）

### 1.1 工件清单

| 字段 | 值 |
|------|-----|
| **modelId** | `e5-multilingual-small-v1` |
| **用途** | 文本语义嵌入（384d，query/passage 前缀） |
| **来源** | HuggingFace `tamikisg/multilingual-e5-small-coreml` |
| **Revision** | `main`（可变 ref，SHA-256 锁定内容完整性；不可变 commit hash 固定追踪于 DEF-35-001，网络可用时回填） |
| **Bundle 文件** | `MultilingualE5Small.mlpackage`（含 `Manifest.json`） |
| **SHA-256** | `af2f01cb5f0cbf22832c9cec2881ea730df4eb65ecd20334245cf823edca11b9`（Manifest.json） |
| **运行时** | Core ML（`.mlpackage` → 编译 `.mlmodelc`，`CoreMLInferenceAdapter`） |
| **转换 lineage** | HF `multilingual-e5-small`（intfloat）→ Core ML 导出（tamikisg 提供 `.mlpackage`）→ Xcode 编译 |
| **运行时许可证** | MIT（tamikisg/multilingual-e5-small-coreml） |
| **权重上游许可证** | 源权重来自 `intfloat/multilingual-e5-small`（MIT）——下游含义交专业法律审查 |
| **NOTICE** | 见 §4 |
| **SBOM** | 见 §4 |
| **商业分发处置** | ⚠️ 工程暂定（legal review pending）；批准前不得进入生产打包 |
| **审批人/日期** | 待 Model Legal and Privacy Approver 批准 |

### 1.2 Tokenizer（附属工件）

| 字段 | 值 |
|------|-----|
| **来源** | 同仓库 `tokenizer.json`（Unigram / SentencePiece，Metaspace 预分词） |
| **Bundle 文件** | `tokenizer.json` |
| **SHA-256** | `cd98e5698b201ba914efb8c18b6709fa8735ab71dcad8d2b431e52e8bf68d932` |
| **许可证** | 随模型仓库（MIT） |
| **消费方** | `E5Tokenizer`（`Echo/Core/Services/E5Tokenizer.swift`） |

### 1.3 参考输出

| 字段 | 值 |
|------|-----|
| **文件** | `Echo/Resources/Models/e5-reference-vectors.json` |
| **内容** | 4+ 条 384d L2 归一化参考向量（bilingual/query/passage 样本） |
| **用途** | US-SRC-011 model semantics；Golden 验证在 Phase 4 4.1 |
| **消费测试** | `ProductionModelInferenceTests.E5ReferenceVectors` |

---

## 2. Whisper tiny Q5_1（ASR）

### 2.1 工件清单

| 字段 | 值 |
|------|-----|
| **modelId** | `whisper-tiny-q5_1-v1` |
| **用途** | 语音转写（16kHz mono PCM → 文本） |
| **来源** | HuggingFace `ggml-org/whisper.cpp`（`ggml-tiny-q5_1.bin` → 重命名 `.gguf`） |
| **Revision** | `main`（R-5.4 批准 tiny；small 为挑战者不打包） |
| **Bundle 文件** | `whisper-tiny-q5_1.gguf` |
| **SHA-256** | `818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7` |
| **运行时** | whisper.cpp（C 互操作桥接 `WhisperRuntimeBridge`；运行时静态库接入前 fail-closed `runtimeNotLinked`） |
| **转换 lineage** | OpenAI Whisper tiny（MIT）→ GGML 量化 Q5_1（ggml-org 提供）→ 重命名 |
| **运行时许可证** | MIT（whisper.cpp） |
| **权重上游许可证** | MIT（OpenAI Whisper） |
| **NOTICE** | 见 §4 |
| **SBOM** | 见 §4 |
| **商业分发处置** | ✅ 已批准（R-5.4，2026-08-01） |
| **审批人/日期** | Model Legal and Privacy Approver / 2026-08-01 |

### 2.2 参考输出

| 字段 | 值 |
|------|-----|
| **文件** | `Echo/Resources/Models/whisper-reference-transcripts.json` |
| **内容** | 状态 `approved`（3F.3b 2026-08-09 回填）：jfk.wav 真实转写样本 + 参考文本 + CER/WER 阈值（0.15） |
| **用途** | US-SRC-011 model semantics；Golden 验证在 Phase 4 4.1 |
| **验证** | `WhisperRuntimeTests.ReferenceCERWER`：真实转写 CER=0.0 ≤ 0.15（spike 实测） |

### 2.3 运行时接入（3F.3b）

| 字段 | 值 |
|------|-----|
| **运行时** | whisper.cpp v1.9.2（本地 SPM 包，vendored 固定 revision `306c88f4d1`，`ThirdParty/whisper.cpp/`） |
| **接入方式** | `NativeWhisperCInterop`（whisper_init_from_file_with_params + whisper_full，Sendable 安全）；`WhisperRuntimeBridge` 默认接线 |
| **构建决策** | `GGML_CPU_GENERIC` + 排除 `arch/arm/*.c`（SPM 无法按架构排除源文件，避免 x86_64 duplicate symbol；见 Package.swift 注释） |
| **校验** | 转写前 SHA-256 与 §2.1 登记值比对（`checksumMismatch` L3）；失败走 fail-closed |
| **GGUF 状态** | `pending-runtime-integration` → `approved`（2026-08-09，3F.3b） |
| **依赖白名单** | AGENTS.md §2.2 白名单审批通过（2026-08-09，人类批准）；SBOM/NOTICE 随 §4 打包前创建 |

---

## 3. SigLIP2-B/32（视觉嵌入）

### 3.1 工件清单

| 字段 | 值 |
|------|-----|
| **modelId** | `siglip2-base-patch32-256-v1` |
| **用途** | 图像语义嵌入（768d，独立 vision generation） |
| **来源** | HuggingFace `google/siglip2-base-patch32-256` |
| **Revision** | `main`（可变 ref，SHA-256 锁定内容完整性） |
| **Bundle 文件** | `siglip2-base-patch32-256/model.safetensors`（PyTorch 转换源） |
| **SHA-256** | `7d241bb3becad218f211f480487f491df4f8c0a472ecf7afdec5615815a301f1` |
| **运行时** | Core ML（`.mlmodelc`，`SigLIP2Embedder`）；3F.3a 转换管线就绪（`Scripts/convert_siglip2.py`），推理接入完成 |
| **转换 lineage** | Google SigLIP2-B/32-256（Apache-2.0）→ PyTorch safetensors → coremltools 9.0 → Xcode coremlcompiler → `SigLIP2BasePatch32.mlmodelc` |
| **运行时许可证** | Apache-2.0 |
| **NOTICE** | 见 §4 |
| **SBOM** | 见 §4 |
| **商业分发处置** | ⚠️ `pending-evaluation`（3F.3a 转换完成 + 真实推理验证 + 参考向量已回填 + 余弦相似度 >0.995 通过；待 Model Legal and Privacy Approver 最终审批后方可进入 Release 打包） |
| **审批人/日期** | 待 Model Legal and Privacy Approver 批准 |

### 3.2 推理接入（3F.3a）

| 字段 | 值 |
|------|-----|
| **接入状态** | `SigLIP2Embedder.embedImage` 真实 Core ML 推理（`SigLIP2BasePatch32.mlmodelc` → 768d L2 归一化） |
| **预处理** | 方向矫正 → aspect-fit 256（最短边）→ center-crop 256 → normalize（mean=[0.5,0.5,0.5], std=[0.5,0.5,0.5]） |
| **推理适配** | MLModel.prediction（pixel_values [1,3,256,256] → embeddings [1,768] probe-token attention pooling → L2 normalize） |
| **错误处理** | 模型未加载 → `EmbedderError.modelNotLoaded` (L3)；推理失败 → `EmbedderError.inferenceFailed` |
| **审计** | 通过 `ModelLoaderActor.reportModelLoaded(.siglip2Vision)` 回报状态；加载失败 `reportModelLoadFailed`（L3） |

### 3.3 参考输出

| 字段 | 值 |
|------|-----|
| **文件** | `Echo/Resources/Models/siglip2-reference-vectors.json` |
| **内容** | 已回填（5 个 solid-color reference samples，PyTorch 真实 768d embedding，由 `Scripts/convert_siglip2.py` 生成） |
| **用途** | US-SRC-011 model semantics；Core ML 运行时余弦相似度 >0.995 已验证（3F.3a 测试）；Golden 验证在 Phase 4 4.1 |

### 3.4 SigLIP2 文本塔（当前 manifest 补录）

| 字段 | 当前声明与核对状态 |
|------|--------------------|
| **modelId** | `siglip2-text-base-patch32-256-v1` |
| **用途** | 与同一 SigLIP2 checkpoint 的视觉塔配对的文本嵌入（768d）；不是生成式 LLM |
| **Revision** | `94dffa8cb1179de3e03f091dbc3917e5d5a9ae84` |
| **运行时工件** | `SigLIP2TextBasePatch32.mlmodelc`；Core ML / FP16 |
| **manifest 摘要** | `3b30a393c14ea9dd07696d87c534b46e217df1aa80d6dccdbd487710f11bc971`；scope 为 `model.mil`，不代表全目录完整性 |
| **转换源** | 与视觉塔相同的 `model.safetensors`；源摘要 `7d241bb3…a301f1`，当前准备脚本定位 `PinnedModels/siglip2-base-patch32-256/` |
| **Tokenizer** | manifest 声明 BPE；仓库有 `siglip2-tokenizer.json`，仍需在完整工件清单中绑定其摘要与许可 |
| **审批与证据** | 通用 manifest 为 `pending-evaluation`；检索路由历史批准记录见 §0，按精确工件核对后同步，不在此次文档评审中推定新的批准 |

---

## 4. NOTICE / SBOM / 合规附件

### 4.1 NOTICE（随包分发声明）

- 当前存在：`Echo/Resources/Models/LICENSE-NOTICE.md`；原登记的 `NOTICE.md` 路径已过时。当前文件是许可说明，存在本身不证明每项 LICENSE 全文、第三方 NOTICE 与转换声明已完整随包。
- 内容要求：每个模型的版权声明、许可证全文引用、无担保声明

### 4.2 SBOM

- 约定位置：`Echo/Resources/Models/SBOM.json`；2026-09-07 文件核对时不存在，不能以 NOTICE 或 manifest 代替，也不能据此推断当前 bundle 没有模型。
- 内容要求：工件 SHA-256、来源 URL、许可证 SPDX ID、转换工具链版本

### 4.3 合规规则（ADR-009 决策 2 强制执行）

1. 未登记工件不得进入打包
2. 未获批模型（`provenance: pending-*`）不得进入 Release 构建
3. 模型升级必须走「新 revision + 新审批」路径，禁止热替换
4. 每次 Phase 集成测试扫描本登记册，与 `model-manifest.json`、`model_checksums.sha256`、`prepare_models.sh` 三方核对

---

## 5. 变更历史

| 日期 | 变更 | 执行人 |
|------|------|--------|
| 2026-08-06 | 初始登记：E5/Whisper/SigLIP2 三工件 + tokenizer 附属件 | On-device ML Lead |
| 2026-08-07 | 3F.3a: Core ML 转换管线（`convert_siglip2.py`）+ `SigLIP2Embedder` 真实推理接入 + 参考向量 schema 就绪 + provenance 模型更新 | On-device ML Lead |
| 2026-08-09 | 3F.3b: whisper.cpp v1.9.2 运行时接入（vendored 固定 revision + GGML_CPU_GENERIC）+ `NativeWhisperCInterop` 真实转写 + 参考转写回填（§2.2 approved）+ GGUF 状态 `pending-runtime-integration` → `approved`（§2.3） | On-device ML Lead |
| 2026-09-07 | 4.0k 规格评审：补齐四项 manifest inventory 与文本塔登记，标明历史计数/审批/哈希 scope 差异，保留检索路由批准记录，纠正 NOTICE 路径并显式记录 SBOM 缺失；未批准或修改任何模型工件 | Codex |

**4.0k 后续研究证据**：已补齐 [host 语言/一次重试](4.0k-generation-language-review.json) 与 [纯 Swift tokenizer 对照](4.0k-swift-tokenizer-review.json)。前者不替代生产 LanguageAligner，后者是独立 CLI，不代表新增已批准 App runtime 或依赖；生成式已批准模型计数保持不变。


## 2026-09-08T15:41:59Z 工件使用批准

用户在当前任务明确回复“批准”，授权固定审批包 `0e202c15169faf241d6ca77fa905493c7d3e57ba1e27f8df2d67c4fc58f136a7` 的 Qwen3-0.6B context1024/int8 per-channel 工件、原生运行时集成方案及 ≤650MB 生成模块预算。审批记录见 `4.0k-approval-packet/approval.json`。48 份冻结附件及 10 个候选资源重新校验一致；进入生产实现。此决定不代表质量、实机资源或发布门禁已经通过。

### App 运行时登记（4.0k，实现中）

`BundledGenerationActor` 完整校验固定资源后，通过默认 composition 中同库的 `ModelManifestActor` 登记 `qwen3-0.6b-generation-context1024-int8-v1`。revision 为 `c1899de289a04d12100db370d81485cdf75e47ca`；artifactHash 是上面的冻结审批清单摘要，清单闭包绑定全部编译权重、tokenizer、配置和许可。运行时 Core ML，Apache-2.0，`qwen3-byte-bpe-pinned-v1` tokenizer，`observations-production-v4` prompt；量化为 int8 per-channel、计算及 KV 为 FP16。

该项 `dimension=151936` 表示真实 logits 输出宽度，pooling/normalization 均为 none；它不是检索 embedding，不创建 IndexGeneration 或修改 ActiveRouteSet。登记只表示已验证的身份，模型可用性仍由实际加载与运行时检查决定。生成式工件使用审批数为 1，生成式产品质量/实机资格/发布通过数仍为 0。App 资源复制与重检使用 `Scripts/prepare_generation_resources.py`，不下载、不提交模型二进制。


### Debug simulator derivative (2026-09-08)

The simulator-first engineering artifact uses the same approved INT8 weights and tokenizer, with 113 RMS operations promoted to FP32. Its separate closed inventory is `4.0k-simulator-artifact-manifest.json`; identity `5a605e013f9bd0e2cfed9d7c44b99bc396628f82088c4aadd61865b1005a7a7f`, model ID `qwen3-0.6b-simulator-rms-fp32-v1`. This is not a second device/release-approved artifact. Debug simulator selects it; device and Release exclude it. Prompt v4 gives explicit Simplified Chinese instructions instead of relying on the locale code alone. Prompt version remains part of the recovery identity.

## 4.0l 视觉理解候选状态（ADR-025，2026-09-08）

照片自动画面描述所需的视觉生成模型/运行时尚未选定、未登记为获批工件。4.0k 的文本生成批准及 SigLIP2 检索编码器登记都不能代替该批准。本轮仅新增产品合同和任务，无新下载、无模型替换、无 App bundle 变更；候选材料须按 ADR-009/023 冻结来源、完整文件身份/许可证和实际预算，再取得确切工件审批。
