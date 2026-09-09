# ADR-023: 离线生成的执行边界与可验证验收

> 2026-09-08 Live Review 补充：手动创作使用 US-AWK-007 已提交的有效文本（标题、描述、标签、canonical 文本），而不是搜索占位摘要；没有文字的照片不提交给文本模型，返回来源空态。调用前后核验同一有效文本和版本。Debug 模拟器同一 RMS-FP32 工件采用 Core ML fastPrediction/infrequent 提示并更新 backend 恢复身份，预算不变。iOS 26 正常 App 摄入/编辑/创作通过；iOS 18 的 CPU 速度尚不能满足完整生成的时间预算，仍为未通过项，不能以清晰错误提示冒充生成完成。

**状态**: 已接受（规格修订；不授予任何具体模型、依赖或分发审批）
**日期**: 2026-09-07
**决策人**: Codex，依人类“先评审规格，不合理先修改文档”指令

## 背景与评审结论

> **2026-09-08 实现进展**：具体 Qwen3 工件使用/集成已获用户批准，默认 AppComposition 已装配真实 provider 与分层报告 generator；详见 `docs/05-planning/4.0k-production-validation.md`。模拟器已通过独立 CPU 兼容图的真实创作与月/年报告闭环；按用户指示暂不等待实机，质量/设备/覆盖率门禁尚未通过；不得宣称 4.0k 或自动报告产品 AC 完成。

4.0k 保留“获批 bundled LLM + 本地创作 + 月/年报告”的产品目标。ADR-022 正确区分了调度基础与真实生成，但仍不足以指导实现和验收。本次只修订文档，不把现有 seam、Stub 测试或历史模型记录补写为生产完成。

| 问题 | 原文/现状依据 | 修订 |
|---|---|---|
| 审批方向与可用工件混淆 | ADR-009 批准方向；4.0k 原约束称“经 ModelManifestActor…批准”，但 actor 是持久化接口 | 明确候选评估、具体工件人类审批、生产装配三个步骤；ready 只表示任务依赖就绪 |
| 输入限制缺 token 与推理状态预算 | ADR-021 §4 只有字节/字符/层数；AGENTS §4.1 要求纯函数性 | 增加 tokenizer 后的上下文/输出预算；KV cache 由运行时 Actor 隔离；确定性针对计划与请求，不承诺跨硬件逐字一致 |
| 层级引用可能丢失来源链 | SYN-002 单次 allow-list 未定义 reduce 输入 | 每次调用绑定实际输入的叶子 MemoryID 集合，逐层传播来源状态，禁止把全周期 ID 自动授予每层 |
| 字符串语言降级可能伪装生成成功 | 双语言 §5.2 未区分 JSON 协议与正文；SYN-001 重试与通用 L1 重试并存 | 先校验 envelope，再校验正文；每调用最多一次语言重试；typed fallback 不作为报告 publication |
| 游标不能替代未持久化的中间结果 | ADR-021 禁止在 resume descriptor 保存模型输出，但要求恢复聚合游标 | Continue 重建所需内存前缀，保留原 checkpoint；身份变化不能继续复用；不持久化生成草稿 |
| 验收可把测试通过误写成能力就绪 | task 仅要求 no-fixture E2E，未声明设备/质量样本/资源预算；登记册计数陈旧 | 明确真实工件、生产依赖图、合成测试数据、模拟器与实机的证据职责，以及未通过时的诚实状态 |

## 1. 4.0k 的工作顺序与审批事实

4.0k 保持一个项目任务，内部按以下顺序交付，不新增可被误认为生产能力的任务状态：

1. **候选与可行性材料**：列出模型/运行时候选、原始发布来源、不可变 revision、转换与量化 lineage、tokenizer/chat template、最低 OS/硬件支持、包体及共存内存估算。先形成可审阅方案与测量计划，不要求用户在没有材料时凭空选择。未获批候选不进入 App Bundle 或生产 composition；研究验证遵守既有模型处置与分发边界。
2. **具体审批**：由 Model Legal/Privacy 审批者记录确切工件与运行时、许可/NOTICE/SBOM、完整 SHA-256 文件清单和 scope。模型/运行时的生产可行性记录必须冻结具体支持设备/OS、输入 token/输出 token、上下文、包体、峰值内存、生成时延、取消响应界限与质量验收集。尚未确认的数值标为 pending，不能以“后续优化”放行生产验收，也不擅自降低现有全 App 内存等门禁。`ModelManifestActor` 只登记/读取已验证的模型身份，不代替人类审批。
3. **生产实现与证据**：审批后装配真实 `LLMProvider`、LanguageAligner、层级生成与恢复路径。`ready` 仅指 4.0j 等依赖完成，不证明步骤 2 已完成；工件审批与验证未完成时，不得声明 4.0k 完成或解除下游依赖。

工件完整性必须覆盖所有运行时权重分片、tokenizer、chat template、配置及转换后文件，使用明确的相对路径与 SHA-256 清单（或可验证的树清单）。仅哈希 `Manifest.json` 或原始 checkpoint 不能证明转换后权重完整。旧 `prepare_models.sh --verify-only` 的成功只代表它实际检查过的文件，不等于新 LLM 的许可/全文件完整性/质量/实机门禁全部通过。4.0k 必须补齐对应机器校验后才能交付。

本 ADR 不选择具体 LLM。双语言图中的旧 Qwen 名称不是批准记录。系统提供的模型也不能仅凭“端侧”就视为满足不可变随包、iOS 18、可审计与零运行时下载的全部要求。

## 2. 有界执行、确定性与状态隔离

- 计划器以稳定排序的当前授权输入、模型/tokenizer/chat-template 身份、算法/限制版本和 `preferredLanguage` 生成可复现的批次、层级与请求配置。推理会话、KV cache 和可变采样状态封装于运行时 Actor，按请求隔离并在结束/取消/撤权时释放；Pipeline 不持有跨请求的可变会话真相。
- 固定解码配置并记录其版本；同输入的计划、排序、请求、限额与验证结论必须可追溯。真实模型不要求跨 OS、硬件、计算单元逐 token/逐字节相同。测试不能用某一设备的整篇生成文本相等来代替语言、结构、来源和质量验证。
- `NarrativeReportLimits` 增加模型适配后的 token 预算：完整渲染后的 system instructions、chat template、JSON schema、来源标识、摘录、重试指令均计入输入；每次调用满足 `inputTokens + reservedOutputTokens <= approvedContextTokens`。字节与字符上限继续用于存储/解析防御，不能换算为固定 token 比率。
- tokenizer/template 必须区分受信任角色控制标记与不可信来源正文；正文中形似 `<|im_end|>` / `<|im_start|>` 的字面文本不得变成 chat 控制 token。可采用可逆 JSON 转义或分段普通文本编码，保持原始来源与解码后正文不变；预算按最终实际 token IDs 计算。边界测试须覆盖控制标记、反斜杠及中英文往返；这只防止结构角色注入，不等于模型能抵抗所有语义指令。
- 同时限制单批来源、摘录、输出 tokens/字节、fan-in、中间结果数量/总驻留字节、最大层数、模型调用次数、执行时间和运行时/KV 峰值内存；解码过程必须有停止边界，不能等无界 `String` 生成后才检查。层级方案必须在预算内收敛为最终 envelope；超限时确定性缩减覆盖并明确标注，或失败，不得无界循环。
- 取消、后台 expiration 和资源压力在每个批次、层级及运行时可支持的解码检查点响应。具体单步最长不可取消区间由工件/设备验证记录证明；不能承诺抢占任意正在执行的 GPU/ANE 操作。暂停/取消完成必须先确认运行时停止和最后 checkpoint 持久化。

Core ML 的 stateful KV cache 是运行时内部状态，并不要求 Pipeline 保存可变状态；Apple 的示例也明确模型需要在准备阶段声明 state。[Apple Core ML 部署说明](https://developer.apple.com/videos/play/wwdc2024/10161/)

输入和生成长度是不同的 token 预算，chat template 的控制 token 也属于实际输入；这是上述预算公式的技术依据，不意味着采用 Transformers 作为生产依赖。[Generation 参数](https://huggingface.co/docs/transformers/main_classes/text_generation)、[Chat templates](https://huggingface.co/docs/transformers/chat_templating)

## 3. 逐层 provenance 与 coverage

1. 叶子调用只获得其实际批次的摘录及 opaque MemoryID。每次 reduce 只获得实际提交的已校验子结果和各子结果携带的叶子 MemoryID/类型化 provenance；该调用 allow-list 为这些子结果中的有效叶子 ID 并集，不是全周期候选集合。中间节点 ID 不冒充 MemoryID。
2. 每层先执行 envelope 字节/结构/数量校验，再逐段检查本次 allow-list。未知/未提交 ID 被拒绝成为锚点；依 SYN-002 AC-3，段落为 `noSource` 或 `partialNoSource`，并非所有未知 ID 都令整篇失败。未知 schema、畸形或超限 envelope 才整次 L2 fail-closed。
3. v1 reduce 只消费有来源的 `cited` 子段落。`noSource`/`partialNoSource` 子段落不得作为事实摘要输入上层；若最终层出现它们，依现有产品合同诚实展示。中间被省略部分必须计入 coverage，不可通过复制同节点其他段落的 ID 把无来源内容洗成 `cited`。allow-list 仍只验证来源身份，不证明事实蕴含。
4. 每次模型调用前和最终 publication 前重验当前授权与来源身份/内容版本；撤权、删除、用户编辑或策略变化导致输入快照不再有效时丢弃受影响中间结果，拒绝发布旧正文。摘要只用于身份比较，不授权访问；不能因“旧 checkpoint 校验过”继续使用缓存。
5. coverage 由实际执行累计：候选、被选择、实际提交模型的唯一叶子来源数分别计数；实际完成的批次/层数、每类省略及截断原因分别记录。`submittedSourceCount` 不能在调用前等同 selected count，`aggregationLayerCount` 不能由计划默认填 1。`NarrativeReportSource` 的授权/删除依赖至少覆盖实际送入最终生成所依赖分支的全部叶子来源，可保守保存本次所有已提交来源；不能仅保存最终展示锚点，否则遗漏引用的输入仍可能影响正文并逃逸撤权/D-005。展示引用与派生依赖分别计算，不能把保守依赖集伪造为模型显式引用。中间成功不产生最终 `.narrativeReportGenerated`，失败不产生报告完成证据。

## 4. 语言对齐、降级与错误语义

- `preferredLanguage` 来自持久 UserPolicy；只有首次初始化使用系统语言映射，不能在每次生成时用 Locale 覆盖用户已选语言。SYN-001 是 4.0k 的直接验收依赖。
- JSON envelope 先解析校验，再识别生成正文的主体语言；schema key、UUID 与协议引用标签不充当正文语言样本。专名及明确标注的原文引用由冻结验收集标注与人工语言复核评判，不能靠模型自行声明或宽泛正则删除正文来绕过运行时检测。不确定/无可识别自然语言不能直接算匹配成功；简中要求还需脚本检查，不能把所有中文检测结果等同简体。主体语言检测不证明逐词纯度、事实正确或双语可读性；简繁转换只可作为脚本诊断信号，不自动改写生成文本或来源。
- 每个有界模型调用（叶子或 reduce）最多一次**语言**重试，即最多两次推理。重试重新生成完整 envelope，并对同一实际输入 allow-list、schema 和 token 预算再校验，不能只替换字符串后保留旧锚点。schema 失败直接走 L2，不再附加未定义的 JSON 修复轮次；通用 L1 退避不能把一次语言重试扩为三次。
- 每个逻辑报告执行尝试使用总模型调用/时间预算；叶子、reduce、语言重试和恢复重放均计入。新一次用户明确 Continue/Restart 或系统合法资源延后机会的预算边界必须显式记录，不能由内部循环悄悄重置。
- 结果类型区分 validated generation、language fallback、failure/cancelled/resource-deferred。语言重试仍失败时展示跟随 preferredLanguage 的本地化降级提示，不把提示写为成功报告、`completed` 或 generated 审计；有真实输入却产生空 `paragraphs`/空正文也属于生成失败。`noData` 只表示当前确实无可用输入，不表示模型没有输出。

| 情况 | 结果 |
|---|---|
| 版本未装配获批生成能力 | `generationUnavailable`，在物化/claim 前返回，无报告 L2 噪声 |
| 已配置模型缺失/损坏/未批准/完整性失败 | L3，零网络、零报告 publication；手动重试只重读本地工件，不批准或修复工件本身 |
| 语言重试耗尽、畸形/空/超限输出或执行预算耗尽 | L2/只可手动重试的真实错误；本地化提示不算报告成功 |
| 权限拒绝 | 当前 PrivacyCheckpoint denial；不得用 Restart 绕过 |
| 用户取消 | 先协作式停止，保留精确 taskId 恢复状态 |
| 系统 expiration/资源不足 | 释放 claim 并等待下一合法机会；不伪装 L2、完成或自动重放已有 L2 |

NaturalLanguage 提供的是最可能语言/语言假设，不是生成质量或事实正确性评分；识别器判断和真实模型语言质量应分别测试。[Apple dominantLanguage](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer/dominantlanguage)

## 5. 无生成草稿持久化的恢复

v1 不新增中间生成正文缓存。`TaskProgress`/`PendingOperations` 不保存模型输出、KV cache、Memory 原文或授权快照；只保存有界游标、模型/算法/限制版本、语言、输入快照 hash 与恢复阶段等无原文字段。输入摘要仅用于重建一致性比较，不能泄露原始来源标识。

同进程 Pause 保留同一个 job；跨进程 Continue 按精确 taskId 重新授权并重建计划，保留原持久 checkpoint。若后续步骤需要已丢失的中间结果，先在内存重放依赖前缀，不能凭游标跳过它们。UI 明确显示重建阶段，不把重放当新增完成进度，不声称恢复到同一 token。所有重放计入此次执行预算，仍受取消/资源检查。

模型、tokenizer、chat template、算法/限制、目标语言或输入内容摘要改变时，旧前缀不可复用；以 L2 提示 Restart 重新规划，Continue 不能静默当 Restart。Restart 遵守 ADR-011 的预留 taskId、当前校验、事务替换 index 0 checkpoint 后单独入队。工件不合法仍走 L3、授权拒绝仍走 denial；二者不能被 Restart 消除。只有完整生成、最终来源复验与既有原子 publication 成功才完成周期。

## 6. 验收证据与未通过状态

- **合同/故障测试**可以注入模型替身、时钟或系统 adapter 验证边界，但报告中必须标为 contract evidence。**生产生成 E2E** 必须使用真实获批工件、真实生产 composition/解析/语言对齐/SQLite publication，无 `-ui-fixture`、Stub、placeholder 或 cloud fallback。允许把人工构造、无 PII 的测试记忆通过生产摄入入口写入隔离测试库；“no-fixture”不要求使用真实用户隐私数据。
- 模拟器用于兼容性、UI 和可执行的功能回归。真实工件生成、资源/热状态、内存、包体与取消时延需在审批记录声明的实机矩阵验证，不能由双模拟器 Live Review 或 Mac 推理测速代替。保留 iOS 18 最低部署目标；未证明的设备范围保持未通过，不默默提高最低系统或缩小产品支持。
- 保留 SYN-001 首次语言匹配率 ≥99%、语言重试成功率 ≥95% 的目标。候选验收前冻结测试集版本、两种语言/混合来源/长短正文/模板/叶子与 reduce 分层、样本量、分母、预期语言和评判规则；畸形、空或不确定结果不得计作成功。首轮无失败导致重试分母为零时报告 N/A，另用故障注入验证一次重试上限，不把 N/A 写作 100%。生产可见成功正文必须全部通过语言与协议检查；降级提示不计生成质量通过。
- 创作质量还需对锁定的无 PII 样本进行人工来源核查、重要信息覆盖、无依据事实与可读性评估。阈值/样本和资源预算在候选审批时确定并记录，不能仅凭“JSON 合法/allow-list 命中”批准模型质量，也不得在见到结果后移动标准。
- 本次修订不降低 SwiftLint、覆盖率、隐私、发布、签名或 no-media 门禁，不生成 screenshot/video，不新增生产依赖。在 2026-09-07 本次规格修订时，模型审批、资源预算和实机结果尚未完成；后续工件批准见本文 2026-09-08 进展，4.0k 与 DEF-78-001 仍未完成。

## 备选方案与后果

| 方案 | 结论 |
|---|---|
| 采纳：同一任务先形成可审批材料，再实现有界、逐层可追溯生成 | 能独立审查规格与模型选择，保留真实生产交付门禁 |
| 在规格中直接固定未经评估的模型或预算 | 容易违反包体/内存/兼容性与审批边界，不采纳 |
| 把中间正文持久化以便无重放恢复 | 需要新增草稿存储、D-005 删除和授权失效协议；v1 不扩大此范围 |
| 要求跨硬件生成文本完全一致，或把 fallback 算生成成功 | 前者混淆计划确定性与推理表现，后者掩盖质量失败，不采纳 |

文档修订明确了实现和验收范围，但不声明现有代码已满足新合同。4.0k 后续实现必须覆盖本文新增的负向场景，4.2/4.3/4.4/4.6/4.7/4.9 消费相应证据。

## 参考

- ADR-009、ADR-011、ADR-020、ADR-021、ADR-022
- `docs/01-spec/用户故事与验收标准规格书.md` US-SYN-001/002/003/004、US-RES-004
- `docs/05-planning/model-provenance-register.md`
- `docs/05-planning/task-status.json` 4.0k、`deferred-items.json` DEF-78-001

## 2026-09-08 模拟器优先执行补充

用户明确要求“先不用考虑真机，先在模拟器走通”。本轮先完成模拟器真实模型工程闭环，实机、质量与发布审批维持未通过，不再以签名/实机阻止模拟器工作。

模拟器 Debug 可使用从已批准量化工件派生的 CPU 兼容计算图：113 处 RMS 归一化提升为 FP32，再转换回 FP16；量化权重、tokenizer、FP16 KV、上下文及全部运行预算保持原身份/限制。该派生图记录独立完整文件 hash 与来源，只在 Debug simulator 装配；设备和 Release 使用原审批工件，禁止把旧工件审批移植为派生图的设备/发布批准。模型登记和恢复身份必须区分两者。App 内仍只加载预编译 Bundle，不进行转换或下载。

**2026-09-08 模拟器超时修复补充**：Debug simulator 工程派生图可采用固定四 token 输入和显式 `valid_count`，分批处理提示词；解码仍每次只消费一个新 token。填充 token 不得写入 KV 或参与有效 token 的因果注意力。全部 199 组量化张量（含 scale/offset）逐值与原审批图比对，打包偏移变化使用新的完整工件 hash，不冒称原文件字节不变。KV 仍为 FP16/112 MiB、context 1024、input 768、output 256、单调用 60 秒，不能因批量输入减少 token 计费或增加语言重试。`predictionCount` 记录真实模型调用次数，输入/输出 token 数独立保留。动态形状和错误掩码实验不进入 App；固定输入、填充隔离、来源重验与双模拟器真实输出须分别验证。此为用户“进行修复”范围内的模拟器工程变更，不是实机、内容质量或 Release 批准。

已执行诊断：原 CPU 图固定前缀仅 2/8 top-1；提升归一化后模拟器为 8/8，并在 15.584 秒/306 predictions 内以 EOS 完成同一真实 tokenizer/语法约束的完整合成正文。该结果支持继续 App E2E，不代表完整质量验收。

提示版本 `observations-production-v4` 对 zh-Hans 使用明确的简体中文指令，并要求先把英文来源事实译成简体中文再概括；JSON keys 和 opaque MemoryID 保持原协议。英文指令内容、语言检测阈值、一次重试上限、事实约束和预算不变。该提示版本计入恢复身份；正文仍先解析 envelope、再由原 Language Aligner 校验。

## 2026-09-08 诗歌模板 Live Review 修复

用户发现选择诗歌后得到一行照片事实摘要。根因是通用 system prompt 的“只总结”与 user prompt 的“单段”要求覆盖模板意图。`creative-forms-production-v10` 为诗歌使用独立双语指令：四行短自由诗、以来源的意象和节奏创作、每个诗行使用独立的结构化段落；报告和 reduce 保持原事实摘要规则。真实模型的诗歌请求携带 typed outputForm；已有 JSON token grammar 约束四个非空单行段落。模型仍逐 token 选择正文、换行与引用，客户端不插入或重排文本。手动诗歌成功前再次检查合计 3–6 个非空诗行，保留模型原文和来源锚点，禁止客户端断行或预制诗句补救。形式不符没有额外自动模型重试，仅提供用户重试错误。形式检查不代替诗意/事实质量审阅；预算、工件身份、语言对齐与隐私边界不变。

Poem citation presentation follow-up (2026-09-08, user requested): group repeated source links below the poem, hide visible technical IDs, and keep per-line provenance/warnings plus current-policy navigation and export behavior unchanged. This is a UI projection only.

## 2026-09-08 中文诗表达修复（v11）

在用户要求继续修复后，中文诗 prompt 加入一组独立的“素材—四行诗”写法示范，明确仅学习表达方式，实际作品仍由获批模型按用户选中的来源逐 token 生成。示范不存为 Memory、不加入请求 allow-list、来源计数、派生关系或审计来源。示范 UUID 必须避开本次全部实际 MemoryID；即使实际来源碰巧使用默认示范 UUID，也要确定性地选择另一个示范 UUID。既有语法约束不接受示范 ID，禁止事后把示范引用映射到真实记忆。

`creative-forms-production-v11` 保留四个模型生成的诗行段落，仅调整中文诗指令和移除该指令的重复尾句；英文诗、报告、reduce、语言重试、生成工件及预算保持现有行为。完整示范照常纳入 tokenizer 输入预算和恢复身份，不能豁免 prefill 计费。该示范是受信任写作指导，不是 fixture provider 或预制输出；客户端不追加示范诗句、不改写生成正文、不清除不合格措辞后伪装成功。

开发对照显示完整示范改善三个合成题材的表达；缩写示范 ID 的版本出现内容串入，已拒绝。整首诗单段输出及较大缓存模型的对照仅保留为研究记录，未装配。真实 Core ML、双模拟器生成及示范隔离回归另记证据；开发样例改善不等于正式语义、双语可读性或整体质量门禁通过。

## 2026-09-08 中文诗传输引用压缩（v12）

v11 在 iOS 18 的完整示范请求超出 60 秒；固定八 token 的计算图更慢，不装配。逐行重复 36 字符 UUID 的传输成本不能改善可核查性，因此在用户持续修复及规格合理性复审授权下，将来源身份与模型传输编码分开：领域 `sourceMemoryIDs` 仍为 canonical UUID，中文诗请求使用显式 `requestAliasV1` 编码，以实际输入 UUID 的稳定排序建立请求独占的 `S1…S24` 双向表。其他生成请求保持现有 UUID 编码。

别名仅是同一身份的传输表示，不是新的来源或模型提供的映射。模型在受限语法内明确选择别名；还原时按名称查表，禁止按生成段落下标、默认首项或 round-robin 绑定。空引用保持空引用；未知别名、畸形或超限传输输出按 L2 拒绝，不生成假 UUID 或自动补绑。还原前后都验证大小/数量边界，正文逐字保留，随后继续原有来源、语言、隐私与导出检查。领域的外来 canonical UUID / `noSource` / `partialNoSource` 语义不变。

请求与一次语言重试携带同一编码版本和实际 allow-list。别名表不进入 TaskProgress、数据库或审计；实际 source count、派生删除关系与导航仍只使用 canonical MemoryID。模型输入及输出 token 指标按真实传输文本计数；还原后的领域 envelope 不伪装为模型多生成的 token。`creative-forms-production-v12` 纳入恢复身份，完整示范、60 秒、输出 256 token 和原有工件保持原预算。本次不装配八 token 图或更大权重，也不将开发样例当正式质量验收。


## PR #79 输入边界修复与 CI 临时范围（2026-09-08）

- `GenerationInputBudget` 使用现有 16,384-byte 防御上限，在 JSON 编码、转义、来源连接前检查来源数、合计字节及 JSON 转义膨胀（包括 `<`、引号、反斜杠、控制字符和多字节 Unicode）。不截断或改写来源事实；超限返回既有 `contextLimit`。完整 prompt 仍由获批 tokenizer 精确计数并保留输出预算，该字节防御不能替代 token 上限。
- 手动创作的 canonical/effective text 读取在同一 SQLite 查询中使用 UTF-8 BLOB 长度和条件投影：超限时不把完整 canonicalText/title/description/tagsJSON 返回 Swift；逐来源扣除本次剩余预算，连接后检查分隔符开销，重新验证来源时同样有界。SQL 的长度判断不承诺底层 SQLite 无页面读取或零内部开销。
- 用户明确决定“先不发布，CI可以先跳过这相关的”：不发布模型附件、不新下载模型。CI 仅用专用环境开关延期 `BundledGenerationIntegrationTests` 的 2 个参数用例和 `CreationPoemIntegrationTests` 的 4 个参数用例；其原测试断言保留，本地默认启用。CI summary 明示延期，其他测试/编译/覆盖率规则保持现状。
- `DEF-79-002` 继续追踪资源分发与 CI 真模型验收；解除条件是用户批准分发、正确物化/验证冻结工件、移除开关并重跑真实测试。`DEF-78-001` 的质量/实机/完整资格和 `4.0l` 自动照片理解边界保持未通过。获批临时 CI 范围不等于完整 Task 4.0k 通过。
