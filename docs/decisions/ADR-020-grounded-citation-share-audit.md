# ADR-020: Grounded 引用与用户中介分享审计边界

**状态**: 已接受  
**日期**: 2026-09-07  
**决策人**: Codex 规格合理性复审（依据人类指令）

## 背景

`4.0i` 原方向要求模型显式返回 source MemoryID、按本次输入 allow-list 校验，并把生成审计与系统分享呈现审计分开。对照现有 `CreativePipeline`、`CreationExportService`、`CreationViewModel`、`AuditLog` schema 与 UIAutomation contracts 后，仍存在六个不可直接验收的问题：

1. allow-list 只能证明 ID 属于本次输入，不能证明来源语义支持段落事实；“杜绝幻觉”或“已验证事实”会构成过度承诺。
2. AC 允许一个或多个来源，但现有领域/UI 模型只表达单个可选 anchor，且未定义部分有效、部分无效 ID 的语义。
3. 生成协议没有版本、上限或明确 JSON schema，纯文本解析容易重新引入位置推断、提示注入与资源失控。
4. 分享前未要求重新读取当前 UserPolicy。生成后撤权时继续导出来源派生内容会绕过动态授权。
5. `sharePayload != nil` 只证明本地 payload 已准备，不能证明系统 share sheet 已真正呈现；用户取消、呈现失败与审计写入失败也未充分区分。
6. 规格要求结构化 `citationCount`、`noSourceCount`、`exportFormat`、`sharePresented` 等字段，但生产 schema 尚无对应类型化列，现有代码把生成 metadata 塞入 `sourceLanguage` JSON，字段语义失真。

此外，项目绝对化描述“所有数据永不离开设备”与用户明确触发复制或系统 share/export 的产品能力存在文字冲突。Echo 可以保证不主动上传或选择接收方，但不能保证系统剪贴板或分享面板的后续目标不会把内容带离设备。

## 决策

### 1. 引用证明 provenance，不声称自动证明事实

- 产品文案与 AC 使用“可验证来源锚点 / 降低幻觉风险”，禁止把 allow-list membership 表述为事实正确、语义蕴含或“杜绝幻觉”。
- UI 使用“来源记忆 / Source memory”语义，不显示“Verified fact”。用户可通过锚点检查当前可访问来源。
- 本任务不引入新的事实蕴含模型。若未来要自动证明 claim-support，必须单独批准本地 verifier、质量数据集和门禁。

### 2. 版本化、受限的结构化生成协议

- 离线模型接收的来源标识只使用本次输入的稳定 opaque MemoryID；不向模型暴露 `assetID`、`sourceLocator` 或其他系统原始标识符。
- 输出采用版本化 JSON envelope：`schemaVersion` 与 `paragraphs[]`；每段至少包含 `text` 和 `sourceMemoryIDs[]`。
- parser 必须设置原始字节数、段落数、单段字符数和每段引用数上限。未知版本、超限、无法解码或非预期根结构整体按 L2 fail-closed，不得回退位置/轮询绑定，也不得展示未校验输出。
- 每段 ID 去重后逐项与输入 allow-list 校验。全部有效时状态为 `cited`；缺失或全部无效时为 `noSource`；有效与无效并存时保留有效锚点并同时标记 `partialNoSource`，不得把该段呈现为完全有据。
- 领域与 UI 值类型必须表达 `[SourceAnchor]` 与类型化 provenance 状态，禁止继续用单个 optional anchor 或 `hasSource: Bool` 作为领域真相。

### 3. 计数语义固定

- `sourceMemoryCount`：通过生成前当前策略过滤、实际提交给模型的唯一 MemoryID 数量。
- `citationCount`：解析后通过 allow-list 的 anchor occurrence 数量；同一来源在不同段落重复引用分别计数，同一段内重复 ID 去重。
- `noSourceCount`：状态为 `noSource` 或 `partialNoSource` 的段落数量。
- `.synthesis` 与 `.creativeGeneration` 共用生成 traceID，但保持事件职责分离；MemoryID 只写摘要，不写生成文本。

### 4. 复制、导出与分享重新授权

- 复制到系统剪贴板以及任何 Markdown/PDF/plain-text 系统分享准备都属于用户中介的内容交接，统一通过 composition-owned export coordinator，并在读取内容或准备 payload 前按引用来源类型执行当前 UserPolicy + PrivacyCheckpoint。
- 生成后来源撤权时，禁止继续导出其派生正文；显示可恢复的授权错误，允许用户返回或基于仍授权来源重新生成。单纯资产离线/消失但策略仍允许时，可保留正文并以 `NoSource`/不可用引用诚实导出。
- Markdown、PDF 与 plain text 都必须保留每段可理解的来源标记；多页 PDF 不得因分页截断正文或引用。外部导出不得包含 `assetID`、`sourceLocator` 或可猜测来源 App 的字段。
- R-001 解释为 Echo 不主动上传、不调用网络服务、不选择或观察后续接收目标。用户明确触发的复制或系统 share/export 是受控交接；交接后的目标行为由用户与系统管理。

### 5. 呈现事实与失败语义

- payload 准备完成不等于 share sheet 已呈现。只有系统分享控制器进入实际呈现回调后，才记录 `.creationSharePresented(sharePresented=true)`。
- 准备失败或控制器未进入呈现回调即失败时，记录 `sharePresented=false` 并显示 L2；用户关闭已呈现面板不产生失败或第二条取消审计。
- 呈现成功后的审计持久化失败不得把已发生的呈现改写为 `false`。它按 L2 暴露并以无原文、无目标 App 的重试描述写入 `PendingOperations`；重试保持幂等。

### 6. 专用结构化审计字段

`AuditLog` 与 `AuditLogEntry` 使用类型化列承载：

- `templateType TEXT`
- `sourceMemoryCount INTEGER`
- `citationCount INTEGER`
- `noSourceCount INTEGER`
- `exportFormat TEXT`，allow-list 为 `plainText | markdown | pdf`
- `sharePresented INTEGER`
- `periodType TEXT`，可选，allow-list 为 `month | year`

禁止把这些字段编码进 `sourceLanguage`、`contentHash` 或通用自由文本。`.creationSharePresented` 不记录 `activityType`、目标 App、用户完成状态、导出原文、`assetID` 或 `sourceLocator`。

## 备选方案

1. **仅修复 round-robin**：改动小，但仍无法表达多引用、部分无来源、真实呈现和结构化审计，拒绝。
2. **引入本地 entailment verifier**：能提高事实支持度，但当前无批准模型、基准或资源预算；作为未来独立任务评估，不纳入 `4.0i`。
3. **禁止所有系统分享**：可维持“数据绝不离机”的字面承诺，但与已批准的 US-SYN-003/004 和迁移边界冲突，拒绝。

## 后果

- `4.0i` 需要同时更新生成协议/parser、领域/UI citation 类型、当前授权复验、导出协调器、系统分享呈现桥、审计模型/schema 与 no-fixture 测试。
- 现有 `sourceLanguage` JSON metadata 属迁移前兼容数据；新写入必须使用专用列，读取旧日志可保持向后兼容，但不得继续新增该反模式。
- 本决策不交付 `4.0j` 的报告调度，也不宣称自动事实验证。

## 参考

- `docs/01-spec/用户故事与验收标准规格书.md` US-SYN-002~004
- `docs/decisions/ADR-013-creation-export-boundary.md`
- `docs/decisions/ADR-017-focus-production-boundaries.md`
- `docs/02-architecture/数据流全链路技术说明文档.md` §5.5.3
- `UIAutomation/Contracts/instances/creation-surface.json`
