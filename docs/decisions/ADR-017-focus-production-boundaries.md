# ADR-017: Focus 生产写入、来源与创作边界

**状态**: 已接受
**日期**: 2026-09-03
**决策人**: Codex 规格合理性评审（依据用户指示）

## 背景

任务 `4.0e` 原合同把编辑重索引、持久冲突、真实媒体解析、PhotoKit 原始资产删除、引用导航、系统分享审计和月度/年度报告调度放在一个切片中。对照当前生产代码与 Apple 公共 API 后发现：

1. `Memory` 只有 `canonicalText/originalTimestamp/userEdited/userLocked`，没有标题、描述和标签的持久化边界；UI 的这些字段仍是展示值。
2. PhotoKit 资产删除与 Echo 的 SQLite/向量删除不可能组成单个跨系统数据库事务。系统资产删除成功后也无法回滚，只能通过持久删除日志补偿完成 Echo 清理。
3. 备忘录、语音备忘录和第三方内容经 Share Extension 摄入后，Echo 不持有原 App 数据的删除权限，因此不能普遍显示“同时删除原始文件”。
4. `CreativePipeline` 当前按段落序号轮询分配来源，不能证明内容实际由该来源支持；这不满足 US-SYN-002/003 的溯源语义。
5. `sharePresented` 是非敏感布尔事实，不应被哈希。生成完成、分享面板呈现和用户是否完成目标 App 操作是三个不同事件。
6. 当前生产代码没有月度/年度叙事报告调度器；测试或 fixture 不能替代 US-SYN-004 的生产实现。

Apple 公共 API 支持在 `PHPhotoLibrary.performChanges` 内通过 `PHAssetChangeRequest.deleteAssets` 请求删除照片资产；`UIActivityViewController` 的完成回调会暴露活动类型与完成状态，但 Echo 为数据最小化不持久化目标活动类型或用户最终操作。

## 决策

### 1. 拆分任务所有权

- `4.0e`：记忆编辑、重新向量化与持久冲突。
- `4.0h`：真实来源解析、PhotoKit 原始资产删除与删除补偿。
- `4.0i`：可验证引用、稳定 Detail 路由与系统分享审计。
- `4.0j`：月度/年度叙事报告的持久调度、存储、队列与审计基础；生成器不可用时在物化/claim 前 fail-closed。
- `4.0k`：批准的端侧生成式模型运行时、LanguageAligner、真实分批/分层生成与无 fixture 生产闭环。

后续 E2E、删除、覆盖率、本地化、文档和 RC 门禁必须依赖实际消费的全部任务，测试任务不得补写缺失生产功能。

### 2. 用户编辑是 canonical memory 的关系扩展

新增由 repository/actor 管理的 `MemoryUserEdit` 关系，以 `memoryId` 为外键并随 Memory 级联删除。至少保存：可选标题、多行纯文本描述、规范化标签集合、更新时间。v1 不承诺富文本格式编辑；描述使用可本地化、可访问、可确定序列化的多行纯文本。原始来源文本保持不变。

用于检索的有效文本按固定顺序由用户标题、用户描述、规范化标签和原 canonical 文本组成。保存事务先生成并持久化新表示与向量，再原子发布新的关系/FTS/representation 绑定、结构化审计和 `memoryEditPostCommit` 清理任务；发布提交前失败保留旧可服务版本。发布提交后用户保存已经成功；旧向量清理或索引持久化失败不得反向报告保存失败，而应恢复提交前已持久化的索引检查点，保留旧向量与 PendingOperations 记录，并等待用户手动重试。覆盖时间戳写入 `Memory.createdAt`，`originalTimestamp` 在第一次覆盖时保存原值且之后不改写。

### 3. 冲突必须持久化

新增 `MemoryEditConflict` 关系保存 memoryId、外部版本摘要、检测时间和可重放的来源变更参数；本地草稿来自 `MemoryUserEdit`。同步遇到 `userLocked=true` 时跳过自动覆盖；未保存编辑会话或已持久化用户编辑遇到外部变化时都持久化 conflict，不覆盖本地编辑。普通保存以数据库条件事务拒绝现存 conflict。选择本地版本会在同一事务清除 conflict 并写 `userLocked=true`；手动合并在同一条件事务发布编辑、清除 conflict 并锁定。选择外部版本由 SyncPipeline 重放持久化变更，只有 canonical/representation 替换成功后才通过级联清除用户编辑关系和 conflict，并保持 `userLocked=false`；失败保留 conflict。显式“重新同步”清除锁并重新读取来源。

### 4. 原始来源删除采用有序 saga（由 ADR-019 收紧）

“同时删除原始文件”仅对当前 UserPolicy 允许、PhotoKit 授权范围内可获取且 `PHAsset.canPerform(.delete)` 的 photo/video 显示。Share Extension 摄入内容和只读、失效、limited-hidden 来源只提供“仅从 Echo 移除”，并明确 Echo 无法删除来源 App 中的原件。

PhotoKit 删除流程为：验证来源、权限与 `canPerform(.delete)` → 在既有 `MemoryDeletionJournal` 中持久化 `intentKind=photoLibraryAndEcho + sourceDeletionState=prepared + phase=.planned` → 请求系统删除 → completion 成功后先持久化 `confirmedDeleted` → 才允许进入既有 D-005 本地清理阶段 → 清除 Echo 向量、FTS、缓存、metadata、关系数据和关联审计 → 标记完成并清理日志。系统拒绝、用户取消或失败时不修改 Echo canonical。恢复时 full authorized 的确认缺失可推进；limited/撤权下不可见为 `indeterminate`，禁止本地清理。系统删除成功但 Echo 清理失败时保留恢复日志并进入 L2。该流程不声称可以回滚已经删除的系统资产。

该 saga 复用现有 `MemoryDeletionJournal` 与后续 D-005 phase，不建立第二套本地清理状态机；但必须增加正交的外部结果门禁，不能让 `.planned` 同时承担两种语义。`4.0h` 补充 PhotoKit 请求前后的编排、能力解析、schema 演进和恢复判定，完整规则以 ADR-019 为准。

### 5. 引用必须由模型输出绑定并经过校验（由 ADR-020 收紧）

生成协议要求每个段落返回显式 source memory IDs。ADR-020 进一步要求版本化、有字节/段落/字符/引用数上限的 JSON envelope，只向模型暴露 opaque MemoryID。解析器只接受当前策略过滤后实际提交模型的稳定 MemoryID；未知、缺失或无法解析的 ID 不得轮询替换。每段以 `[SourceAnchor]` 和 `cited/noSource/partialNoSource` 表达 provenance；allow-list 命中不声称自动证明事实。有来源锚点点击后重新按当前 UserPolicy 和 source resolver 校验，再进入对应 Detail；失败显示诚实不可用状态。

### 6. 分享与生成审计分离（由 ADR-020 收紧）

- `.creativeGeneration`：生成完成时记录 `templateType`、`sourceMemoryCount`、`citationCount`、`noSourceCount`。
- `.creationSharePresented`：本地导出准备完成且系统 share sheet 成功呈现后记录 `exportFormat`、`sharePresented=true`，报告可附 `periodType`。
- `.narrativeReportGenerated`：报告生成后记录 `periodType`、实际使用的数据源类别和幂等周期键摘要。

`sharePresented` 使用结构化布尔字段，不哈希；MemoryID、周期幂等键和自由文本只保存摘要。Echo 不持久化 `activityType`、目标 App、用户完成状态或导出原文。复制与所有导出准备前重新执行当前 UserPolicy + PrivacyCheckpoint，按 ADR-024，所有外部格式默认只含标题和正文，引用及来源状态留在 App 内。只有系统控制器实际呈现回调后才写 true；用户关闭已呈现的 share sheet 不算失败，准备或未进入呈现回调即失败按 L2 并写 false。真实呈现后的审计写入失败不得改写事实，须进入不含原文/目标的幂等 L2 重试。审计字段必须使用专用 typed columns，不得编码进 `sourceLanguage`；完整规则见 ADR-020。

### 7. 叙事报告采用持久的 earliest-eligible 调度（由 ADR-021/022 收紧）

月报和年报使用本地持久周期键保证每周期最多生成一次。ADR-021 进一步规定：月/年持久开关新安装默认开启，在同意持久化且首条可用 canonical memory 落库时建立 `eligibleFrom`，升级/关闭后重开使用新基线；只覆盖刚结束的完整公历周期；首次物化冻结时区与 UTC 边界；每次扫描只 CAS claim 一个最早周期。`NarrativeReportPeriod/Report/Source` 形成独立领域真相，成功 publication 原子写报告、来源关系、完成状态与审计。L2 仅手动重试，系统 expiration/资源不足只延后；无数据、删除与撤权分别使用 `noData`/`invalidated` 和 D-005 清除边界。详细可执行合同以 ADR-021 为准。

ADR-022 进一步确认当前生产 composition 尚无批准的生成式 LLM：`4.0j` 只交付上述调度/存储基础和可注入生成器 seam，生产无生成器时不得物化、claim 或写 L2；`4.0k` 才能以批准的 Bundle 工件、真实 `LLMProvider`、`LanguageAligner` 和 no-fixture E2E 关闭自动生成 AC。Stub 仅是单元测试证据。

## 备选方案

| 方案 | 描述 | 结论 |
|------|------|------|
| A（采纳） | 拆为四个生产边界，使用关系扩展、删除 saga、显式引用协议和持久调度 | 可执行、可恢复、可独立验证 |
| B | 保留单一 `4.0e` 巨型任务 | 风险与验收边界过大，失败无法定位 |
| C | 通过 fixture 或后续 E2E 补足缺失行为 | 无生产实现，违反真实性门禁 |
| D | 对所有来源提供原始删除并把 PhotoKit/SQLite 当作原子事务 | 超出 iOS 权限与事务能力 |

## 后果

- Phase 4 新增 `4.0h`、`4.0i`、`4.0j`、`4.0k`，任务数由 22 增至 26。
- `4.0e` 仍是当前首个 ready 任务，但范围缩小为编辑/冲突闭环。
- 需要数据库迁移与新 Actor/repository API；所有新写路径遵守 PrivacyCheckpoint、strict concurrency、D-005 和 hash-only 内容审计。
- v1 编辑器不保留富文本样式，但标题、描述、标签和时间覆盖均可持久化、检索和恢复。
- 只有当前可获取且 `PHAsset.canPerform(.delete)` 的 PhotoKit photo/video 支持从 Echo 发起原始资产删除；Share Extension 音频原件不持久化时只展示转写文本。

## 参考

- `docs/01-spec/用户故事与验收标准规格书.md` US-AWK-007、US-PRV-004、US-SYN-002~004
- `docs/02-architecture/架构设计文档.md`
- `docs/02-architecture/数据流全链路技术说明文档.md`
- `docs/decisions/ADR-010-canonical-generation-lifecycle.md`
- `docs/decisions/ADR-013-creation-export-boundary.md`
- `docs/decisions/ADR-019-photokit-source-deletion-recovery.md`
- `docs/decisions/ADR-020-grounded-citation-share-audit.md`
- `docs/decisions/ADR-021-narrative-report-scheduling-persistence.md`
- `docs/decisions/ADR-022-offline-generation-runtime-gate.md`
- Apple Developer Documentation: `PHAssetChangeRequest.deleteAssets(_:)`, `UIActivityViewController.completionWithItemsHandler`
