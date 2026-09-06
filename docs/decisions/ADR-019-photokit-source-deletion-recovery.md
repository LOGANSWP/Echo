# ADR-019: PhotoKit 来源解析与可恢复删除边界

**状态**: 已接受
**日期**: 2026-09-05
**决策人**: Codex 规格合理性评审（依据用户指示）

## 背景

任务 `4.0h` 原合同以“持久化既有 `MemoryDeletionJournal(.planned)` → 请求 PhotoKit 删除 → 恢复时按资产是否可解析决定是否进入 D-005”为主线。结合当前生产模型、既有删除实现与 Apple 公开 API 复核后，发现该合同仍有不可安全实现之处：

1. 现有 `MemoryDeletionPhase.planned` 只表示 Echo 本地 D-005 清理尚未开始，不能区分“PhotoKit 请求尚未获得系统结果”和“外部资产已确认删除、允许本地清理”。若直接复用，崩溃恢复可能在系统删除失败或尚未执行时误删 Echo canonical 数据。
2. `PHAsset.fetchAssets(withLocalIdentifiers:)` 查不到资产并不总能证明资产已删除。limited 选择范围变化、权限撤回或系统限制都会让资产对 App 不可见；这些状态必须与全授权下的“确认不存在”分开。
3. `US-ING-003` 明确原始语音文件不持久化，当前 canonical `sourceLocator` 对 Share Extension 音频只保存 dedupe key，因此 `US-AWK-005` 不能同时承诺语音原件的本地播放。
4. Share Extension 进程没有公开 API 可靠获得 host App bundle identifier。来源能力不能依赖把分享内容猜成 Notes 或 Voice Memos；只能诚实记录 `importOrigin=shareExtension`、内容类型及 Echo 实际保留的本地表示。
5. PhotoKit 的删除可行性不只取决于 `.readWrite` 授权。资产还必须在当前授权范围内可获取，并通过 `PHAsset.canPerform(.delete)`；系统在 `performChanges` 时仍会展示自己的编辑确认。
6. `userNotified=true` 是用户实际看到提示后的事实，不能在清理 `ExcludedAssets` 时预先写入。

## 决策

### 1. 来源解析使用类型化、分面的结果

`FocusSourceResolver` 每次解析都读取当前 `UserPolicy` 与系统授权快照，只返回 `Sendable` 值类型或由 Actor 持有的受控媒体会话。解析结果至少分开表达：

- `contentAvailability`: `available` / `offlineUnavailable` / `authorizationDenied` / `limitedScopeHidden` / `missing` / `unsupported`；
- `presentation`: PhotoKit 图片/视频、canonical 文本、转写文本或诚实不可用；
- `sourceDeletionCapability`: `removeFromEchoOnly` / `photoLibraryDeletable`。

内容是否已下载和是否可删除是两个独立维度。Echo 继续禁止为展示下载 iCloud-only 资源，但可获取且 `canPerform(.delete)` 的 `PHAsset` 可以具备删除能力。只有 photo/video、当前 UserPolicy 允许、PhotoKit 状态为 `.authorized` 或 `.limited`、资产在当前范围内可获取且 `asset.canPerform(.delete)` 时，才返回 `photoLibraryDeletable`。

Share Extension 文本只展示 Echo 已保存的 canonical 文本；Share Extension 音频按 `US-ING-003` 只展示转写文本，v1 不承诺原始音频播放。note/voice/thirdParty 均不具有来源 App 删除能力。来源 App 身份未知时不得由 bundle ID、文件名或内容启发式猜测。

### 2. 在同一删除日志中增加外部结果门禁

不新建第二套 D-005 清理阶段，但必须扩展 `MemoryDeletionJournal`，把“用户意图/外部系统结果”与现有本地清理 `phase` 正交保存：

- `intentKind`: `echoOnly` / `externalCascade` / `photoLibraryAndEcho`；
- `sourceDeletionState`: `notApplicable` / `prepared` / `confirmedDeleted` / `notDeleted` / `indeterminate`；
- `sourceDeletionOutcome`: 可选的结构化结果，如 `userCancelled`、`systemDenied`、`systemFailed`、`completionSucceeded`、`reconciledAbsent`、`authorizationInsufficient`。

同一 `memoryId` 同时只允许一个活动删除 intent。对于 `photoLibraryAndEcho`：

1. 先完成 `PrivacyCheckpoint(.delete)`、当前来源能力与 `canPerform(.delete)` 校验；
2. 持久化 `phase=.planned + sourceDeletionState=.prepared`；
3. 调用 `PHPhotoLibrary.performChanges`，由系统呈现编辑确认；
4. completion 成功后先持久化 `confirmedDeleted`，再允许现有 D-005 phase 从 `.planned` 推进；
5. 用户取消、系统拒绝或调用失败时写入 `notDeleted` 与失败审计，保持 canonical/向量/缓存/ExcludedAssets 不变，然后安全结束 intent；
6. 系统已确认删除后，即使来源授权随后撤回，也必须继续本地 D-005 补偿。该补偿使用 `.delete` checkpoint，但不把已撤回的来源读取权限当作保留本地副本的理由。

`sourceDeletionState != confirmedDeleted` 时，`photoLibraryAndEcho` 日志绝对不得进入缓存、向量、审计清理或 canonical 删除阶段。

### 3. 崩溃恢复不得把“不可见”当作“已删除”

恢复 `prepared` intent 时重新读取 PhotoKit 授权和资产状态：

- full `.authorized` 且资产仍可获取：判定 `notDeleted`，保持 Echo 数据，结束本次 intent，用户可重新发起；
- full `.authorized` 且 localIdentifier 确认不存在：可记录 `reconciledAbsent` 并转为 `confirmedDeleted`；
- `.limited` 且资产仍在当前选择范围内：判定 `notDeleted`；
- `.limited` 下不可获取，或状态为 denied/restricted/notDetermined：结果为 `indeterminate`，保持 journal 与全部 Echo 数据，显示 L2 可恢复动作；不得自动清理。

`indeterminate` 状态允许用户稍后恢复足够授权后复验，或明确改选“仅从 Echo 移除”。后者是新的显式用户选择，按 `echoOnly` 语义写入 `ExcludedAssets`，不得静默改写原 intent。

### 4. 外部级联删除只覆盖可可靠观察的 PhotoKit 资产

v1 的 `US-PRV-007` 仅对已摄入、可通过 PhotoKit 稳定 localIdentifier 追踪的 photo/video 生效。`PHPhotoLibraryChangeObserver` 只在系统向 App 投递变更时触发处理；App 启动/进入前台时执行补偿核对。Share Extension 文本、音频和第三方文件的来源原件位于其他 App 或文件提供者控制域，Echo 不声称能监听其删除。

limited 范围内的“资产不再可见”只表示 `limitedScopeHidden`，不是删除证据；不得触发级联清理。硬性“删除后 5 秒内完成”改为“Echo 收到可验证删除事件或在 full 授权下确认缺失后尽快启动可恢复 D-005 清理”，不承诺 iOS 未给执行机会时的墙钟时间。

### 5. 审计字段必须是真实的结构化事实

`.memoryDeleted` 至少结构化保存：`preservedOriginal`、`sourceDeletionRequested`、`sourceDeletionCompleted`、`sourceDeletionOutcome`、`excludedAssetWritten`、`success`。`.cascadeDeleteFromOriginal` 保存 hash-only 的 asset/memory identity、`excludedAutoCleaned`、`excludedAssetWritten=false` 与结果。

清理无效排除项时先记录 `userNotified=false`。只有“已排除项目”界面实际展示一次性提示后，才另写 `.excludedAutoCleaned` 展示事件并记录 `userNotified=true`；禁止提前宣称用户已获知。

## 验证矩阵

- 来源：PhotoKit image/video、Share Extension text/audio/file、未知来源；
- PhotoKit：authorized、limited-visible、limited-hidden、denied、restricted、notDetermined；
- 能力：asset 可获取但 `canPerform(.delete)==false`、iCloud-only 内容未下载但资产可删除；
- 系统结果：用户取消、系统拒绝、失败、成功；
- 崩溃点：journal prepared 后、系统成功后但 confirmedDeleted 持久化前、confirmedDeleted 后每个 D-005 phase；
- 恢复：full-present、full-missing、limited-visible、limited-hidden、撤权；
- 审计：失败不冒充成功、ID hash-only、`userNotified` 只在真实展示后为 true；
- 并发：同一 memory 双击删除、删除与“仅从 Echo 移除”竞态、外部 change observer 与用户删除竞态。

## 备选方案

| 方案 | 描述 | 结论 |
|------|------|------|
| A（采纳） | 扩展现有 journal，以外部结果门禁保护既有 D-005 phase | 保留单一清理状态机，同时封闭崩溃与授权歧义 |
| B | 继续只用 `.planned` 并以 fetch 为空推断删除成功 | limited/撤权下会误删 Echo 数据，不接受 |
| C | 新建完全独立的 PhotoKit 删除状态机 | 能表达语义，但会与 D-005 重复阶段和恢复逻辑 |
| D | 系统删除成功前先删除 Echo 数据 | 用户取消或系统失败时不可恢复，不接受 |

## 后果

- `4.0h` 需要受控扩展 `MemoryDeletionJournal` schema、恢复协调器、结构化审计字段与 foreground reconciliation；不能只做 UI adapter。
- Source resolver 不再声称能识别 Share Extension host App，也不再承诺非持久化语音原件播放。
- PhotoKit limited 状态变得更保守：不可见资产不会自动级联删除，优先避免误删本地记忆。
- `4.2`、`4.5`、`4.6` 必须消费并验证该门禁，不能用 fixture 或单纯 fetch-missing 测试替代。

## 参考

- Apple Developer Documentation: `PHAsset.canPerform(_:)`
- Apple Developer Documentation: `PHAssetChangeRequest.deleteAssets(_:)`
- Apple Developer Documentation: `PHPhotoLibrary.performChanges(_:completionHandler:)`
- Apple Developer Documentation: Delivering an Enhanced Privacy Experience in Your Photos App
- `docs/decisions/ADR-008-source-import-boundaries.md`
- `docs/decisions/ADR-010-canonical-generation-lifecycle.md`
- `docs/decisions/ADR-017-focus-production-boundaries.md`
- `docs/01-spec/用户故事与验收标准规格书.md` US-SRC-001/003、US-ING-003、US-AWK-005、US-PRV-004/007
