# Echo UI 文档路由

> **责任**：告诉 Agent 针对 UI 任务读取哪份文档，而不是让 Agent 重读 bootstrap 全文
> **无需读取本文全文**：按任务选择下表对应文档即可
> **最后同步**：2026-09-07，ADR-022 拆分 4.0j 调度基础与 4.0k 真实端侧生成运行时证据

---

## 文档地图

| 文档 | 路径 | 用途 | 何时读取 |
|------|------|------|----------|
| **设计风格** | `echo-memory-canvas-style.md` | 完整 Apple 原生基础、Discovery/Focus/Task 映射、共享 token、内容卡片、响应式与可访问性、禁止项 | 任何 UI 实现任务 |
| **自动化工作流** | `automation-workflow.md` | 状态机、任务账本桥接、自动继续、唯一 simulator 所有者（双审查设备 17 Pro + 16 Pro）、重试、停止、恢复、试点评分和批准点 | 执行 `$ui-bootstrap-build-echo` 时 |
| **架构** | `architecture.md` | 六层职责、单向数据流、组件边界、受保护和允许内容 | 理解 UI 层与 Core 层的边界时 |
| **测试与 Artifact** | `testing-and-artifacts.md` | PR 与 nightly 矩阵、artifact 字段、测试层级、安全、各阶段 Definition of Done | 编写测试或收集 artifact 时 |
| **命令兼容性** | `command-compatibility.md` | 14 个现有命令 + 3 个新增命令在 Phase 3 UI 模式下的行为表 | 不确定某个命令是否可用于 Phase 3 时 |

---

## 按任务选择

| 任务 | 必读文档 |
|------|----------|
| Phase 3 UI 实现（3.1–3.9） | `echo-memory-canvas-style.md` + `architecture.md` |
| Phase 3F UI 任务（3F.7–3F.10） | `echo-memory-canvas-style.md` + `architecture.md` + `automation-workflow.md`（按 canonical plan §7 + §6.2.2 执行；checklist 含双设备 Live Sim Review 与 §4.6.7–4.6.10 UIAutomation 契约） |
| Phase 4 共享视觉基础（4.0） | `echo-memory-canvas-style.md` + `architecture.md` + `testing-and-artifacts.md` + DesignProfile/Surface schemas + acceptance policy |
| Phase 4 Discovery（4.0a） | style + architecture + testing + Home/Search Surface Contracts |
| Phase 4 Focus（4.0b） | style + architecture + testing + Detail/Creation/Translation Surface Contracts |
| Phase 4 Task（4.0c） | style + architecture + testing + Settings/Onboarding/Awakening/BackgroundTask/Degradation/ResumeProgress Surface Contracts |
| Phase 4 渐进式权限（4.0f） | style + architecture + testing + ADR-018 + Onboarding/Awakening Surface Contracts + PRV-008/SRC-001/AWK-001~003 AC 原文 |
| Phase 4 真实断点恢复（4.0g） | architecture + testing + ADR-011 + BackgroundTask/ResumeProgress Surface/State/Action/Journey Contracts + acceptance policy + SYS-001 AC 原文；重点核对精确 taskId、checkpoint no-overwrite、Restart 分阶段语义、raw type、当前授权与幂等恢复 |
| Phase 4 交互式唤醒卡（4.0d） | style + architecture + testing + US-AWK-005 AC 原文 + ADR-016 + Home/Detail contracts；Bundle 离线音乐、MemoryFeeling 关系、card→Focus intent 属于生产功能闭环，不是第四种 surface family |
| Phase 4 记忆编辑与冲突（4.0e） | architecture + testing + US-AWK-007 AC 原文 + ADR-010/017 + Memory Detail contracts |
| Phase 4 来源解析与删除（4.0h） | architecture + testing + US-PRV-004/007 AC 原文 + ADR-008/017/019 + Memory Detail delete contracts；重点核对 `canPerform(.delete)`、prepared/confirmed 外部门禁、limited-hidden 非删除、transcript-only Share audio 与真实通知审计 |
| Phase 4 引用与分享（4.0i） | architecture + testing + US-SYN-002/003/004 AC 原文 + ADR-013/017/020 + Detail/Creation contracts + acceptance policy；重点核对版本化有界 JSON、多引用/partialNoSource、provenance 非事实证明、当前授权复验、三格式引用保留、真实呈现回调与 typed audit columns |
| Phase 4 叙事调度（4.0j）与真实生成（4.0k） | architecture + testing + US-SYN-004 AC 原文 + ADR-009/011/017/021/022 + Creation report-library State/Action Contracts + acceptance policy；4.0j 核对持久开关/独立 eligibleFrom、完整周期/冻结时区、CAS、report/source、原子 publication、noData/L2/BG/D-005 及 generator=nil 零 claim；4.0k 核对获批 bundled LLM、生产 adapter、Language Aligner、真实分批/分层与 no-fixture E2E |
| UI 测试 | `testing-and-artifacts.md` |
| UI 交付 | `automation-workflow.md`（§批准点 — 含 UI 审查指南：页面清单/导航路径/未实现说明） |
| 首次 bootstrap | `echo-readiness.md` + `automation-workflow.md` |

---

## Phase 3F 感知

UI bootstrap skill 流水线（`$init-session-echo`、`$next-task-echo`、`$ui-bootstrap-build-echo`、`$ui-status-echo`、`$ui-retry-echo`）是 **3F-aware** 的：

- **phase 是字符串**：`docs/05-planning/task-status.json` 的 `phase_order` 与 `current_phase` 均为字符串，包含 `"3F"`（`["1","2","3","3F","4","5"]`）
- **UI 模式匹配精确 `"3"`**：`init-session-echo` / `next-task-echo` 的 UI 分支仅在 `current_phase == "3"`（精确字符串匹配）时进入 UI handoff/bootstrap 模式；`current_phase == "3F"` 时命令按通用流程运行，UI 模式不自动触发
- **全部 Phase 3F 任务按 canonical plan §7 + §6.2.2 协议执行**：Phase 3F 的 UI 任务（3F.7 UI→Core 全域接线、3F.8 Awakening 与 system adapters、3F.9 Apple Translation 与 grounded creation、3F.10 i18n/accessibility/errors）与其余 3F 任务一样走任务清单 → §6.2.2 单脚本交付 → PR → 人类合并，checklist 额外含双设备 Live Simulator Review、AX tree、无媒体 manifest 与 UIAutomation Contracts/Fixtures（§4.6.7–4.6.10）。`$ui-bootstrap-build-echo` 为 Phase 3 专用（校验 `current_phase == "3"` 精确匹配），**不适用于 Phase 3F**
- **UI 工作延续同一设计 profile 与规则**：Phase 3F UI 工作继续使用已批准的 `echo-memory-canvas` 设计配置与本文档目录全部规则（双设备 Live Simulator Review、无媒体 manifest `visualMediaCaptured: false`）；`3F.0` 人类合并后，standing authority 允许在任务穷尽式 Files 清单内修改 UI-adjacent Core 接线文件
- **2026-08-31 视觉决策（补充）**：方案 B「平衡画布」是全 App 唯一视觉方向。Home/Search 在丰富真实内容时默认 adaptive masonry；Focus/Task 保留其原生信息架构但必须使用相同 token、容器、组件语义与 motion，不允许保留另一套旧皮肤。
- 详见 `command-compatibility.md`

---

## 实际路径映射

| 提案路径 | 实际路径 | 状态 |
|----------|----------|------|
| `docs/ui/README.md` | `docs/ui/README.md` | ✅ |
| `docs/ui/echo-memory-canvas-style.md` | `docs/ui/echo-memory-canvas-style.md` | ✅ |
| `docs/ui/automation-workflow.md` | `docs/ui/automation-workflow.md` | ✅ |
| `docs/ui/architecture.md` | `docs/ui/architecture.md` | ✅ |
| `docs/ui/testing-and-artifacts.md` | `docs/ui/testing-and-artifacts.md` | ✅ |
| `docs/ui/echo-readiness.md` | `docs/ui/echo-readiness.md` | ✅ |
| `UIAutomation/Contracts/` | `UIAutomation/Contracts/` | ✅ |
| `UIAutomation/Fixtures/` | `UIAutomation/Fixtures/` | ✅ |
| `UIAutomation/Policies/` | `UIAutomation/Policies/` | ✅ |
| `UIAutomation/Artifacts/` | `UIAutomation/Artifacts/` | ✅ |
| `.ui-automation/state.json` | `.ui-automation/state.json` | ✅ |

---

## 权威顺序

冲突时按以下顺序，前者高于后者：
1. 用户当前明确指令 + 仓库根 `AGENTS.md` + 受保护政策
2. `docs/05-planning/task-status.json`（项目 phase、任务生命周期唯一权威）；`docs/05-planning/deferred-items.json`（延期任务追踪，与 task-status.json 同级维护）
3. `UIAutomation/Contracts` 与 `UIAutomation/Policies`（UI 机器契约）
4. 本目录下的拆分设计文档
5. 原始 bootstrap 规范（仅首次初始化输入，物化后不再是运行权威）

**3F.10 交付（2026-08-12）**：i18n/accessibility/errors 任务完成——`Localizable.xcstrings` 双语目录（336 keys）、`LanguageCenter` 统一语言、L1~L4 错误分级本地化、`SystemMonitor` 低电量/热降级运行时接线、双设备 Live Sim Review 通过（`UIAutomation/Artifacts/manifests/3F.10-i18n-accessibility-run-manifest.json`，`visualMediaCaptured: false`）。
