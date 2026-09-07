# ADR-013: 创作与导出边界

**状态**: 已接受
**日期**: 2026-08-04
**决策人**: Model Legal and Privacy Approver（审批）+ Language and Creation Lead（实现）

## 背景

基线中 SYN-001~008 全部为 Stub/Absent/spec-invalid：语言选择为 fixture 过渡、生成无生产路径、直接 Apple Notes 创建/深链 API 不可用（SYN-003/004）、Prompt 编辑器无有界分析管线、情绪干预合成缺失、术语表无运行时/Golden、降级模板仅为显示模拟。`FixtureTranslationService` 仅映射 2 个字符串；`translationCache` 为内存缓存不跨重启（DEF-43-002/003）。

## 决策

1. **Apple Translation 仅展示层**：`AppleTranslationService` 实现 `TranslationService.translate`；先做 LanguageAvailability 检查（不支持的语言对 → `unavailable` 状态保留原文 + 语言标签）；**绝不编造翻译质量分数**（ADR-005 已把质量兜底改为源语言检测置信度 <0.9 时保留原文）。
2. **七天持久缓存**：`PersistentTranslationCache`（TTL=7d，持久化跨重启）；术语表优先，未命中再调 Apple Translation；语言对齐重试 ≤1。
3. **Grounded creation**（ADR-009 批准保留，ADR-017/020 收紧）：`CreativePipeline` 通过批准离线运行时生成。模型只接收 opaque MemoryID，生成协议为版本化、受限 JSON；解析器只接受当前策略过滤后实际提交模型的 allow-list。禁止按段落序号轮询绑定；多引用、无来源和部分无来源使用 `[SourceAnchor]` 与类型化 provenance 状态。allow-list 命中证明来源身份，不自动证明事实正确。
4. **导出边界**：复制、Markdown/PDF/plain-text 系统 share 统一经 composition-owned export coordinator 在准备前执行当前 UserPolicy + PrivacyCheckpoint；撤权时阻止派生正文交接，策略仍允许但来源离线时保留诚实不可用标记。所有格式保留引用，多页 PDF 不截断。Notes 交接**仅用系统 share/export 流**，删除 `notes://echo/...` 深链；用户中介的 Notes 交接不伪造 URL。只有系统控制器实际呈现回调后才记录 `sharePresented=true`；Echo 不保存 activityType、目标 App 或最终完成状态，完整规则见 ADR-020。
5. **创作控制面**：仅当 SYN 保留时创建 `CreativePipeline`/`CreationExportService` 并暴露生产控制；若 SYN 移出 v1 则删除不可达生产控制并断言范围一致性（本 ADR 采用保留路径）。

## 备选方案

| 方案 | 描述 | 结论 |
|------|------|------|
| **A（采纳）** | Apple Translation 展示层 + 七天持久缓存 + grounded creation + 系统 share 导出 | ✅ 满足 US-DIS-002/US-SYN 保留子集，全离线 |
| B | 直接 Apple Notes 创建/深链 | ❌ 私有 API，spec-invalid |
| C | 云端翻译/生成 | ❌ 违反 R-001/R-005 |

## 后果

### 正面

- 翻译可用性检查、uncertain fallback、七天缓存跨重启、grounded anchors、导出内容全部可测。
- 关闭 DEF-43-002/003、DEF-44-001 的证据路径确定。
- 无伪造 Notes URL，交接走用户可见系统流。

### 负面

- 不支持语言对只能保留原文（功能受限但透明）。
- Grounded creation 输出质量受离线运行时限制；来源 allow-list 只证明 provenance，无法通过校验或部分无法校验的内容必须诚实标记 `NoSource/partialNoSource`。
- 导出文件语言选择需遵循 preferredLanguage。

## 参考

- `docs/01-spec/用户故事与验收标准规格书.md` US-DIS-002、US-SYN-001~008
- `docs/03-implementation/双语言实现说明文档.md` §6.4/§8.1
- AGENTS.md R-004、§6（跨语言与 i18n 契约）
- `docs/05-planning/phase3f-execution-plan.md` §4.6.9（3F.9 文档合同）
- ADR-005（翻译质量兜底修订）、ADR-009（离线模型运行时）、ADR-020（来源锚点与分享审计）
