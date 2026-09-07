# Echo UI 测试与 Artifact 规范

> **上游权威**：`Echo SwiftUI UI Agent 自动化 Bootstrap 与执行规范.md` §12、§13、§17、§18、§20

---

## 1. PR 与 Nightly 验证矩阵

| 维度 | PR 门禁 | Nightly 门禁 |
|------|---------|-------------|
| 契约 | 所有 schema 和引用校验 | 全量校验并检查孤立 ID |
| Build | 受影响 target clean build | 全量支持配置 build |
| State | canonical loaded + 变更相关 | loading/loaded/empty/error/modal |
| Journey | 受影响关键路径 smoke | 全量关键 journey |
| Device | 双固定 simulator：iPhone 17 Pro (iOS 26.5) + iPhone 16 Pro (iOS 18.x) | 小屏、标准屏、iPad |
| Theme | 变更相关 | light + dark |
| Dynamic Type | default + 1 accessibility size | default、中间档、最大支持档 |
| Locale | 默认 | long Latin、CJK、RTL 或伪本地化 |
| Contrast | 默认 | increased contrast |
| Motion | 变更相关 | Reduce Motion 开/关 |
| 可访问性 | 自动 audit、稳定 ID、关键标签 | audit、语义证据 + 人工记录 |
| 视觉 | 双设备 Live Sim Review（变更 surface） | 结构化检查，不保存媒体 |
| 安全 | artifact secret/PII 扫描 | 依赖、权限、telemetry 复核 |
| Masonry | 受影响 surface 的 rich-data 默认双列 + 低数据/AX 回退检查 | 全部 Discovery surface 的阈值、启用/回退、列数、稳定顺序与 Dynamic Type 响应 |
| Surface Family | 受影响 surface 的 family 规则验证（禁止 Focus/Task 使用 masonry） | 全部 surface 的 family 规则全量验证 |
| Visual Profile | 受影响 surface 的共享 token/component 与 App Shell 一致性 | 全 App 逐 Surface `echo-memory-canvas` 一致性审计 |

---

## 2. 测试策略

> **String Catalog 验证**（所有测试层级的通用前置条件）：
> - PR 门禁：所有 `zh-Hans` + `en-US` 键均有值，无缺失翻译
> - 运行时校验：`String(localized:)` 不应 fallback 到开发语言
> - 术语表覆盖率 ≥ 90%（基于 `UIAutomation/Fixtures/` 术语 Golden Dataset 校验）

### 2.1 契约测试
- 校验 schema 版本、必需字段、未知字段策略
- 确认 design profile 为 `echo-memory-canvas`、基础为 `apple-native`
- 校验 surface/state/action/journey/fixture/artifact 交叉引用
- 所有 fixture 可确定性解码

### 2.2 Adapter 测试
- 使用 Core 协议受控替身验证状态映射
- 验证异步取消、重复 action、错误映射、主线程发布
- 断言 adapter 不保存第二份领域真相

### 2.3 View 与组件测试
- 每个关键 state 有具名 Preview
- 验证 Dynamic Type、主题、长文本、空内容和可访问性语义
- Discovery 验证 rich-data 状态默认 masonry、稳定语义排序、真实 aspect ratio 和低数据/AX 单列回退
- Focus 与 Task 验证不存在 masonry
- 所有 Surface 验证 `designProfileId=echo-memory-canvas`，并检查共享 typography、accent、spacing、radii、container hierarchy、status/action components 与 motion
- 一致性测试不得把像素截图作为真相；使用 token/component 身份、accessibility tree、布局模式和双设备 Live Review 共同验收
- Preview 是开发反馈，**不是**最终视觉审批渠道

### 2.4 Journey 测试
- XCUITest 从用户可观察入口执行
- 使用稳定 accessibility identifier，避免依赖坐标
- 关键断言覆盖行为结果和必要语义

### 2.5 视觉与可访问性测试
- **不调用 screenshot/screen-recording API**
- 不生成 reference/actual/diff，不维护图像 baseline
- 自动化使用 accessibility tree、元素存在性、点击区域、文本截断审计
- 自动 accessibility audit 不能替代 VoiceOver/Voice Control/Switch Control 专项检查
- 最终视觉判断只通过 **Live Simulator Review（双设备）**（bootstrap 规范 §11.4）：iPhone 17 Pro (iOS 26.5) 主审查 + iPhone 16 Pro (iOS 18.x) 最低版本审查
- Home 必须分别验收 0、1~19、20+ 三档真实数据状态；20+ 在默认 Dynamic Type 与足够宽度下应呈现双列平衡画布
- Home 的 0 条状态必须拆分验证：有真实活跃扫描任务时显示真实 determinate 进度；无任务/已完成/未授权时不显示 ProgressView 或扫描中文案
- Search 必须分别验收 `<6` 与 `>=6` 个可展示结果；`>=6` 时仅当 `scanEligible` 严格多于 `continuousReading` 才进入 masonry，平票与连续阅读占多数均保持单列
- “可展示”测试数据必须满足：策略允许、未排除、来源可解析、稳定 memoryId/Focus 路由存在，并具有真实 aspect ratio 或真实摘要；失效来源不得计入阈值
- VoiceOver reading order 必须与稳定语义数据顺序一致，不以视觉列位置作为断言
- 4.0a 验证通用 Discovery 卡无水平滑动手势；4.0d 验证 US-AWK-005 专用唤醒卡左右滑与等价按钮/辅助功能动作产生相同 intent，并覆盖稳定 next/无后继禁用、取消不写入、`MemoryFeeling` 事务/级联删除/不可搜索、hash-only 审计、Bundle 离线音乐与显式 opt-in 后仅设备非云端曲目匹配；扫描不得出现 MusicKit catalog/personal/recently-played 路径
- 4.0b 必须从真实 Home/Search 路由进入 Detail，验证稳定 MemoryID 与返回栈；分别覆盖 note/photo/voice/video 的真实展示或诚实不可用态，禁止 bundled sample 进入生产证据
- 4.0b Creation 必须覆盖 grounded output、无来源、runtime unavailable、引用跳转与 NoSource；Notes 入口只断言系统 share sheet 呈现/取消/呈现失败，不断言“已保存”、目标 App 或笔记链接
- 4.0b Translation 必须覆盖 cache hit、`<0.9` uncertain、unsupported pair、L2 retry 与原文/译文关系；Focus 三个 Surface 均验证无 masonry、共享组件/token、Accessibility Dynamic Type 与 VoiceOver reading order
- 4.0e 以 no-fixture 路径验证 `MemoryUserEdit` 多行纯文本编辑、安全重索引发布、时间戳备份、持久 `MemoryEditConflict`、local/external/merge 与 `userLocked` 同步跳过；每个故障点必须证明旧版本仍可服务
- 4.0h 验证类型化来源矩阵：PhotoKit photo/video 分开断言内容可用性与删除能力；Share Extension text 展示 canonical，audio 只展示转写且所有 Share 来源不可删、不猜测 host App。删除能力要求 UserPolicy、authorized/limited-visible、资产可获取与 `PHAsset.canPerform(.delete)`；iCloud-only 未下载不与删除能力混为一谈。请求前持久化同一 journal 的 `intentKind=photoLibraryAndEcho + sourceDeletionState=prepared + phase=.planned`，只有 `confirmedDeleted` 解锁 D-005。覆盖取消/拒绝/失败、full-present/full-missing、limited-visible/limited-hidden、撤权、每个崩溃点、同 memory 并发 intent、真实结构化审计，以及 ExcludedAssets 提示实际展示前后 `userNotified=false→true`
- 4.0i 验证版本化受限 JSON envelope 的正常/未知版本/畸形/超限路径，opaque source ID 精确 allow-list，无 round-robin fallback，以及 `[SourceAnchor]` + `cited/noSource/partialNoSource` 多引用语义；断言 UI 不把 provenance 表述为事实验证。导航在当前 UserPolicy 下进入稳定 Detail 或诚实不可用。复制、plain text、Markdown、PDF 分别覆盖当前授权复验、撤权阻断、离线来源保留诚实标记、引用保留和多页无截断。分享测试区分 payload 就绪但未呈现、准备失败、呈现失败、真实呈现、呈现后关闭和呈现后审计写入失败；验证 typed audit columns、幂等 L2 重试，以及零 activityType、目标 App、原文、assetID/sourceLocator
- 4.0j 验证月/年周期键、跨时区、重复启动、错过周期、关闭开关、TaskQueue/Progress 重启恢复和不可用数据分区省略；fixture 报告不得计为调度证据
- 4.0c 必须逐一覆盖 Settings、Onboarding、AwakeningSettings、BackgroundTask、Degradation、ResumeProgress：`designProfileId=echo-memory-canvas`、Task/no-masonry、系统 container、共享 grouped/status/action 组件、default + Accessibility Dynamic Type、VoiceOver reading order、Reduce Motion、light/dark 与 destructive confirmation。生产路径不得注入 fixture，也不得改变现有 consent/permission/model/task/migration/delete 副作用
- 4.0c 契约门禁必须把六个 Task surface 的 legacy contract 全部迁移或补齐为 v1 schema-compatible surface/state/action/journey；稳定 ID 保持不变，surface 声明的每个 state 均有唯一 state contract，journey 的每个非终态 action 均可解析，禁止以“历史格式”跳过校验
- 4.0c Onboarding 视觉验收只验证诚实状态层级；4.0f 以 no-fixture production adapter + 调用 spy 覆盖：consent 持久化完成前零受保护请求；仅 Connect Photos 请求 PhotoKit，Not Now 零调用；通知独立 opt-in；geofence When In Use 与 Always 两段请求；emotion 仅请求 HRV read scope；anniversary 零系统权限；拒绝/跳过可继续；打开页面与重启零自动 prompt
- 4.0f 不断言 HealthKit read granted/denied。测试只断言 request lifecycle、请求类型集合、样本可读/空样本回退与 unsupported；不得用 `authorizationStatus(for:)` 或 request completion success 作为读取授权证据
- 4.0f 的 Core Location fake 必须证明 async 请求在 delegate 回调前不完成；Always 只在 When In Use 后的第二个明确动作发生。通知测试在 completion 后复读 `UNNotificationSettings`，并覆盖 provisional/ephemeral 映射
- 4.0f 必须证明唤醒偏好和 HealthKit request lifecycle 写入 SQLite 后可跨 ViewModel/重启恢复，同时所有系统授权快照均来自 live adapter；恢复偏好不得产生 request API 调用
- 4.0g 必须以 no-fixture 路径证明已持久化任务可在重启后重建：Continue 从准确 resume point 执行且入队不覆盖 checkpoint；Restart 先事务性替换为 index 0 可重试记录再单独入队，入队失败保留记录。覆盖未知 raw task type、malformed/oversized/version-mismatch resumeData、撤权后恢复、多个同 taskType taskId、当前会话活跃行排除、double-tap/取消-完成竞态、pause 保留同 job、完成/最终失败清理和结构化实际 userChoiceOnRestart 审计。恢复中间态禁止重复操作，只在队列接管后显示 resumed/restarted
- Settings migration journey 必须区分“加密 Echo 迁移包”和“全部原始媒体导出”：前者覆盖 system share/AirDrop handoff、分离密钥、覆盖/合并/冲突/rollback；后者必须不存在。测试不得检查或持久化传输密钥、原文、截图或分享目标 App

### 2.6 权限流程测试（Permission Flow Testing）
- 系统权限对话框拒绝路径覆盖（相册、麦克风、语音、通知等）
- 权限变更后的 UI 更新验证（从 Settings 返回后的状态刷新）
- XCUITest 使用 `addUIInterruptionMonitor` 处理系统弹窗
- 覆盖场景：首次拒绝 → 降级 UI / 空状态引导 / 设置引导入口

### 2.7 多分支旅程测试（Multi-branch Journey Testing）
- 每个 Journey 的分支路径（同意/拒绝、成功/失败、有数据/无数据）均需覆盖
- 禁止仅覆盖 Happy Path；分支覆盖度是 Journey 测试的必过门禁

### 2.8 跨 Surface 旅程测试（Cross-Surface Journey Testing）
- Home → Search → Detail → 返回的完整路径（跨 Discovery → Focus 边界）
- 通知点击 → 深层链接到具体记忆详情
- 验证 NavigationStack 返回栈完整性

---

## 3. Artifact 规范

每次运行必须生成 manifest，记录：
1. run ID、actor、时间、commit SHA 和 dirty flag
2. 契约版本/hash、fixture ID/hash、acceptance policy hash
3. Xcode、SDK、runtime、设备（双审查设备 17 Pro + 16 Pro 的 UDID/runtime）、架构、locale、timezone、主题
4. simulator 所有者（唯一 owner）、工具版本和配置摘要
5. surface/state/journey/test ID
6. build/test/audit/视觉结果
7. raw build log、结构化测试摘要、accessibility tree、`.xcresult`、crash report、manifest hash
8. `visualMediaCaptured`：布尔字段，必须为 `false`。**绝不**记录 screenshot、reference/actual/diff、video 路径

### Artifact 保留策略
| 产物 | 保留规则 |
|------|----------|
| manifest、结构化摘要、必要日志、accessibility tree | 持久化到 `UIAutomation/Artifacts/` |
| 通过的 `.xcresult` | 摘要写入 manifest 后可删除 |
| 失败的 `.xcresult` | 保留至 blocker 解决或任务完成 |
| CI artifact | 短期 retention，不提交到 Git |

---

## 4. 各阶段 Definition of Done

### Bootstrap DoD
- 只读 inventory + 保护路径清单
- 14 个现有命令兼容性清单
- Migration map（全部责任有归属）
- AGENTS.md 路由 merge
- `docs/ui/` 6 文件完整
- `UIAutomation/` 4 目录
- `.ui-automation/state.json` schema
- 适配后的 init/next 命令
- 新增 ui-bootstrap-build/status/retry 命令
- **String Catalog 完整性扫描**：所有 `zh-Hans` + `en-US` 键均有值，术语表覆盖率 ≥ 90%
- 每批结构变更后的 build 原始日志

### 试点 DoD
- 候选评分表与选择记录（8 维度评分 + 淘汰原因）
- 试点 surface/state/action/journey/fixture 契约（schema 校验通过）
- Fixture 完整性验证（覆盖契约声明的所有 state）
- SwiftUI View + 薄 adapter + 具名 Previews
- Adapter/行为/XCUITest/accessibility 证据
- Live Simulator Review 上下文（双设备 17 Pro iOS 26 + 16 Pro iOS 18，surfaceId/stateId/fixtureId 匹配）
- **UI 审查指南**（报告必需）：本次添加/修改页面清单（🆕/✏️ + 文件路径）+ 导航路径（如何点击到达）+ 未实现功能/临时效果（🔮 Phase 标记、fixture/stub 数据、String Catalog 未迁移）
- **不生成持久化视觉媒体**
- **权限拒绝路径测试通过**：试点 surface 关联的所有系统权限，拒绝路径均已通过 XCUITest

### 后续切片 DoD
- 受影响 readiness/hash 复检
- 一个边界清楚的 UI 切片
- 必要测试 + 受影响验证矩阵
- 两台 Simulator（17 Pro iOS 26 + 16 Pro iOS 18）导航到目标 state 并保持前台

---

## 5. Phase 3F 感知

> Phase 3F 的 UI 任务（3F.7–3F.10）沿用本节全部测试与 artifact 规则，以下为 3F 专项补充。phase ID 为字符串（含 `"3F"`），任务账本见 `docs/05-planning/task-status.json`。

- **测试套件**：每个 Phase 3F UI 任务配套 `EchoTests/Phase3F/` 单元/集成测试（如 `3F.7_UIToCoreIntegrationTests.swift`、`3F.8_AwakeningSystemAdaptersTests.swift`）与 `EchoUITests` 旅程套件；阶段集成测试为 `EchoTests/Phase3F/Phase3FIntegrationTests.swift`（`3F.11`）
- **PR 门禁不变**：受影响 target clean build、契约校验、双设备 Live Simulator Review（变更 surface）、String Catalog 双语键完整，均与 §1 一致
- **双设备 Live Simulator Review 要求**：Phase 3F UI 交付的视觉批准仍只通过双设备 Live Simulator Review——iPhone 17 Pro (iOS 26.5) 主审查 + iPhone 16 Pro (iOS 18.x) 最低版本审查，同一产物安装到两台设备；Agent 不能自行批准界面
- **无媒体 manifest**：每次运行的 manifest 必须记录 `visualMediaCaptured: false`（§3 第 8 项），Phase 3F 同样不创建、不持久化 screenshot、video、reference/actual/diff，不维护图像 baseline
- **生产集成专项**：Phase 3F 的测试强调「默认 App 无 `-ui-fixture` 参数」的生产路径证据（如 3F.7 默认 live adapter、3F.11 no-fixture E2E），fixtures 仅用于测试或 Preview，不作为生产完成证据
