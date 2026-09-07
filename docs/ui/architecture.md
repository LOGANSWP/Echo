# Echo UI 架构规范

> **上游权威**：`Echo SwiftUI UI Agent 自动化 Bootstrap 与执行规范.md` §5、§10、§15
> **不得覆盖**：Core Actor/Pipeline 实现、数据库 schema、模型集成

---

## 1. 六层架构

```
第一层：意图与人工批准层      → 维护 echo-memory-canvas，管理批准点
第二层：契约与场景层          → surface/state/action/journey/fixture 稳定 ID
第三层：编排与状态机层        → 推进状态、重试、唯一 simulator 所有者（双审查设备）
第四层：UI 生成与适配层       → SwiftUI View、design token、薄 adapter
第五层：执行与验证层          → schema 校验、build、test、accessibility audit
第六层：证据/治理与安全层     → run manifest、审计链、批准记录
```

**边界**：
- 第一层**不能写生产代码**
- 第四层 adapter **不得保存第二份领域真相**
- 第六层 Agent **不能批准自己的输出**

---

## 2. 单向数据流

### 2.1 完整路径
```
Core/Actor → 只读值类型输出 → @MainActor @Observable Adapter
→ UI State (typed enum) → SwiftUI View
→ User Action → Adapter Intent 方法 → Core Pipeline 接口
→ 结果回调 → Adapter 状态更新 → View 重新渲染
```

### 2.2 错误传播路径
```
Core throws (L1-L4) → Adapter do/catch → 映射规则：
  L1 → 静默重试 3 次（1s/2s/4s），失败升级 L2
  L2 → state = .error(L2)，View 显示 Toast + 重试按钮
  L3 → state = .error(L3)，View 显示全屏引导页
  L4 → state = .error(L4)，View 显示 Banner + 冲突入口
```

### 2.3 加载态路径
```
User Action → Adapter state = .loading → View ProgressView/skeleton
→ await Core → 成功: .completed / 失败: .error
```

### 2.4 取消传播路径
```
View .onDisappear → Adapter task?.cancel()
→ Core Task.checkCancellation() → CancellationError
→ Adapter state = .cancelled
```

### 2.5 约束
- View 不直接写数据库
- Adapter 不保存独立领域模型
- Core 不依赖 SwiftUI

---

## 3. 组件边界

| 角色 | 职责 | 禁止 |
|------|------|------|
| **App Shell** | 根导航、依赖装配、应用级环境 | 实现领域规则 |
| **Surface View** | 一个 surface 的布局和交互组合 | 直接读取数据库 |
| **Component** | 可复用的视觉和语义行为 | 大量布尔开关组合 |
| **Adapter** | 主线程 UI 状态、异步生命周期、错误映射、intent 转发 | 保存第二份领域真相 |
| **Fixture Loader** | Preview/测试环境加载确定性数据 | 访问网络/生产数据库 |
| **Journey Driver** | 通过稳定 accessibility identifier 操作 UI | 调用 View 内部方法 |
| **Artifact Collector** | 收集执行证据 | 改变测试结果或 UI 状态 |

---

## 4. 受保护内容（只读）

### 4.1 受保护路径

| 路径 | 内容 | 原因 |
|------|------|------|
| `Echo/EchoApp.swift` | `@main` 入口点 | App 生命周期 |
| `Echo/App/` | AppDelegate（BGTask） | 系统回调 |
| `Echo/Core/Actors/` | 所有 Actor | 可变状态封装 |
| `Echo/Core/Pipelines/` | 所有 Pipeline | 业务规则 |
| `Echo/Core/Models/` | 领域模型 | 数据结构契约 |
| `Echo/Core/Services/` | 向量存储、模型加载、Embedder、ASR | 持久化、推理封装 |
| `Echo/Resources/Models/` | Core ML 模型包 | 不可损毁 |

### 4.2 抽象受保护内容

1. Core 领域逻辑和公共语义（所有 `Echo/Core/` 子目录）
2. 数据模型、数据库 schema、迁移和持久化规则
3. `DatabaseManager` 的打开、事务和生命周期规则
4. 隐私声明、签名、entitlements、发布配置和 secrets
5. CI 安全门禁、SwiftLint 基线和 acceptance policy
6. Live Simulator 审批规则和 acceptance policy
7. 模型文件、模型下载或打包逻辑、ProximaKit 集成边界

> UI 层**不得**：导入 Core Actor 可变方法以外的内部符号、直接访问 SQLite/ProximaKit、修改 Core 目录下任何文件。

---

## 5. 允许内容

1. SwiftUI Views 和纯表现组件
2. UI semantic tokens 和组件样式
3. `@MainActor @Observable` 薄适配器
4. Preview support 和确定性 fixtures
5. UI contract、UI 层测试和 artifact 收集配置

> 任何允许内容一旦需要改变受保护语义，就停止自动生成并升级为独立工程决策。

---

## 6. ViewModel 契约

> **上游权威**：AGENTS.md §8.1（ViewModel 强制规范）

### 6.1 标注要求
- 所有 ViewModel **必须标注 `@MainActor`**
- **必须使用 `@Observable` 宏**，禁止手动 `objectWillChange.send()`

### 6.2 状态枚举
```swift
enum State {
  case idle          // 初始
  case loading       // 加载中
  case completed(T)  // 成功
  case error(ErrorLevel)  // L1-L4 错误
  case cancelled     // 取消
}
```
状态流转：`idle→loading→completed/error/cancelled`，禁止 `idle→completed` 直接跳转。

### 6.3 action 方法规则
- 每个 action 方法**第一行必须设置 `state = .loading`**
- 副作用仅通过 action 方法触发，禁止在 computed property 中触发

### 6.4 值类型持有
- ViewModel 只能持有值类型副本（Sendable）
- 不可变 Actor 引用（`let`）是合法的
- 禁止持有数据库引用

### 6.5 进度订阅
- 使用 `Task` 或 `.task` 修饰符，禁止 `Task.detached`

---

## 7. 适配器契约

### 7.1 职责
| 职责 | 说明 |
|------|------|
| 线程隔离 | Core Actor → `@MainActor` 状态 |
| 状态映射 | Core 值类型 → UI State |
| 错误映射 | L1-L4 → Toast/Banner/全屏/冲突 |
| Intent 转发 | User Action → Core `await` 调用 |
| 生命周期 | 管理 Task，View 消失时 cancel |

### 7.2 错误映射模式
| Core | UI | 用户操作 |
|------|----|---------|
| L1 瞬态 | 静默重试，不显示 UI | 无 |
| L2 可恢复 | Toast + 重试按钮 | 点击重试 |
| L3 阻断 | 全屏引导页 | 按引导操作 |
| L4 数据冲突 | Banner + 冲突入口 | 手动解决 |

### 7.3 禁止清单
- ❌ 保存第二份领域真相
- ❌ 复制业务规则
- ❌ 持有数据库引用
- ❌ 在 computed property 中触发 Core 调用
- ❌ `Task.detached`

---

## 8. Surface Family 架构映射

> **上游权威**：`echo-memory-canvas-style.md` §3

| 属性 | Discovery | Focus | Task |
|------|-----------|-------|------|
| 适用场景 | Home/Search | Memory detail/translation | Settings/errors/permissions |
| 布局 | rich-data 默认 adaptive masonry；低数据/AX 回退单列 | 单列+metadata | Form/List/Sheet/Alert |
| Masonry | ✅ 达到 Surface 真实内容阈值时默认；稳定语义顺序 | ❌ 禁止 | ❌ 禁止 |
| 参考章节 | style §3.1, §5, §6 | style §3.2, §7.1 | style §3.3, §7.2 |

每个具体 Surface View 头部必须声明 family 归属。AppShell 是系统宿主，不属于 Task surface；它只负责承载三类 family、统一系统 chrome 与应用级环境。交叉引用：`echo-memory-canvas-style.md`。

### 8.1 平衡画布组合边界

- `HomeViewModel` 只提供来自 live adapter 的稳定、有序 section/card 值类型；View 根据契约阈值决定 masonry 或单列呈现，不重新推导领域排序。`4.0a` 可新增只读 `DiscoveryMemoryProviding` 协议及 production adapter；若现有 repository 缺少计数/最近记忆读取，可补充无副作用读 API，但不得新增存储、schema、迁移或写路径。
- Home 的 `empty`、`lowData`、`richData` 是展示状态映射，不是第二份记忆数据库状态；阈值输入是当前策略允许、未排除、来源可解析且可安全展示的真实记忆数量。0 条时只有真实 ProgressActor 扫描任务可以驱动进度 UI。
- Search 保留 SearchPipeline 的相关度顺序；UI adapter 只映射 `presentationKind = scanEligible | continuousReading`。照片/视频且来源可解析，或去除首尾空白后非空且不超过 160 个 Swift `Character`（扩展字形簇）的可独立理解摘要为 `scanEligible`；更长或需要连续阅读的备忘录、语音转写/正文为 `continuousReading`。不少于 6 个可展示结果、`scanEligible` 严格多于半数、非 Accessibility Dynamic Type、VoiceOver 关闭且可用内容宽度至少 340pt（2 × 164pt + 12pt）才进入 masonry，平票按单列；masonry 装箱不得改变语义顺序、partial/low-confidence 状态或反馈绑定的 `memoryId`。
- Home 与 Search 共用 Memory Card 协议；卡片打开后路由到 Focus surface，详情页不得继承 masonry。
- ProgressActor/TaskQueueActor、离线、降级和权限状态仍通过独立 runtime adapter 注入，不得混入布局计算。
- 通用 Discovery 卡片不使用水平滑动手势；US-AWK-005 唤醒卡的左右滑是专用 variant，且必须提供等价按钮和 `accessibilityAction`。`next` 消费稳定唤醒顺序且无后继项时禁用；`recordFeeling` 只在 `MemoryFeeling` 事务提交成功后产生已记录状态/审计。音乐默认消费 Bundle 曲库，可选设备匹配仅在显式 opt-in 后通过系统 adapter 读取非云端本地曲目，不得调用 MusicKit Web Service。

### 8.2 全 App Profile 应用

- 所有 Surface View 必须引用 `designProfileId = echo-memory-canvas`，不允许功能域自行定义平行的 color/type/spacing/radius/motion 系统。
- 共享颜色层必须把重点色建模为 `warmAccent` / `onWarmAccent` 语义对：Asset Catalog 的 `AccentColor` / `OnAccentColor` 分别提供浅色 `#A64B32` + `#FFFFFF` 与深色 `#E08A68` + `#1C1C1E`。组件同时消费背景与前景 token，禁止假定 accent 上永久使用白色。
- 共享视觉 primitives 由 UI Component 层提供：Memory Card、section header、metadata group、status presentation、primary/secondary action；功能域只组合，不复制样式常量。
- Discovery/Focus/Task 的布局策略分别独立，但消费相同 token 与组件语义。Focus/Task 禁止 masonry 不代表可以保留与平衡画布无关的旧视觉皮肤。
- AppShell 统一 NavigationStack/TabView、toolbar 与页面背景；各功能域不得自定义一套 tab、back、search 或 modal chrome。
- 4.0 只交付共享 DesignProfile/component 与 AppShell；4.0a 覆盖 Home/Search，4.0b 覆盖 Detail/Creation/Translation，4.0c 覆盖 Settings/Onboarding/Awakening/BackgroundTask/Degradation/ResumeProgress。4.2/4.7/4.14 通过逐 Surface contract audit 证明任务族合并后没有遗漏。
- `4.0c` 仅允许修改六个 Task domain 的 View、UI 值类型/薄 adapter、fixtures、Surface Contracts 与相关测试；Core、数据库 schema/迁移、系统权限语义、任务调度和领域副作用保持只读。生产依赖缺失时必须映射为明确不可用/错误，禁止回退 fixture 或伪造成功。
- 权限编排是独立生产边界：PIPL consent 持久化成功先于受保护数据请求；PhotoKit 仅由 Connect Photos 触发；通知投递独立 opt-in；geofence 采用 When In Use → 单独确认 Always；HealthKit 只表达 request lifecycle 与样本可用性。`AwakeningPreferenceActor` 持久化用户偏好/request lifecycle，系统授权仍由 adapter 实时读取。该修正由 `4.0f` 交付，不得夹带进 `4.0c` 视觉切片。
- `TaskProgress` 只描述持久化进度，不能单独重建原始 queued job。继续/重新开始必须由 composition-owned typed allow-list launcher 按精确 taskId 重建并重做当前隐私校验。Continue 保留 checkpoint；Restart 在 SQLite 事务内替换为 index 0 可重试记录后再单独入队，失败不丢记录。多条同类型记录逐条可见，当前会话仍被队列拥有的 taskId 不显示 prompt。只在队列实际接管后才发布 resumed/restarted 并写入用户选择、resume point 与实际结果审计；该闭环由 `4.0g` 交付，`4.0c`/`4.4` 不得以 fixture 或只读进度代替。
- Settings 迁移展示必须消费 ADR-008/ADR-010 的真实加密 migration service：`DeviceMigrationActor` 负责编排，`DeviceMigrationService.exportPackage` / `importPackage` 负责 ECHOMIG1 加密迁移包的导出与导入；禁止使用 `PhotoSearchMigrationActor` 代替设备迁移边界。迁移包与“导出全部原始媒体”是不同概念。ViewModel 不持有密钥、不推断分享目标，也不复制 package/merge/rollback 规则。
- `4.0b` 仅允许修改 Focus View、UI 值类型/薄 adapter、fixtures、Surface Contracts 与相关测试；Core、数据库 schema/迁移和领域写语义保持只读。真实 adapter 缺少编辑重索引、冲突持久化或原始来源删除边界时，UI 必须映射为明确不可用/错误，不得在视觉切片中复制写规则或以 fixture 成功代替生产行为。
- ADR-017 将后续生产接线拆分：`4.0e` 负责 `MemoryUserEdit`、安全重索引和持久 conflict；`4.0h` 负责真实来源解析与 PhotoKit 删除 saga（恢复细则由 ADR-019 收紧）；`4.0i` 负责 ADR-020 定义的受限结构化 source anchors、稳定 Detail 路由、当前授权下的复制/导出/分享与 `.creationSharePresented`；`4.0j` 负责持久 earliest-eligible 叙事报告调度。ViewModel 只转发 intent 和映射状态，不直接持有数据库、PHAsset、删除 journal 或第二份授权真相。
- Detail 经 `FocusSourceResolver` 在当前 UserPolicy 下分别映射 `contentAvailability`、presentation 与 `sourceDeletionCapability`；解析失败不回退 bundled sample。只有当前范围内可获取且 `PHAsset.canPerform(.delete)` 的 PhotoKit photo/video 暴露原始删除动作；内容未下载不自动等于不可删除。Share Extension 文本读取 canonical 内容，音频因原件不持久化只展示转写，所有 Share Extension 来源只允许从 Echo 移除且不得猜测 host App。limited-hidden/撤权不可见不等于删除。Creation 消费 `[SourceAnchor]` 与 `cited/noSource/partialNoSource`，allow-list 只证明 provenance；复制/导出/分享由 export coordinator 在准备前重新执行当前 UserPolicy + PrivacyCheckpoint，撤权阻止派生正文交接，所有格式保留引用。只有系统分享控制器真实呈现回调才是 `sharePresented=true` 证据；Notes 交接不产生 Echo 可验证的“已保存”状态。Translation 继续作为 Detail 内 cache-first 的展示层能力，NLTagger `<0.9` 或语言对不支持时保留原文。
- `4.0` 的 `surface_families = [discovery, focus, task]` 表示共享基础必须支持三类 family，不表示 AppShell 同时属于三类 family，也不授权 `4.0` 修改具体功能页。

---

## 9. Phase 3F 兼容记录与 Phase 4 当前状态

> `docs/05-planning/task-status.json` 的 phase 为字符串（`phase_order = ["1","2","3","3F","4","5"]`）。Phase 3F 已完成；截至 2026-09-02，`current_phase = "4"` 且 Phase 4 为 `in_progress`。下列 3F 规则作为历史兼容记录保留；当前 Task/权限/恢复边界以本章前述 `4.0c`/`4.0f`/`4.0g` 规则为准。

- **Phase 3F UI 任务**：3F.7（UI→Core 全域接线）、3F.8（Awakening 与 system adapters）、3F.9（Apple Translation 与 grounded creation）、3F.10（i18n、accessibility 与 production errors）按 canonical plan §7 + §6.2.2 协议执行（任务清单 → §6.2.2 单脚本交付 → PR → 人类合并；checklist 含双设备 Live Sim Review 与 §4.6.7–4.6.10 UIAutomation 契约），**不经 `$ui-bootstrap-build-echo`**（该 skill 为 Phase 3 专用，校验 `current_phase == "3"` 精确匹配；见 `README.md`、`command-compatibility.md`）
- **UI-adjacent Core 接线的受控例外**：§4 的「受保护内容（只读）」保持 Core 只读基线；`3F.0` 人类合并后，standing authority 允许在**任务穷尽式 Files 清单内**修改 UI-adjacent Core 接线文件（如 3F.7 的默认 live adapter 接线），超出任务明示范围仍须停止升级为独立决策
- **测试**：每个 Phase 3F UI 任务的单元/集成测试位于 `EchoTests/Phase3F/`（如 `3F.7_UIToCoreIntegrationTests.swift`），UI 旅程测试在 `EchoUITests` 套件；阶段集成测试为 `EchoTests/Phase3F/Phase3FIntegrationTests.swift`
- **验证**：Phase 3F UI 交付仍需**双设备 Live Simulator Review**（iPhone 17 Pro iOS 26.5 主审查 + iPhone 16 Pro iOS 18.x 最低版本审查），并生成**无媒体 manifest**（`visualMediaCaptured: false`），不创建或持久化 screenshot/video
