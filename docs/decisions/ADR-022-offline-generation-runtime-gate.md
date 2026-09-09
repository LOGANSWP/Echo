# ADR-022: 离线生成运行时门禁与叙事报告任务拆分

**状态**: 已接受
**日期**: 2026-09-07
**决策人**: Codex（依人类“规格不合理先修改”指令，在 PR #78 预审中执行）

## 背景

> **2026-09-08 实现进展**：具体 Qwen3 工件使用/集成已获用户批准，默认 AppComposition 已装配真实 provider 与分层报告 generator；详见 `docs/05-planning/4.0k-production-validation.md`。模拟器 Core ML 加载失败、实机开发签名阻断，质量/设备/覆盖率门禁尚未通过；不得宣称 4.0k 或自动报告产品 AC 完成。

ADR-009 批准了“不可变捆绑 LLM 运行时/工件 + 许可证 + 校验和”的方向，但仓库当前没有已登记、已批准且可装配的生成式 LLM 工件。生产装配 `LiveAppAdapters.resolveLLMProvider()` 明确返回 `nil`，因此 `CreativePipeline` 和 `CreativeNarrativeReportGenerator` 只能在注入测试替身时成功。

原 `4.0j` 同时要求调度/持久化基础和生产自动生成闭环，并以 Stub generator 的测试结果把 US-SYN-004 AC-3/5/6 标为完整生产证据。这违反“fixture 不得作为生产完成证据”的既有边界，也会导致默认开启的生命周期扫描在没有运行时的版本中反复把真实周期写成 L2 `retryRequired`。

## 决策

1. `4.0j` 收敛为“月度与年度叙事报告持久调度与存储基础”：交付持久开关与独立基线、完整周期规划、CAS claim、TaskQueue/Progress 接线、报告/来源 schema、原子 publication、noData/L2/资源延后、D-005 删除、Creation 报告库以及可注入的 `NarrativeReportGenerating` seam。
2. 当生产生成器未装配时，自动或用户扫描必须在 claim/物化周期前返回显式 `generationUnavailable`；不得创建 `retryRequired`、`PendingOperations`、伪报告或 generated 审计。UI 对用户明确扫描显示真实不可用状态。
3. 新增 `4.0k`“端侧生成式模型运行时与叙事报告生成闭环”，负责：
   - 选择并经 Model Legal/Privacy 批准可商业分发的端侧生成模型与运行时；
   - 固定不可变 revision、SHA-256、许可证、NOTICE、SBOM、转换 lineage 与模型登记；
   - 生产实现并装配 `LLMProvider`，保持 R-001/R-004/R-005；
   - 实现真正消费 `sourceBatches` 的确定性有界分批/分层聚合，而非一次扁平化或静默依赖 Stub；
   - 以真实 bundled artifact 的 no-fixture 端到端测试证明 US-SYN-004 自动生成、来源协议、语言对齐、资源门禁和重启行为。
4. US-SYN-004 产品 AC 保持不变，因为产品要求本身合理；实现状态明确为 Partial，直到 `4.0k` 完成。所有会宣称 US-SYN-004 生产闭环、全 Pipeline E2E 或 Release Candidate 的下游任务必须依赖 `4.0k`。
5. `4.0j` 的 Stub generator 只验证调度器、队列和 publication seam，不得再表述为生产生成证据。PR #78 可在修复其自身调度缺陷并诚实标注范围后交付基础，但不得宣称 US-SYN-004 全部完成。

## 备选方案

> **合理性复审补充（2026-09-07，ADR-023）**：保留本 ADR 的任务拆分及产品目标。4.0k 按候选证据→确切工件人类审批→生产验收执行；ready 不表示模型获批。SYN-001/002 的直接验收依赖、完整 token/运行时预算、逐层引用、语言失败与恢复重放详见 ADR-023。本文“产品 AC 保持不变”描述 PR #78 当时的拆分决定，不阻止后续经用户授权的规格修订；本次新增明确合同不构成生产完成证据。

| 方案 | 描述 | 结论 |
|------|------|------|
| **A（采纳）** | 保留产品 AC，拆分 4.0j 基础与 4.0k 真实运行时 | 技术依赖与证据边界清晰，不伪造能力 |
| B | 用固定模板或抽取式拼接冒充生成式报告 | 无法满足 ADR-009 与叙事质量目标，也会弱化产品语义 |
| C | 继续以 Stub 通过视为生产闭环 | 违反 fixture 证据禁令，且真实 App 永远无法生成 |
| D | 接入云端 LLM | 违反 R-001/R-005 绝对红线 |

## 后果

- `4.0j` 在生成器缺失时 fail-closed，不制造误导性的 L2 待重试记录。
- Phase 4 增加一个不可绕过的模型/运行时交付任务；RC 时间线取决于模型许可、包体积、质量与实机性能审批。
- 现有调度和持久化代码可独立审查、合并并被 `4.0k` 复用。
- US-SYN-003 及其他依赖同一生成运行时的故事也应在 `4.0k` 中重新审计真实完成状态。

## 参考

- `docs/decisions/ADR-009-offline-model-runtime.md`
- `docs/decisions/ADR-013-creation-export-boundary.md`
- `docs/decisions/ADR-020-grounded-citation-share-audit.md`
- `docs/decisions/ADR-021-narrative-report-scheduling-persistence.md`
- `docs/01-spec/用户故事与验收标准规格书.md` US-SYN-003/004
- AGENTS.md R-001/R-004/R-005、§13.2、§17.2
