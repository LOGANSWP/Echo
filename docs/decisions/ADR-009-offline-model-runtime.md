# ADR-009: 离线模型运行时与生成决策

**状态**: 已接受
**日期**: 2026-08-04
**决策人**: Model Legal and Privacy Approver（审批）+ On-device ML Lead（实现）

## 背景

基线中模型 Bundle 0/6：E5/SigLIP2/Whisper 均为 scaffold/不可达推理；`ModelLoaderActor` 状态与 embedder 实际加载不同步（DEF-34-003）；`prepare_models.sh` 的 E5/SIGLIP2 revision 是可变 ref `main`（DEF-35-001）；模型许可证/校验和/SBOM/分发批准无登记（`model-provenance-register.md` 不存在）。US-SRC-011 无可用视觉 embedding 与主观查询 Golden 集。SYN 故事（生成）依赖的离线 LLM 运行时无批准。

## 决策

1. **模型空间分离**：E5 384d 文本嵌入、SigLIP2 视觉嵌入、Whisper 转写各自独立 generation + VectorStoreActor；禁止跨空间对齐（ADR-006）。
2. **不可变捆绑工件**：每个捆绑工件固定不可变 revision + SHA-256（`model_checksums.sha256`）、转换 lineage、运行时许可证、tokenizer 许可证、NOTICE 位置、SBOM 位置、商业分发处置、审批人与审批日期，全部登记到 `docs/05-planning/model-provenance-register.md`；manifest→bundle→register 计数 100%，哈希全部可验证；未获批模型不得进入打包。
3. **零网络运行时**：模型随 App 分发，App 内无下载代码（R-005）；`prepare_models.sh --verify-only` 校验 100% 存在/有效。
4. **离线 LLM 决策（本 ADR 批准）**：**保留 grounded creation（US-SYN-001/002/003/004/005/006/007/008 的批准子集）**，采用不可变捆绑运行时/工件 + 许可证 + 校验和，并实现 `LanguageAligner`（单次重试 ≤1，R-004 语言对齐）。语言输出仅 zh-Hans/en-US。
5. **Loader 状态回报**：embedder→ModelLoaderActor 状态回报机制（关闭 DEF-34-003）；损坏/缺失工件进入 L3 阻断 + 手动重试（US-RES-004）。
6. **参考输出**：`e5-reference-vectors.json`、`siglip2-reference-vectors.json`、`whisper-reference-transcripts.json` 提供确定性参考（US-SRC-011 model semantics），Golden 验证在 Phase 4 4.1。

> **实施状态校正（2026-09-07，ADR-022）**：本 ADR 批准的是约束与方向，不等于生成式 LLM 工件已经登记或生产接线完成。当前 `LiveAppAdapters.resolveLLMProvider()` 返回 `nil`，model provenance register 也没有批准的生成式工件。`4.0j` 只能交付调度/存储基础；`4.0k` 必须完成不可变工件审批、真实 `LLMProvider`、`LanguageAligner` 和 no-fixture 生成证据后，SYN 自动生成能力才能声明生产完成。Stub/fixture 不得作为该证据。

## 备选方案

> **执行合同补充（2026-09-07，ADR-023）**：具体模型审批前先完成候选/设备/预算材料；ModelManifestActor 只登记身份，不授予分发许可。批准清单须覆盖全部运行时权重与 tokenizer/template/config，不能以源 checkpoint 或单个 Manifest.json 摘要替代。token/上下文/输出、会话 KV 状态、逐层 provenance、语言失败与恢复重放的可测合同见 ADR-023。

| 方案 | 描述 | 结论 |
|------|------|------|
| **A（采纳）** | 保留离线 generation：不可变捆绑 LLM 运行时 + Language Aligner | ✅ 满足 v1 创作闭环、R-004/R-005，全离线 |
| B | 移除全部 SYN 故事 | ❌ 丢失核心创作能力（Echo 记忆助手的差异化功能） |
| C | 云端 LLM 兜底 | ❌ 违反 R-001/R-005 绝对红线 |

## 后果

### 正面

- 全部模型工件可溯源、可验证、全离线；`model-provenance-register` 成为分发唯一事实源。
- Language Aligner 保证 AI 输出语言符合 `UserPolicy.preferredLanguage`。
- 关闭 DEF-34-003/004、DEF-35-001 的证据路径确定。
- **3F.3b（2026-08-09）**：whisper.cpp v1.9.2 运行时接入 — 真实转写可用（`NativeWhisperCInterop`），GGUF SHA-256 校验强制，参考转写回填（CER=0.0）。

### 负面

- 捆绑 LLM 增加包体积；须接受体积/质量权衡并经 Model Legal 批准。
- 不可变工件使模型升级走「新 revision + 新审批」路径，无法热替换。
- 参考输出需维护与模型 revision 一一对应。
- **3F.3b 决策**：whisper.cpp 以 `GGML_CPU_GENERIC` 构建（SPM 无法按架构排除源文件，避免 x86_64 duplicate symbol），无 NEON 专属加速 — CPU 推理约 28s/11s 音频，可接受。

## 参考

- `docs/01-spec/用户故事与验收标准规格书.md` US-ING-001~005、US-RET-001/002/006、US-RES-001/004、US-SRC-011、US-SYN-001~008
- AGENTS.md R-004/R-005
- `docs/02-architecture/技术选型文档.md`、`docs/03-implementation/双语言实现说明文档.md`
- `docs/05-planning/model-provenance-register.md`（3F.3 创建）
- ADR-006（范围契约）、ADR-013（创作/导出边界）、ADR-022（生成运行时门禁）
