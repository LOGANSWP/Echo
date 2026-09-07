# ADR-021: 月度与年度叙事报告调度、持久化与删除边界

**状态**: 已接受
**日期**: 2026-09-07
**决策人**: Codex（依人类指令执行规格合理性复审）

## 背景

US-SYN-004 与 ADR-017 已确定月报/年报采用 `earliest-eligible`、持久周期键、`TaskQueueActor` 与 `ProgressActor`，但仍缺少可实现且可测试的周期定义、首次启用基线、跨时区行为、并发 claim、报告本体存储、来源删除、空数据终态和系统后台过期语义。原任务约束还把 L2 描述为“手动重试或下一合法调度机会重建”，与 ADR-011 的“L2 仅手动重试、无自动重放”冲突。

若仅保存“完成键”，后台生成的正文没有可恢复读取位置；若正文与完成键分开写入，并发的启动/前台/后台触发可能重复生成或留下半完成状态。若不保存报告引用的 MemoryID 关系，记忆删除或撤权后也无法完成派生数据清理与交接前复验。

## 决策

### 1. 周期与启用基线

1. 月报覆盖当前本地日历中**刚结束的完整公历月**，年报覆盖**刚结束的完整公历年**；不生成进行中的月份或年份。
2. 月度与年度调度分别使用持久开关，并分别持有 `monthlyEligibleFrom` / `yearlyEligibleFrom`，新安装默认开启，以保持“自动生成、可关闭”的产品语义。新安装在 PIPL 同意已持久化且第一条可用 canonical memory 落库时同时设置两类基线；已有数据的升级安装在本版本首次成功迁移时设置。关闭某类调度只停止该类新周期，重新开启只以该时刻重设该类基线，不得改变另一类仍开启调度的基线；不得自动补算各自基线之前或关闭期间的周期。已完成报告继续保留，除非用户删除或执行数据主权清除。
3. 周期身份为稳定 `periodType + periodKey`：月为 `month:YYYY-MM`，年为 `year:YYYY`。首次物化周期时同时保存日历标识、时区标识与 `[startInstant, endInstant)` UTC 边界；设备后续跨时区不重算既有边界，也不改变键。只有 `endInstant >` 该周期类型对应的 `eligibleFrom` 才可被物化；该类型首个周期的实际输入范围从 `max(startInstant, eligibleFrom)` 开始，并在 coverage metadata 明确 `partialBaseline=true` 与实际 coverage 起点，避免等待下一个完整年，也不读取基线前历史数据。
4. 同一次扫描最多 claim 一个最早符合周期。结束时间相同时先处理月报再处理年报；后续周期等待下一次 App 启动、进入前台、获准后台执行或用户明确生成/重试，避免一次唤醒形成无界追赶。

### 2. 持久状态与 exactly-once publication

1. 新增 `NarrativeReportActor`，通过 `DatabaseManager` 管理：
   - `NarrativeReportSchedule`：月/年开关、各自的 `eligibleFrom` 与设置 revision；
   - `NarrativeReportPeriod`：周期身份、冻结边界、状态与 claim revision；
   - `NarrativeReport`：版本化且有大小上限的本地报告 envelope、标题与创建时间；
   - `NarrativeReportSource`：报告与 opaque MemoryID 的关系，用于授权复验和删除级联。
2. 周期状态至少区分 `eligible`、`claimed`、`retryRequired`、`completed`、`noData`、`invalidated`。数据库对 `(periodType, periodKey)` 建唯一约束，claim 使用 compare-and-set/revision；启动、前台和后台并发触发只能有一个获胜者。
3. 生成成功后，先由 `PrivacyActor` 依据当前 checkpoint 准备不含内容的 Sendable `NarrativeReportAuditPayload`；该步骤只生成已校验值，不提前写 AuditLog。随后由 `DatabaseManager` 的专用 publication API 在一个**无挂起点事务**中写入报告 envelope、来源关系、周期 `completed` 状态与 payload 对应的 `.narrativeReportGenerated` 结构化记录。任一写入失败整体回滚，不允许跨 Actor 伪原子、不允许“有完成键但无报告”或“有报告但无审计”的可见成功。
4. `noData` 是自动调度终态：当前策略下周期内没有任何可用 canonical memory 时不生成正文，也不写 `.narrativeReportGenerated`，但持久化 `noData` 以避免每次前台重复计算。因该周期尚未成功，后续仅可由用户明确请求重新生成；不能用 fixture 或占位数据把它改写为成功。

### 3. 队列、恢复与错误

1. 报告任务新增稳定 `TaskType` 与版本化、有大小上限的 resume descriptor，只保存周期身份、聚合游标与算法/限制版本；不得保存授权快照、报告原文、Memory 原文、模型输出或任意闭包。
2. 所有调度、claim、生成、恢复与发布异步入口先执行适用的 `PrivacyCheckpoint`，并按当前 `UserPolicy` 与真实来源重新筛选。任务经 `TaskQueueActor` 串行执行，`ProgressActor` 只保存进度快照，不充当周期完成真相。
3. 生命周期扫描只自动 claim `eligible` 周期。进入 `retryRequired`/`PendingOperations` 的 L2 周期必须由用户明确重试，后续扫描不得自动重放或重建。
4. 系统后台到期与低电量、serious/critical thermal 等资源不足不是 L2：任务协作式停止，在安全 checkpoint 释放 claim 并回到可调度状态，等待下一合法机会。用户取消则保留可恢复状态，遵循 ADR-011 的逐 taskId Continue/Restart 语义，不得被普通扫描接管。
5. 后台执行仅是补偿机会。实现必须注册允许的 `BGProcessingTask` identifier、启用 capability/Info.plist 声明、处理 expiration、准确调用 completion 并按系统规则重新提交请求；产品和测试均不得承诺精确执行时刻。

### 4. 输入有界与诚实降级

1. 聚合顺序必须确定：按周期、来源类型、时间与稳定 MemoryID 排序；相同输入与配置产生相同中间批次和报告请求。
2. 输入采用版本化 `NarrativeReportLimits`，显式限制单批来源数、单条摘录扩展字形簇数、中间聚合层数/数量、模型输入字节与最终 envelope 大小。超限数据使用确定性分批与层级聚合，不得构造无界 prompt；任何覆盖截断或分区缺失都进入报告的结构化 coverage metadata。
3. 至少存在一个真实、当前授权的数据分区即可生成报告。人物或 HealthKit 等可选能力不可用时省略该分区并明确标注，不得用 fixture、占位人物、推断身份或伪造健康数据补齐版式。
4. 生成沿用 ADR-020 的版本化 provenance envelope。allow-list 只证明来源身份，不自动证明事实；所有可核查数据点使用 `cited/noSource/partialNoSource` 与可验证来源锚点。

### 5. 读取、分享、删除与审计

1. 完成报告仅在本地以 `NSFileProtectionComplete` 保护。Creation/Focus UI 读取持久报告和真实调度状态，不得把 fixture 报告当生产证据。
2. 查看已持久报告可以保留“来源当前不可用”的诚实标记；导航、复制、导出、打印或系统分享准备仍须按 ADR-020 重新执行当前授权复验。Notes 只通过用户可见的系统 share/export 交接，Echo 不推断目标 App 或保存结果。
3. 用户可以删除报告；删除事务同时将其周期标记为 `invalidated`。删除 canonical memory 时，同一 D-005 清理事务删除所有引用它的 `NarrativeReportSource` 与对应派生报告，并把周期标记为 `invalidated`。`invalidated` 在 v1 是不可重新生成的终态，防止删除后的派生内容被自动或手动复建；未来若提供历史重建，必须以新的版本化产品合同和身份键另行审批。撤销全部同意时清除调度设置、报告、来源关系、周期状态和相关待处理描述。
4. `.narrativeReportGenerated` 使用专用 typed columns：`periodType`、以 canonical JSON 编码且排序去重的真实 source-type enum 数组 `dataSourcesUsed`，以及 64 字符 hash-only `periodKeyDigest`；不记录正文、标题、原文、MemoryID、source locator 或目标 App。`periodKeyDigest` 建事件范围内唯一索引，禁止窗口扫描或复用 traceID 猜测幂等。

## 备选方案

| 方案 | 描述 | 结论 |
|------|------|------|
| **A（采纳）** | 默认开启的持久月/年开关与基线 + 周期/报告/来源状态 + 原子 publication + 手动 L2 | 保留自动生成语义，同时可测试、可恢复并满足隐私删除与 exactly-once |
| B | 仅保存完成键，正文保留在内存或 UI | 后台生成结果会丢失，无法删除派生数据 |
| C | 每次启动重新扫描并自动重试所有失败周期 | 可能重复耗电，且违反 ADR-011 的 L2 仅手动重试 |
| D | 依赖固定每月/每年后台时刻 | iOS 不保证执行时刻，属于不可验证承诺 |
| E | 无界读取全年所有原文后一次性生成 | 内存/模型上下文不可控，无法形成稳定测试边界 |

## 后果

### 正面

- 周期、跨时区、漏跑补偿、重复触发、空数据与关闭/重启语义均可确定性测试。
- 报告本体、来源关系、周期完成和审计不会出现部分可见提交。
- L2、系统 expiration 和资源延后不再混用，避免静默自动重放。
- 删除与撤权可覆盖派生报告，不留下无法定位的本地副本。

### 负面

- 需要新增 SQLite schema/迁移、报告 Actor、任务类型、恢复 launcher 与 BGProcessingTask 接线。
- 历史周期不会在首次启用时无限补算；希望补算时必须由后续显式产品动作单独定义。
- 系统可能长期不给后台机会，报告只能在后续前台或明确用户动作中生成。

## 参考

- `docs/01-spec/用户故事与验收标准规格书.md` US-SYN-002~004
- `docs/decisions/ADR-011-task-progress-boundary.md`
- `docs/decisions/ADR-017-focus-production-boundaries.md`
- `docs/decisions/ADR-020-grounded-citation-share-audit.md`
- AGENTS.md §4.3~4.5、§5.4、§17.2
- Apple BackgroundTasks documentation: `BGProcessingTask` is opportunistic; the system chooses launch timing and may expire work.
