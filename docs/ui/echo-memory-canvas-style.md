# Echo Memory Canvas · 设计风格规范

> **上游权威**：用户批准的 `echo-memory-canvas` 设计配置，扩展 `apple-native` 基础
> **物化来源**：`Echo SwiftUI UI Agent 自动化 Bootstrap 与执行规范.md` §7
> **不得覆盖**：Core 领域逻辑、数据库 schema、模型集成、隐私声明、CI 门禁
> **最后同步**：2026-09-03，ADR-017 补充 Focus 编辑、来源删除、引用/分享与叙事调度生产边界

---

## 1. 设计配置标识

- **Profile ID**：`echo-memory-canvas`
- **Base Profile**：`apple-native`
- **批准状态**：用户已批准；2026-08-31 进一步选择方案 B「平衡画布」作为唯一方向
- **风格强度**：“约 60% Pinterest-inspired 内容组织 + 40% Apple 原生交互”仅作为方向性简写；它不是逐页面比例、像素相似度目标或自动化验收指标。验收以 surface family、共享 token/component、系统交互和可访问性契约为准
- **全 App 范围**：所有页面必须体现同一平衡画布视觉语言；Discovery 表达最强，Focus/Task 通过共享 token、容器、媒体处理、层级与 motion 保持一致
- **额外灵感来源**：Pinterest 启发图片优先密度、非等高内容节奏与连续探索；**不是**产品依赖、品牌关系或复制其 UI 的许可
- **边界**：系统导航、Tab Bar、搜索行为、菜单、编辑、权限、错误与恢复继续使用 Apple 原生交互模式；一致不等于所有页面都使用 masonry

---

## 2. Apple 原生基础

### 2.1 系统容器与导航
- 优先使用 `NavigationStack`、`TabView`、`List`、`Form`、`Sheet`、`Alert`、`Menu`、`Toolbar`、`Searchable` 等系统容器和交互模式

### 2.2 Typography
- 只使用系统 Dynamic Type text styles（`.largeTitle`、`.title`、`.headline`、`.body`、`.callout`、`.subheadline`、`.footnote`、`.caption`）
- 不用固定字号构建主要信息层级
- 长文本可自然增长，不通过裁切维持卡片外形
- 标题、摘要、正文、metadata、caption 和 action 标签形成稳定层级

### 2.3 Color
- 使用 `Color.primary`、`.secondary`、系统 `background`、`fill`、`tint` 等 semantic colors
- 完整适配 light、dark 和 increased contrast
- Echo 使用温暖、克制的陶土色语义对，通过 Asset Catalog 提供 light/dark appearance：
  - `warmAccent`（`AccentColor` asset）：浅色 sRGB `#A64B32`；深色 sRGB `#E08A68`
  - `onWarmAccent`（`OnAccentColor` asset）：浅色 `#FFFFFF`；深色 `#1C1C1E`
- SwiftUI 只通过 `EchoColorToken.warmAccent` / `.onWarmAccent` 消费该色对；重点 action 不得把前景色固定为 `.white`
- Accent 限定于：tint、选中态、重点 action 和少量状态强调
- 对比度门禁同时验证 `warmAccent` 与 `onWarmAccent` 的 appearance 配对；颜色不得作为状态或动作的唯一语义

### 2.4 SF Symbols
- 使用 SF Symbols 及其语义化 variant（`.fill`、`.circle`、`.slash`）
- 自定义图标只在系统符号无法表达产品概念时使用
- 自定义图标必须满足同等可访问性要求

### 2.5 可访问性
- 保留标准 focus、keyboard、VoiceOver、Voice Control、Switch Control、Reduce Motion
- 保留 context menu、swipe action、destructive confirmation 和系统手势行为
- 所有交互元素有 `accessibilityLabel`、`accessibilityHint`
- 动态内容变化触发 `accessibilityAnnouncement`

### 2.6 Motion
- 使用系统 motion、transition 和反馈语义
- `Reduce Motion` 开启时移除非必要位移和连续动画
- 不用视觉新奇性覆盖可预测性
- 转场保留空间关系

### 2.7 系统版本适配
- 最新系统视觉 API 不得成为最低部署版本不可用时的硬依赖
- 必须提供 `@available` 检查和 Apple 原生回退

---

## 3. 三类 Surface Family

### 3.1 Discovery surfaces
**适用场景**：Home、Search、collection browsing

- **丰富真实内容状态默认使用双列 adaptive masonry**；非等高卡片由真实媒体比例和摘要长度驱动
- Home 以 Ask Echo → 今日回响 → 最近导入 → 主题/时间集合构成连续发现画布；不可用区块直接隐藏
- Search 在结果足以扫描且以图片/短摘要为主时使用同一画布语法，保持查询相关度的稳定语义顺序
- 空数据、低数据、长文本与无障碍状态使用单列内容卡片或系统 List，不为维持瀑布流伪造内容
- 布局服务于扫描、比较和发现，不改变系统导航、Tab、搜索、菜单或选择行为
- **Masonry 默认与回退条件**（见 §6.1、§6.2）

### 3.2 Focus surfaces
**适用场景**：Memory detail、media viewing、translation

- 使用沉浸式单列系统导航
- 主内容按阅读或观看顺序呈现
- 相关来源、时间、位置、转写、翻译和操作进入清晰分组的 metadata
- **明确禁止 masonry**，不使用 masonry 分割注意力

### 3.3 Task surfaces
**适用场景**：Edit、settings、permissions、background tasks、errors、recovery

- 使用 Apple 原生 `Form`、`List`、`Sheet`、`Alert`、`Menu`、`Toolbar`
- 共享本 profile 的字体、颜色、间距、卡片语气和 motion
- **明确禁止 masonry**
- 任务完成率、可读性、系统习惯和错误恢复优先于内容发现感

### 3.4 Surface 契约强制
每个 Surface 契约必须声明：
- `designProfileId: echo-memory-canvas`
- `surfaceFamily: discovery | focus | task`
- 所选系统容器
- 回退条件

AppShell 是 Apple 原生系统宿主，负责 NavigationStack、TabView、toolbar、search 与 modal 基础行为；它承载 Discovery/Focus/Task，但自身不是 Task surface，也不创建第四种 `surfaceFamily`。因此 AppShell 使用 DesignProfile 合约验收，不创建伪造的 AppShell Surface 合约。

### 3.5 全 App 一致性契约

- AppShell、Home、Search、Detail、Settings、Onboarding、Awakening、BackgroundTask、Creation、Degradation、ResumeProgress、Translation 全部属于同一 `echo-memory-canvas` profile
- 所有页面共享系统 Dynamic Type 层级、warm restrained accent、8/12/16/20pt spacing cadence、语义化背景、统一圆角映射、SF Symbols 与 Reduce Motion 行为
- 内容容器保持共同 DNA：清晰主内容、轻量 section header、次级 metadata、克制边框/材质；不得出现某个页面独有的第二套按钮、颜色、阴影或标题体系
- 全局 App Shell 保持同一 NavigationStack/TabView 语义；页面差异只来自 surface family 的信息架构责任
- Discovery 使用瀑布流表达探索；Focus 使用单列媒体与 grouped metadata 表达沉浸；Task 使用 grouped system containers 表达完成任务——三者视觉同源但布局不相同

---

## 4. 共享 Token 与视觉语言

### 4.1 Typography Token
```
title:       .largeTitle / .title
subtitle:    .headline
body:        .body
metadata:    .subheadline
caption:     .caption
action:      .callout
```
仅使用系统 Dynamic Type text styles。

### 4.2 Color Token
```
primary:     Color.primary
secondary:   Color.secondary
background:  Color(.systemBackground)
groupedBg:   Color(.systemGroupedBackground)
fill:        Color(.systemFill)
separator:   Color(.separator)
accent:      Color.accentColor
```
温暖、克制的 accent，限定于 tint、选中态、重点 action。

### 4.3 Radii Token
```
imageRadius: 系统上下文映射（卡片内图片）
cardRadius:  系统上下文映射（卡片容器）
```
不把超大圆角当作品牌替代品，不手工模拟系统 chrome。

### 4.4 Spacing Token
```
compact:   8pt  — iPhone masonry gutter、图标间距
normal:    12pt — 卡片内边距
grouped:   16pt — metadata 分组
section:   20pt — Form/List section 周边
```
间距随 size class 与 Dynamic Type 调整，不靠 magic number 拼接。

### 4.5 Materials
- 卡片优先使用 `systemBackground`、`systemGroupedBackground`、`systemFill`、`separator`
- 阴影、模糊和玻璃效果只能帮助层级，不得堆叠成主要信息架构

### 4.6 Image Policy
- 图片按来源比例、预先声明的受支持比例或语义裁切展示
- 缩略图允许安全裁切
- 人物、文字、票据等敏感内容需使用适合的 `contentMode`（`.fit`）或单列回退
- 加载前 fixture 必须提供稳定 `aspectRatio` metadata，避免异步重排

### 4.7 Metadata Hierarchy
1. 内容本体（图片/视频/文本/音频）
2. 标题或摘要
3. 时间、来源、类型和状态
4. 重复或低价值 metadata 合并到次级层，不用图标噪声替代文字含义

### 4.8 Symbols and Motion
- 图标：SF Symbols
- 动画：系统 `withAnimation` + `transaction` 语义
- 转场：保留空间关系，`Reduce Motion` 可简化

---

## 5. 内容类型卡片（Memory Cards）

Discovery surfaces 使用统一 Memory Card 协议，包含以下 variants。

### 5.1 Photo Card
- 以图片为主，保留稳定 aspect metadata
- 显示必要标题或日期
- VoiceOver label：先描述记忆类型与可用替代文本，再读关键 metadata
- Fixture：离线、确定、控制 `contentId`、`aspectRatio`、时间戳

### 5.2 Video Card
- 使用稳定 poster fixture、时长和 `play.rectangle` SF Symbol 或系统 overlay
- 自动化 fixture 不自动播放
- 辅助技术区分视频与静态图片
- Fixture：离线、确定、控制 `contentId`、`aspectRatio`、`duration`、poster

### 5.3 Text/Note Card
- 正文摘要可自然换行
- masonry 中只接受已由展示 adapter 标记为 `scanEligible` 的短摘要，可使用最多 3 行的预览；需要连续阅读的文本必须标记为 `continuousReading` 并触发单列，单列正文可自然增长
- 提供完整内容入口
- 不得使用固定卡片高度裁掉正文，也不得把原文截断后错误标记为可独立理解的短摘要
- Fixture：离线、确定、控制 `contentId`、`textContent`、`locale`、`title`

### 5.4 Voice Card
- 显示录音类型 icon、时长、可用转写摘要和播放状态语义
- 波形若存在必须来自确定 fixture，不能成为理解内容的唯一方式
- Fixture：离线、确定、控制 `contentId`、`duration`、`transcriptSummary`、`locale`

### 5.5 Mixed Memory Card
- 为图片、视频、文字、语音组合提供一个主内容和明确的类型摘要
- 避免在单卡内堆叠完整子卡
- VoiceOver 使用单一可理解容器，必要 action 单独暴露
- Fixture：离线、确定、控制 `contentId`、`primaryType`、`subTypes`、`summary`

### 5.6 卡片通用要求
- 由系统 text styles、semantic colors、materials、buttons 和 interaction primitives 组成
- 不复制 Pinterest 的外观或品牌元素
- 测试验证：accessibility label、value、traits、action、reading order、点击区域和内容类型
- 不以颜色、图片或 SF Symbol 作为唯一语义

---

## 6. 响应式、排序与可访问性规则

### 6.1 Masonry 启用条件
**仅 Discovery surfaces** 满足以下全部条件时默认使用 adaptive masonry：
- Regular Dynamic Type（非 accessibility sizes）
- 可用内容宽度可容纳至少两张最小宽度为 152pt 的卡片及 gutter；不得仅以 horizontal size class 判定
- 当前区块达到其 Surface 契约声明的真实内容阈值，且卡片具有稳定 ID 与 aspect ratio metadata
- 卡片以媒体、短摘要或可独立理解的记忆单元为主，适合视觉扫描
- Home：总记忆数达到 20 条后才进入 rich-data 画布；单个瀑布流区块至少有 6 张真实可展示卡片
- Search：至少 6 个可展示结果，且 adapter 映射的 `scanEligible` 结果严格多于 `continuousReading`；平票或 `continuousReading` 占多数时维持相关度优先的单列结果。`scanEligible` 仅包括来源可解析的照片/视频，或去除首尾空白后非空且不超过 160 个 Swift `Character`（扩展字形簇）的可独立理解摘要；更长或需连续阅读的备忘录、语音转写/正文标记为 `continuousReading`
- 双列还要求非 Accessibility Dynamic Type、VoiceOver 关闭且可用内容宽度至少 340pt（2 × 164pt 最小卡宽 + 12pt 列距）；任一条件不满足即单列
- iPhone 默认两列；iPad 根据可用宽度、Split View 和 152pt 最小卡宽自适应为 2~5 列

“可展示”统一指：当前 UserPolicy 允许、未排除、原始来源仍可解析、稳定 `memoryId` 与 Focus 跳转存在，且媒体具有真实 aspect ratio 或文本具有真实摘要。不可展示项目不进入任何数量阈值。

### 6.2 单列/List 回退（必须）
以下任一条件触发回退到单列卡片或系统 List：
- Accessibility Dynamic Type（`.accessibility1` 及以上）
- 可用内容宽度无法容纳两张 152pt 卡片及 gutter
- 未达到 Surface 的真实内容阈值
- 长文本（超出摘要策略）
- 复杂语义（需要连续阅读顺序）
- 关键图片无法安全裁切
- 辅助技术难以理解视觉列顺序

### 6.3 排序规则
- 排序由显式稳定 key 决定（产品定义的相关度、记忆时间与稳定 ID tie-breaker）
- 布局计算不得改变语义顺序
- 刷新、旋转、Dynamic Type 变化和重复 fixture 运行必须得到确定顺序

### 6.4 Reading Order
- VoiceOver 与键盘 reading order 按语义数据顺序，**不是**按视觉装箱结果
- 跨列视觉位置不能成为 journey 或测试的唯一定位方式

### 6.5 卡片高度
- 卡片高度由内容和受支持比例决定
- 不得固定高度裁切文本
- 不得用无限文本撑开破坏扫描
- 达到摘要边界时提供明确的完整内容入口和辅助技术语义

### 6.6 平衡画布的视觉节奏
- 第一屏优先出现 Ask Echo 和最多一个有真实匹配的重点「今日回响」入口，不使用静态 hero 补位
- 画布通过 4:5、1:1、3:4 等真实或安全裁切比例形成节奏，不使用随机高度
- 图片优先但不图片独占：语音、视频、短文本和混合记忆继续使用各自 Card variant
- section header 保持轻量；不把筛选 chip、悬浮按钮或装饰徽章堆叠成第二套导航
- 卡片点击进入 Focus surface，进入详情后立即恢复单列阅读语法

---

## 7. Focus 与 Task 的共享表达

### 7.1 Focus surfaces
- 单列内容流、系统 back 行为、可预测 toolbar、grouped metadata
- 主媒体沿用 Memory Card 的真实比例、圆角和来源 metadata；进入详情后扩大为阅读/观看主内容，而不是换一套视觉语言
- metadata group 使用与 Discovery 卡片一致的背景、间距、圆角和 warm accent，但不拆成瀑布流
- Creation 与 Translation 延续相同标题层级、引用卡片和内容容器，不使用独立的“工具型”皮肤
- 媒体沉浸不隐藏必要的可访问退出路径
- 翻译同时保留原文与译文关系
- Focus 的“内容优先”不是隐藏状态或动作：主媒体/正文在第一层，引用与 grouped metadata 在第二层，编辑/删除/导出按主要、次要、破坏性层级放置；禁止把所有动作渲染为同权重的纵向按钮墙。
- Detail 的生产媒体只能来自当前授权下可解析的真实本地来源；示例媒体只属于 Preview/fixture。解析失败时使用本地化诚实降级，不得以 bundled sample 冒充用户内容。
- Creation 的 Notes 入口只呈现系统 share/export 流；Echo 不显示“已保存到 Notes”、不提供笔记深链，也不推断 share sheet 中的用户选择。
- Translation 是 Detail 内的 Focus 子区；原文、译文、语言标签和来源上下文必须同时可理解，不创建独立工具皮肤或破坏返回栈。

### 7.2 Task surfaces
- Form/List section、系统 disclosure、toggle、picker、progress、sheet、alert、confirmation
- Settings、Onboarding、Awakening、BackgroundTask、Degradation 与 ResumeProgress 使用同一 grouped background、section header、状态图标、圆角映射和 accent
- 权限、加载、空态、错误和恢复组件共享相同的图标—标题—说明—主要动作层级，状态颜色只表达语义，不创建页面品牌色
- Onboarding 可使用更宽松的留白和单一重点插图/符号，但字体、按钮、进度、卡片和后续 App 保持同源
- Onboarding 的 PIPL 同意必须先持久化成功；失败时停留在可重试状态。相册只由“连接照片”请求，`Not Now` 无系统调用并直接继续。通知使用独立投递 opt-in；geofence/emotion/anniversary 开关不得隐式请求通知
- geofence 首次启用请求 When In Use；终止态区域唤醒的 Always 权限必须在解释差异后由第二个明确动作请求。HealthKit UI 只显示 not requested/request completed/unsupported 与实际样本可用性，不显示系统无法披露的 read-granted/read-denied
- 可选权限拒绝/跳过不阻止进入 App，不自动循环重试；系统返回 denied/restricted 后才显示用户主动触发的设置恢复。同意/拒绝必须同层可见且同等醒目，不使用预选、弱化或视觉诱导
- 错误与恢复明确说明：发生了什么、可执行动作、结果
- ResumeProgress 只有在生产 task reconstruction/launcher 可用时才能将“继续”或“重新开始”显示为可完成动作；仅能读取 `TaskProgress` 时必须诚实显示不可用，fixture 状态不得作为生产恢复证据
- Settings 设备迁移必须呈现加密用户中介迁移包与 Finder/iTunes 加密本地备份两条路径，明确原始媒体不进入迁移包；不得把迁移包误写成“导出全部原始记忆”
- 不伪装成内容卡片瀑布流

### 7.3 三类 Family 的视觉一致性
通过共享 token 和行为达成一致，不来自把同一布局套到所有页面：
- Typography、semantic colors、`warmAccent` / `onWarmAccent` 陶土色对、radii、spacing
- Materials、metadata hierarchy、SF Symbols、system motion
- 相同语义使用相同组件：Memory Card、section header、status presentation、primary/secondary action、metadata group
- 页面级验收必须同时检查“符合 family 布局”与“符合全 App profile”；只满足其中之一不算通过

---

## 8. 明确禁止项

1. ❌ 在 edit、settings、permissions、background tasks、errors、recovery、memory detail、media viewing 或 translation 上使用 masonry
2. ❌ 为增强 Pinterest 感而自定义导航栏、Tab Bar、搜索行为、按钮、手势或转场；方案 B 的强度来自内容画布，不来自复制 chrome
3. ❌ 复制 Pinterest 名称、商标、图标、品牌色、文案、布局细节或可识别 trade dress
4. ❌ 硬编码只适用于单一设备、系统版本或外观的尺寸、颜色、列数和卡片高度
5. ❌ 用固定卡片高度裁切正文、Dynamic Type 内容或本地化文本
6. ❌ 用模糊、玻璃、阴影、大圆角、复杂动画或视觉新奇性代替清晰信息架构
7. ❌ 在一个任务中重新提出多套视觉方向

---

## 9. 批准记录

| 事项 | 批准人 | 日期 | 来源 |
|------|--------|------|------|
| `echo-memory-canvas` 设计配置 | 用户 | 2026-07-25 | bootstrap 规范 §7 |
| `apple-native` 基础 | 用户 | 2026-07-25 | bootstrap 规范 §7.1 |
| Discovery/Focus/Task 三类映射 | 用户 | 2026-07-25 | bootstrap 规范 §7.2 |
| 方案 B「平衡画布」（全 App 视觉身份；Discovery 表达最强，Focus/Task 同源但不使用 masonry） | 用户 | 2026-08-31 | 当前产品决策 |

> 若要改变 profile、Apple 原生基础或三类 surface 映射，必须修订本文和 `docs/ui/echo-memory-canvas-style.md` 并重新获得用户批准。

---

## 10. 空态与加载态（Empty & Loading States）

### 10.1 空态规则

#### 10.1.1 Discovery — 无记忆时的品牌欢迎页

**Surface Family**: `discovery`

- 当系统没有可展示记忆时，HomeView 展示品牌空态而非空白列表
- 仅当 ProgressActor 存在真实活跃扫描任务时，页面才显示由真实 `processedCount/totalCount` 驱动的 determinate `ProgressView`，文案（String Catalog）为 zh-Hans `"Echo 正在扫描你的记忆…"` / en-US `"Echo is scanning your memories…"`
- 扫描已完成、没有活跃扫描任务或用户尚未授权数据源时，不显示 ProgressView 或扫描中文案；改为根据真实授权/来源状态提供相册授权或系统分享导入入口
- 扫描完成后按真实 `visibleMemoryCount` 切换至低数据/rich-data 内容；结果仍为 0 时保留诚实导入空态

#### 10.1.2 Focus — 数据加载失败空态

**Surface Family**: `focus`

- 居中布局：SF Symbol `tray` + `"无法加载记忆"` + `"请稍后重试"` + 重试按钮
- 不阻塞导航：用户仍可返回上一级

#### 10.1.3 Task — 列表为空说明

**Surface Family**: `task`

- 系统 List/Form 标准空态，居中对齐 SF Symbol + 说明文案
- 不展示品牌元素或动画

### 10.2 加载态规则

- 通用：系统 `ProgressView()`（indeterminate），`.tint(Color.accentColor)`
- 确定进度：`ProgressView(value:total:)` + 数值文本

#### 10.2.1 骨架屏（Skeleton Screen）

**Surface Family**: `discovery`

- 使用系统 `.redacted(reason: .placeholder)` 实现
- 卡片数量：iPhone 4-6 张 / iPad 8-12 张
- **明确禁止**：自定义 shimmer 动画、第三方 skeleton 库

#### 10.2.2 Reduce Motion 适配

- 移除骨架屏渐变、保留数值更新但移除动画曲线

---

## 11. Toast、Banner 与通知栏

### 11.1 通知层级总览

| 类型 | 样式 | 位置 | 持续方式 |
|------|------|------|----------|
| L1 瞬态 | Toast | 底部居中 | 2秒自动消失 |
| L2 可恢复 | Banner | 顶部横条 | 手动关闭 |
| L3/L4 阻断 | 全屏页 | 全屏 | 用户操作后关闭 |
| 降级横幅 | Banner | 顶部横条 | 条件解除后自动消失 |

### 11.2 L1 Toast

- 浅色圆角胶囊，底部安全区域内居中
- 可选 SF Symbol + 单行文案
- 无操作按钮，从底部滑入/滑出

### 11.3 L2 Banner

- 顶部安全区域下方横条，左侧 SF Symbol + 文案 + 右侧"重试"按钮
- 手动关闭，不自动消失

### 11.4 降级横幅

- 顶部 Banner，黄色/橙色色调
- 低电量→`battery.25`，过热→`thermometer.high`，模型降级→`exclamationmark.triangle`
- 条件解除后自动淡出

### 11.5 冷却期提醒（PRV-005）

- L2 Banner 样式，每 3 小时最多显示一次
- 仅提供"关闭"按钮

---

## 12. 全屏错误与恢复页面

### 12.1 L3 阻断错误

- 全屏 `fullScreenCover`，禁止 dismissing
- 大 SF Symbol + 标题 + 双语说明 + "前往设置"/"重试加载模型"按钮

### 12.2 L4 数据冲突

- 全屏 `fullScreenCover`
- 双栏对比视图（本地版本 vs 外部版本），冲突字段黄色高亮
- "保留本地"/"保留外部"/"手动合并"三个操作按钮

---

## 13. 后台任务面板（Background Task Panel）

**Surface Family**: `task`

### 13.1 展示方式
- 底部 Sheet（`.medium` detent，可拖拽至 `.large`）
- iPad：侧边栏形式，320pt

### 13.2 任务列表项
- SF Symbol 图标 + 任务名称 + determinate 进度条 + 已处理/总数 + 状态标签
- 操作：暂停（`pause.circle`）、取消（`xmark.circle`）

### 13.3 自动隐藏
- 无活跃任务时延迟 1.5 秒自动关闭
- 空态：居中 `"没有正在进行的任务"`

---

## 14. 筛选与搜索 UI 模式

**Surface Family**: `discovery`

### 14.1 搜索栏
- 系统 `.searchable` 修饰符，300ms debounce
- 搜索作用域：全部/照片/视频/备忘录/语音

### 14.2 筛选控件
- 时间范围：系统 `DatePicker`（compact 模式）
- 内容类型：水平滚动 SF Symbol 标签（photo/video/note.text/waveform），多选
- 地点：搜索建议列表 + 可选 MapKit 缩略图

### 14.3 低置信度横幅（US-RET-006）
- 搜索结果顶部半透明横幅，`info.circle` + "以下结果相关性较低"（双语）

### 14.4 反馈按钮
- 每个搜索结果卡片右下角 👍/👎 迷你按钮
- 选中态 `Color.accentColor`，点击有缩放动画

### 14.5 Bad Case 标记
- 长按卡片 → contextMenu "标记问题"

---

## 15. 引导流程（Onboarding Flow）

**Surface Family**: `task`

### 15.1 展示方式
- 全屏 `.fullScreenCover`，分步 `TabView` 页面

### 15.2 Step 1 欢迎页
- Echo logo + `"Echo · 回响"` + `"你的记忆，触手可及"` + "开始"按钮

### 15.3 Step 2 PIPL 隐私同意
- 可滚动隐私政策摘要 + "同意并继续" / "不同意"；两者同层可见、同等醒目且均不预选，不以颜色、尺寸或层级诱导同意
- “同意并继续”进入持久化进行态；只有持久化成功才进入下一步，失败显示原位重试，不允许照片请求抢跑

### 15.4 Step 3 可选资料库连接
- 仅呈现可跳过的照片资料库连接；用户明确选择“连接照片”后才请求 PhotoKit
- 通知、位置与 HealthKit 不进入首次启动序列。通知由独立投递动作请求；位置/HealthKit 由相应唤醒功能明确启用，且不串联通知
- 用户主动选择“暂不连接”直接继续，不显示设置入口；系统返回 denied/restricted 后显示“前往设置”和“继续使用”。limited/full 按真实范围继续，不自动请求其他权限、不循环重试，也不阻止进入 App

### 15.4.1 Awakening 渐进式授权
- “启用通知投递”只请求通知；通知不可用不关闭 App 内卡片生成或三个唤醒偏好
- “启用地理围栏”首次只请求 When In Use；说明后台能力后，由单独的“允许后台区域唤醒”动作请求 Always
- “启用情绪唤醒”只请求 HRV read scope；请求完成不等于 read granted，UI 以可读样本/无可读样本表达运行结果
- “启用纪念日”不触发系统权限；系统通知投递仍由独立 opt-in 控制

### 15.5 Step 4 语言选择
- 系统 Picker，zh-Hans / en-US

### 15.6 Step 5 等待扫描
- Determinate 进度条 + `"正在扫描你的记忆…"`

---

## 16. 离线与连接状态指示器

### 16.1 离线模式指示器（US-RES-001 AC-3）
- 顶部 Banner，浅灰背景，`wifi.slash` + "离线模式 — 仅显示已缓存的记忆"

### 16.2 首次启动无网络
- 引导流程完全离线可用，本地 Core ML 模型无需联网

### 16.3 同步语义（离线-only，禁止 CloudKit/iCloud）
- Echo 生产环境**没有 CloudKit / iCloud 同步**（R-001 红线：禁止任何数据上传云端；R-005：模型加载无网络下载），任何 UI 状态**不得暗示 iCloud/云端同步存在**
- 数据源同步仅在设备本地进行：PhotoKit 当前授权范围内读取（自动）+ Share Extension 显式分享摄入。Share Extension 不推断宿主 App；共享文本作为可读正文，共享音频完成离线转写后只保留 transcript，不承诺原音频播放
- 若设置页需要展示数据状态，使用**离线语义**：本地优先徽标（如"所有数据仅保存在本机"），**禁止**使用 `icloud.fill`/`icloud`/`icloud.slash` 或任何云端同步状态指示器
- 设备迁移（US-SRC-007）通过加密迁移包导出/导入完成，不经过任何云端同步服务

---

## 17. 内容卡片增强规则

### 17.1 Pinterest 启发的内容组织密度

> **重要声明**：仅受 Pinterest 内容组织密度启发，**绝不复制**其品牌、颜色、字体、导航或控件。

- 丰富真实内容状态默认采用两列自适应瀑布流（条件与回退见 §6.1、§6.2）
- iPhone 首屏目标可扫描 4~6 张卡片；iPad 根据宽度显示 8~12 张，但不得为命中数量目标裁切正文或伪造卡片
- 大图、短文本、语音和视频卡片按真实内容比例交错，形成可预测的扫描韵律
- Home 与 Search 共享 Card 语法、gutter、metadata hierarchy 和 Focus 跳转，不各自创造第二套视觉系统

### 17.2 卡片交互
- 长按：contextMenu（查看详情/标记问题/分享/移出 Echo）
- 点击：进入 Focus surface
- 通用 masonry/ScrollView 卡片不定义水平滑动手势；移出 Echo、收藏与反馈通过显式按钮、Menu/contextMenu 和等价 `accessibilityAction` 提供，避免与纵向滚动及辅助技术手势冲突
- **US-AWK-005 专用唤醒卡例外**：左滑“下一张”、右滑“记录感受”，并同时提供等价可见按钮与辅助功能动作；不得把该语义复用于普通 Home/Search 记忆卡。`next` 只按稳定唤醒顺序前进，无后继项时手势和按钮均不可用；只有感受保存成功才呈现已记录状态
- 音乐建议始终有随包离线来源，不以 Apple Music 授权作为卡片展示前置条件。“匹配此设备音乐”是独立的显式权限动作；拒绝/受限/空库/失败后仍显示随包建议，不显示假播放按钮

### 17.3 卡片 Accessibility
- VoiceOver label：`"[类型]，[内容描述]，[时间]，[位置]"`
- Magic Tap = 查看详情
- 每个卡片是单一 `accessibilityElement`
