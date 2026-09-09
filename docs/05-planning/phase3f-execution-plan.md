# Echo Phase 3F 开发 Agent 执行指令（2026-08）

**For agentic workers:** Preferred when available: use `subagent-driven-development` or `executing-plans` to implement this plan task-by-task. First detect whether named skills are installed; if unavailable, follow the embedded equivalent workflows in §2 and the cited sections. Missing skills never block execution, and no external skill installation or repository `SKILL.md` is required or permitted without human approval. Ordinary `☐` bullets are execution checks. This current instruction contains the complete Phase `3F.0` bootstrap content, but it does not claim that `3F.0` already exists as a ready ledger task. Before bootstrap, the target repository's current `AGENTS.md` remains authoritative and a human on the target machine must explicitly authorize and start the docs-only bootstrap worktree/PR. After that authorization, `3F.0` materializes this instruction as the canonical plan at `docs/05-planning/phase3f-execution-plan.md`, extracts Appendix C to `docs/05-planning/phase3f-story-matrix.md`, and creates `docs/05-planning/phase3f-evidence-index.md`.

**Goal:** 在默认 Echo App 路径上完成 Phase 3F 功能闭环与生产集成，以 `3F.11` 的无 fixture 生产 E2E 门禁作为 Phase 4 的唯一入口。

**Architecture:** 保持 Swift 6 Cognitive Pipeline + Actor Isolation + `@MainActor @Observable` ViewModel 架构；SQLite `Memory`/`Representation` 是规范事实源，每个模型空间使用独立 generation 与 `VectorStoreActor`，通过 `ActiveRouteSet` 原子发布。所有来源、推理、检索、反馈、唤醒、翻译与创作必须由应用持有的 composition root 接入默认 App，fixtures 仅可用于测试或预览。

**Tech Stack:** Swift 6、SwiftUI/Observation（iOS 18+）、Swift Concurrency、SQLite3、ProximaKit 1.7、Core ML、whisper.cpp、PhotoKit、HealthKit、CoreLocation、UserNotifications、Apple Translation、XCTest/Swift Testing/XCUITest。

## 1. 使命、成功定义与执行权

你是 Echo Phase 3F 的专职开发 Agent。你从零上下文开始。当前仓库根目录 `AGENTS.md` 始终高于本文件。`3F.0` 人类合并前，目标机器上当前的 `AGENTS.md` 是唯一已生效的仓库规约；本文件只提供待显式启动的 bootstrap 内容，不能覆盖其 Core 只读、任务选择、Git 交付或禁止 screenshot/video 等规则，也不能假装 `3F.0` 已经是 ledger 中可自动选择的 `ready` 任务。只有目标机器上的人类明确授权并启动 §1.1 所述 docs-only bootstrap PR 与隔离 worktree/branch 后，Agent 才可执行 `3F.0`；授权缺失立即停止。合并前禁止交付任何其他 PR，也禁止修改任何业务代码、测试代码、Xcode 工程、CI、签名配置或发布配置。合并后，以已修订的 `AGENTS.md`、canonical execution plan、`docs/01-spec/用户故事与验收标准规格书.md` 和已接受 ADR 为执行权威；仍有冲突时以最新 `AGENTS.md` 为准并停止执行。

成功必须同时满足：

1. `3F.0` 至 `3F.10` 全部由人类合并并标记 `done`。
2. 默认 App 完成同意、真实来源、真实模型、规范存储、摄入、检索、反馈、编辑/删除、唤醒、翻译/创作、重启恢复闭环。
3. `3F.11` 的 Release device/simulator、全套测试、覆盖率、隐私、制品、签名与 no-fixture E2E 全绿。
4. v1 范围内未关闭 P0=0、P1=0；正式移出 v1 的项目具有批准记录、owner、目标任务/版本和验收证据。
5. `3F.11` 人类合并后才把 `current_phase` 从 `"3F"` 改为 `"4"`。

### 1.1 授权

授权分两段生效：

1. **显式 bootstrap 授权：** `3F.0` 人类合并前不存在 standing automatic Phase 3F authority。目标机器上的人类必须明确启动并授权唯一的 `3F.0` docs-only bootstrap PR、任务分支和注册 worktree，并向 §6.2.1 提供 `PHASE3F_BOOTSTRAP_AUTHORIZATION=human-approved-docs-only`、`PHASE3F_BOOTSTRAP_AUTHORIZED_BY` 与 `PHASE3F_BOOTSTRAP_AUTHORIZED_AT`。任一值缺失或授权范围不匹配均立即停止。该一次性授权只允许 §4.5、§4.6.0 与 3F.0 Files 穷尽清单中的文档、planning、policy、command 与状态 schema 变更，以及相应 commit、push、创建或更新这一份 PR；不允许业务代码、测试、Xcode、CI、签名、发布配置或其他 PR。
2. **合并后持续授权：** `3F.0` 必须明确修订 `AGENTS.md` §17 与 `docs/ui/` 规则。只有该 docs-only PR 被人类合并后，用户授予的持续权限才允许 Agent 按 3F.1 至 3F.11 各任务穷尽式 Files 清单自动修改指定 Core、UI、测试、Xcode、CI 与发布文件，并自动 commit、push、创建或更新目标为 `dev-1.0` 的当前任务 PR，无需逐任务重复批准。人类批准仍仅对合并 PR、关闭 PR、删除本地或远程分支，以及任何超出当前任务明示范围的操作为强制要求。持续权限不允许覆盖现有工作、绕过门禁或执行上述人类专属操作。

### 1.2 禁止事项

- 禁止调用 `gh pr merge`、任何合并 API、自动关闭 PR 或删除本地/远程分支。
- 禁止降低、跳过、静音或删除测试、覆盖率、隐私、静态分析、签名或发布门禁。
- 禁止把 fixture、Preview、模拟状态、手工依赖注入、手工数据库写入或 manual injection 当成生产完成证据。
- 禁止把模型、用户数据、凭据、签名材料、DerivedData、`.xcresult` 或生成制品提交到 Git。
- 禁止新增网络下载、云端 AI、分析 SDK、Combine、`Task.detached`、`@unchecked Sendable` 或 `nonisolated(unsafe)`。
- 禁止猜测 Apple API、模型 runtime、Share Extension 传输、canonical repository 或 creation API；仓库没有的合同必须先由 `3F.0` 形成批准的规格和 ADR。
- 禁止在 `3F.11` 之前启动 Golden、性能、TestFlight、Release Candidate 或最终发布集成。

## 2. 首选技能与内嵌等价工作流

每个任务开始前先检测下列命名技能是否已安装。已安装技能可作为首选辅助，但本指令中的行为、顺序、安全边界与停止条件始终为规范要求。任何技能缺失都不得阻断执行，也不得触发自动安装；安装任何外部技能必须先取得人类明确批准。Agent 无需读取外部或仓库内的 `SKILL.md`，必须能只依靠本指令完成任务。

1. `using-git-worktrees`（可选）：可用时用于隔离工作区；不可用时严格执行 §6.2.1，从最新 `origin/dev-1.0` 建立 clean isolated worktree/branch，并保留其冲突、no-overwrite、no-reset、no-clean 与 no-delete 规则。
2. `executing-plans` 或 `subagent-driven-development`（可选）：可用时用于任务编排；不可用时按本指令 3F.0→3F.11、显式 dependencies、§3 preflight 与每任务 checklist 顺序执行，禁止跨未满足依赖并行。
3. `test-driven-development`（可选）：可用时用于测试先行；不可用时执行 §6.1 与每任务 checklist 的 RED→GREEN 流程，先写失败测试、确认目标 RED、逐 AC 最小实现，再运行 focused 与 cumulative gates。
4. `systematic-debugging`（可选）：可用时用于根因分析；不可用时执行 §9，保存完整日志，形成至少三个可证伪假设，运行最小复现，切换不同方案，并在三种方案失败后阻断和记录证据。
5. `frontend`（可选）：仅在 3F.7、3F.8、3F.9、3F.10 的 UI 改动中使用；不可用时直接遵循本节 UI 规则、§4.6 同名文档合同、`docs/ui/` 规则与 UIAutomation contracts，并保持已批准的 `echo-memory-canvas`。
6. `verification-before-completion`（可选）：可用时用于完成前验证；不可用时执行 §6 的 focused、cumulative、UI、Release、static/privacy/model/compliance 顺序，并按 §11 记录当前 commit 的新鲜命令、exit code、计数与制品证据。
7. `requesting-code-review`（可选）：可用时用于独立审查；不可用时执行 §8，对规格、质量、安全、review threads 与 CI logs 做独立审查，分类有效缺陷、过度建议和误报，且有效缺陷先补失败测试。
8. `git-master`（可选）：可用时用于 Git 操作；不可用时原样执行 §6.2.1 的 clean setup 和 §6.2.2 的 staged diff、commit、push、PR create/update 与 ledger-body refresh；合并、关闭和删除仍由人类控制。
9. `visual-qa`（可选）：若已安装，仅可使用不要求媒体捕获且不冲突的审查部分；不可用或要求媒体捕获时，直接执行本节、§4.6 与 UI contracts 的双设备 Live Simulator Review、AX tree、统一日志和结构化 manifest 流程。
10. 所有 UI 变更遵循项目 `AGENTS.md` §17 和 `docs/ui/testing-and-artifacts.md`。只执行双设备 Live Simulator Review、AX tree、统一日志和结构化 manifest，不创建或持久化 screenshot、video、reference、actual 或 diff。任何可选技能都不得覆盖项目规则、改变设计方向、弱化安全要求或引入媒体捕获。

## 3. Preflight：任何改动之前

☐ Bootstrap authority：`3F.0` 开始前，先读取目标仓库当前 `AGENTS.md`；它在 pre-merge 阶段保持权威。`3F.0` 不走普通 `ready → in_progress` 自动选择，不要求或假设当前 ledger 已存在 3F phase/task record。目标机器上的人类必须明确启动并授权 docs-only bootstrap PR 与隔离 worktree/branch，并提供 §1.1 的三个 bootstrap authorization 值；缺失立即停止。该授权与 §6.2.1 注册 worktree 创建属于 pre-task environment setup，不是 task ledger transition。 ☐ 从 §6.2 表设置当前任务的 `TASK_ID`、`BRANCH`、`COMMIT_SUBJECT`、`PR_TITLE`、`RELATED_STORIES`。在不修改 ledger 的 clean repository root 执行 `git status --short` 与 `git log --oneline -10`；然后运行 §6.2.1，记录其打印的 `PHASE3F_WORKTREE_PATH`，并要求之后每个文件、Git、Python、测试和其他 tool command 都以该精确路径为 working directory。 ☐ 执行 `xcodebuild -list -project Echo.xcodeproj`，确认 `Echo`、`EchoTests`、`EchoUITests` 与 `Echo` scheme。 ☐ 运行 `python3 Scripts/gen_compile_commands.py`；该文件只用于本机 LSP，不提交。 ☐ 解析两个 ledger：`python3 -m json.tool docs/05-planning/task-status.json >/dev/null` 与 `python3 -m json.tool docs/05-planning/deferred-items.json >/dev/null`。 ☐ 对 `3F.0`，只读解析 bootstrap 前的两个 planning JSON 作为迁移输入，不执行普通候选任务选择、`backlog → ready` 级联或现有 task 状态写入。进入 §6.2.1 创建/复用且确认 clean 的隔离 worktree 后，原子写入 §4 的新 phase/task/deferred 图，初始 `3F.0.status` 必须是 `in_progress` 并写实际 UTC `last_updated`；随后才开始 docs-only 实现。不得修改业务代码、测试、Xcode、CI、签名或发布配置。 ☐ 对已由人类合并 `3F.0` 后的 `3F.1` 至 `3F.11`，在隔离 worktree 中重新解析两个 ledger，精确读取 `phase_order`、`current_phase`、候选任务与 dependencies；禁止数值减法、前缀推断、最大 ID 推断。仅此时执行满足依赖任务的 `backlog → ready` 级联，并把当前已存在的 `ready` 任务改为 `in_progress`、写实际 UTC `last_updated`。§6.2.2 只能在实现、文档和全部验证完成后运行。 ☐ 先运行该任务相关既有测试，保存基线；若基线失败，记录为当前任务阻断并按失败恢复流程处理。

## 4. Phase 3F 账本迁移（3F.0 必须原子落地）

### 4.1 `task-status.json` 根与 phase schema

根对象增加：

```
{
  "current_phase": "3F",
  "phase_order": ["1", "2", "3", "3F", "4", "5"]
}
```

所有 phase ID 统一为字符串。六个 phase 对象必须完整写入以下关系，不得省略 `null` 边界，也不得从 ID 数值或任务最大值推断：

| id     | name                 | status        | previous_phase_id | next_phase_id | integration_task_id | integration_test | integration_test_file                             |
| ------ | -------------------- | ------------- | ----------------- | ------------- | ------------------- | ---------------- | ------------------------------------------------- |
| `"1"`  | `基础设施搭建`       | `done`        | `null`            | `"2"`         | `"1.9"`             | `passed`         | `EchoTests/Phase1/Phase1IntegrationTests.swift`   |
| `"2"`  | `核心认知管线`       | `done`        | `"1"`             | `"3"`         | `"2.14"`            | `passed`         | `EchoTests/Phase2/Phase2IntegrationTests.swift`   |
| `"3"`  | `UI 与集成`          | `done`        | `"2"`             | `"3F"`        | `"3.10"`            | `passed`         | `EchoTests/Phase3/Phase3IntegrationTests.swift`   |
| `"3F"` | `功能完成与生产集成` | `in_progress` | `"3"`             | `"4"`         | `"3F.11"`           | `pending`        | `EchoTests/Phase3F/Phase3FIntegrationTests.swift` |
| `"4"`  | `质量保障与发布准备` | `not_started` | `"3F"`            | `"5"`         | `"4.14"`            | `pending`        | `EchoTests/Phase4/Phase4IntegrationTests.swift`   |
| `"5"`  | `创新工具预研与原型` | `not_started` | `"4"`             | `null`        | `"5.11"`            | `pending`        | `null`                                            |

Phase 3 保持 `done`，说明改为“UI 与可注入交互切片完成，不代表生产功能完成”。Phase 4 设置 `status: "not_started"`、`entry_gate: "3F.11"`、所有强制任务 `backlog`；命令不得在 `3F.11 == done` 前级联 Phase 4 为 `ready`。

### 4.2 任务记录

`3F.0` 在人类显式授权的隔离 bootstrap branch 内把以下 12 个完整对象原子写入 `docs/05-planning/task-status.json`；这些对象在写入前不被视为已存在的 ledger tasks，`3F.0` 也不经过普通 `ready → in_progress` 选择。初始原子写入必须把 `3F.0.status` 设为 `in_progress`，其余 3F.1 至 3F.11 保持 `backlog`。`documents_required` 与 §4.6 同名任务合同的全部 Exact paths 集合完全相等；任何 tracked path 增删都必须同时修改两处。当前指令及其 Appendix C 是 `3F.0` 的内嵌 bootstrap content，不是 Exact path，也不进入 `documents_required` 或 Files 集合。显示对象中的 `last_updated: null` 是 JSON-safe invalid sentinel，不得写入最终 ledger；3F.0 在同一原子写入中把 12 个 sentinel 全部替换为同一个实际 UTC RFC 3339 时间，替换不完整则写入失败。docs-only 实现和验证完成后，3F.0 在 §6.2.2 前把自身从 `in_progress` 改为 `review` 并写新的实际 UTC 时间；安全敏感任务的 `owner` 同时写实现 owner 与强制 approver。以下 fenced blocks 各自是合法 JSON 数组；按出现顺序连接其数组元素，得到唯一的 Phase 3F record set（3F.0 bootstrap 原子写入 12 条；2026-08-07 拆分 3F.3 新增 3F.3a/3F.3b，当前为 14 条）。3F.3a/3F.3b 两条记录的 `last_updated` 由拆分规划 PR 一并替换为实际 UTC 时间，非 3F.0 sentinel 替换范围。

```
[
  {
    "id": "3F.0",
    "title": "规格、范围、账本与接口冻结",
    "story": ["US-SRC-002", "US-SRC-006", "US-ING-001", "US-ING-002", "US-ING-003", "US-ING-004", "US-RET-003", "US-RET-004", "US-SYN-003", "US-SYN-004", "US-AWK-002", "US-PRV-003", "US-PRV-005", "US-PRV-007"],
    "status": "in_progress",
    "owner": {"implementation": "Technical Program Lead", "approver": "Product and Architecture Lead"},
    "documents_required": ["AGENTS.md", "README.md", "docs/INDEX.md", "docs/01-spec/用户故事与验收标准规格书.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/技术选型文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/03-implementation/双语言实现说明文档.md", "docs/04-ai-native/产品创新工具全景指南.md", "docs/05-planning/开发计划安排文档.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-evidence-index.md", "docs/ui/README.md", "docs/ui/architecture.md", "docs/ui/automation-workflow.md", "docs/ui/testing-and-artifacts.md", "docs/ui/command-compatibility.md", "docs/ui/echo-readiness.md", "docs/ui/echo-memory-canvas-style.md", "UIAutomation/Policies/README.md", "UIAutomation/Policies/acceptance-policy.json", "UIAutomation/Policies/protected-paths.json", "UIAutomation/Policies/retry-policy.json", "docs/decisions/ADR-006-phase3f-scope-contracts.md", "docs/decisions/ADR-007-production-composition-consent.md", "docs/decisions/ADR-008-source-import-boundaries.md", "docs/decisions/ADR-009-offline-model-runtime.md", "docs/decisions/ADR-010-canonical-generation-lifecycle.md", "docs/decisions/ADR-011-task-progress-boundary.md", "docs/decisions/ADR-012-awakening-system-boundary.md", "docs/decisions/ADR-013-creation-export-boundary.md", "docs/decisions/ADR-014-release-compliance-boundary.md", ".opencode/commands/init-session-echo.md", ".opencode/commands/next-task-echo.md", ".opencode/commands/do-task-echo.md", ".opencode/commands/status-echo.md", ".opencode/commands/test-phase-echo.md", ".opencode/commands/test-integration-echo.md", ".opencode/commands/test-unit-echo.md", ".opencode/commands/read-spec-echo.md", ".opencode/commands/retry-task-echo.md", ".opencode/commands/commit-pr-echo.md", ".opencode/commands/pr-review-echo.md", ".opencode/commands/pr-merge-echo.md", ".opencode/commands/ui-bootstrap-build-echo.md", ".opencode/commands/ui-status-echo.md", ".opencode/commands/ui-retry-echo.md", ".opencode/commands/sync-docs-echo.md", ".ui-automation/state.schema.json"],

    "dependencies": [ ],

    "test_file": null,
    "acceptance_evidence": ["规划 JSON 解析、唯一 ID、依赖存在、无环、phase links 与 Phase 4 lock 审查", "66 个故事全部进入 phase3f-story-matrix.md 的任务或批准延期", "三个 UIAutomation policy 保留停止条件并授权 Phase 3F 路径"],
"last_updated": null,
    "notes": "Creates the canonical tracked plan from the current instruction, the story matrix from Appendix C, and the evidence-index skeleton.",
    "pr": null
  },
  {
    "id": "3F.1",
    "title": "Production composition、首次启动、同意与隐私",
    "story": ["US-PRV-001", "US-PRV-004", "US-PRV-005", "US-PRV-006", "US-PRV-008", "US-SRC-001", "US-RES-004"],
    "status": "backlog",
    "owner": {"implementation": "iOS Platform Lead", "approver": "Privacy Engineering Lead"},
    "documents_required": ["README.md", "docs/ui/echo-memory-canvas-style.md", "docs/01-spec/用户故事与验收标准规格书.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/decisions/ADR-007-production-composition-consent.md", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json", "UIAutomation/Contracts/instances/onboarding-surface.json", "UIAutomation/Contracts/instances/onboarding-journey-happy-path.json", "UIAutomation/Contracts/instances/onboarding-journey-privacy-declined.json", "UIAutomation/Contracts/instances/onboarding-journey-permission-denied.json", "UIAutomation/Contracts/instances/onboarding-state-welcome.json", "UIAutomation/Contracts/instances/onboarding-state-language.json", "UIAutomation/Contracts/instances/onboarding-state-privacy-consent.json", "UIAutomation/Contracts/instances/onboarding-state-declined.json", "UIAutomation/Contracts/instances/onboarding-state-permissions.json", "UIAutomation/Contracts/instances/onboarding-state-permission-denied.json", "UIAutomation/Contracts/instances/onboarding-state-completed.json", "UIAutomation/Contracts/instances/onboarding-action-start.json", "UIAutomation/Contracts/instances/onboarding-action-selectLanguage.json", "UIAutomation/Contracts/instances/onboarding-action-privacyAgree.json", "UIAutomation/Contracts/instances/onboarding-action-privacyDecline.json", "UIAutomation/Contracts/instances/onboarding-action-declinedClose.json", "UIAutomation/Contracts/instances/onboarding-action-permissionAllow.json", "UIAutomation/Contracts/instances/onboarding-action-permissionDeny.json", "UIAutomation/Contracts/instances/onboarding-action-permissionSkip.json", "UIAutomation/Contracts/instances/onboarding-action-openSettings.json", "UIAutomation/Fixtures/onboarding/onboarding-welcome.json", "UIAutomation/Fixtures/onboarding/onboarding-language.json", "UIAutomation/Fixtures/onboarding/onboarding-privacy-consent.json", "UIAutomation/Fixtures/onboarding/onboarding-declined.json", "UIAutomation/Fixtures/onboarding/onboarding-permissions.json", "UIAutomation/Fixtures/onboarding/onboarding-permission-denied.json", "UIAutomation/Fixtures/onboarding/onboarding-completed.json"],
    "dependencies": ["3F.0"],
"test_file": "EchoTests/Phase3F/3F.1_ProductionCompositionTests.swift",
    "acceptance_evidence": ["无 fixture 新装、拒绝、同意、重启与撤回清除证据", "AuditLog schema/storage migration proves eventType, timestamp, traceID, policyVersion and success are required", "hash-only audit content, 30-day cleanup boundary and NSFileProtectionComplete evidence", "Privacy approver 对 deny-by-default、事务清除与 audit contract 签字", "evidence index 中的 commit、命令和制品索引"],
"last_updated": null, "notes": "Closes DEF-45-002 only with purge evidence.", "pr": null
  }
]
[
  {
    "id": "3F.2", "title": "PhotoKit、Share Extension 与真实来源",
    "story": ["US-SRC-001", "US-SRC-003", "US-SRC-004", "US-SRC-005", "US-SRC-008", "US-SRC-012", "US-SRC-013", "US-PRV-001"],
    "status": "backlog", "owner": {"implementation": "iOS Sources Lead", "approver": "Privacy Engineering Lead"},
    "documents_required": ["README.md", "docs/01-spec/用户故事与验收标准规格书.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/decisions/ADR-008-source-import-boundaries.md", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json"],
"dependencies": ["3F.0", "3F.1"], "test_file": "EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift",
    "acceptance_evidence": ["真实 PhotoKit 与 Share Extension 输入、权限撤回、队列原子性和去重证据", "Privacy approver 对 App Group 最小数据边界签字"],
"last_updated": null, "notes": "Migrated from 4.20.", "pr": null, "migrated_from": ["4.20"]
  },
  {
    "id": "3F.3", "title": "E5、SigLIP2、Whisper 与离线生成决策落地",
    "story": ["US-ING-001", "US-ING-002", "US-ING-003", "US-ING-004", "US-ING-005", "US-RET-001", "US-RET-002", "US-RET-006", "US-RES-001", "US-RES-004", "US-SRC-011"],
    "status": "backlog", "owner": {"implementation": "On-device ML Lead", "approver": "Model Legal and Privacy Approver"},
    "documents_required": ["README.md", "docs/ui/echo-memory-canvas-style.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/技术选型文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/03-implementation/双语言实现说明文档.md", "docs/03-implementation/开发避坑与关键注意点手册.md", "docs/decisions/ADR-009-offline-model-runtime.md", "docs/05-planning/model-provenance-register.md", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json", "UIAutomation/Contracts/instances/onboarding-surface.json", "UIAutomation/Contracts/instances/onboarding-state-model-loading.json", "UIAutomation/Contracts/instances/onboarding-action-beginLoad.json", "UIAutomation/Fixtures/onboarding/onboarding-model-loading.json", "UIAutomation/Contracts/instances/onboarding-state-completed.json", "UIAutomation/Fixtures/onboarding/onboarding-completed.json", "UIAutomation/Contracts/instances/onboarding-state-model-load-error.json", "UIAutomation/Contracts/instances/onboarding-state-model-unavailable.json", "UIAutomation/Contracts/instances/onboarding-action-retryModelLoad.json", "UIAutomation/Contracts/instances/onboarding-journey-model-load-recovery.json", "UIAutomation/Fixtures/onboarding/onboarding-model-load-error.json", "UIAutomation/Fixtures/onboarding/onboarding-model-unavailable.json"],
"dependencies": ["3F.0"], "test_file": "EchoTests/Phase3F/3F.3_ProductionModelInferenceTests.swift",
    "acceptance_evidence": ["每个模型的 revision、SHA-256、转换 lineage、license、NOTICE、SBOM 与商业分发批准", "US-SRC-011 model-semantics reference outputs", "参考输出、损坏恢复与零网络证据"],
"last_updated": null, "notes": "Migrated from 4.21 and 4.22; ADR-009 governs.", "pr": null, "migrated_from": ["4.21", "4.22"]
  },
  {
    "id": "3F.3a", "title": "SigLIP2 Core ML 转换与视觉推理接入",
    "story": ["US-ING-004", "US-SRC-011", "US-RET-001"],
    "status": "ready", "owner": {"implementation": "On-device ML Lead", "approver": "Model Legal and Privacy Approver"},
    "documents_required": ["README.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/技术选型文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/03-implementation/双语言实现说明文档.md", "docs/03-implementation/开发避坑与关键注意点手册.md", "docs/decisions/ADR-009-offline-model-runtime.md", "docs/05-planning/model-provenance-register.md", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json"],
"dependencies": ["3F.0", "3F.3"], "test_file": "EchoTests/Phase3F/3F.3a_SigLIP2ConversionTests.swift",
    "acceptance_evidence": ["PyTorch→Core ML 转换 lineage + 固定 revision + SHA-256 登记（model-provenance-register §3）", "参考向量余弦相似度 > 0.995 验证（siglip2-reference-vectors.json 回填）", "四类门禁：法律、转换一致性、Echo 数据集实机评测、实体设备资源门禁", "SigLIP2Embedder 真实 embedImage 推理（768d，独立 vision generation）"],
"last_updated": null, "notes": "Split from 3F.3: 3F.3 delivers conversion source + preprocessing; this task completes Core ML conversion, reference-vector validation and real vision inference. ADR-009 decisions 1/2 govern.", "pr": null
  },
  {
    "id": "3F.3b", "title": "whisper.cpp 运行时接入与真实转写",
    "story": ["US-ING-003", "US-ING-005", "US-SRC-011"],
    "status": "ready", "owner": {"implementation": "On-device ML Lead", "approver": "Model Legal and Privacy Approver"},
    "documents_required": ["README.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/技术选型文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/03-implementation/双语言实现说明文档.md", "docs/03-implementation/开发避坑与关键注意点手册.md", "docs/decisions/ADR-009-offline-model-runtime.md", "docs/05-planning/model-provenance-register.md", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json"],
"dependencies": ["3F.0", "3F.3"], "test_file": "EchoTests/Phase3F/3F.3b_WhisperRuntimeTests.swift",
    "acceptance_evidence": ["whisper.cpp 依赖白名单审批（AGENTS.md §2.2）+ SBOM/NOTICE/许可证登记", "NativeWhisperCInterop 实现（whisper_init_from_file + whisper_full），替代 UnavailableWhisperCInterop", "真实 16kHz mono PCM 转写，whisper-reference-transcripts.json 回填（CER/WER 阈值）", "GGUF SHA-256 与 model-provenance-register §2 一致性验证"],
"last_updated": null, "notes": "Split from 3F.3: 3F.3 delivers GGUF artifact + fail-closed bridge; this task introduces whisper.cpp runtime (§2.2 whitelist approval), C interop and real transcription. Closes DEF-51-002 ASR contract.", "pr": null
  },
  {
    "id": "3F.4", "title": "Canonical storage 与 generation 生命周期",
    "story": ["US-ING-006", "US-PRV-004", "US-PRV-006", "US-PRV-007", "US-AWK-007", "US-FBK-001", "US-FBK-002", "US-FBK-003"],
    "status": "backlog", "owner": {"implementation": "Storage Architecture Lead", "approver": "Privacy Engineering Lead"},
    "documents_required": ["README.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/03-implementation/开发避坑与关键注意点手册.md", "docs/decisions/ADR-010-canonical-generation-lifecycle.md", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json"],
"dependencies": ["3F.1", "3F.3"], "test_file": "EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift",
    "acceptance_evidence": ["迁移、原子发布、重启恢复、rollback 与事务删除矩阵", "ADR-010 与架构、数据流、避坑规则一致性审查"],
"last_updated": null, "notes": "Owns canonical generation architecture and pitfalls.", "pr": null
  }
]
[
  {
    "id": "3F.5", "title": "Production ingestion",
    "story": ["US-ING-001", "US-ING-002", "US-ING-003", "US-ING-004", "US-ING-005", "US-ING-006", "US-SRC-012", "US-SRC-013", "US-SYS-001", "US-RES-001", "US-RES-002", "US-RES-003", "US-RES-004"],
    "status": "backlog", "owner": {"implementation": "Ingestion Lead", "approver": "Architecture Lead"},
    "documents_required": ["README.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/03-implementation/开发避坑与关键注意点手册.md", "docs/decisions/ADR-011-task-progress-boundary.md", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json"],
"dependencies": ["3F.2", "3F.3", "3F.3a", "3F.3b", "3F.4"], "test_file": "EchoTests/Phase3F/3F.5_ProductionIngestionTests.swift",
    "acceptance_evidence": ["四类真实来源 trace、canonical/vector/FTS 计数、取消重启恢复与 rollback 证据"],
"last_updated": null, "notes": "ADR-011 governs task progress.", "pr": null
  },
  {
    "id": "3F.6", "title": "Production search 与 feedback",
    "story": ["US-RET-001", "US-RET-002", "US-RET-003", "US-RET-004", "US-RET-005", "US-RET-006", "US-RET-007", "US-RET-008", "US-FBK-001", "US-FBK-002", "US-FBK-003", "US-PRV-001", "US-SRC-010", "US-SRC-011"],
    "status": "backlog", "owner": {"implementation": "Search and Ranking Lead", "approver": "Privacy Engineering Lead"},
    "documents_required": ["README.md", "docs/ui/echo-memory-canvas-style.md", "docs/01-spec/用户故事与验收标准规格书.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/03-implementation/双语言实现说明文档.md", "docs/03-implementation/开发避坑与关键注意点手册.md", "docs/decisions/ADR-010-canonical-generation-lifecycle.md", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json", "UIAutomation/Contracts/instances/search-surface.json", "UIAutomation/Contracts/instances/search-journey-basic.json", "UIAutomation/Contracts/instances/search-state-idle.json", "UIAutomation/Contracts/instances/search-state-loading.json", "UIAutomation/Contracts/instances/search-state-loaded.json", "UIAutomation/Contracts/instances/search-state-empty.json", "UIAutomation/Contracts/instances/search-state-error.json", "UIAutomation/Contracts/instances/search-state-lowconfidence.json", "UIAutomation/Contracts/instances/search-action-submit.json", "UIAutomation/Contracts/instances/search-action-retry.json", "UIAutomation/Contracts/instances/search-action-like.json", "UIAutomation/Contracts/instances/search-action-dislike.json", "UIAutomation/Contracts/instances/search-action-badcase.json", "UIAutomation/Fixtures/search/search-loaded.json", "UIAutomation/Fixtures/search/search-empty.json", "UIAutomation/Fixtures/search/search-lowconfidence.json", "UIAutomation/Fixtures/search/search-multitype.json", "UIAutomation/Contracts/instances/search-state-partial-results.json", "UIAutomation/Contracts/instances/search-journey-partial-results.json", "UIAutomation/Fixtures/search/search-partial-results.json"],
"dependencies": ["3F.3", "3F.4", "3F.5"], "test_file": "EchoTests/Phase3F/3F.6_ProductionSearchFeedbackTests.swift",
    "acceptance_evidence": ["各 channel、timeout、partial、RRF、filter、rerank、低置信度与同查询 feedback 证据", "US-SRC-010 health+memory/location+photo parser, per-source authorization, temporal alignment, source labels and crossAppSearch source-list audit", "US-SRC-011 subjective-ranking/feedback traces", "PendingOperations 手工重试与授权证据"],
"last_updated": null, "notes": "ADR-010 governs generation routing and feedback identity.", "pr": null
  }
]
[
  {
    "id": "3F.7", "title": "UI 到 Core 全域接线",
    "story": ["US-AWK-005", "US-AWK-007", "US-PRV-002", "US-PRV-003", "US-PRV-004", "US-SYS-001", "US-SET-001", "US-SET-002", "US-SET-003", "US-SET-004", "US-RES-001", "US-RES-002", "US-RES-003", "US-RES-004", "US-SRC-007", "US-SRC-009"],
    "status": "backlog", "owner": {"implementation": "iOS UI Integration Lead and iOS Platform Security Lead", "approver": "Security Engineering Lead, Privacy Engineering Lead and Architecture Lead"},
    "documents_required": ["AGENTS.md", "README.md", "docs/ui/echo-memory-canvas-style.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/decisions/ADR-008-source-import-boundaries.md", "docs/decisions/ADR-010-canonical-generation-lifecycle.md", "docs/ui/architecture.md", "docs/ui/automation-workflow.md", "docs/ui/testing-and-artifacts.md", "docs/ui/echo-readiness.md", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json", "UIAutomation/Contracts/instances/search-to-detail-journey.json", "UIAutomation/Contracts/instances/memory-detail-surface.json", "UIAutomation/Contracts/instances/memory-detail-journey-basic.json", "UIAutomation/Contracts/instances/memory-detail-state-loading.json", "UIAutomation/Contracts/instances/memory-detail-state-loaded.json", "UIAutomation/Contracts/instances/memory-detail-state-editing.json", "UIAutomation/Contracts/instances/memory-detail-state-translated.json", "UIAutomation/Contracts/instances/memory-detail-state-conflict.json", "UIAutomation/Contracts/instances/memory-detail-state-error.json", "UIAutomation/Contracts/instances/memory-detail-action-edit.json", "UIAutomation/Contracts/instances/memory-detail-action-save.json", "UIAutomation/Contracts/instances/memory-detail-action-translate.json", "UIAutomation/Contracts/instances/memory-detail-action-delete.json", "UIAutomation/Contracts/instances/memory-detail-action-delete-original.json", "UIAutomation/Contracts/instances/memory-detail-action-remove-from-echo.json", "UIAutomation/Contracts/instances/memory-detail-action-keep-local.json", "UIAutomation/Contracts/instances/memory-detail-action-keep-external.json", "UIAutomation/Contracts/instances/memory-detail-action-retry.json", "UIAutomation/Contracts/instances/background-tasks-surface.json", "UIAutomation/Contracts/instances/background-tasks-journey-basic.json", "UIAutomation/Contracts/instances/background-tasks-state-loading.json", "UIAutomation/Contracts/instances/background-tasks-state-loaded.json", "UIAutomation/Contracts/instances/background-tasks-state-empty.json", "UIAutomation/Contracts/instances/background-tasks-state-error.json", "UIAutomation/Contracts/instances/background-tasks-action-open.json", "UIAutomation/Contracts/instances/background-tasks-action-pause.json", "UIAutomation/Contracts/instances/background-tasks-action-cancel.json", "UIAutomation/Contracts/instances/background-tasks-action-retry.json", "UIAutomation/Contracts/instances/resume-progress-surface.json", "UIAutomation/Contracts/instances/resume-progress-journey-basic.json", "UIAutomation/Contracts/instances/resume-progress-state-none.json", "UIAutomation/Contracts/instances/resume-progress-state-checking.json", "UIAutomation/Contracts/instances/resume-progress-state-prompt.json", "UIAutomation/Contracts/instances/resume-progress-state-resumed.json", "UIAutomation/Contracts/instances/resume-progress-state-restarted.json", "UIAutomation/Contracts/instances/resume-progress-state-error.json", "UIAutomation/Contracts/instances/resume-progress-action-start.json", "UIAutomation/Contracts/instances/resume-progress-action-continue.json", "UIAutomation/Contracts/instances/resume-progress-action-restart.json", "UIAutomation/Contracts/instances/resume-progress-action-retry.json", "UIAutomation/Fixtures/memory-detail/memory-detail-loaded.json", "UIAutomation/Fixtures/memory-detail/memory-detail-photo-loaded.json", "UIAutomation/Fixtures/memory-detail/memory-detail-video-loaded.json", "UIAutomation/Fixtures/memory-detail/memory-detail-voice-loaded.json", "UIAutomation/Fixtures/memory-detail/memory-detail-translated.json", "UIAutomation/Fixtures/memory-detail/memory-detail-conflict.json", "UIAutomation/Fixtures/memory-detail/memory-detail-error.json", "UIAutomation/Fixtures/background-tasks/background-tasks-loaded.json", "UIAutomation/Fixtures/background-tasks/background-tasks-empty.json", "UIAutomation/Fixtures/background-tasks/background-tasks-error.json", "UIAutomation/Fixtures/resume-progress/resume-progress-none.json", "UIAutomation/Fixtures/resume-progress/resume-progress-pending.json", "UIAutomation/Fixtures/resume-progress/resume-progress-error.json", "UIAutomation/Contracts/instances/degradation-banner-surface.json", "UIAutomation/Contracts/instances/degradation-banner-state-normal.json", "UIAutomation/Contracts/instances/degradation-banner-state-lowPower.json", "UIAutomation/Contracts/instances/degradation-banner-state-thermal.json", "UIAutomation/Contracts/instances/degradation-banner-state-modelDegraded.json", "UIAutomation/Fixtures/degradation-banner/degradation-normal.json", "UIAutomation/Fixtures/degradation-banner/degradation-low-power.json", "UIAutomation/Fixtures/degradation-banner/degradation-thermal.json", "UIAutomation/Fixtures/degradation-banner/degradation-model-degraded.json", "UIAutomation/Contracts/instances/settings-surface.json", "UIAutomation/Contracts/instances/settings-state-loaded.json", "UIAutomation/Contracts/instances/settings-action-startDeviceMigration.json", "UIAutomation/Contracts/instances/settings-action-selectMigrationStrategy.json", "UIAutomation/Contracts/instances/settings-action-applyBatchConflictResolution.json", "UIAutomation/Contracts/instances/settings-action-exportDataOverview.json", "UIAutomation/Contracts/instances/settings-journey-device-migration.json", "UIAutomation/Contracts/instances/settings-journey-data-overview.json", "UIAutomation/Fixtures/settings/settings-loaded.json", "UIAutomation/Fixtures/settings/settings-migration-conflicts.json", "UIAutomation/Fixtures/settings/settings-data-overview.json"],
"dependencies": ["3F.1", "3F.4", "3F.6"], "test_file": "EchoTests/Phase3F/3F.7_UIToCoreIntegrationTests.swift",
    "acceptance_evidence": ["默认 live adapter、跨 surface journey、编辑删除重启、真实设置与进度证据", "US-SRC-007 mandatory recordCount>=1/chunkCount>=2, manifest-plus-data shape, unconditional manifest-only rejection and smallest-valid package evidence", "US-SRC-007 RFC 8785 manifest, unsigned UTF-8 record ordering/duplicate rejection, exact cross-chunk payload stream, overflow-safe length equality and per-record hash evidence", "US-SRC-007 canonical LF header, complete chunk-0 plaintext hash, no manifest self-digest, independent manifest/data chunk sizing, big-endian no-padding framing, AAD and manifest-first vectors", "US-SRC-007 fixed-format AES-GCM-256+HKDF-SHA256 package, K_transfer lifecycle, deterministic K_i vectors, 96-bit nonce authentication, rejection matrix, resource bounds, filesystem cleanup, staging publication/rollback and OS-backup boundary evidence", "US-SRC-007 encrypted package/local-backup restore, strategy/conflict/integrity/reingest/ExcludedAssets/original-file prohibition and deviceMigrationCompleted evidence", "US-SRC-009 live counts/storage/vector/model-state, <=5-second refresh, JSON export and dataOverviewAccessed evidence", "Security, Privacy and Architecture approval records", "双设备 Live Simulator Review、AX tree、日志和无媒体 manifest"],
"last_updated": null, "notes": "Owns search, detail, background-task, resume and degradation UIAutomation assets declared in the 3F.7 record and contract.", "pr": null
  }
]
[
  {
    "id": "3F.8", "title": "Awakening 与 system adapters",
    "story": ["US-AWK-001", "US-AWK-002", "US-AWK-003", "US-AWK-005", "US-SRC-010"],
    "status": "backlog", "owner": {"implementation": "iOS System Integration Lead", "approver": "Privacy Engineering Lead"},
    "documents_required": ["README.md", "docs/ui/echo-memory-canvas-style.md", "docs/01-spec/用户故事与验收标准规格书.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/ui/testing-and-artifacts.md", "docs/ui/echo-readiness.md", "docs/decisions/ADR-012-awakening-system-boundary.md", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json", "UIAutomation/Contracts/instances/awakening-settings-surface.json", "UIAutomation/Contracts/instances/awakening-settings-state-loading.json", "UIAutomation/Contracts/instances/awakening-settings-state-loaded.json", "UIAutomation/Contracts/instances/awakening-settings-state-empty-permissions.json", "UIAutomation/Contracts/instances/awakening-settings-state-unavailable.json", "UIAutomation/Contracts/instances/awakening-settings-state-error.json", "UIAutomation/Contracts/instances/awakening-settings-state-all-disabled.json", "UIAutomation/Contracts/instances/awakening-settings-action-toggleGeofence.json", "UIAutomation/Contracts/instances/awakening-settings-action-toggleEmotion.json", "UIAutomation/Contracts/instances/awakening-settings-action-toggleAnniversary.json", "UIAutomation/Contracts/instances/awakening-settings-action-requestNotification.json", "UIAutomation/Contracts/instances/awakening-settings-action-openSystemSettings.json", "UIAutomation/Contracts/instances/awakening-settings-action-showGeofenceDetail.json", "UIAutomation/Contracts/instances/awakening-settings-action-dismissGeofenceDetail.json", "UIAutomation/Contracts/instances/awakening-settings-journey-basic.json", "UIAutomation/Contracts/instances/awakening-settings-journey-no-permissions.json", "UIAutomation/Contracts/instances/awakening-settings-journey-unavailable.json", "UIAutomation/Fixtures/awakening-settings/awakening-settings-loading.json", "UIAutomation/Fixtures/awakening-settings/awakening-settings-loaded.json", "UIAutomation/Fixtures/awakening-settings/awakening-settings-no-permissions.json", "UIAutomation/Fixtures/awakening-settings/awakening-settings-unavailable.json", "UIAutomation/Fixtures/awakening-settings/awakening-settings-error.json", "UIAutomation/Fixtures/awakening-settings/awakening-settings-all-disabled.json"],
"dependencies": ["3F.1", "3F.4", "3F.6", "3F.7"], "test_file": "EchoTests/Phase3F/3F.8_AwakeningSystemAdaptersTests.swift",
    "acceptance_evidence": ["权限、系统信号、持久卡片、通知请求与响应路由证据", "US-SRC-010 live HealthKit provider protocol conformance, denial, minimized temporal mapping and 3F.6 fusion integration", "Privacy approver 对 HealthKit 最小化与通知边界签字"],
"last_updated": null, "notes": "Creates the missing awakening states, actions, journeys and six deterministic fixtures declared by the surface contract.", "pr": null
  },
  {
    "id": "3F.9", "title": "Apple Translation 与 grounded creation",
    "story": ["US-DIS-002", "US-SYN-001", "US-SYN-002", "US-SYN-003", "US-SYN-004", "US-SYN-005", "US-SYN-006", "US-SYN-007", "US-SYN-008"],
    "status": "backlog", "owner": {"implementation": "Language and Creation Lead", "approver": "Model Legal and Privacy Approver"},
    "documents_required": ["README.md", "docs/ui/echo-memory-canvas-style.md", "docs/01-spec/用户故事与验收标准规格书.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/03-implementation/双语言实现说明文档.md", "docs/decisions/ADR-009-offline-model-runtime.md", "docs/decisions/ADR-013-creation-export-boundary.md", "docs/ui/testing-and-artifacts.md", "docs/ui/echo-readiness.md", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json", "UIAutomation/Contracts/instances/translation-surface.json", "UIAutomation/Contracts/instances/translation-journey-basic.json", "UIAutomation/Contracts/instances/translation-state-original.json", "UIAutomation/Contracts/instances/translation-state-translating.json", "UIAutomation/Contracts/instances/translation-state-translated.json", "UIAutomation/Contracts/instances/translation-state-cached.json", "UIAutomation/Contracts/instances/translation-state-low-confidence.json", "UIAutomation/Contracts/instances/translation-state-error.json", "UIAutomation/Contracts/instances/translation-action-toggle.json", "UIAutomation/Contracts/instances/translation-action-retry.json", "UIAutomation/Contracts/instances/creation-surface.json", "UIAutomation/Contracts/instances/creation-journey-generate-save-basic.json", "UIAutomation/Contracts/instances/creation-journey-prompt-edit-confirm.json", "UIAutomation/Contracts/instances/creation-state-idle.json", "UIAutomation/Contracts/instances/creation-state-empty.json", "UIAutomation/Contracts/instances/creation-state-generating.json", "UIAutomation/Contracts/instances/creation-state-generated.json", "UIAutomation/Contracts/instances/creation-state-share-handoff.json", "UIAutomation/Contracts/instances/creation-state-error.json", "UIAutomation/Contracts/instances/creation-action-select-template.json", "UIAutomation/Contracts/instances/creation-action-edit-prompt.json", "UIAutomation/Contracts/instances/creation-action-confirm-prompt.json", "UIAutomation/Contracts/instances/creation-action-reset-prompt.json", "UIAutomation/Contracts/instances/creation-action-generate.json", "UIAutomation/Contracts/instances/creation-action-retry.json", "UIAutomation/Contracts/instances/creation-action-copy.json", "UIAutomation/Contracts/instances/creation-action-export.json", "UIAutomation/Contracts/instances/creation-action-share.json", "UIAutomation/Contracts/instances/creation-action-save-to-notes.json", "UIAutomation/Fixtures/translation/translation-zh-en-high.json", "UIAutomation/Fixtures/translation/translation-zh-en-low.json", "UIAutomation/Fixtures/translation/translation-zh-en-cached.json", "UIAutomation/Fixtures/translation/translation-error.json", "UIAutomation/Fixtures/creation/creation-idle.json", "UIAutomation/Fixtures/creation/creation-empty.json", "UIAutomation/Fixtures/creation/creation-prompt-draft.json", "UIAutomation/Fixtures/creation/creation-generated-report.json", "UIAutomation/Fixtures/creation/creation-generated-letter.json", "UIAutomation/Fixtures/creation/creation-share-handoff.json", "UIAutomation/Fixtures/creation/creation-error.json", "UIAutomation/Contracts/instances/translation-state-availability-checking.json", "UIAutomation/Contracts/instances/translation-state-unavailable.json", "UIAutomation/Contracts/instances/translation-journey-availability-fallback.json", "UIAutomation/Fixtures/translation/translation-availability-checking.json", "UIAutomation/Fixtures/translation/translation-unavailable.json"],
"dependencies": ["3F.0", "3F.3", "3F.3a", "3F.3b", "3F.4", "3F.6", "3F.7"], "test_file": "EchoTests/Phase3F/3F.9_TranslationCreationTests.swift",
    "acceptance_evidence": ["Apple Translation availability、uncertain fallback、七天 cache 与重启证据", "grounded anchors、Markdown/PDF/share 与模型分发批准"],
"last_updated": null, "notes": "Scope follows the human-approved 3F.0 LLM decision.", "pr": null
  }
]
[
  {
    "id": "3F.10", "title": "i18n、accessibility 与 production errors",
    "story": ["US-DIS-001", "US-DIS-003", "US-DIS-004", "US-SET-001", "US-RES-001", "US-RES-002", "US-RES-003", "US-RES-004", "US-SYS-001", "US-SRC-009"],
    "status": "backlog", "owner": {"implementation": "Localization and Accessibility Lead", "approver": "Release Quality Lead"},
    "documents_required": ["AGENTS.md", "README.md", "docs/ui/echo-memory-canvas-style.md", "docs/01-spec/用户故事与验收标准规格书.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/03-implementation/双语言实现说明文档.md", "docs/03-implementation/开发避坑与关键注意点手册.md", "docs/decisions/ADR-011-task-progress-boundary.md", "docs/ui/README.md", "docs/ui/automation-workflow.md", "docs/ui/testing-and-artifacts.md", "docs/ui/echo-readiness.md", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json", "UIAutomation/Contracts/instances/degradation-banner-surface.json", "UIAutomation/Contracts/instances/degradation-banner-state-normal.json", "UIAutomation/Contracts/instances/degradation-banner-state-lowPower.json", "UIAutomation/Contracts/instances/degradation-banner-state-thermal.json", "UIAutomation/Contracts/instances/degradation-banner-state-modelDegraded.json", "UIAutomation/Fixtures/degradation-banner/degradation-normal.json", "UIAutomation/Fixtures/degradation-banner/degradation-low-power.json", "UIAutomation/Fixtures/degradation-banner/degradation-thermal.json", "UIAutomation/Fixtures/degradation-banner/degradation-model-degraded.json", "UIAutomation/Contracts/instances/degradation-banner-action-dismiss.json", "UIAutomation/Contracts/instances/degradation-banner-action-retryModelLoad.json", "UIAutomation/Contracts/instances/degradation-banner-action-toggleBackgroundTasks.json", "UIAutomation/Contracts/instances/degradation-banner-action-openSettings.json", "UIAutomation/Contracts/instances/degradation-banner-journey-lifecycle.json", "UIAutomation/Contracts/instances/degradation-banner-state-l1Transient.json", "UIAutomation/Contracts/instances/degradation-banner-state-l2Recoverable.json", "UIAutomation/Contracts/instances/degradation-banner-state-l3Blocking.json", "UIAutomation/Contracts/instances/degradation-banner-state-l4Conflict.json", "UIAutomation/Contracts/instances/degradation-banner-action-retryL1.json", "UIAutomation/Contracts/instances/degradation-banner-action-retryPendingOperation.json", "UIAutomation/Contracts/instances/degradation-banner-action-openBlockingRecovery.json", "UIAutomation/Contracts/instances/degradation-banner-action-resolveConflict.json", "UIAutomation/Contracts/instances/degradation-banner-journey-l1-l4.json", "UIAutomation/Fixtures/degradation-banner/degradation-l1-transient.json", "UIAutomation/Fixtures/degradation-banner/degradation-l2-recoverable.json", "UIAutomation/Fixtures/degradation-banner/degradation-l3-blocking.json", "UIAutomation/Fixtures/degradation-banner/degradation-l4-conflict.json"],
"dependencies": ["3F.7", "3F.8", "3F.9"], "test_file": "EchoTests/Phase3F/3F.10_LocalizationAccessibilityErrorTests.swift",
    "acceptance_evidence": ["双语 catalog 100%、硬编码 0、AX5、contrast、reduced motion 与 L1-L4 证据", "US-SRC-009 merged-into-US-SYS-001 localized and accessible task/resume/error trace", "ADR-011 与架构、数据流、避坑的 degradation 合同一致性"],
"last_updated": null, "notes": "Owns complete declared degradation and L1-L4 UIAutomation coverage.", "pr": null
  },
  {
    "id": "3F.11", "title": "Production E2E 与 Phase 4 准入门禁", "story": ["3F.11", "US-SRC-010"],
    "status": "backlog", "owner": {"implementation": "Release Quality Lead", "approver": "Release Manager and Privacy Engineering Lead"},
    "documents_required": ["AGENTS.md", "README.md", "CHANGELOG.md", "docs/INDEX.md", "docs/01-spec/用户故事与验收标准规格书.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/技术选型文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/03-implementation/双语言实现说明文档.md", "docs/03-implementation/开发避坑与关键注意点手册.md", "docs/05-planning/开发计划安排文档.md", "docs/05-planning/app-store-privacy-disclosure.md", "docs/05-planning/model-provenance-register.md", "docs/05-planning/phase3f-execution-plan.md", "docs/05-planning/phase3f-story-matrix.md", "docs/05-planning/phase3f-release-checklist.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json", "docs/05-planning/deferred-items.json", "docs/ui/testing-and-artifacts.md", "docs/decisions/ADR-014-release-compliance-boundary.md"],
    "dependencies": ["3F.1", "3F.2", "3F.3", "3F.3a", "3F.3b", "3F.4", "3F.5", "3F.6", "3F.7", "3F.8", "3F.9", "3F.10"],
    "test_file": "EchoTests/Phase3F/Phase3FIntegrationTests.swift",
"acceptance_evidence": ["全部 Release、测试、coverage、模型、隐私、合规、签名与 no-fixture E2E 预合并证据", "US-SRC-010 no-fixture search-to-HealthKit E2E", "Echo and EchoShareExtension per-target security/compliance reports", "3F.7 migration-security per-test revalidation and Security/Privacy/Architecture approver record", "P0=0、P1=0 与 Release Manager/Privacy gate approver 签字", "不包含 merge SHA 或 Phase 4 已解锁声明的 pre-merge evidence index"],
"last_updated": null, "notes": "Finalizes pre-merge evidence only; a human-triggered finalizer records merge SHA and unlocks Phase 4.", "pr": null
  }
]
```

#### 4.2.1 Previously unmapped source-story ownership

- `US-SRC-007`: owned by `3F.7` for encrypted user-mediated migration package export/import, Finder/iTunes encrypted local-backup restore, merge/conflict/integrity/reingest/ExcludedAssets behavior and live Settings integration.
- `US-SRC-009`: specification is merged into `US-SYS-001` with every original AC retained; owned jointly by `3F.7` for the live data-overview service, JSON export and Settings integration and `3F.10` for production error, localization and accessibility behavior. It is not deferred.
- `US-SRC-010`: owned by `3F.6` for the search contract, `3F.8` for HealthKit-backed system adaptation, and `3F.11` for no-fixture production E2E. It is not deferred.
- `US-SRC-011`: owned by `3F.3` for model semantics (E5 reference outputs), `3F.3a` for SigLIP2 reference-vector verification, `3F.3b` for Whisper reference-transcript verification, `3F.6` for subjective ranking and feedback behavior, and Phase 4 `4.1` for Golden validation. It is not deferred.
- `US-AWK-004` and `US-AWK-006`: remain the two explicit approved product deferrals represented by `DEF-001` and `DEF-002`; they count toward the 66-story matrix only through those approved records and are not silently absorbed into another task.
- `3F.0` must materialize these ownership rows in `docs/05-planning/phase3f-story-matrix.md`; the matrix gate passes only when all 66 unique story IDs have at least one explicit owner or an approved non-v1 removal record. These four stories may not use the deferral path.

状态生命周期固定为：`backlog → ready → in_progress → blocked|review → approved → merged → done`。Agent 只能写到 `review`/`approved`；`merged`/`done` 由人类合并或人类触发的自动化写入。

### 4.3 Phase 4 冻结与重排

`3F.0` 必须删除旧 Phase 4 记录并原子写入以下 14 个完整记录。字段和值是完整合同，不得省略、改名或另设默认值。以下 fenced blocks 各自是合法 JSON 数组；按出现顺序连接其数组元素，得到唯一的 14-record Phase 4 record set：

```
[
  {
    "id": "4.1",
    "title": "Golden Dataset 与反馈排序质量验收",
    "story": ["US-RET-001", "US-RET-002", "US-RET-003", "US-RET-004", "US-RET-005", "US-RET-006", "US-RET-007", "US-RET-008", "US-FBK-001", "US-FBK-002", "US-FBK-003", "US-SRC-011"],
    "owner": "QA Lead",
    "documents_required": ["docs/01-spec/用户故事与验收标准规格书.md", "docs/03-implementation/双语言实现说明文档.md", "docs/05-planning/开发计划安排文档.md", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["3F.11"],
    "test_file": "EchoTests/Phase4/CrossLingualTests.swift",
    "acceptance_evidence": ["不少于 800 条 zh-Hans/en-US 跨语言 Golden 用例且 Recall@10 >= 85% 的报告", "US-SRC-011 model semantics 与 subjective ranking 的 Golden 子集及逐项期望/实际排名", "不少于 200 条点赞、点踩、时间衰减和权重截断反馈用例的逐项结果", "不少于 100 条术语用例且术语表命中率 >= 90% 的报告", "失败样本 ID、期望排名、实际排名和修复提交的可定位索引"],
    "migrated_from": ["4.1", "4.7"]
  },
  {
    "id": "4.2",
    "title": "全 Pipeline 生产端到端集成测试",
    "story": ["US-SRC-001", "US-SRC-003", "US-SRC-004", "US-SRC-005", "US-SRC-008", "US-SRC-012", "US-SRC-013", "US-ING-001", "US-ING-002", "US-ING-003", "US-ING-004", "US-ING-005", "US-ING-006", "US-RET-001", "US-RET-002", "US-RET-003", "US-RET-004", "US-RET-005", "US-RET-006", "US-RET-007", "US-RET-008", "US-FBK-001", "US-FBK-002", "US-FBK-003", "US-AWK-001", "US-AWK-002", "US-AWK-003", "US-AWK-005", "US-AWK-007", "US-SYN-001", "US-SYN-002", "US-SYN-003", "US-SYN-004", "US-SYN-005", "US-SYN-006", "US-SYN-007", "US-SYN-008", "US-PRV-001", "US-PRV-004", "US-PRV-005", "US-PRV-006", "US-PRV-007", "US-PRV-008", "US-SYS-001"],
    "owner": "iOS Integration Lead",
    "documents_required": ["docs/01-spec/用户故事与验收标准规格书.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["3F.11"],
    "test_file": "EchoTests/Phase4/AllPipelinesTests.swift",
    "acceptance_evidence": ["默认 App 无 -ui-fixture 参数的来源、摄入、检索、反馈、编辑、删除、唤醒、翻译和创作全链路通过记录", "真实 PhotoKit 与 Share Extension 输入的 traceID 贯穿 PrivacyCheckpoint、SQLite、generation route 和审计日志", "进程终止后重启恢复 active route、任务进度、翻译缓存和用户策略的日志", "Release simulator 与 CODE_SIGNING_ALLOWED=NO device build 均为 exit code 0"],
    "migrated_from": ["4.2"]
  },
  {
    "id": "4.3",
    "title": "性能基准与资源门禁验证",
    "story": ["US-RET-001", "US-RES-001", "US-RES-004"],
    "owner": "Performance Engineering Lead",
    "documents_required": ["docs/02-architecture/技术选型文档.md", "docs/03-implementation/开发避坑与关键注意点手册.md", "docs/05-planning/开发计划安排文档.md", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["3F.11"],
    "test_file": "EchoTests/Phase4/BenchmarkTests.swift",
    "acceptance_evidence": ["检索 P95 < 200ms 的原始样本与汇总报告", "峰值内存 < 1.5GB 的 Instruments allocation 记录", "摄入、索引构建、检索和唤醒的 CPU、energy、thermal 指标记录", "基准设备、系统版本、数据规模、模型 revision 和重复次数清单"],
    "migrated_from": ["4.3"]
  },
  {
    "id": "4.4",
    "title": "低电量、过热与模型加载恢复验证",
    "story": ["US-RES-001", "US-RES-002", "US-RES-003", "US-RES-004", "US-SYS-001"],
    "owner": "iOS Reliability Lead",
    "documents_required": ["docs/01-spec/用户故事与验收标准规格书.md", "docs/02-architecture/架构设计文档.md", "docs/03-implementation/开发避坑与关键注意点手册.md", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["3F.11"],
    "test_file": "EchoTests/Phase4/DegradationRecoveryTests.swift",
    "acceptance_evidence": ["低电量与 serious/critical thermal state 下任务暂停、降级提示和恢复的状态转移记录", "模型缺失、校验和错误、加载失败和手动重试成功的故障注入矩阵", "L1 重试、L2 PendingOperations 手动重试、L3 阻断和 L4 冲突的逐级证据", "任务取消后 TaskProgress 保留且重启选择继续或重来的测试结果"],
    "migrated_from": ["4.4", "4.5"]
  }
]
[
  {
    "id": "4.5",
    "title": "ExcludedAssets 边界场景测试",
    "story": ["US-PRV-001", "US-PRV-004", "US-PRV-007", "US-SRC-008", "US-SRC-012"],
    "owner": "Privacy Engineering Lead",
    "documents_required": ["AGENTS.md", "docs/01-spec/用户故事与验收标准规格书.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["3F.11"],
    "test_file": "EchoTests/Phase4/ExcludedAssetsBoundaryTests.swift",
    "acceptance_evidence": ["仅用户主动选择仅从 Echo 移除时写入 ExcludedAssets 的全写路径测试", "系统自动删除和原始文件级联删除不写入 ExcludedAssets 的负向测试", "级联删除同步清理无效排除记录的事务故障注入结果", "重新授权一键恢复和手动恢复前原始文件存在性检查的 UI 与审计证据"],
    "migrated_from": ["4.6"]
  },
  {
    "id": "4.6",
    "title": "覆盖率、静态分析与隐私门禁复核",
    "story": ["3F.11"],
    "owner": "Release Quality Lead",
    "documents_required": ["AGENTS.md", "docs/03-implementation/开发避坑与关键注意点手册.md", "docs/05-planning/phase3f-release-checklist.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["3F.11"],
    "test_file": "EchoTests/Phase4/QualityGateTests.swift",
    "acceptance_evidence": ["全局 line coverage >= 95% 的 xcresult 与解析报告", "PrivacyCheckpoint 覆盖率 100% 的静态扫描报告", "SwiftLint 0 violations 且 strict concurrency 0 warnings 的命令输出", "Combine、Task.detached、@unchecked Sendable、nonisolated(unsafe)、网络下载和明文审计内容扫描均为 0 命中"],

    "migrated_from": [ ]

  },
  {
    "id": "4.7",
    "title": "双语、本地化与无障碍验收",
    "story": ["US-DIS-001", "US-DIS-002", "US-DIS-003", "US-DIS-004", "US-SET-001", "US-RES-001", "US-RES-002", "US-RES-003", "US-RES-004"],
    "owner": "Localization and Accessibility Lead",
    "documents_required": ["docs/01-spec/用户故事与验收标准规格书.md", "docs/03-implementation/双语言实现说明文档.md", "docs/ui/testing-and-artifacts.md", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["3F.11"],
    "test_file": "EchoTests/Phase4/LocalizationAccessibilityTests.swift",
    "acceptance_evidence": ["String Catalog 的 zh-Hans 与 en-US 可见文案覆盖率均为 100%", "源语言不确定、译文缓存七天、跨重启和 preferredLanguage 对齐的测试结果", "iPhone 17 Pro iOS 26.5 与 iPhone 16 Pro iOS 18.x 的 AX tree 和 Live Simulator Review manifest", "Dynamic Type、VoiceOver announcement 和颜色对比度 >= 4.5:1 的验收记录"],

    "migrated_from": [ ]

  },
  {
    "id": "4.8",
    "title": "完成项目与发布文档更新",
    "story": ["3F.11"],
    "owner": "Technical Documentation Lead",
    "documents_required": ["README.md", "docs/INDEX.md", "docs/01-spec/用户故事与验收标准规格书.md", "docs/02-architecture/架构设计文档.md", "docs/02-architecture/技术选型文档.md", "docs/02-architecture/数据流全链路技术说明文档.md", "docs/03-implementation/双语言实现说明文档.md", "docs/03-implementation/开发避坑与关键注意点手册.md", "docs/05-planning/开发计划安排文档.md", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["3F.11"],
    "test_file": null,
    "acceptance_evidence": ["README、INDEX、规格、架构、技术选型、数据流、双语言、避坑和开发计划互链检查清单", "文档中的版本、平台、模型 revision、门禁阈值和任务 ID 与已发布配置一致的审计结果", "所有已解决 deferred 条目的 resolution_evidence 索引", "所有外部可见发布文案为英文且项目文档允许中文或双语的检查结果"],
    "migrated_from": ["4.8"]
  }
]
[
  {
    "id": "4.9",
    "title": "发布合规、归档与签名验证",
    "story": ["US-PRV-001", "US-PRV-004", "US-PRV-005", "US-PRV-006", "US-PRV-007", "US-PRV-008"],
    "owner": "Release Engineering Lead",
    "documents_required": ["AGENTS.md", "README.md", "docs/decisions/ADR-014-release-compliance-boundary.md", "docs/05-planning/phase3f-release-checklist.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["3F.11"],
    "test_file": "EchoTests/Phase4/ReleaseComplianceTests.swift",
    "acceptance_evidence": ["受控 release 环境中的 signed archive、ExportOptions、签名身份、provisioning profile 和 entitlements 校验结果", "PrivacyInfo.xcprivacy、权限用途文案、PIPL 同意与撤回流程的合规检查", "模型 artifact revision、SHA-256、license 和 SBOM 的一一对应清单", "Release 包零运行时下载、零分析 SDK、零用户数据外传的网络与依赖扫描报告"],

    "migrated_from": [ ]

  },
  {
    "id": "4.10",
    "title": "生成并批准 Release Candidate",
    "story": ["4.10"],
    "owner": "Release Manager",
    "documents_required": ["docs/05-planning/phase3f-release-checklist.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/开发计划安排文档.md", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["4.1", "4.2", "4.3", "4.4", "4.5", "4.6", "4.7", "4.8", "4.9"],
    "test_file": null,
    "acceptance_evidence": ["唯一 RC build number、marketing version、Git commit 和 archive SHA-256 的不可变记录", "4.1 至 4.9 均为 done 且证据链接可访问的 gate checklist", "P0=0、P1=0 和所有 v1 范围变更均有批准记录的缺陷清单", "Release Manager 对指定 RC 可进入 TestFlight 的签字记录"],

    "migrated_from": [ ]

  },
  {
    "id": "4.11",
    "title": "TestFlight 内测（内部 50 人）",
    "story": ["4.11"],
    "owner": "TestFlight Program Manager",
    "documents_required": ["docs/05-planning/phase3f-release-checklist.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/开发计划安排文档.md", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["4.10"],
    "test_file": null,
    "acceptance_evidence": ["与 4.10 完全相同 build number 和 archive identity 的 TestFlight processing 记录", "50 名内部测试者的邀请、安装资格和测试窗口记录，不包含个人敏感信息", "按设备、系统版本、场景、严重度和复现步骤整理的反馈清单", "TestFlight 合规问卷和出口合规状态完成记录"],
    "migrated_from": ["4.9"]
  }
]
[
  {
    "id": "4.12",
    "title": "修复 TestFlight 新发现 P0/P1 缺陷",
    "story": ["4.12"],
    "owner": "Defect Triage Lead",
    "documents_required": ["docs/05-planning/deferred-items.json", "docs/05-planning/phase3f-release-checklist.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["4.11"],
    "test_file": null,
    "acceptance_evidence": ["每个 TestFlight P0/P1 缺陷的复现测试、根因、修复提交和回归结果", "修复后未关闭 P0=0 且未关闭 P1=0 的缺陷查询结果", "每个决定移出 v1 的非 P0/P1 项均有 owner、目标任务或版本和批准记录", "修复构建的 commit、build number 与替代 RC 候选关系记录"],
    "migrated_from": ["4.10"]
  },
  {
    "id": "4.13",
    "title": "Release Candidate 全量回归",
    "story": ["4.13"],
    "owner": "QA Regression Lead",
    "documents_required": ["docs/05-planning/phase3f-release-checklist.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/deferred-items.json", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["4.12"],
    "test_file": "EchoTests/Phase4/ReleaseCandidateRegressionTests.swift",
    "acceptance_evidence": ["最新 RC 上 EchoTests 与 EchoUITests 全量串行执行均为 0 failure", "4.1 至 4.9 的质量、性能、隐私、合规和签名门禁在最新 RC 上重新通过", "无 fixture 默认 App 的双设备生产 E2E 与重启恢复记录", "TestFlight 修复缺陷逐项回归且未关闭 P0=0、P1=0 的报告"],

    "migrated_from": [ ]

  },
  {
    "id": "4.14",
    "title": "Phase 4 集成测试：质量保障与最终发布验证",
    "story": ["4.14"],
    "owner": "Release Manager",
    "documents_required": ["README.md", "docs/INDEX.md", "docs/05-planning/开发计划安排文档.md", "docs/05-planning/deferred-items.json", "docs/05-planning/phase3f-release-checklist.md", "docs/05-planning/phase3f-evidence-index.md", "docs/05-planning/task-status.json"],
    "status": "backlog",
    "dependencies": ["4.1", "4.2", "4.3", "4.4", "4.5", "4.6", "4.7", "4.8", "4.9", "4.10", "4.11", "4.12", "4.13"],
    "test_file": "EchoTests/Phase4/Phase4IntegrationTests.swift",
    "acceptance_evidence": ["4.1 至 4.13 全部为 done 且每项 acceptance_evidence 均有可定位制品", "EchoTests/Phase4/Phase4IntegrationTests.swift 在最终 RC 上 exit code 0", "Phase 1、2、3、3F、4 的累计单元与集成测试均为 0 failure", "最终 RC 身份、签名、SBOM、隐私、文档、P0=0 和 P1=0 的发布证据索引", "人类最终发布批准记录，Agent 未执行 merge、close 或 delete"],
    "migrated_from": ["4.11"]
  }
]
```

旧 `4.20` 迁入 `3F.2`，记录 `migrated_from: ["4.20"]`。旧 `4.21` 与 `4.22` 迁入 `3F.3`，记录 `migrated_from: ["4.21", "4.22"]`。以下 Phase 5 记录保持原题目、原依赖、原 `test_file` 和原 `notes`，只改 ID、状态与迁移字段：

| new id | title | migrated_from | status | dependencies | test_file |
| ------ | ----- | ------------- | ------ | ------------ | --------- |
|        |       |               |        |              |           |

| `5.6` | `R-3.9 挑战者：PP-OCRv6 备选 OCR 路线` | `["4.12"]` | `backlog` | `[ ]` | `EchoTests/Phase4/PPOCRv6ChallengeTests.swift` |

| `5.7` | `R-3.9 挑战者：Echo 自有蒸馏双语重排器训练管线` | `["4.13"]` | `backlog` | `[ ]` | `EchoTests/Phase4/BilingualRerankerTests.swift` |

| `5.8` | `R-3.9 挑战者：Qwen3-Embedding-0.6B 4-bit 挑战赛（MLX Swift 实机）` | `["4.23"]` | `backlog` | `[ ]` | `EchoTests/Phase4/Qwen3EmbeddingChallengeTests.swift` |

| `5.9` | `R-3.9 挑战者：EmbeddingGemma Q4 挑战赛（gated terms 审查 + 实机评测）` | `["4.24"]` | `backlog` | `[ ]` | `EchoTests/Phase4/EmbeddingGemmaChallengeTests.swift` |

| `5.10` | `R-3.9 挑战者：WhisperKit runtime 对照实验` | `["4.25"]` | `backlog` | `[ ]` | `EchoTests/Phase4/WhisperKitChallengeTests.swift` |

| `5.11` | `Phase 5 集成测试：创新工具原型验证` | `["5.5"]` | `backlog` | `["5.1", "5.2", "5.3", "5.4", "5.6", "5.7", "5.8", "5.9", "5.10"]` | `null` |

`5.6` 至 `5.10` 是并行非发布门禁研究。`5.11` 是新的 Phase 5 integration task。`3F.11` 人类合并前，Phase 4 任何任务都不得为 `ready` 或 `in_progress`。

### 4.4 deferred ledger schema 与关闭规则

每个 active deferral 增加并填写：

```
{
  "owners": ["role"],
  "target_tasks": ["3F.1"],
  "acceptance_evidence": ["可定位的测试、日志或批准记录"],
  "tracking_status": "open",
  "recheck_trigger": "target task review or Phase 3F integration scan"
}
```

关闭时移入 `resolved_deferred`，写 `resolved_at`、`resolved_by_task`、`resolution_evidence`；没有证据不得关闭。

| Deferred                                                 | owners          | target_tasks   | 关闭证据                                                     |
| -------------------------------------------------------- | --------------- | -------------- | ------------------------------------------------------------ |
| DEF-34-001/002                                           | AI/iOS          | 3F.6           | ID-based metadata、timeout/error 分离、partial results 测试  |
| DEF-34-003/004、DEF-35-001                               | AI/Release      | 3F.3           | loader 状态、预处理/PCM、revision/hash/license/SBOM          |
| DEF-37-001                                               | AI/iOS          | 3F.6, 3F.7     | feedback L2 写 PendingOperations 且仅手动重试                |
| DEF-38-001/002                                           | Storage/iOS     | 3F.4, 3F.7     | `originalTimestamp`、`userLocked` 持久化与同步/编辑测试      |
| DEF-39-1                                                 | iOS/Core        | 3F.7, 3F.10    | Settings live adapter 与 L1/L3/L4 注入证据                   |
| DEF-39-2/3、DEF-42-001                                   | iOS             | 3F.7           | 真实导出/状态/ProgressActor 证据                             |
| DEF-41-1、DEF-42-002、DEF-43-001、DEF-45-001、DEF-46-001 | iOS/QA          | 3F.10          | 双语 catalog 100%、可见硬编码为 0                            |
| DEF-41-2                                                 | iOS/QA          | 3F.10          | AX5、banner、iOS 18/26 双版本证据                            |
| DEF-43-002/003                                           | iOS/Storage     | 3F.9           | Apple Translation 与七天 cache 跨重启                        |
| DEF-44-001                                               | AI/iOS/QA       | 3F.9, 3F.10    | grounded creation、i18n、AX                                  |
| DEF-45-002                                               | Privacy/iOS     | 3F.1           | consent 持久化、撤回、事务清除                               |
| DEF-38-003                                               | QA/DevOps       | 4.6            | Phase 4 全局覆盖率 `>=95%` 报告与修复后的 coverage gate      |
| DEF-47-001                                               | QA/DevOps       | 4.6            | 测试 helper 修复、全套测试通过与可定位证据                   |
| DEF-001/002                                              | Product         | 4.10 blocker   | 实现任务，或批准移出 v1 并同步规格/故事矩阵                  |
| DEF-35-002                                               | Product/Privacy | v1.x，v1 外    | ADR、规格移除和目标版本                                      |

### 4.5 必须理解 `3F` ID 的文件

3F.0 同一 PR 更新：

- `.opencode/commands/init-session-echo.md`、`next-task-echo.md`、`do-task-echo.md`、`status-echo.md`、`test-phase-echo.md`、`test-integration-echo.md`、`test-unit-echo.md`、`read-spec-echo.md`、`retry-task-echo.md`、`commit-pr-echo.md`、`pr-review-echo.md`、`pr-merge-echo.md`、`ui-bootstrap-build-echo.md`、`ui-status-echo.md`、`ui-retry-echo.md`、`sync-docs-echo.md`。
- `AGENTS.md`、`README.md`、`docs/INDEX.md`、`docs/05-planning/开发计划安排文档.md`、`docs/ui/README.md`、`docs/ui/command-compatibility.md`、`.ui-automation/state.schema.json`。
- 新建且只新建以下 ADR：`docs/decisions/ADR-006-phase3f-scope-contracts.md`、`docs/decisions/ADR-007-production-composition-consent.md`、`docs/decisions/ADR-008-source-import-boundaries.md`、`docs/decisions/ADR-009-offline-model-runtime.md`、`docs/decisions/ADR-010-canonical-generation-lifecycle.md`、`docs/decisions/ADR-011-task-progress-boundary.md`、`docs/decisions/ADR-012-awakening-system-boundary.md`、`docs/decisions/ADR-013-creation-export-boundary.md`、`docs/decisions/ADR-014-release-compliance-boundary.md`。
- 不创建脚本或测试。用现有 JSON parser、现有 CI 和 PR diff review 验证唯一 ID、依赖存在且无环、`phase_order`、previous/next、`integration_task_id`、Phase 4 entry gate 与 deferred 必填字段。

所有命令改为精确字符串 lookup、显式 `previous_phase_id`/`next_phase_id`、显式 `integration_task_id`、包含关系确定 phase、`EchoTests/Phase${phase.id}`。UI 专用模式只匹配精确 `"3"`，不得捕获 `"3F"`。

### 4.6 穷尽式文件范围与逐任务文档合同

每个任务章节的 **Files** 是 source、test、project、script、CI、配置、文档与 machine-readable UI contract 的穷尽清单，不是示例。禁止用模糊路径、泛化描述或未定标记扩大范围。若 RED 测试证明必须修改未列文件，任务改为 `blocked`，先由人类批准并合并只修订 canonical plan、named ADR 与任务账本的 scope PR，再恢复实现。以下合同中的文档、planning 与 ADR 条目是 §4.2 `documents_required` 的唯一来源；UIAutomation 与命令条目是同名任务 Files 的强制 machine-readable 合同。每个任务的 Files 必须明确纳入同名合同。

#### 4.6.0 3F.0 文档合同

- **Operation:** Update. **Exact paths:** `AGENTS.md`; `README.md`; `docs/INDEX.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/技术选型文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/04-ai-native/产品创新工具全景指南.md`; `docs/05-planning/开发计划安排文档.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`; `docs/ui/README.md`; `docs/ui/architecture.md`; `docs/ui/automation-workflow.md`; `docs/ui/testing-and-artifacts.md`; `docs/ui/command-compatibility.md`; `docs/ui/echo-readiness.md`; `docs/ui/echo-memory-canvas-style.md`; `UIAutomation/Policies/README.md`. **Required delta:** Install Phase 3F authority, corrected ACs, exact contracts, graph, scope, privacy boundaries and UI execution readiness. `产品创新工具全景指南.md` must classify Firebase Vertex AI, network search and cloud fallback as research-only and prohibited in Echo production. `echo-memory-canvas-style.md` must remove or reconcile iCloud sync status UI with the no-CloudKit production contract. `UIAutomation/Policies/README.md` must summarize post-3F.0 scoped Core/config/delivery authority while preserving all stop rules. **Acceptance check:** Cross-link audit, 66-story mapping, no iCloud sync status UI that implies CloudKit, policy-summary parity, zero contradictory P0 ACs, and exact path diff review. **Owner:** Technical Program Lead. **Approver:** Product and Architecture Lead, with Privacy Engineering Lead approval for privacy text.
- **Operation:** Create. **Exact paths:** `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-story-matrix.md`; `docs/05-planning/phase3f-evidence-index.md`. **Required delta:** Copy this approved current instruction into the tracked execution plan, extract the complete calibrated 66-story mapping from Appendix C into the story matrix, and create an evidence skeleton with one entry for every task plus a distinct post-merge finalizer entry. Every 3F.0 through 3F.11 task entry reserves exactly one §11.1 PR-body marker pair; the current task's pair must contain a complete English body from real results before its §6.2.2 delivery, while future task pairs may remain unpopulated until those tasks execute. **Acceptance check:** The current instruction is the complete 3F.0 bootstrap authority; the story matrix reproduces Appendix C metadata, aggregate counts, all 66 unique rows and evidence cells, evidence interpretation, blockers and verdict; all later task instructions cite the canonical plan, read-only story matrix, and shared evidence index; the evidence index has no fabricated implementation or merge evidence; each delivered task passes the marker uniqueness, heading, AC-table, nonempty-section and no-placeholder extraction checks. **Owner:** Technical Program Lead. **Approver:** Product and Architecture Lead.
- **Operation:** Update. **Exact paths:** `UIAutomation/Policies/acceptance-policy.json`; `UIAutomation/Policies/protected-paths.json`; `UIAutomation/Policies/retry-policy.json`. **Required delta:** Authorize the approved 3F.1 to 3F.11 path, scoped Core/UI/config edits and task-ID handling while preserving stop conditions, protected assets, retry ceilings, no-overwrite and no-media rules. **Acceptance check:** JSON parse passes and a before/after policy review proves no stop condition or gate was weakened. **Owner:** UI Automation Lead. **Approver:** Architecture Lead and Release Quality Lead.
- **Operation:** Create. **Exact paths:** `docs/decisions/ADR-006-phase3f-scope-contracts.md`; `docs/decisions/ADR-007-production-composition-consent.md`; `docs/decisions/ADR-008-source-import-boundaries.md`; `docs/decisions/ADR-009-offline-model-runtime.md`; `docs/decisions/ADR-010-canonical-generation-lifecycle.md`; `docs/decisions/ADR-011-task-progress-boundary.md`; `docs/decisions/ADR-012-awakening-system-boundary.md`; `docs/decisions/ADR-013-creation-export-boundary.md`; `docs/decisions/ADR-014-release-compliance-boundary.md`. **Required delta:** Record exact signatures, owners, alternatives, consequences and legacy migration for every blocked production contract. **Acceptance check:** Each ADR is accepted, linked from plan and task, and contains no unresolved marker. **Owner:** Architecture Lead. **Approver:** Named Product, Privacy, Model Legal or Release approver stated in each ADR.
- **Operation:** Update. **Exact paths:** `.opencode/commands/init-session-echo.md`; `.opencode/commands/next-task-echo.md`; `.opencode/commands/do-task-echo.md`; `.opencode/commands/status-echo.md`; `.opencode/commands/test-phase-echo.md`; `.opencode/commands/test-integration-echo.md`; `.opencode/commands/test-unit-echo.md`; `.opencode/commands/read-spec-echo.md`; `.opencode/commands/retry-task-echo.md`; `.opencode/commands/commit-pr-echo.md`; `.opencode/commands/pr-review-echo.md`; `.opencode/commands/pr-merge-echo.md`; `.opencode/commands/ui-bootstrap-build-echo.md`; `.opencode/commands/ui-status-echo.md`; `.opencode/commands/ui-retry-echo.md`; `.opencode/commands/sync-docs-echo.md`; `.ui-automation/state.schema.json`. **Required delta:** Implement exact string task/phase lookup, explicit links and integration IDs, 3F-safe paths, UI exact-3 matching and post-merge finalizer behavior. **Acceptance check:** Command review proves no numeric phase inference and no pre-merge Phase 4 unlock. **Owner:** Developer Experience Lead. **Approver:** Technical Program Lead.

#### 4.6.1 3F.1 文档合同

- **Operation:** Update. **Exact paths:** `README.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/decisions/ADR-007-production-composition-consent.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`. **Required delta:** Record the live composition root, startup states, deny-by-default consent version/timestamps, revocation transaction, purge boundary and audit-storage contract. Every audit row requires `eventType`, `timestamp`, `traceID`, `policyVersion`, `success`; content fields are hash-only; retention cleanup removes rows older than 30 days; the SQLite/audit file uses `NSFileProtectionComplete`. Record schema/storage migration, failing tests, evidence, PR state and DEF-45-002 disposition. **Acceptance check:** Default-App and purge evidence links resolve; migration proves required fields and protection; plaintext scan is zero; 30-day cleanup boundary tests pass; ADR signatures match code; ledger JSON parses; Privacy Engineering Lead approves the audit contract; evidence index has a 3F.1 entry. **Owner:** iOS Platform Lead. **Approver:** Privacy Engineering Lead.
- **Operation:** Read-only. **Exact path:** `docs/05-planning/phase3f-story-matrix.md`. **Required delta:** None. Use its 3F.1 story-to-AC rows as the closed input set. **Acceptance check:** PR diff contains no change to this file. **Owner:** iOS Platform Lead. **Approver:** Product and Architecture Lead for any future scope-change PR.
- **Operation:** Read-only. **Exact path:** `docs/ui/echo-memory-canvas-style.md`. **Required delta:** None; consume the no-CloudKit-reconciled UI contract. **Acceptance check:** No diff and no 3F.1 UI state reintroduces iCloud sync status. **Owner:** iOS Platform Lead. **Approver:** Product and Architecture Lead.
- **Operation:** Update. **Exact paths:** `UIAutomation/Contracts/instances/onboarding-surface.json`; `UIAutomation/Contracts/instances/onboarding-journey-happy-path.json`; `UIAutomation/Contracts/instances/onboarding-journey-privacy-declined.json`; `UIAutomation/Contracts/instances/onboarding-journey-permission-denied.json`; `UIAutomation/Contracts/instances/onboarding-state-welcome.json`; `UIAutomation/Contracts/instances/onboarding-state-language.json`; `UIAutomation/Contracts/instances/onboarding-state-privacy-consent.json`; `UIAutomation/Contracts/instances/onboarding-state-declined.json`; `UIAutomation/Contracts/instances/onboarding-state-permissions.json`; `UIAutomation/Contracts/instances/onboarding-state-permission-denied.json`; `UIAutomation/Contracts/instances/onboarding-state-completed.json`; `UIAutomation/Contracts/instances/onboarding-action-start.json`; `UIAutomation/Contracts/instances/onboarding-action-selectLanguage.json`; `UIAutomation/Contracts/instances/onboarding-action-privacyAgree.json`; `UIAutomation/Contracts/instances/onboarding-action-privacyDecline.json`; `UIAutomation/Contracts/instances/onboarding-action-declinedClose.json`; `UIAutomation/Contracts/instances/onboarding-action-permissionAllow.json`; `UIAutomation/Contracts/instances/onboarding-action-permissionDeny.json`; `UIAutomation/Contracts/instances/onboarding-action-permissionSkip.json`; `UIAutomation/Contracts/instances/onboarding-action-openSettings.json`; `UIAutomation/Fixtures/onboarding/onboarding-welcome.json`; `UIAutomation/Fixtures/onboarding/onboarding-language.json`; `UIAutomation/Fixtures/onboarding/onboarding-privacy-consent.json`; `UIAutomation/Fixtures/onboarding/onboarding-declined.json`; `UIAutomation/Fixtures/onboarding/onboarding-permissions.json`; `UIAutomation/Fixtures/onboarding/onboarding-permission-denied.json`; `UIAutomation/Fixtures/onboarding/onboarding-completed.json`. **Required delta:** Align states/actions/journeys and deterministic test data with persisted consent, denial, permission, completion and relaunch behavior. **Acceptance check:** Every JSON validates against the existing schema and XCUITest uses fixtures only under explicit test mode; no fixture is production evidence. **Owner:** iOS Platform Lead. **Approver:** Privacy Engineering Lead and UI Automation Lead.

#### 4.6.2 3F.2 文档合同

- **Operation:** Update. **Exact paths:** `README.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/decisions/ADR-008-source-import-boundaries.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`; `Echo/Core/Models/AuditEvent.swift`. **Required delta:** Record PhotoKit authorization/change observation, share-only Notes/Voice path, App Group envelope, dedupe, exclusions, audit (`.shareExtensionImported` event added in `Echo/Core/Models/AuditEvent.swift`, US-SRC-003 AC-4), revocation, test and PR evidence. **Acceptance check:** ADR types and entitlement paths match implementation, real-source evidence resolves, and ledgers parse. **Owner:** iOS Sources Lead. **Approver:** Privacy Engineering Lead.
- **Operation:** Read-only. **Exact path:** `docs/05-planning/phase3f-story-matrix.md`. **Required delta:** None. **Acceptance check:** No diff. **Owner:** iOS Sources Lead. **Approver:** Product and Architecture Lead for a scope-change PR.

#### 4.6.3 3F.3 文档合同

- **Operation:** Update. **Exact paths:** `README.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/技术选型文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/decisions/ADR-009-offline-model-runtime.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`. **Required delta:** Document separated E5/SigLIP2 spaces, tokenizer/pooling/normalization, Whisper PCM path, loader recovery, LLM/aligner decision, runtime data flow, packaging pitfalls, tests and deferred closure. **Acceptance check:** ADR-009 governs all model decisions, architecture/data-flow/pitfall sections match code, and evidence links include reference outputs and zero-network scan. **Owner:** On-device ML Lead. **Approver:** Model Legal and Privacy Approver.
- **Operation:** Create. **Exact path:** `docs/05-planning/model-provenance-register.md`. **Required delta:** For every bundled artifact record source URL, immutable revision, SHA-256, conversion lineage, runtime license, tokenizer license, NOTICE location, SBOM location, commercial-distribution disposition, approver and approval date. **Acceptance check:** Manifest-to-bundle-to-register count is 100%, every hash verifies, and no model enters packaging without approval. **Owner:** On-device ML Lead. **Approver:** Model Legal and Privacy Approver.
- **Operation:** Read-only. **Exact path:** `docs/05-planning/phase3f-story-matrix.md`. **Required delta:** None. **Acceptance check:** No diff. **Owner:** On-device ML Lead. **Approver:** Product and Architecture Lead for a scope-change PR.
- **Operation:** Read-only. **Exact path:** `docs/ui/echo-memory-canvas-style.md`. **Required delta:** None; consume model-loading UI semantics after no-CloudKit reconciliation. **Acceptance check:** No diff and no loader state implies cloud model or iCloud sync. **Owner:** On-device ML Lead. **Approver:** Product and Architecture Lead.
- **Operation:** Update. **Exact paths:** `UIAutomation/Contracts/instances/onboarding-surface.json`; `UIAutomation/Contracts/instances/onboarding-state-model-loading.json`; `UIAutomation/Contracts/instances/onboarding-action-beginLoad.json`; `UIAutomation/Fixtures/onboarding/onboarding-model-loading.json`; `UIAutomation/Contracts/instances/onboarding-state-completed.json`; `UIAutomation/Fixtures/onboarding/onboarding-completed.json`. **Required delta:** Replace fixture-only model progress semantics with real loader progress, successful completion and offline-only behavior. **Acceptance check:** Schema validation passes, completion follows verified artifacts, and production code cannot reach a fixture. **Owner:** On-device ML Lead. **Approver:** Model Legal and Privacy Approver and UI Automation Lead.
- **Operation:** Create. **Exact paths:** `UIAutomation/Contracts/instances/onboarding-state-model-load-error.json`; `UIAutomation/Contracts/instances/onboarding-state-model-unavailable.json`; `UIAutomation/Contracts/instances/onboarding-action-retryModelLoad.json`; `UIAutomation/Contracts/instances/onboarding-journey-model-load-recovery.json`; `UIAutomation/Fixtures/onboarding/onboarding-model-load-error.json`; `UIAutomation/Fixtures/onboarding/onboarding-model-unavailable.json`. **Required delta:** Add deterministic missing/corrupt artifact failure, manual retry and unavailable-state coverage without runtime download. **Acceptance check:** New JSON validates against existing schemas and the recovery journey reaches completed only after checksum and reference-output success. **Owner:** On-device ML Lead. **Approver:** Model Legal and Privacy Approver and UI Automation Lead.

#### 4.6.4 3F.4 文档合同

- **Operation:** Update. **Exact paths:** `README.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/decisions/ADR-010-canonical-generation-lifecycle.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`. **Required delta:** Define canonical Memory/Representation schema, deterministic IDs, generation manifests/files, active route restore, shadow build, atomic publish, rollback, feedback identity, deletion and migration pitfalls. **Acceptance check:** ADR-010 owns the decision, architecture/data-flow/pitfall diagrams and transaction boundaries match fault-injection evidence, and ledgers parse. **Owner:** Storage Architecture Lead. **Approver:** Privacy Engineering Lead.
- **Operation:** Read-only. **Exact path:** `docs/05-planning/phase3f-story-matrix.md`. **Required delta:** None. **Acceptance check:** No diff. **Owner:** Storage Architecture Lead. **Approver:** Product and Architecture Lead for a scope-change PR.

#### 4.6.5 3F.5 文档合同

- **Operation:** Update. **Exact paths:** `README.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/decisions/ADR-011-task-progress-boundary.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`. **Required delta:** Record source-to-extraction-to-inference-to-canonical/generation flow, TaskQueue/Progress boundaries, cancellation, resume, L1-L4, rollback and test evidence. **Acceptance check:** ADR-011 signatures match code, four source traces resolve, and evidence index identifies rollback checkpoints. **Owner:** Ingestion Lead. **Approver:** Architecture Lead.
- **Operation:** Read-only. **Exact path:** `docs/05-planning/phase3f-story-matrix.md`. **Required delta:** None. **Acceptance check:** No diff. **Owner:** Ingestion Lead. **Approver:** Product and Architecture Lead for a scope-change PR.

#### 4.6.6 3F.6 文档合同

- **Operation:** Update. **Exact paths:** `README.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/decisions/ADR-010-canonical-generation-lifecycle.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`. **Required delta:** Define authorized channels, generation routing, timeout/partial split, RRF, filters, metadata lookup, bounded reranking, low confidence, cache invalidation, query-conditioned feedback and PendingOperations pitfalls. Define US-SRC-010 `CrossAppIntentParser` protocol and injected-provider fusion for health+memory and location+photo intents, per-source authorization, temporal alignment, source labels and `.crossAppSearch` audit source list. **Acceptance check:** ADR-010 owns route/feedback identity; architecture/data-flow/pitfall sections match deterministic ranking and cross-app tests; unauthorized sources never execute; injected-provider fusion preserves temporal alignment/source labels; deferred closures have links. **Owner:** Search and Ranking Lead. **Approver:** Privacy Engineering Lead.
- **Operation:** Read-only. **Exact path:** `docs/05-planning/phase3f-story-matrix.md`. **Required delta:** None. **Acceptance check:** No diff. **Owner:** Search and Ranking Lead. **Approver:** Product and Architecture Lead for a scope-change PR.
- **Operation:** Read-only. **Exact path:** `docs/ui/echo-memory-canvas-style.md`. **Required delta:** None; consume search surface and no-CloudKit UI semantics. **Acceptance check:** No diff and search has no iCloud sync-status dependency. **Owner:** Search and Ranking Lead. **Approver:** Product and Architecture Lead.
- **Operation:** Update. **Exact paths:** `UIAutomation/Contracts/instances/search-surface.json`; `UIAutomation/Contracts/instances/search-journey-basic.json`; `UIAutomation/Contracts/instances/search-state-idle.json`; `UIAutomation/Contracts/instances/search-state-loading.json`; `UIAutomation/Contracts/instances/search-state-loaded.json`; `UIAutomation/Contracts/instances/search-state-empty.json`; `UIAutomation/Contracts/instances/search-state-error.json`; `UIAutomation/Contracts/instances/search-state-lowconfidence.json`; `UIAutomation/Contracts/instances/search-action-submit.json`; `UIAutomation/Contracts/instances/search-action-retry.json`; `UIAutomation/Contracts/instances/search-action-like.json`; `UIAutomation/Contracts/instances/search-action-dislike.json`; `UIAutomation/Contracts/instances/search-action-badcase.json`; `UIAutomation/Fixtures/search/search-loaded.json`; `UIAutomation/Fixtures/search/search-empty.json`; `UIAutomation/Fixtures/search/search-lowconfidence.json`; `UIAutomation/Fixtures/search/search-multitype.json`. **Required delta:** Align search states/actions and deterministic fixtures with channel provenance, partial results, low confidence and feedback. **Acceptance check:** JSON schema validation and focused XCUITest pass; fixture reachability remains test-only. **Owner:** Search and Ranking Lead. **Approver:** UI Automation Lead and Privacy Engineering Lead.
- **Operation:** Create. **Exact paths:** `UIAutomation/Contracts/instances/search-state-partial-results.json`; `UIAutomation/Contracts/instances/search-journey-partial-results.json`; `UIAutomation/Fixtures/search/search-partial-results.json`. **Required delta:** Declare timeout/error-separated partial results with successful-channel provenance and unavailable-channel reasons. **Acceptance check:** Surface state list includes `partialResults`, schema validation passes and the journey proves partial results are not rendered as full success or total error. **Owner:** Search and Ranking Lead. **Approver:** UI Automation Lead and Privacy Engineering Lead.

#### 4.6.7 3F.7 文档合同

- **Operation:** Update. **Exact paths:** `AGENTS.md`; `README.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/decisions/ADR-008-source-import-boundaries.md`; `docs/decisions/ADR-010-canonical-generation-lifecycle.md`; `docs/ui/architecture.md`; `docs/ui/automation-workflow.md`; `docs/ui/testing-and-artifacts.md`; `docs/ui/echo-readiness.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`. **Required delta:** Record thin live adapters, default dependency graph, surface actions, fixture isolation, dual-device review and no-media evidence. ADR-008 and ADR-010 must define the US-SRC-007 encrypted user-mediated AirDrop/system-share package and Finder/iTunes encrypted local-backup restore boundary, target-empty/overwrite/merge strategies, per-item/batch conflict resolution, deterministic ID integrity, missing-item reingest, local ExcludedAssets migration, and prohibition on exporting all original memory files. Architecture/data flow must define US-SRC-009 live data-overview counts, storage use, vector dimensions, model states, <=5-second updates, JSON statistics export and `.dataOverviewAccessed`. **Acceptance check:** Default construction, migration fault/integrity/conflict evidence and live data-overview evidence resolve; Privacy and Architecture approvers accept both ADR changes; docs contain no fixture-as-production or CloudKit claim. **Owner:** iOS UI Integration Lead. **Approver:** Architecture Lead and Privacy Engineering Lead.
- **Migration-security sub-contract governed jointly by ADR-008 and ADR-010:** App-imported AirDrop/system-share migration uses a versioned fixed-format package with no arbitrary archive paths. The algorithm identifier is exactly `AES-GCM-256+HKDF-SHA256`; every other identifier fails closed. The source generates one fresh random 256-bit `K_transfer` per archive and displays it separately as a one-time base64url/QR transfer secret. `K_transfer` is never embedded in the package, logged, copied to clipboard, backed up or persisted after session end. No wrapped keys, cloud service, key server or remote recovery behavior exists.
- **Exact chunk-key/encryption protocol:** For chunk index `i`, derive `K_i = HKDF-SHA256(inputKeyMaterial: K_transfer, salt: UTF8(lowercaseArchiveUUIDString), info: UTF8("EchoMigration/v1/chunk/" + decimal(i)), outputByteCount: 32)`. The salt is exactly the 36 ASCII/UTF-8 bytes of the lowercase RFC 4122 hyphenated archive UUID string with `8-4-4-4-12` shape, never raw UUID memory bytes. Encrypt each chunk with CryptoKit `AES.GCM` using `K_i` and a fresh random 96-bit nonce stored next to that chunk's ciphertext and authentication tag. Header `manifestSHA256` is exactly 64 lowercase ASCII hex characters encoding SHA-256 over the RFC 8785 canonical UTF-8 chunk-0 manifest plaintext bytes. Reject uppercase digest text, prefixes and every non-64 length.
- **Canonical RFC 8785 chunk-0 manifest:** Serialize chunk-0 plaintext with RFC 8785 JSON Canonicalization Scheme (JCS) to UTF-8 with no BOM and no trailing newline. The root object has exactly six mandatory fields: `archiveUUID`, `schemaVersion`, `chunkCount`, `totalPlaintextBytes`, `recordCount`, `records`; none is optional. Every record object has exactly `type`, `id`, `byteLength`, `sha256`. Normalize every string to Unicode NFC before JCS. For record ordering, normalize `type` and `id` to NFC, encode each as UTF-8 and compare the resulting unsigned byte sequences lexicographically: type bytes are the primary key and id bytes are the secondary key. If both byte sequences are identical, reject the archive as a duplicate record key; never preserve input order as a tie-breaker. `type` and `id` must not contain control characters. Every `sha256` is exactly 64 lowercase ASCII hex characters. All numeric fields are JSON integers in `0...2^53-1`; reject floats, NaN, Infinity and values outside that range. Reject duplicate JSON keys and every unknown root or record field. Header `manifestSHA256` is SHA-256 over these complete canonical UTF-8 bytes. The manifest schema MUST NOT contain `manifestSHA256` or any copy of its own digest.
- **Canonical package header:** The package begins with exactly the following UTF-8 bytes, LF line endings only, no BOM, fields in this order and one final blank line. Every decimal field is unsigned, has no sign and has no leading zero except the single character `0`.

```
ECHOMIG1
algorithm=AES-GCM-256+HKDF-SHA256
archiveUUID=<uuid>
schemaVersion=<unsigned decimal>
chunkCount=<unsigned decimal>
totalPlaintextBytes=<unsigned decimal>
manifestSHA256=<64 lowercase hex>
```

- **Canonical chunk framing:** Immediately after the final header LF, each chunk record contains, in order: 4-byte unsigned big-endian chunk index; 4-byte unsigned big-endian `plaintextLength`; 12-byte random nonce; exactly `plaintextLength` ciphertext bytes; 16-byte GCM tag. There is no padding. `recordCount >= 1` and `chunkCount >= 2` are mandatory; `chunkCount=0` and `chunkCount=1` are always invalid. Indexes are contiguous `0...chunkCount-1`; no chunk has zero plaintext length. Chunk 0 is the encrypted RFC 8785 manifest and at least one data chunk at index 1 must follow. Framing permits manifest plaintext length 1 byte...4 MiB. Data chunks are indexes `1...chunkCount-1`; every non-final data chunk is exactly 4 MiB and the final data chunk is 1 byte...4 MiB. `totalPlaintextBytes` counts only concatenated record payload data and explicitly excludes chunk-0 manifest bytes. Manifest-only archives are always rejected.
- **Canonical logical data stream and record mapping:** After chunk 0, logical data plaintext is exactly the concatenation of each record payload in canonical manifest record order. There is no separator, record length prefix, padding or trailing byte. A record may cross a 4 MiB data-chunk boundary. Slice this concatenated stream into exact 4 MiB non-final data chunks and one 1 byte...4 MiB final data chunk. Require `recordCount == records.count`; every record `byteLength >= 1`; an overflow-safe sum of all `byteLength` values equals `totalPlaintextBytes`; and decrypted data-stream length equals `totalPlaintextBytes` exactly. Reject arithmetic overflow, underflow, short stream, trailing data and every length mismatch before atomic publication. For each record, reconstruct its payload boundary from canonical ordered `byteLength` values, stream exactly that byte slice into protected staging, compute SHA-256 over those exact payload bytes and compare to the record `sha256` before marking the record valid. Publish only after every record validates; any failure leaves active database/routes untouched.
- **Exact AAD:** For each chunk, AAD is exactly the UTF-8 bytes of `EchoMigration/v1|<lowercase UUID>|<schemaVersion decimal>|<chunkIndex decimal>|<chunkCount decimal>|<plaintextLength decimal>|<manifestSHA256 lowercase hex>`. Decimal fields use canonical unsigned base-10 without leading zeroes; UUID is lowercase RFC 4122 hyphenated; digest is exactly the canonical 64-character lowercase hex form. Header values represented in AAD must match byte-for-byte, so altering any of those values causes tag verification failure. Because the mandated AAD does not contain `totalPlaintextBytes`, the authenticated manifest must repeat only the header's `totalPlaintextBytes` value for this consistency check; it never repeats `manifestSHA256`. A totalPlaintextBytes header/manifest mismatch is rejected after chunk 0 authentication and before staging allocation.
- **Receiver/key lifecycle and OS-backup boundary:** The receiver obtains only `K_transfer` out of band through user scan or entry, derives each `K_i` identically, authenticates every chunk before staging and destroys in-memory references to `K_transfer` and `K_i` after success, failure or cancellation. Finder/iTunes encrypted local-backup restoration is distinct: the OS manages backup encryption and keys; Echo never accesses backup keys and performs only post-restore schema, integrity and active-route validation.
- **Migration rejection and resource contract:** Before any database mutation or import allocation, reject unknown package version or algorithm, malformed/noncanonical header, wrong key, AES-GCM tamper/tag failure, truncation, duplicate/replayed archive UUID, duplicate canonical `(type,id)` key, noncontiguous/out-of-order/missing chunks, invalid zero/oversized chunk or record length, manifest/hash mismatch, overflow/underflow/short/trailing data, path traversal attempt and unsupported record type. Validate separately: `manifestPlaintextByteLength <= 4 MiB`; data-only `totalPlaintextBytes <= 4 GiB`; expansion ratio <= 100:1; record count <= 1,000,000; and overflow-safe `manifestPlaintextByteLength + totalPlaintextBytes` <= `min(2 GiB, 50% of currently free disk)` and within the package limit. Any exceeded, inconsistent or unprovable bound fails closed before allocation/import.
- **Validation order:** (1) Parse the fixed header and chunk-record framing with bounded reads. (2) Reject `chunkCount < 2`, missing chunk index 1, zero `recordCount`, empty `records`, noncontiguous indexes, invalid lengths/shapes and exceeded declared limits without trusting authenticity or allocating staging. (3) Derive `K_0`, authenticate/decrypt chunk 0 and require `manifestPlaintextByteLength <= 4 MiB`. (4) Require valid RFC 8785 JCS UTF-8; hash complete canonical bytes and compare to header `manifestSHA256`. (5) Validate mandatory schema and exact header equality; require overflow-safe `sum(record.byteLength) == totalPlaintextBytes`; enforce data-only/manifest/combined resource bounds; only then allocate protected staging. (6) Authenticate all data chunks, reconstruct the concatenated payload stream, require its exact length equals `totalPlaintextBytes`, stream each record slice and verify its hash. (7) Publish only when every count, boundary, reference and record hash validates. Any failure leaves active database/routes unchanged.
- **Migration filesystem/publication contract:** Temporary and staging files use `NSFileProtectionComplete`, fixed app-owned directories, no-follow opens, explicit symlink rejection and backup exclusion. Cleanup is deterministic on success, failure, cancellation and next launch. Import targets a new staging database and generation; validate every count, hash and reference before atomic publication. Any rejection or rollback leaves the active database and active routes unchanged. **Implementation owner:** iOS Platform Security Lead. **Mandatory approvers:** Security Engineering Lead, Privacy Engineering Lead and Architecture Lead.
- **Operation:** Read-only. **Exact path:** `docs/05-planning/phase3f-story-matrix.md`. **Required delta:** None. **Acceptance check:** No diff. **Owner:** iOS UI Integration Lead. **Approver:** Product and Architecture Lead for a scope-change PR.
- **Operation:** Read-only. **Exact path:** `docs/ui/echo-memory-canvas-style.md`. **Required delta:** None; consume live UI semantics after no-CloudKit reconciliation. **Acceptance check:** No diff and default live UI contains no iCloud sync status. **Owner:** iOS UI Integration Lead. **Approver:** Product and Architecture Lead.

- **Operation:** Update. **Exact paths:** `UIAutomation/Contracts/instances/search-to-detail-journey.json`; `UIAutomation/Contracts/instances/memory-detail-surface.json`; `UIAutomation/Contracts/instances/memory-detail-journey-basic.json`; `UIAutomation/Contracts/instances/memory-detail-state-loading.json`; `UIAutomation/Contracts/instances/memory-detail-state-loaded.json`; `UIAutomation/Contracts/instances/memory-detail-state-editing.json`; `UIAutomation/Contracts/instances/memory-detail-state-translated.json`; `UIAutomation/Contracts/instances/memory-detail-state-conflict.json`; `UIAutomation/Contracts/instances/memory-detail-state-error.json`; `UIAutomation/Contracts/instances/memory-detail-action-edit.json`; `UIAutomation/Contracts/instances/memory-detail-action-save.json`; `UIAutomation/Contracts/instances/memory-detail-action-translate.json`; `UIAutomation/Contracts/instances/memory-detail-action-delete.json`; `UIAutomation/Contracts/instances/memory-detail-action-delete-original.json`; `UIAutomation/Contracts/instances/memory-detail-action-remove-from-echo.json`; `UIAutomation/Contracts/instances/memory-detail-action-keep-local.json`; `UIAutomation/Contracts/instances/memory-detail-action-keep-external.json`; `UIAutomation/Contracts/instances/memory-detail-action-retry.json`; `UIAutomation/Contracts/instances/background-tasks-surface.json`; `UIAutomation/Contracts/instances/background-tasks-journey-basic.json`; `UIAutomation/Contracts/instances/background-tasks-state-loading.json`; `UIAutomation/Contracts/instances/background-tasks-state-loaded.json`; `UIAutomation/Contracts/instances/background-tasks-state-empty.json`; `UIAutomation/Contracts/instances/background-tasks-state-error.json`; `UIAutomation/Contracts/instances/background-tasks-action-open.json`; `UIAutomation/Contracts/instances/background-tasks-action-pause.json`; `UIAutomation/Contracts/instances/background-tasks-action-cancel.json`; `UIAutomation/Contracts/instances/background-tasks-action-retry.json`; `UIAutomation/Contracts/instances/resume-progress-surface.json`; `UIAutomation/Contracts/instances/resume-progress-journey-basic.json`; `UIAutomation/Contracts/instances/resume-progress-state-none.json`; `UIAutomation/Contracts/instances/resume-progress-state-checking.json`; `UIAutomation/Contracts/instances/resume-progress-state-prompt.json`; `UIAutomation/Contracts/instances/resume-progress-state-resumed.json`; `UIAutomation/Contracts/instances/resume-progress-state-restarted.json`; `UIAutomation/Contracts/instances/resume-progress-state-error.json`; `UIAutomation/Contracts/instances/resume-progress-action-start.json`; `UIAutomation/Contracts/instances/resume-progress-action-continue.json`; `UIAutomation/Contracts/instances/resume-progress-action-restart.json`; `UIAutomation/Contracts/instances/resume-progress-action-retry.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-loaded.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-photo-loaded.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-video-loaded.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-voice-loaded.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-translated.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-conflict.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-error.json`; `UIAutomation/Fixtures/background-tasks/background-tasks-loaded.json`; `UIAutomation/Fixtures/background-tasks/background-tasks-empty.json`; `UIAutomation/Fixtures/background-tasks/background-tasks-error.json`; `UIAutomation/Fixtures/resume-progress/resume-progress-none.json`; `UIAutomation/Fixtures/resume-progress/resume-progress-pending.json`; `UIAutomation/Fixtures/resume-progress/resume-progress-error.json`. **Required delta:** Align search-to-detail, edit/delete/conflict, background-task and resume states/actions with live Core behavior. **Acceptance check:** Schema validation, exact UI suites, dual-device manifests and production fixture-isolation scan pass. **Owner:** iOS UI Integration Lead. **Approver:** UI Automation Lead.
- **Operation:** Create. **Exact paths:** `UIAutomation/Contracts/instances/settings-surface.json`; `UIAutomation/Contracts/instances/settings-state-loaded.json`; `UIAutomation/Contracts/instances/settings-action-startDeviceMigration.json`; `UIAutomation/Contracts/instances/settings-action-selectMigrationStrategy.json`; `UIAutomation/Contracts/instances/settings-action-applyBatchConflictResolution.json`; `UIAutomation/Contracts/instances/settings-action-exportDataOverview.json`; `UIAutomation/Contracts/instances/settings-journey-device-migration.json`; `UIAutomation/Contracts/instances/settings-journey-data-overview.json`; `UIAutomation/Fixtures/settings/settings-loaded.json`; `UIAutomation/Fixtures/settings/settings-migration-conflicts.json`; `UIAutomation/Fixtures/settings/settings-data-overview.json`. **Required delta:** Materialize deterministic Settings contracts for device migration strategy/conflict handling and live data-overview export. **Acceptance check:** JSON validates; migration journey covers target-empty, overwrite, merge, per-item and batch conflict paths; overview journey proves live values, <=5-second refresh and JSON export; fixtures remain test-only. **Owner:** iOS UI Integration Lead. **Approver:** UI Automation Lead, Architecture Lead and Privacy Engineering Lead.
- **Operation:** Read-only. **Exact paths:** `UIAutomation/Contracts/instances/degradation-banner-surface.json`; `UIAutomation/Contracts/instances/degradation-banner-state-normal.json`; `UIAutomation/Contracts/instances/degradation-banner-state-lowPower.json`; `UIAutomation/Contracts/instances/degradation-banner-state-thermal.json`; `UIAutomation/Contracts/instances/degradation-banner-state-modelDegraded.json`; `UIAutomation/Fixtures/degradation-banner/degradation-normal.json`; `UIAutomation/Fixtures/degradation-banner/degradation-low-power.json`; `UIAutomation/Fixtures/degradation-banner/degradation-thermal.json`; `UIAutomation/Fixtures/degradation-banner/degradation-model-degraded.json`. **Required delta:** None. Use as the existing adapter integration contract; 3F.10 owns semantic updates. **Acceptance check:** No diff in 3F.7. **Owner:** iOS UI Integration Lead. **Approver:** Release Quality Lead for future scope changes.

#### 4.6.8 3F.8 文档合同

- **Operation:** Update. **Exact paths:** `README.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/ui/testing-and-artifacts.md`; `docs/ui/echo-readiness.md`; `docs/decisions/ADR-012-awakening-system-boundary.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`. **Required delta:** Record system adapter permissions, data minimization, best-effort windows, card persistence/dedupe, notification request/response split and evidence. Record the live HealthKit provider conformance consumed by US-SRC-010 health+memory search, including authorization and minimized temporal samples. **Acceptance check:** ADR-012 matches implementation; live HealthKit integration tests prove authorized temporal data reaches 3F.6 fusion and denial blocks the source; Privacy approval, ledgers and evidence links resolve. **Owner:** iOS System Integration Lead. **Approver:** Privacy Engineering Lead.
- **Operation:** Read-only. **Exact path:** `docs/05-planning/phase3f-story-matrix.md`. **Required delta:** None. **Acceptance check:** No diff. **Owner:** iOS System Integration Lead. **Approver:** Product and Architecture Lead for a scope-change PR.
- **Operation:** Read-only. **Exact path:** `docs/ui/echo-memory-canvas-style.md`. **Required delta:** None; consume awakening UI semantics after no-CloudKit reconciliation. **Acceptance check:** No diff and awakening state does not depend on iCloud sync status. **Owner:** iOS System Integration Lead. **Approver:** Product and Architecture Lead.
- **Operation:** Update. **Exact paths:** `UIAutomation/Contracts/instances/awakening-settings-surface.json`; `UIAutomation/Contracts/instances/awakening-settings-state-loading.json`; `UIAutomation/Contracts/instances/awakening-settings-state-loaded.json`; `UIAutomation/Contracts/instances/awakening-settings-state-empty-permissions.json`; `UIAutomation/Contracts/instances/awakening-settings-state-unavailable.json`. **Required delta:** Align existing loading, loaded, no-permissions and unavailable declarations with live system adapters and the exact surface IDs. **Acceptance check:** Schema validation and exact awakening UI suite pass using injected test system signals. **Owner:** iOS System Integration Lead. **Approver:** Privacy Engineering Lead and UI Automation Lead.
- **Operation:** Create. **Exact paths:** `UIAutomation/Contracts/instances/awakening-settings-state-error.json`; `UIAutomation/Contracts/instances/awakening-settings-state-all-disabled.json`; `UIAutomation/Contracts/instances/awakening-settings-action-toggleGeofence.json`; `UIAutomation/Contracts/instances/awakening-settings-action-toggleEmotion.json`; `UIAutomation/Contracts/instances/awakening-settings-action-toggleAnniversary.json`; `UIAutomation/Contracts/instances/awakening-settings-action-requestNotification.json`; `UIAutomation/Contracts/instances/awakening-settings-action-openSystemSettings.json`; `UIAutomation/Contracts/instances/awakening-settings-action-showGeofenceDetail.json`; `UIAutomation/Contracts/instances/awakening-settings-action-dismissGeofenceDetail.json`; `UIAutomation/Contracts/instances/awakening-settings-journey-basic.json`; `UIAutomation/Contracts/instances/awakening-settings-journey-no-permissions.json`; `UIAutomation/Contracts/instances/awakening-settings-journey-unavailable.json`; `UIAutomation/Fixtures/awakening-settings/awakening-settings-loading.json`; `UIAutomation/Fixtures/awakening-settings/awakening-settings-loaded.json`; `UIAutomation/Fixtures/awakening-settings/awakening-settings-no-permissions.json`; `UIAutomation/Fixtures/awakening-settings/awakening-settings-unavailable.json`; `UIAutomation/Fixtures/awakening-settings/awakening-settings-error.json`; `UIAutomation/Fixtures/awakening-settings/awakening-settings-all-disabled.json`. **Required delta:** Materialize all six states, all seven actions and all three journeys declared by `awakening-settings-surface.json`, with six deterministic fixtures for loading, loaded, no-permissions, unavailable, error and all-disabled. **Acceptance check:** Every declared ID resolves to one exact contract, every state resolves to deterministic test input, all JSON validates, and fixtures remain test-only evidence. **Owner:** iOS System Integration Lead. **Approver:** Privacy Engineering Lead and UI Automation Lead.

#### 4.6.9 3F.9 文档合同

- **Operation:** Update. **Exact paths:** `README.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/decisions/ADR-009-offline-model-runtime.md`; `docs/decisions/ADR-013-creation-export-boundary.md`; `docs/ui/testing-and-artifacts.md`; `docs/ui/echo-readiness.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`. **Required delta:** Record Apple Translation availability and uncertain fallback, persistent seven-day cache, terminology precedence, grounded anchors, approved offline runtime, Markdown/PDF/share and user-mediated Notes handoff. **Acceptance check:** ADR-009 and ADR-013 match code, cache/relaunch and export evidence resolves, and no fabricated Notes URL remains. **Owner:** Language and Creation Lead. **Approver:** Model Legal and Privacy Approver.
- **Operation:** Read-only. **Exact path:** `docs/05-planning/phase3f-story-matrix.md`. **Required delta:** None. **Acceptance check:** No diff. **Owner:** Language and Creation Lead. **Approver:** Product and Architecture Lead for a scope-change PR.
- **Operation:** Read-only. **Exact path:** `docs/ui/echo-memory-canvas-style.md`. **Required delta:** None; consume translation/creation UI semantics after no-CloudKit reconciliation. **Acceptance check:** No diff and export/share UI does not imply iCloud sync. **Owner:** Language and Creation Lead. **Approver:** Product and Architecture Lead.
- **Operation:** Update. **Exact paths:** `UIAutomation/Contracts/instances/translation-surface.json`; `UIAutomation/Contracts/instances/translation-journey-basic.json`; `UIAutomation/Contracts/instances/translation-state-original.json`; `UIAutomation/Contracts/instances/translation-state-translating.json`; `UIAutomation/Contracts/instances/translation-state-translated.json`; `UIAutomation/Contracts/instances/translation-state-cached.json`; `UIAutomation/Contracts/instances/translation-state-low-confidence.json`; `UIAutomation/Contracts/instances/translation-state-error.json`; `UIAutomation/Contracts/instances/translation-action-toggle.json`; `UIAutomation/Contracts/instances/translation-action-retry.json`; `UIAutomation/Contracts/instances/creation-surface.json`; `UIAutomation/Contracts/instances/creation-journey-generate-save-basic.json`; `UIAutomation/Contracts/instances/creation-journey-prompt-edit-confirm.json`; `UIAutomation/Contracts/instances/creation-state-idle.json`; `UIAutomation/Contracts/instances/creation-state-empty.json`; `UIAutomation/Contracts/instances/creation-state-generating.json`; `UIAutomation/Contracts/instances/creation-state-generated.json`; `UIAutomation/Contracts/instances/creation-state-share-handoff.json`; `UIAutomation/Contracts/instances/creation-state-error.json`; `UIAutomation/Contracts/instances/creation-action-select-template.json`; `UIAutomation/Contracts/instances/creation-action-edit-prompt.json`; `UIAutomation/Contracts/instances/creation-action-confirm-prompt.json`; `UIAutomation/Contracts/instances/creation-action-reset-prompt.json`; `UIAutomation/Contracts/instances/creation-action-generate.json`; `UIAutomation/Contracts/instances/creation-action-retry.json`; `UIAutomation/Contracts/instances/creation-action-copy.json`; `UIAutomation/Contracts/instances/creation-action-export.json`; `UIAutomation/Contracts/instances/creation-action-share.json`; `UIAutomation/Contracts/instances/creation-action-save-to-notes.json`; `UIAutomation/Fixtures/translation/translation-zh-en-high.json`; `UIAutomation/Fixtures/translation/translation-zh-en-low.json`; `UIAutomation/Fixtures/translation/translation-zh-en-cached.json`; `UIAutomation/Fixtures/translation/translation-error.json`; `UIAutomation/Fixtures/creation/creation-idle.json`; `UIAutomation/Fixtures/creation/creation-empty.json`; `UIAutomation/Fixtures/creation/creation-prompt-draft.json`; `UIAutomation/Fixtures/creation/creation-generated-report.json`; `UIAutomation/Fixtures/creation/creation-generated-letter.json`; `UIAutomation/Fixtures/creation/creation-share-handoff.json`; `UIAutomation/Fixtures/creation/creation-error.json`. **Required delta:** Align translation and creation states/actions/journeys with the approved production semantics and deterministic test data. **Acceptance check:** Schema validation, exact translation/creation UI suites, offline scan and fixture-isolation scan pass. **Owner:** Language and Creation Lead. **Approver:** Model Legal and Privacy Approver and UI Automation Lead.
- **Operation:** Create. **Exact paths:** `UIAutomation/Contracts/instances/translation-state-availability-checking.json`; `UIAutomation/Contracts/instances/translation-state-unavailable.json`; `UIAutomation/Contracts/instances/translation-journey-availability-fallback.json`; `UIAutomation/Fixtures/translation/translation-availability-checking.json`; `UIAutomation/Fixtures/translation/translation-unavailable.json`. **Required delta:** Declare Apple Translation availability checking and unsupported-pair fallback before translation starts. **Acceptance check:** Surface state list includes both states, unavailable retains original text and language label, and all JSON validates. **Owner:** Language and Creation Lead. **Approver:** Model Legal and Privacy Approver and UI Automation Lead.

#### 4.6.10 3F.10 文档合同

- **Operation:** Update. **Exact paths:** `AGENTS.md`; `README.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/decisions/ADR-011-task-progress-boundary.md`; `docs/ui/README.md`; `docs/ui/automation-workflow.md`; `docs/ui/testing-and-artifacts.md`; `docs/ui/echo-readiness.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`. **Required delta:** Record catalog policy, language mapping, AX/Dynamic Type/contrast/motion, L1-L4, PendingOperations, low-power/thermal/model degradation architecture, data flow and pitfalls. ADR-011 governs task-progress and degradation recovery boundaries. **Acceptance check:** Architecture/data-flow/pitfall sections match runtime fault tests, catalog parity is 100%, visible hardcoded strings are 0 and evidence links resolve. **Owner:** Localization and Accessibility Lead. **Approver:** Release Quality Lead.
- **Operation:** Read-only. **Exact path:** `docs/05-planning/phase3f-story-matrix.md`. **Required delta:** None. **Acceptance check:** No diff. **Owner:** Localization and Accessibility Lead. **Approver:** Product and Architecture Lead for a scope-change PR.
- **Operation:** Read-only. **Exact path:** `docs/ui/echo-memory-canvas-style.md`. **Required delta:** None; consume localization, accessibility and degradation UI semantics after no-CloudKit reconciliation. **Acceptance check:** No diff and localized catalogs contain no iCloud sync-status copy. **Owner:** Localization and Accessibility Lead. **Approver:** Product and Architecture Lead.
- **Operation:** Update. **Exact paths:** `UIAutomation/Contracts/instances/degradation-banner-surface.json`; `UIAutomation/Contracts/instances/degradation-banner-state-normal.json`; `UIAutomation/Contracts/instances/degradation-banner-state-lowPower.json`; `UIAutomation/Contracts/instances/degradation-banner-state-thermal.json`; `UIAutomation/Contracts/instances/degradation-banner-state-modelDegraded.json`; `UIAutomation/Fixtures/degradation-banner/degradation-normal.json`; `UIAutomation/Fixtures/degradation-banner/degradation-low-power.json`; `UIAutomation/Fixtures/degradation-banner/degradation-thermal.json`; `UIAutomation/Fixtures/degradation-banner/degradation-model-degraded.json`. **Required delta:** Align degradation states with real power, thermal, model and L1-L4 sources. **Acceptance check:** Schema validation, fault-driven exact UI suites, dual-device manifests and fixture-isolation scan pass. **Owner:** Localization and Accessibility Lead. **Approver:** Release Quality Lead and UI Automation Lead.
- **Operation:** Create. **Exact paths:** `UIAutomation/Contracts/instances/degradation-banner-action-dismiss.json`; `UIAutomation/Contracts/instances/degradation-banner-action-retryModelLoad.json`; `UIAutomation/Contracts/instances/degradation-banner-action-toggleBackgroundTasks.json`; `UIAutomation/Contracts/instances/degradation-banner-action-openSettings.json`; `UIAutomation/Contracts/instances/degradation-banner-journey-lifecycle.json`; `UIAutomation/Contracts/instances/degradation-banner-state-l1Transient.json`; `UIAutomation/Contracts/instances/degradation-banner-state-l2Recoverable.json`; `UIAutomation/Contracts/instances/degradation-banner-state-l3Blocking.json`; `UIAutomation/Contracts/instances/degradation-banner-state-l4Conflict.json`; `UIAutomation/Contracts/instances/degradation-banner-action-retryL1.json`; `UIAutomation/Contracts/instances/degradation-banner-action-retryPendingOperation.json`; `UIAutomation/Contracts/instances/degradation-banner-action-openBlockingRecovery.json`; `UIAutomation/Contracts/instances/degradation-banner-action-resolveConflict.json`; `UIAutomation/Contracts/instances/degradation-banner-journey-l1-l4.json`; `UIAutomation/Fixtures/degradation-banner/degradation-l1-transient.json`; `UIAutomation/Fixtures/degradation-banner/degradation-l2-recoverable.json`; `UIAutomation/Fixtures/degradation-banner/degradation-l3-blocking.json`; `UIAutomation/Fixtures/degradation-banner/degradation-l4-conflict.json`. **Required delta:** Materialize all four actions and lifecycle journey already declared by the surface, then extend the surface with explicit L1-L4 states, recovery actions, journey and deterministic fixtures. **Acceptance check:** Every surface action/journey/state resolves to one contract, L2 is manual PendingOperations retry, L3 blocks, L4 exposes conflict resolution, and all JSON validates. **Owner:** Localization and Accessibility Lead. **Approver:** Release Quality Lead and UI Automation Lead.

#### 4.6.11 3F.11 文档合同

- **Operation:** Update. **Exact paths:** `AGENTS.md`; `README.md`; `docs/INDEX.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/技术选型文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/05-planning/开发计划安排文档.md`; `docs/05-planning/model-provenance-register.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`; `docs/ui/testing-and-artifacts.md`; `docs/decisions/ADR-014-release-compliance-boundary.md`. **Required delta:** Finalize pre-merge implementation truth, gate outputs, artifact identity, deferred state and release-compliance boundary without claiming a merge SHA or unlocking Phase 4. **Acceptance check:** Cross-document version/path/threshold audit passes and every evidence link resolves at the 3F.11 head SHA. **Owner:** Release Quality Lead. **Approver:** Release Manager and Privacy Engineering Lead.
- **Operation:** Read-only. **Exact path:** `docs/05-planning/phase3f-story-matrix.md`. **Required delta:** None. **Acceptance check:** No diff. **Owner:** Release Quality Lead. **Approver:** Product and Architecture Lead for a scope-change PR.
- **Operation:** Create. **Exact paths:** `CHANGELOG.md`; `docs/05-planning/app-store-privacy-disclosure.md`; `docs/05-planning/phase3f-release-checklist.md`. **Required delta:** Record user-visible Phase 3F changes; exact App Store data-collection/disclosure answers and external privacy-policy version; release checklist fields for signing approver, evidence location, artifact digest, retention rule and expiry date; complete executable-target inventory and per-target `Echo`/`EchoShareExtension` networking, linked-SDK, secret, entitlement, privacy-manifest, required-reason API and purpose-string results. **Acceptance check:** Privacy manifest, App Store answers and policy version are mutually consistent; every checklist field is populated; every executable app/extension target has a named report; Release Manager and Privacy Engineering Lead approve the inventory and findings. **Owner:** Release Quality Lead. **Approver:** Release Manager and Privacy Engineering Lead.
- **Operation:** Finalize, do not create. **Exact path:** `docs/05-planning/phase3f-evidence-index.md`. **Required delta:** Add all pre-merge 3F.11 logs, artifact digests, PR head SHA, gate results, P0/P1 counts and approver records. Leave `merge_sha`, final `done` state and Phase 4 unlock empty until the human-triggered finalizer runs. **Acceptance check:** Evidence index existed since 3F.0, contains entries from every 3F.1 through 3F.10 PR, and labels 3F.11 as pre-merge review. **Owner:** Release Quality Lead. **Approver:** Release Manager and Privacy Engineering Lead.

## 5. 当前可直接使用的接口

不得改名后让后续任务猜测。3F.0 若批准破坏性变更，必须在 ADR 中给出旧→新迁移表并同步所有调用者。

```
public func DatabaseManager.open() async throws
public func PrivacyActor.loadPolicy() async throws
public func PrivacyActor.getPolicy() async -> UserPolicy
public func PrivacyActor.updatePolicy(_ newPolicy: UserPolicy) async throws
public func PrivacyActor.validate(
    operation: PrivacyOperation,
    traceID: String,

    sourceTypes: [String] = [ ]

) async -> PrivacyCheckpoint

public protocol EmbedderProtocol: Sendable {
    func embedImage(assetId: String) async throws -> [Float]
    func embedText(_ text: String) async throws -> [Float]
}

public protocol ASREngineProtocol: Sendable {
    func transcribe(audioTrackAssetId: String) async throws -> String
}

public func IngestPipeline.ingestImage(
    assetId: String,
    exifMetadata: Data? = nil,
    traceID: String = UUID().uuidString
) async throws -> MemoryEntry
public func IngestPipeline.ingestVideo(
    assetId: String,
    frameAssetIds: [String],
    audioTrackAssetId: String? = nil,
    traceID: String = UUID().uuidString
) async throws -> [MemoryEntry]
public func IngestPipeline.ingestText(
    text: String,
    sourceLanguage: String,
    sourceId: String,
    traceID: String = UUID().uuidString
) async throws -> MemoryEntry
public func IngestPipeline.ingestVoice(
    audioAssetId: String,
    sourceLanguage: String? = nil,
    transcriptConfidence: Float? = nil,
    traceID: String = UUID().uuidString
) async throws -> MemoryEntry

public func SearchPipeline.search(
    query: String,
    k: Int = 10,
    filter: SearchFilter? = nil,
    traceID: String = UUID().uuidString
) async throws -> [SearchResultItem]

public func FeedbackPipeline.recordLike(
    memoryId: UUID,
    queryText: String,
    cosineSimilarity: Double,
    traceID: String = UUID().uuidString
) async throws -> FeedbackEntry
public func FeedbackPipeline.recordDislike(
    memoryId: UUID,
    queryText: String,
    cosineSimilarity: Double,
    traceID: String = UUID().uuidString
) async throws -> FeedbackEntry
public func FeedbackPipeline.markBadCase(
    memoryId: UUID,
    queryText: String,
    reason: String? = nil,
    cosineSimilarity: Double = 0.0,
    traceID: String = UUID().uuidString
) async throws -> FeedbackEntry

public func GenerationRegistryActor.registerGeneration(
    _ generation: IndexGeneration
) async throws
public func GenerationRegistryActor.vectorStore(
    for generationId: String
) -> VectorStoreActor?
public func GenerationRegistryActor.publishRoute(
    _ route: ActiveRouteSet
) async throws
public func GenerationRegistryActor.loadActiveRoute() async throws -> ActiveRouteSet?

public func AwakeningPipeline.handleGeofenceEnter(
    regionId: String,
    traceID: String = UUID().uuidString
) async -> AwakeningEnterResult

public protocol HealthKitProvider: AnyObject, Sendable {
    func isHealthDataAvailable() -> Bool
    func requestAuthorization() async -> Bool
    func inferMoodFromHRV() async -> MoodState?
}
public protocol SentimentProvider: AnyObject, Sendable {
    func analyzeSentiment(queries: [String], feelings: [String]) async -> MoodState?
}
protocol TranslationService: Sendable {
    func translate(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> TranslationResult
}
```

## 6. 全局验证与交付协议

### 6.1 每个任务的固定验证顺序

1. focused：把当前任务表中的 suite 名写入 `FOCUSED_SUITE`，运行下面完整命令，不得只复制参数片段：

```
xcodebuild test \
  -project Echo.xcodeproj \
  -scheme Echo \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:"$FOCUSED_SUITE"
```

`FOCUSED_SUITE` 必须是 `EchoTests/ProductionCompositionTests`、`EchoTests/RealDataSourcesTests`、`EchoTests/ProductionModelInferenceTests`、`EchoTests/CanonicalGenerationTests`、`EchoTests/ProductionIngestionTests`、`EchoTests/ProductionSearchFeedbackTests`、`EchoTests/CrossAppSearchTests`、`EchoTests/UIToCoreIntegrationTests`、`EchoTests/DeviceMigrationTests`、`EchoTests/DeviceMigrationSecurityTests`、`EchoTests/DataOverviewTests`、`EchoTests/AwakeningSystemAdaptersTests`、`EchoTests/CrossAppHealthIntegrationTests`、`EchoTests/TranslationCreationTests`、`EchoTests/LocalizationAccessibilityErrorTests` 或 `EchoTests/Phase3FIntegrationTests` 之一。3F.0 是 docs-only，没有 focused source test。3F.6、3F.7、3F.8 必须按各自任务章节逐 suite 独立运行完整命令并在实现前全部观察 RED；每次 focused run 的 XCTest summary 必须报告 executed test count > 0，suite empty、suite not found 或 executed count 0 均视为命令失败而非 RED。UI production E2E 使用同一完整模板，把最后一行替换为 `-only-testing:EchoUITests/Phase3FProductionE2ETests`。 2. cumulative：运行本节下方的完整累计单元/集成测试命令，必须串行。 3. UI 变更：先用完整模板运行受影响的精确 `EchoUITests/<SuiteName>`，再用本节下方的完整全量 UI 命令。 4. Release simulator：`xcodebuild build -project Echo.xcodeproj -scheme Echo -configuration Release -destination 'generic/platform=iOS Simulator'`。 5. Release device compile：`xcodebuild build -project Echo.xcodeproj -scheme Echo -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`；需要签名的 archive 证据仅在受控 release 环境生成。 6. 静态门禁：SwiftLint、strict concurrency、PrivacyCheckpoint、禁用 API/网络扫描与 planning ledger validator。 7. 3F.11 执行完整 no-fixture、coverage、合规与签名检查。

所有 `xcodebuild test` 命令都必须完整包含 project、scheme、configuration、destination、串行参数和精确 suite。禁止发布仅含参数碎片的命令。

累计单元/集成测试使用：

```
xcodebuild test \
  -project Echo.xcodeproj \
  -scheme Echo \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:EchoTests
```

全量 UI 测试使用同一命令，把最后一行替换为 `-only-testing:EchoUITests`。受影响 UI suite 必须使用同一完整命令模板和一个精确 `EchoUITests/<SuiteName>` 值。

### 6.2 每任务 branch setup 与 delivery

3F.0 先在 `AGENTS.md` 明确多故事阶段任务可用任务 ID 代替单一 US ID。每个任务从下表复制 Task 列到 `TASK_ID`，并复制同一行四个精确值到 `BRANCH`、`COMMIT_SUBJECT`、`PR_TITLE`、`RELATED_STORIES`。`RELATED_STORIES` 必须保持英文标识格式，不得省略或改写为中文。

| Task  | BRANCH                                        | COMMIT_SUBJECT                                          | PR_TITLE                                                     | RELATED_STORIES                                              |
| ----- | --------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| 3F.0  | `docs/phase3f-spec-ledger-3F.0`               | `docs(docs): define phase 3f execution contracts`       | `docs(docs): define Phase 3F contracts [3F.0]`               | `US-SRC-002, US-SRC-006, US-ING-001, US-ING-002, US-ING-003, US-ING-004, US-RET-003, US-RET-004, US-SYN-003, US-SYN-004, US-AWK-002, US-PRV-003, US-PRV-005, US-PRV-007` |
| 3F.1  | `feature/phase3f-production-composition-3F.1` | `feat(config): add production app composition`          | `feat(config): add production app composition [3F.1]`        | `US-PRV-001, US-PRV-004, US-PRV-005, US-PRV-006, US-PRV-008, US-SRC-001, US-RES-004` |
| 3F.2  | `feature/phase3f-real-data-sources-3F.2`      | `feat(pipeline): add production data sources`           | `feat(pipeline): add production data sources [3F.2]`         | `US-SRC-001, US-SRC-003, US-SRC-004, US-SRC-005, US-SRC-008, US-SRC-012, US-SRC-013, US-PRV-001` |
| 3F.3  | `feature/phase3f-production-models-3F.3`      | `feat(service): add offline production inference`       | `feat(service): add offline production inference [3F.3]`     | `US-ING-001, US-ING-002, US-ING-003, US-ING-004, US-ING-005, US-RET-001, US-RET-002, US-RET-006, US-RES-001, US-RES-004, US-SRC-011` |
| 3F.4  | `feature/phase3f-canonical-generations-3F.4`  | `feat(actor): add canonical generation lifecycle`       | `feat(actor): add canonical generation lifecycle [3F.4]`     | `US-ING-006, US-PRV-004, US-PRV-006, US-PRV-007, US-AWK-007, US-FBK-001, US-FBK-002, US-FBK-003` |
| 3F.5  | `feature/phase3f-production-ingestion-3F.5`   | `feat(pipeline): add production ingestion`              | `feat(pipeline): add production ingestion [3F.5]`            | `US-ING-001, US-ING-002, US-ING-003, US-ING-004, US-ING-005, US-ING-006, US-SRC-012, US-SRC-013, US-SYS-001, US-RES-001, US-RES-002, US-RES-003, US-RES-004` |
| 3F.6  | `feature/phase3f-search-feedback-3F.6`        | `feat(pipeline): add production search feedback`        | `feat(pipeline): add production search and feedback [3F.6]`  | `US-RET-001, US-RET-002, US-RET-003, US-RET-004, US-RET-005, US-RET-006, US-RET-007, US-RET-008, US-FBK-001, US-FBK-002, US-FBK-003, US-PRV-001, US-SRC-010, US-SRC-011` |
| 3F.7  | `feature/phase3f-ui-core-wiring-3F.7`         | `feat(viewmodel): wire live core adapters`              | `feat(viewmodel): wire live Core adapters [3F.7]`            | `US-AWK-005, US-AWK-007, US-PRV-002, US-PRV-003, US-PRV-004, US-SYS-001, US-SET-001, US-SET-002, US-SET-003, US-SET-004, US-RES-001, US-RES-002, US-RES-003, US-RES-004, US-SRC-007, US-SRC-009` |
| 3F.8  | `feature/phase3f-awakening-adapters-3F.8`     | `feat(pipeline): add awakening system adapters`         | `feat(pipeline): add awakening system adapters [3F.8]`       | `US-AWK-001, US-AWK-002, US-AWK-003, US-AWK-005, US-SRC-010` |
| 3F.9  | `feature/phase3f-translation-creation-3F.9`   | `feat(service): add translation and creation`           | `feat(service): add translation and creation [3F.9]`         | `US-DIS-002, US-SYN-001, US-SYN-002, US-SYN-003, US-SYN-004, US-SYN-005, US-SYN-006, US-SYN-007, US-SYN-008` |
| 3F.10 | `feature/phase3f-i18n-accessibility-3F.10`    | `feat(view): add production localization accessibility` | `feat(view): add production localization and accessibility [3F.10]` | `US-DIS-001, US-DIS-003, US-DIS-004, US-SET-001, US-RES-001, US-RES-002, US-RES-003, US-RES-004, US-SYS-001, US-SRC-009` |
| 3F.11 | `test/phase3f-production-gate-3F.11`          | `test(config): add phase 3f production gate`            | `test(config): add Phase 3F production gate [3F.11]`         | `3F.11, US-SRC-010`                                          |

#### 6.2.1 Branch/worktree setup（仅 preflight）

> 🔧 **修订（人类批准 2026-08-04，记录于 AGENTS.md §17.9）**：本 worktree setup **仅适用于 `3F.0` bootstrap**（已执行完毕）。`3F.1` 至 `3F.11` 在**主仓库内普通分支**执行（`git checkout -b {type}/{description}-US-XXX`），**不再创建 worktree**，不再运行本脚本；§6.2.2 交付脚本继续使用，其 `PHASE3F_WORKTREE_PATH` 设为主仓库根路径（workdir/root 守卫等效通过）。

下列脚本是 task ledger transition 之前的 environment setup。必须从 clean repository root 运行；它只执行 guard、fetch、registered worktree ownership validation、`git worktree add`/reuse 与 task-worktree rebase，不 stage、commit、push 或创建/更新 PR。`3F.0` 还必须由目标机器上的人类先提供 §1.1 三个显式授权值。技能缺失不影响此 fallback。

```
set -euo pipefail
: "${TASK_ID:?STOP: TASK_ID is required}"
: "${BRANCH:?STOP: BRANCH is required}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
test "$PWD" = "$REPO_ROOT" || {
  echo "STOP: run worktree setup from repository root $REPO_ROOT" >&2
  exit 1
}
test "$(git rev-parse --is-inside-work-tree)" = "true"
test -z "$(git status --porcelain)" || {
  echo "STOP: repository root has uncommitted or untracked work" >&2
  exit 1
}
git fetch origin
git show-ref --verify --quiet refs/remotes/origin/dev-1.0 || {
  echo "STOP: origin/dev-1.0 does not exist after fetch" >&2
  exit 1
}

case "$TASK_ID" in
  *[!A-Za-z0-9._-]*|'')
    echo "STOP: TASK_ID cannot form a safe worktree directory name" >&2
    exit 1
    ;;
esac
SAFE_TASK_ID="$TASK_ID"

if test "$TASK_ID" = "3F.0"; then
  : "${PHASE3F_BOOTSTRAP_AUTHORIZATION:?STOP: human bootstrap authorization is required}"
  : "${PHASE3F_BOOTSTRAP_AUTHORIZED_BY:?STOP: human bootstrap approver is required}"
  : "${PHASE3F_BOOTSTRAP_AUTHORIZED_AT:?STOP: bootstrap authorization time is required}"
  test "$PHASE3F_BOOTSTRAP_AUTHORIZATION" = "human-approved-docs-only" || {
    echo "STOP: bootstrap authorization is not docs-only" >&2
    exit 1
  }
  test "$BRANCH" = "docs/phase3f-spec-ledger-3F.0" || {
    echo "STOP: 3F.0 bootstrap branch does not match the authorized branch" >&2
    exit 1
  }
fi

BRANCH_REF="refs/heads/$BRANCH"
export REPO_ROOT BRANCH_REF

WORKTREE_PATH="$(python3 - <<'PY'
import os
import stat
import subprocess
from pathlib import Path

branch_ref = os.environ["BRANCH_REF"]
result = subprocess.run(
    ["git", "worktree", "list", "--porcelain"],
    check=True,
    text=True,
    capture_output=True,
)

records = [ ]

record = {}
for line in result.stdout.splitlines() + [""]:
    if not line:
        if record:
            records.append(record)
            record = {}
        continue
    key, _, value = line.partition(" ")
    record[key] = value

matches = [item for item in records if item.get("branch") == branch_ref]
if len(matches) > 1:
    raise SystemExit(
        f"STOP: branch {branch_ref} is registered to more than one worktree"
    )
if not matches:
    print("")
    raise SystemExit(0)

raw = Path(matches[0]["worktree"])
raw_stat = os.lstat(raw)
if stat.S_ISLNK(raw_stat.st_mode):
    raise SystemExit(f"STOP: registered worktree path is a symlink: {raw}")
canonical = raw.resolve(strict=True)
canonical_stat = os.lstat(canonical)
if not stat.S_ISDIR(canonical_stat.st_mode):
    raise SystemExit(f"STOP: registered worktree path is not a directory: {canonical}")
if canonical_stat.st_uid != os.getuid():
    raise SystemExit(f"STOP: registered worktree has wrong owner: {canonical}")
print(canonical)
PY
)"

PRIVATE_WORKTREE_BASE=""
WORKTREE_CREATED="false"
if test -z "$WORKTREE_PATH"; then
  PRIVATE_WORKTREE_BASE="$(python3 - <<'PY'
import os
import stat
import tempfile
from pathlib import Path

base = Path(tempfile.mkdtemp(prefix="echo-phase3f-worktree-"))
os.chmod(base, 0o700)
base_stat = os.lstat(base)
if stat.S_ISLNK(base_stat.st_mode):
    raise SystemExit(f"STOP: private worktree base is a symlink: {base}")
if not stat.S_ISDIR(base_stat.st_mode):
    raise SystemExit(f"STOP: private worktree base is not a directory: {base}")
if base_stat.st_uid != os.getuid():
    raise SystemExit(f"STOP: private worktree base has wrong owner: {base}")
if stat.S_IMODE(base_stat.st_mode) != 0o700:
    raise SystemExit(f"STOP: private worktree base mode is not 0700: {base}")
print(base.resolve(strict=True))
PY
)"
  export PRIVATE_WORKTREE_BASE
  WORKTREE_PATH="$PRIVATE_WORKTREE_BASE/$SAFE_TASK_ID"
  export WORKTREE_PATH
  python3 - <<'PY'
import os
import stat
from pathlib import Path

base = Path(os.environ["PRIVATE_WORKTREE_BASE"]).resolve(strict=True)
target = Path(os.environ["WORKTREE_PATH"])
if target.parent != base:
    raise SystemExit("STOP: task worktree is not a direct child of the private base")

for component in (base, target):
    try:
        component_stat = os.lstat(component)
    except FileNotFoundError:
        continue
    if stat.S_ISLNK(component_stat.st_mode):
        raise SystemExit(f"STOP: symlink component under private base: {component}")
    if component_stat.st_uid != os.getuid():
        raise SystemExit(f"STOP: wrong-owner component under private base: {component}")
if os.path.lexists(target):
    raise SystemExit(f"STOP: new task worktree path already exists: {target}")
PY

  if git show-ref --verify --quiet "$BRANCH_REF"; then
  git worktree add "$WORKTREE_PATH" "$BRANCH"
  elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    git worktree add --track -b "$BRANCH" "$WORKTREE_PATH" "origin/$BRANCH"
  else
    git worktree add -b "$BRANCH" "$WORKTREE_PATH" origin/dev-1.0
  fi
  WORKTREE_CREATED="true"
fi

export WORKTREE_PATH WORKTREE_CREATED
python3 - <<'PY'
import os
import stat
import subprocess
from pathlib import Path

target = Path(os.environ["WORKTREE_PATH"]).resolve(strict=True)
branch_ref = os.environ["BRANCH_REF"]
target_stat = os.lstat(target)
if stat.S_ISLNK(target_stat.st_mode):
    raise SystemExit(f"STOP: task worktree path is a symlink: {target}")
if not stat.S_ISDIR(target_stat.st_mode):
    raise SystemExit(f"STOP: task worktree path is not a directory: {target}")
if target_stat.st_uid != os.getuid():
    raise SystemExit(f"STOP: task worktree has wrong owner: {target}")
try:
    os.chmod(target, 0o700)
    target_stat = os.lstat(target)
except OSError as error:
    raise SystemExit(f"STOP: cannot harden or stat task worktree {target}: {error}") from error
if stat.S_ISLNK(target_stat.st_mode):
    raise SystemExit(f"STOP: task worktree became a symlink after chmod: {target}")
if not stat.S_ISDIR(target_stat.st_mode):
    raise SystemExit(f"STOP: task worktree is not a directory after chmod: {target}")
if target_stat.st_uid != os.getuid():
    raise SystemExit(f"STOP: task worktree owner changed after chmod: {target}")
if (target_stat.st_mode & 0o077) != 0:
    raise SystemExit(f"STOP: task worktree mode is broader than 0700: {target}")

if os.environ["WORKTREE_CREATED"] == "true":
    base = Path(os.environ["PRIVATE_WORKTREE_BASE"]).resolve(strict=True)
    if target.parent != base:
        raise SystemExit("STOP: created worktree escaped its private base")
    for component in (base, target):
        component_stat = os.lstat(component)
        if stat.S_ISLNK(component_stat.st_mode):
            raise SystemExit(f"STOP: symlink component after worktree add: {component}")
        if component_stat.st_uid != os.getuid():
            raise SystemExit(f"STOP: wrong-owner component after worktree add: {component}")
        if component == base and stat.S_IMODE(component_stat.st_mode) != 0o700:
            raise SystemExit(f"STOP: private base mode changed from 0700: {base}")

result = subprocess.run(
    ["git", "worktree", "list", "--porcelain"],
    check=True,
    text=True,
    capture_output=True,
)

records = [ ]

record = {}
for line in result.stdout.splitlines() + [""]:
    if not line:
        if record:
            records.append(record)
            record = {}
        continue
    key, _, value = line.partition(" ")
    record[key] = value
matches = [item for item in records if item.get("branch") == branch_ref]
if len(matches) != 1:
    raise SystemExit(f"STOP: expected exactly one registered worktree for {branch_ref}")
registered = Path(matches[0]["worktree"]).resolve(strict=True)
if registered != target:
    raise SystemExit(
        f"STOP: registered worktree path mismatch: expected {target}, got {registered}"
    )
print(target)
PY

test "$(git -C "$WORKTREE_PATH" symbolic-ref --short HEAD)" = "$BRANCH" || {
  echo "STOP: registered worktree does not own $BRANCH" >&2
  exit 1
}
test -z "$(git -C "$WORKTREE_PATH" status --porcelain)" || {
  echo "STOP: task worktree is not clean before rebase" >&2
  exit 1
}
if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  git -C "$WORKTREE_PATH" rebase "origin/$BRANCH"
fi
git -C "$WORKTREE_PATH" rebase origin/dev-1.0
test -z "$(git -C "$WORKTREE_PATH" status --porcelain)" || {
  echo "STOP: prepared task worktree is not clean" >&2
  exit 1
}

PHASE3F_WORKTREE_PATH="$WORKTREE_PATH"
export PHASE3F_WORKTREE_PATH
cd "$PHASE3F_WORKTREE_PATH"
printf 'PHASE3F_WORKTREE_PATH=%s\n' "$PHASE3F_WORKTREE_PATH"
```

任何 ownership ambiguity、`git worktree add` 或 `rebase` 冲突都因 `set -euo pipefail` 立即停止并保留现场。禁止 `checkout -f`、`reset --hard`、`clean`、强推、删除分支或删除 worktree。Agent 必须记录脚本打印的绝对 `PHASE3F_WORKTREE_PATH`；从此处开始，当前任务的每个 file/tool/Git/Python/build/test 命令都必须把该路径设为 working directory。禁止切换或修改 main worktree branch。

#### 6.2.2 Delivery（仅实现与全部验证完成后）

只有当前任务实现完成、§6.1 全部适用验证通过、文档合同完成、evidence index 已更新且当前任务的 §11.1 PR-body marker block 已由真实 AC/证据结果完整填充后，才运行下列唯一脚本。必须在 §6.2.1 打印的 task worktree 中运行。脚本以 fail-closed 顺序完成 intended/staged checks、PR-body extraction/validation、implementation commit/push、PR create/update、task-status ledger commit/push、本地 PR body ledger insertion/revalidation 与最终 PR edit；禁止拆分执行或在失败后续跑。

```
set -euo pipefail
: "${TASK_ID:?STOP: TASK_ID is required}"
: "${BRANCH:?STOP: BRANCH is required}"
: "${COMMIT_SUBJECT:?STOP: COMMIT_SUBJECT is required}"
: "${PR_TITLE:?STOP: PR_TITLE is required}"
: "${RELATED_STORIES:?STOP: RELATED_STORIES is required}"
: "${PHASE3F_WORKTREE_PATH:?STOP: PHASE3F_WORKTREE_PATH is required}"

test "$PWD" = "$PHASE3F_WORKTREE_PATH" || { echo "STOP: workdir" >&2; exit 1; }
test "$(git rev-parse --show-toplevel)" = "$PHASE3F_WORKTREE_PATH" || { echo "STOP: root" >&2; exit 1; }
test "$(git symbolic-ref --short HEAD)" = "$BRANCH" || { echo "STOP: branch" >&2; exit 1; }
if test "$TASK_ID" = "3F.0"; then
  : "${PHASE3F_BOOTSTRAP_AUTHORIZATION:?STOP: bootstrap auth}"
  : "${PHASE3F_BOOTSTRAP_AUTHORIZED_BY:?STOP: bootstrap approver}"
  : "${PHASE3F_BOOTSTRAP_AUTHORIZED_AT:?STOP: bootstrap time}"
  test "$PHASE3F_BOOTSTRAP_AUTHORIZATION" = "human-approved-docs-only"
fi

TASK_STATUS_PATH=docs/05-planning/task-status.json
EVIDENCE_INDEX_PATH=docs/05-planning/phase3f-evidence-index.md
COMMIT_MESSAGE_FILE=""
LEDGER_COMMIT_MESSAGE_FILE=""
PR_BODY_FILE=""
VALIDATOR_FILE=""
cleanup() { for f in "$COMMIT_MESSAGE_FILE" "$LEDGER_COMMIT_MESSAGE_FILE" "$PR_BODY_FILE" "$VALIDATOR_FILE"; do test -z "$f" || rm -f -- "$f" || true; done; }
trap cleanup EXIT

COMMIT_MESSAGE_FILE="$(mktemp -t echo-phase3f-commit.XXXXXX)"
LEDGER_COMMIT_MESSAGE_FILE="$(mktemp -t echo-phase3f-ledger-commit.XXXXXX)"
PR_BODY_FILE="$(mktemp -t echo-phase3f-pr-body.XXXXXX)"
VALIDATOR_FILE="$(mktemp -t echo-phase3f-validator.XXXXXX)"
chmod 600 "$COMMIT_MESSAGE_FILE" "$LEDGER_COMMIT_MESSAGE_FILE" "$PR_BODY_FILE" "$VALIDATOR_FILE"
cat >"$VALIDATOR_FILE" <<'PY'
import os,re,stat,sys
from pathlib import Path
p=Path(sys.argv[1]); b=p.read_text(encoding="utf-8").strip()
def bad(s): raise SystemExit("STOP: "+s)
if not b: bad("empty body")
if stat.S_IMODE(p.stat().st_mode)!=0o600: bad("body mode")
if "<!-- PR-BODY:" in b: bad("nested marker")
h=("## Overview","## Related Specs","## AC Coverage","## Testing","## Documentation and Ledger","## Risks","## Deferred Items","## Self-Check")

m=[ ]

for x in h:
 q=list(re.finditer(rf"(?m)^{re.escape(x)}[ \t]*$",b))
 if len(q)!=1: bad("heading "+x)
 m.append(q[0])
if [x.start() for x in m]!=sorted(x.start() for x in m): bad("heading order")
for i,x in enumerate(m):
 if not b[x.end():(m[i+1].start() if i+1<len(m) else len(b))].strip(): bad("empty section")
a="| AC # | Spec Summary | Test File | Implementation | Status |"
if b.count(a)!=1 or a not in b[m[2].end():m[3].start()]: bad("AC table")
x=re.compile(r"(?i)\b(?:TODO|TBD|TBC|FIXME|PLACEHOLDER)\b|\[[^\]\n]*(?:insert|fill|describe|brief|replace|pending|placeholder|todo|tbd|xxx)[^\]\n]*\]|\[(?:\.{3}|…)\]|<[^>\n]+>|\{\{[^{}\n]+\}\}")
if x.search(b): bad("placeholder")
if len(sys.argv)>2:
 if b.count("## Task Ledger")!=1: bad("ledger count")
 for line in (f'- Task: {os.environ["TASK_ID"]}',"- Status: review",f'- PR: {os.environ["PR_URL"]}',f'- Head: {os.environ["BRANCH"]}',"- Base: dev-1.0",f'- Ledger commit: {os.environ["LEDGER_COMMIT"]}'):
  if b.count(line)!=1: bad("ledger field")
PY

test -n "$(git status --porcelain)" || { echo "STOP: no changes" >&2; exit 1; }
git add -p
test -n "$(git diff --cached --name-only)" || { echo "STOP: no staged files" >&2; exit 1; }
git diff --cached --check
{
  printf '%s\n\n' "$COMMIT_SUBJECT"
  printf 'Task: %s\n\n' "$TASK_ID"
  printf 'Related: %s\n' "$RELATED_STORIES" | fold -s -w 72
  printf '\nAC coverage: Complete.\n'
  printf 'Each listed AC has a test and implementation.\n'
  printf 'Approved scope decisions are recorded where applicable.\n'
  printf '\nEvidence: Indexed in the PR body.\n'
  printf 'Focused, cumulative, Release, static, and privacy gates passed.\n'
} > "$COMMIT_MESSAGE_FILE"
test "$(git diff --cached --name-only -- "$EVIDENCE_INDEX_PATH")" = "$EVIDENCE_INDEX_PATH" || { echo "STOP: evidence not staged" >&2; exit 1; }
test -z "$(git diff --name-only -- "$EVIDENCE_INDEX_PATH")" || { echo "STOP: evidence unstaged" >&2; exit 1; }
export TASK_ID TASK_STATUS_PATH EVIDENCE_INDEX_PATH PR_BODY_FILE
python3 - <<'PY'
import json
import os
from pathlib import Path

task_id = os.environ["TASK_ID"]
evidence_path = Path(os.environ["EVIDENCE_INDEX_PATH"])
body_path = Path(os.environ["PR_BODY_FILE"])
text = evidence_path.read_text(encoding="utf-8")
task_status = json.loads(Path(os.environ["TASK_STATUS_PATH"]).read_text(encoding="utf-8"))
start_marker = f"<!-- PR-BODY:{task_id}:START -->"
end_marker = f"<!-- PR-BODY:{task_id}:END -->"

def find(v):
    if isinstance(v,dict):

        return ([v] if v.get("id")==task_id and "status" in v else [ ])+sum((find(x) for x in v.values()),[ ])


    if isinstance(v,list): return sum((find(x) for x in v),[ ])


    return [ ]

m=find(task_status); expected="review" if task_id=="3F.0" else "in_progress"
if len(m)!=1 or m[0].get("status")!=expected: raise SystemExit("STOP: task state")
if text.count(start_marker)!=1 or text.count(end_marker)!=1: raise SystemExit("STOP: marker count")
start=text.index(start_marker)+len(start_marker); end=text.index(end_marker)
if end<=start: raise SystemExit("STOP: marker order")
body=text[start:end].strip()
if not body: raise SystemExit("STOP: empty marker body")
if "<!-- PR-BODY:" in body: raise SystemExit("STOP: nested marker")

os.chmod(body_path, 0o600)
body_path.write_text(f"{body}\n", encoding="utf-8")
if body_path.stat().st_size == 0:
    raise SystemExit(f"STOP: PR body file is empty for {task_id}")
PY
python3 "$VALIDATOR_FILE" "$PR_BODY_FILE"
git commit -F "$COMMIT_MESSAGE_FILE"
git push -u origin "$BRANCH"
PR_COUNT="$(gh pr list --base dev-1.0 --head "$BRANCH" --state open \
  --json number --jq 'length')"
case "$PR_COUNT" in
  0|1) ;;
  *) echo "STOP: expected zero or one open PR, found $PR_COUNT" >&2; exit 1 ;;
esac
if test "$PR_COUNT" = "1"; then
  PR_NUMBER="$(gh pr list --base dev-1.0 --head "$BRANCH" --state open \
    --json number --jq '.[0].number')"
  PR_URL="$(gh pr list --base dev-1.0 --head "$BRANCH" --state open \
    --json url --jq '.[0].url')"
  gh pr edit "$PR_NUMBER" --title "$PR_TITLE" --body-file "$PR_BODY_FILE"
else
  PR_URL="$(gh pr create --base dev-1.0 --head "$BRANCH" \
    --title "$PR_TITLE" --body-file "$PR_BODY_FILE")"
  PR_NUMBER="${PR_URL##*/}"
fi
case "$PR_NUMBER" in
  ''|*[!0-9]*) echo "STOP: cannot parse PR number from $PR_URL" >&2; exit 1 ;;
esac
LAST_UPDATED="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
export TASK_ID BRANCH RELATED_STORIES PR_URL PR_NUMBER TASK_STATUS_PATH LAST_UPDATED
python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["TASK_STATUS_PATH"])
data = json.loads(path.read_text(encoding="utf-8"))
def find(v):
    if isinstance(v,dict):

        return ([v] if v.get("id")==os.environ["TASK_ID"] and "status" in v else [ ])+sum((find(x) for x in v.values()),[ ])


    if isinstance(v,list): return sum((find(x) for x in v),[ ])


    return [ ]

matches=find(data)
if len(matches)!=1: raise SystemExit("STOP: task record")
task=matches[0]
task["status"] = "review"
task["last_updated"] = os.environ["LAST_UPDATED"]
task["pr"] = {
    "number": int(os.environ["PR_NUMBER"]),
    "url": os.environ["PR_URL"],
    "head": os.environ["BRANCH"],
    "base": "dev-1.0",
}
path.write_text(
    json.dumps(data, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
python3 -m json.tool "$TASK_STATUS_PATH" >/dev/null
git add -- "$TASK_STATUS_PATH"
test "$(git diff --cached --name-only)" = "$TASK_STATUS_PATH" || {
  echo "STOP: ledger commit contains a file other than $TASK_STATUS_PATH" >&2
  git diff --cached --name-only >&2
  exit 1
}
git diff --cached --check
git diff --cached -- "$TASK_STATUS_PATH"
{
  printf 'chore(config): record %s review state\n\n' "$TASK_ID"
  printf 'Task: %s\n' "$TASK_ID"
  printf 'Related: %s\n' "$RELATED_STORIES" | fold -s -w 72
} > "$LEDGER_COMMIT_MESSAGE_FILE"
git commit -F "$LEDGER_COMMIT_MESSAGE_FILE"
git push origin "$BRANCH"
LEDGER_COMMIT="$(git rev-parse HEAD)"
export PR_BODY_FILE LEDGER_COMMIT
python3 - <<'PY'
import os
import re
from pathlib import Path

body_path = Path(os.environ["PR_BODY_FILE"])
body = body_path.read_text(encoding="utf-8").rstrip()
body = re.sub(
    r"\n## Task Ledger\n.*?(?=\n## |\Z)",
    "",
    body,
    flags=re.DOTALL,
).rstrip()
ledger = "\n".join(
    [
        "## Task Ledger",
        f'- Task: {os.environ["TASK_ID"]}',
        "- Status: review",
        f'- PR: {os.environ["PR_URL"]}',
        f'- Head: {os.environ["BRANCH"]}',
        "- Base: dev-1.0",
        f'- Ledger commit: {os.environ["LEDGER_COMMIT"]}',
    ]
)
body = f"{body}\n\n{ledger}\n"

body_path.write_text(body, encoding="utf-8")
os.chmod(body_path, 0o600)
if body_path.stat().st_size == 0:
    raise SystemExit("STOP: PR body is empty after ledger insertion")
PY
python3 "$VALIDATOR_FILE" "$PR_BODY_FILE" ledger
gh pr edit "$PR_NUMBER" --body-file "$PR_BODY_FILE"
```

PR body 必须为英文，并在 evidence index 当前任务条目中使用 §11.1 的精确 marker pair；正文必须依次包含 `## Overview`、`## Related Specs`、`## AC Coverage`、`## Testing`、`## Documentation and Ledger`、`## Risks`、`## Deferred Items`、`## Self-Check`，以及精确 AC table header `| AC # | Spec Summary | Test File | Implementation | Status |`。所有内容必须来自当前任务真实结果。脚本从不重新加载可变 remote PR body；ledger refresh 只修改此前已验证的本地 `PR_BODY_FILE`，再次验证后才 final edit。`3F.0` pre-merge delivery 仅限目标机器人类显式授权的 docs-only bootstrap PR；3F.1 至 3F.11 standing automatic authority 仅在 3F.0 人类合并后生效。完成后等待人类合并，绝不自动 merge、关闭 PR、删除分支或删除 worktree。

## 7. Phase 3F 任务执行

### 3F.0: 规格、范围、账本与接口冻结

**Files**

- Modify: `AGENTS.md`; `README.md`; `docs/INDEX.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/技术选型文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/04-ai-native/产品创新工具全景指南.md`; `docs/05-planning/开发计划安排文档.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`; `docs/ui/README.md`; `docs/ui/architecture.md`; `docs/ui/automation-workflow.md`; `docs/ui/testing-and-artifacts.md`; `docs/ui/command-compatibility.md`; `docs/ui/echo-readiness.md`; `docs/ui/echo-memory-canvas-style.md`; `UIAutomation/Policies/README.md`; `UIAutomation/Policies/acceptance-policy.json`; `UIAutomation/Policies/protected-paths.json`; `UIAutomation/Policies/retry-policy.json`; `.opencode/commands/init-session-echo.md`; `.opencode/commands/next-task-echo.md`; `.opencode/commands/do-task-echo.md`; `.opencode/commands/status-echo.md`; `.opencode/commands/test-phase-echo.md`; `.opencode/commands/test-integration-echo.md`; `.opencode/commands/test-unit-echo.md`; `.opencode/commands/read-spec-echo.md`; `.opencode/commands/retry-task-echo.md`; `.opencode/commands/commit-pr-echo.md`; `.opencode/commands/pr-review-echo.md`; `.opencode/commands/pr-merge-echo.md`; `.opencode/commands/ui-bootstrap-build-echo.md`; `.opencode/commands/ui-status-echo.md`; `.opencode/commands/ui-retry-echo.md`; `.opencode/commands/sync-docs-echo.md`; `.ui-automation/state.schema.json`.
- Create: `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-story-matrix.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/decisions/ADR-006-phase3f-scope-contracts.md`; `docs/decisions/ADR-007-production-composition-consent.md`; `docs/decisions/ADR-008-source-import-boundaries.md`; `docs/decisions/ADR-009-offline-model-runtime.md`; `docs/decisions/ADR-010-canonical-generation-lifecycle.md`; `docs/decisions/ADR-011-task-progress-boundary.md`; `docs/decisions/ADR-012-awakening-system-boundary.md`; `docs/decisions/ADR-013-creation-export-boundary.md`; `docs/decisions/ADR-014-release-compliance-boundary.md`.
- Test: no source or test file may be created or changed. Validate JSON syntax with `python3 -m json.tool`, inspect exact-ID and graph invariants in the PR diff, and let existing documentation/ledger CI run unchanged.

**Interfaces**

- Consumes: current ledger shape, 66-story spec, the complete calibrated mapping embedded in Appendix C, interfaces in §5.
- Produces: approved exact signatures and exact source/test file paths for App composition, explicit consent state/version/timestamps/revocation, normalized source item, Share/App Group import envelope and dedupe key, canonical Memory/Representation repository, TaskQueue, generation route selection, production/fixture mode, card repository, creation runtime and export boundary. Later tasks may consume only these accepted signatures and paths.

**AC/spec inputs:** all 14 spec-invalid stories: SRC-002/006, ING-001/002/003/004, RET-003/004, SYN-003/004, AWK-002, PRV-003/005/007；explicit ownership repair for US-SRC-007/009/010/011; plus `README.md:5-7`, `AGENTS.md` R-001/R-002/R-003/R-004/R-005/R-006/R-007/R-008 and D-001/D-002/D-003/D-004/D-005, and Appendix C.

☐ Before any 3F.0 task action, verify the target-machine human explicitly authorized and started this docs-only bootstrap PR/worktree by supplying all three §1.1 authorization values. Treat §6.2.1 as pre-task environment setup; if authorization is absent, mismatched, or not attributable to a human, stop. Do not use normal ready-task selection and do not claim 3F.0 already exists in the ledger. ☐ Amend `AGENTS.md` §17 and the exact `docs/ui/` files in §4.6.0 to record the standing authority in §1.1 for scoped 3F Core/source edits and automatic commit/push/create-or-update-PR actions without repeated approval, while preserving human-only merge/close/delete/out-of-scope actions and the no-overwrite and no-media-capture rules. This PR contains no business code, test code, Xcode, CI, signing or release-config edit. ☐ Create `docs/05-planning/phase3f-execution-plan.md` from this approved current instruction, extract Appendix C to `docs/05-planning/phase3f-story-matrix.md`, and create the task-plus-finalizer skeleton at `docs/05-planning/phase3f-evidence-index.md`. ☐ Add the Phase 3F schema, 12 complete task records, task graph, Phase 4 freeze, deferred metadata and exact-ID command behavior from §4. ☐ Validate both planning JSON files and all three policy JSON files with `python3 -m json.tool`; review the diff for unique string IDs, dependency existence, acyclicity, phase boundaries, integration IDs, migration records, policy stop conditions and Phase 4 lock. Existing CI must remain unchanged and pass. ☐ Amend ACs: Notes/Voice are share-only; iMessage automatic history and People identity are out of v1; scheduling is earliest-eligible/best-effort; E5 384d, SigLIP2 visual and lexical spaces remain separate generations; audit export uses bounded pagination/split files; Notes handoff uses system share/export only. ☐ Decide offline LLM scope: either approve immutable bundled runtime/artifact/license/checksum and Language Aligner for retained SYN stories, or remove those stories from v1 with owners and target version. No 3F.3/3F.9 implementation begins without this accepted decision. ☐ Resolve DEF-38-003 by a recorded human choice. Option A restores global coverage to `>=95%` before 3F.1 can become ready. Option B approves a temporary ratchet for 3F.1 through 3F.10 that never permits global coverage to decrease from the human-merged 3F.0 baseline and requires `>=95%` line coverage for every changed production file. Option B still requires hard global coverage `>=95%` at 3F.11. No task may choose a lower number, reset the baseline or move this obligation to Phase 4. ☐ Add ADRs containing concrete signatures and ownership for all ten blocked contracts listed above; include migration from legacy `MemoryEntry`/single 512d store. ☐ Update `docs/04-ai-native/产品创新工具全景指南.md` so Firebase Vertex AI, network search and cloud fallback are research-only and prohibited from Echo production. ☐ Update `docs/ui/echo-memory-canvas-style.md` to remove or reconcile the iCloud sync status UI with Echo's no-CloudKit contract; update `UIAutomation/Policies/README.md` so its Core/config/delivery summary reflects post-3F.0 scoped authority without weakening stop rules. ☐ Run JSON parsing, existing documentation/ledger checks and the unchanged repository CI applicable to a docs-only PR. Do not add or modify source tests to make 3F.0 pass. ☐ Complete every operation and acceptance check in §4.6.0, including ledger notes, deferred mappings and AC coverage evidence. After docs-only validation succeeds and before §6.2.2, atomically change only the newly created 3F.0 task lifecycle fields from `in_progress` to `review` with a fresh UTC `last_updated`; populate this task's exact §11.1 PR-body marker block from real results, remove every placeholder, and pass extraction validation. ☐ Use only the explicitly human-authorized registered worktree/branch `docs/phase3f-spec-ledger-3F.0` prepared by §6.2.1. After docs-only implementation, validation, and the pre-delivery `review` transition, run the single §6.2.2 script with commit `docs(docs): define phase 3f execution contracts` and PR `docs(docs): define Phase 3F contracts [3F.0]`.

**Expected evidence:** accepted AC diff and ADRs; successful JSON parse output; recorded unique-ID, dependency, cycle, phase-link, integration-ID, migration and Phase 4 lock review; all 66 unique stories mapped, including explicit non-deferred rows for US-SRC-007/009/010/011; zero unresolved P0 specification conflicts; Phase 4 visibly locked.

### 3F.1: Production composition、首次启动、同意与隐私

**Files**

- Modify: `Echo/EchoApp.swift`, `Echo/App/AppDelegate.swift`, `Echo/UI/AppShell/AppRootView.swift`, `Echo/UI/AppShell/AppViewModel.swift`, `Echo/UI/Onboarding/OnboardingViewModel.swift`, `Echo/UI/Settings/SettingsViewModel.swift`, `Echo/Core/Actors/PrivacyActor.swift`, `Echo/Core/Actors/DatabaseManager.swift`.
- Create: `Echo/App/AppComposition.swift`; `Echo/Core/Models/ConsentState.swift`; `Echo/Core/Models/AuditEvent.swift`; `Echo/Core/Actors/ConsentStoreActor.swift`; `EchoTests/Phase3F/3F.1_ProductionCompositionTests.swift`.
- Test/extend: `EchoTests/Phase2/PrivacyActorTests.swift`, `EchoTests/Phase3/AppShellTests.swift`, `EchoTests/Phase3/OnboardingTests.swift`, `EchoTests/Phase3/SettingsViewModelTests.swift`.
- Modify documentation/planning: `README.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/decisions/ADR-007-production-composition-consent.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`.
- Read-only documentation: `docs/05-planning/phase3f-story-matrix.md`; `docs/ui/echo-memory-canvas-style.md`.
- Modify UIAutomation: `UIAutomation/Contracts/instances/onboarding-surface.json`; `UIAutomation/Contracts/instances/onboarding-journey-happy-path.json`; `UIAutomation/Contracts/instances/onboarding-journey-privacy-declined.json`; `UIAutomation/Contracts/instances/onboarding-journey-permission-denied.json`; `UIAutomation/Contracts/instances/onboarding-state-welcome.json`; `UIAutomation/Contracts/instances/onboarding-state-language.json`; `UIAutomation/Contracts/instances/onboarding-state-privacy-consent.json`; `UIAutomation/Contracts/instances/onboarding-state-declined.json`; `UIAutomation/Contracts/instances/onboarding-state-permissions.json`; `UIAutomation/Contracts/instances/onboarding-state-permission-denied.json`; `UIAutomation/Contracts/instances/onboarding-state-completed.json`; `UIAutomation/Contracts/instances/onboarding-action-start.json`; `UIAutomation/Contracts/instances/onboarding-action-selectLanguage.json`; `UIAutomation/Contracts/instances/onboarding-action-privacyAgree.json`; `UIAutomation/Contracts/instances/onboarding-action-privacyDecline.json`; `UIAutomation/Contracts/instances/onboarding-action-declinedClose.json`; `UIAutomation/Contracts/instances/onboarding-action-permissionAllow.json`; `UIAutomation/Contracts/instances/onboarding-action-permissionDeny.json`; `UIAutomation/Contracts/instances/onboarding-action-permissionSkip.json`; `UIAutomation/Contracts/instances/onboarding-action-openSettings.json`; `UIAutomation/Fixtures/onboarding/onboarding-welcome.json`; `UIAutomation/Fixtures/onboarding/onboarding-language.json`; `UIAutomation/Fixtures/onboarding/onboarding-privacy-consent.json`; `UIAutomation/Fixtures/onboarding/onboarding-declined.json`; `UIAutomation/Fixtures/onboarding/onboarding-permissions.json`; `UIAutomation/Fixtures/onboarding/onboarding-permission-denied.json`; `UIAutomation/Fixtures/onboarding/onboarding-completed.json`.

**Interfaces**

- Consumes: `DatabaseManager.open()`, PrivacyActor methods in §5, 3F.0 composition/consent contracts.
- Produces: one app-owned dependency graph and startup state machine; deny-by-default persisted consent; transactional revoke/purge result; explicit model-unavailable, route-unavailable and index-unavailable startup states consumed by 3F.2/3F.3/3F.4/3F.7/3F.11.

**AC/spec inputs:** US-PRV-001/004/005/006/008, US-SRC-001, US-RES-004, AGENTS R-001/R-005/R-006 and D-001/D-002/D-003/D-004/D-005.

☐ Mark `3F.1` in progress and quote accepted AC/ADR text. ☐ Write failing tests for clean install→onboarding, denied consent→no business data access, accepted consent→policy load and permitted DB open, composition/startup state creation, explicit model-unavailable/route-unavailable/index-unavailable states, relaunch restoration, revocation→transactional purge and purge failure→blocked state with audit. Add failing migration/storage tests proving every audit event requires `eventType`, `timestamp`, `traceID`, `policyVersion`, `success`; content is hash-only; rows older than 30 days are cleaned; audit storage has `NSFileProtectionComplete`. ☐ Set `FOCUSED_SUITE=EchoTests/ProductionCompositionTests` and run the complete §6.1 focused command. Confirm RED on default construction. ☐ Implement the minimal composition/startup/consent path one AC at a time. Migrate AuditLog schema/storage atomically, reject missing required fields, hash content before persistence, schedule deterministic 30-day cleanup and apply `NSFileProtectionComplete`. 3F.1 may open SQLite, load policy, create the app-owned composition and startup states, and expose explicit unavailable states. It must not require a real model, active route, built index, reference inference or search readiness. Those become available only through 3F.3 and 3F.4, and full startup readiness is proven only by 3F.11. No fixture fallback is allowed in Release. ☐ Run focused tests, Privacy/Phase3 regressions, all `EchoTests`, Release simulator/device and static gates. ☐ Complete every operation and acceptance check in §4.6.1; update the existing evidence index in the same PR and close DEF-45-002 only with evidence. Before §6.2.2, populate this task's exact §11.1 PR-body marker block from real results, remove every placeholder, and pass extraction validation. ☐ Prepare registered worktree/branch `feature/phase3f-production-composition-3F.1` through §6.2.1 and use its printed path for every later command; after implementation and verification, run the single §6.2.2 script with commit `feat(config): add production app composition` and PR `feat(config): add production app composition [3F.1]`.

**Expected evidence:** clean-install run manifest、accessibility tree 与 unified log without `-ui-fixture`; explicit unavailable-state transitions; persisted policy snapshot; restart log; purge fault-injection report; DB/file inventory before/after revocation; AuditLog migration SQL/schema inventory; required-field rejection matrix; plaintext scan with zero hits; 30-day cleanup boundary output; file-protection attribute proof; Privacy Engineering Lead acceptance. 遵循 `AGENTS.md`，不生成 screenshot/video。

> **✅ 3F.1 实现记录（2026-08-04）**：`Echo/App/AppComposition.swift` composition root + `AppStartupState` 状态机（requiresConsent/ready/modelUnavailable/routeUnavailable/indexUnavailable/purgeBlocked）；`ConsentStoreActor` deny-by-default 同意持久化 + 事务性撤回/清除（PurgeBoundary，失败 blocked + `.purgeFailed` 审计，成功审计自擦除）；AuditLog `contentHash` 列（hash-only）+ 必填字段 NOT NULL + 30 天清理 + NSFileProtectionComplete。测试证据见 `docs/05-planning/phase3f-evidence-index.md` 3F.1 条目；DEF-45-002 以 purge evidence 关闭。Release simulator build 的 `simulateError` `#Preview` 编译错误在 dev-1.0 基线同样复现（非 3F.1 引入）。

### 3F.2: PhotoKit、Share Extension 与真实来源

**Files**

- Modify: `Echo.xcodeproj/project.pbxproj`; `Echo/App/AppDelegate.swift`; `Echo/Core/Pipelines/SyncPipeline.swift`; `Echo/Core/Pipelines/IngestPipeline.swift`; `Echo/Core/Models/AuditEvent.swift` (新增 `.shareExtensionImported` 审计事件, US-SRC-003 AC-4).
- Create: `Echo/Config/Echo-Info.plist`; `Echo/Config/Echo.entitlements`; `Echo/Core/Sources/PhotoKitSourceAdapter.swift`; `Echo/Core/Sources/PhotoKitChangeObserver.swift`; `Echo/Core/Models/SharedImportEnvelope.swift`; `Echo/Core/Actors/SharedImportQueueActor.swift`; `EchoShareExtension/ShareViewController.swift`; `EchoShareExtension/Info.plist`; `EchoShareExtension/EchoShareExtension.entitlements`; `EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift`.
- Test/extend: `EchoTests/Phase2/SyncPipelineTests.swift`, `EchoTests/Phase2/IngestPipelineImageTests.swift`, `EchoTests/Phase2/2.5_IngestPipelineTextTests.swift`.
- Modify documentation/planning: `README.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/decisions/ADR-008-source-import-boundaries.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`.
- Read-only documentation: `docs/05-planning/phase3f-story-matrix.md`.

**Interfaces**

- Consumes: accepted source item/import envelope/dedupe contracts; current `IngestPipeline.ingest*` signatures; ExcludedAssets and consent/revoke result.
- Produces: authorized photo/video stream, change events and shared text/audio queue entries consumed by 3F.5; stable source identity, audit and progress.

**AC/spec inputs:** US-SRC-001/003/004/005/008/012/013, US-PRV-001, accepted share-only AC and App Group ADR.

☐ Write failing tests for limited/full/denied/revoked Photos, ExcludedAssets filtering, change dedupe, shared text/audio validation, App Group queue atomicity and duplicate delivery. ☐ Set `FOCUSED_SUITE=EchoTests/RealDataSourcesTests` and run the complete §6.1 focused command. Confirm RED. ☐ Implement PhotoKit acquisition/change observation and the user-mediated Share Extension; reject unsupported types and plaintext audit content. ☐ Prove permission revocation stops reads and shared import survives app relaunch exactly once. ☐ Run focused, source/ingest regressions, all `EchoTests`, Share Extension build, both Release builds and static/privacy gates. ☐ Complete every operation and acceptance check in §4.6.2 and update the existing evidence index in the same PR. Before §6.2.2, populate this task's exact §11.1 PR-body marker block from real results, remove every placeholder, and pass extraction validation. ☐ Prepare registered worktree/branch `feature/phase3f-real-data-sources-3F.2` through §6.2.1 and use its printed path for every later command; after implementation and verification, run the single §6.2.2 script with commit `feat(pipeline): add production data sources` and PR `feat(pipeline): add production data sources [3F.2]`.

**Expected evidence:** simulator seeded-photo and physical-device limited-library traces; real share-sheet text/audio import; App Group queue/audit records; revocation and dedupe logs. Fixture or direct `assetId` calls do not satisfy this task.

### 3F.3: E5、SigLIP2、Whisper 与离线生成决策落地

**Files**

- Modify: `Echo/Core/Services/EmbedderService.swift`; `Echo/Core/Services/E5Embedder.swift`; `Echo/Core/Services/SigLIP2Embedder.swift`; `Echo/Core/Services/ASREngineService.swift`; `Echo/Core/Services/WhisperASREngine.swift`; `Echo/Core/Services/OCREngine.swift`; `Echo/Core/Services/LexicalEngine.swift`; `Echo/Core/Actors/ModelLoaderActor.swift`; `Echo/Core/Actors/ModelManifestActor.swift`; `Echo/Core/Models/ModelManifest.swift`; `Echo.xcodeproj/project.pbxproj`; `Scripts/prepare_models.sh`; `Scripts/model_checksums.sha256`.
- Create: `Echo/Core/Services/E5Tokenizer.swift`; `Echo/Core/Services/CoreMLInferenceAdapter.swift`; `Echo/Core/Services/WhisperRuntimeBridge.swift`; `Echo/Core/Services/LanguageAligner.swift`; `Echo/Resources/Models/model-manifest.json`; `Echo/Resources/Models/e5-reference-vectors.json`; `Echo/Resources/Models/siglip2-reference-vectors.json`; `Echo/Resources/Models/whisper-reference-transcripts.json`; `EchoTests/Phase3F/3F.3_ProductionModelInferenceTests.swift`. `Echo/Core/Services/LanguageAligner.swift` is created only when the human-approved 3F.0 SYN decision retains offline generation; otherwise it is absent and that absence is asserted.
- Test/extend: `EchoTests/Phase1/ModelLoaderActorTests.swift`, `EchoTests/Phase1/ModelBundleTests.swift`, `EchoTests/Phase2/R3_PureFunctionTests.swift`, `EchoTests/Phase2/RA_CanonicalModelTests.swift`.
- Modify documentation/planning: `README.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/技术选型文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/decisions/ADR-009-offline-model-runtime.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`.
- Create documentation: `docs/05-planning/model-provenance-register.md`.
- Read-only documentation: `docs/05-planning/phase3f-story-matrix.md`; `docs/ui/echo-memory-canvas-style.md`.
- Modify UIAutomation: `UIAutomation/Contracts/instances/onboarding-surface.json`; `UIAutomation/Contracts/instances/onboarding-state-model-loading.json`; `UIAutomation/Contracts/instances/onboarding-action-beginLoad.json`; `UIAutomation/Fixtures/onboarding/onboarding-model-loading.json`; `UIAutomation/Contracts/instances/onboarding-state-completed.json`; `UIAutomation/Fixtures/onboarding/onboarding-completed.json`.
- Create UIAutomation: `UIAutomation/Contracts/instances/onboarding-state-model-load-error.json`; `UIAutomation/Contracts/instances/onboarding-state-model-unavailable.json`; `UIAutomation/Contracts/instances/onboarding-action-retryModelLoad.json`; `UIAutomation/Contracts/instances/onboarding-journey-model-load-recovery.json`; `UIAutomation/Fixtures/onboarding/onboarding-model-load-error.json`; `UIAutomation/Fixtures/onboarding/onboarding-model-unavailable.json`.

**Interfaces**

- Consumes: `EmbedderProtocol`, `ASREngineProtocol`, `ModelManifest`, 3F.0 model/LLM ADR.
- Produces: real offline E5 384d text embedding, separate SigLIP2 visual embedding, Whisper transcript, immutable manifest/revision/hash/license/runtime identity, loader state/recovery; if retained, approved offline generation and Language Aligner contracts.

**AC/spec inputs:** US-ING-001/002/003/004/005, US-RET-001/002/006, US-RES-001/004, US-SRC-011 model semantics, the exact retained subset of US-SYN-001/002/003/004/005/006/007/008 recorded by 3F.0, AGENTS R-004/R-005 and model-space ADR.

☐ Write failing bundle/hash/license/reference-output/offline-network tests and corrupt/missing artifact recovery tests. ☐ Run `bash Scripts/prepare_models.sh --verify-only`. Set `FOCUSED_SUITE=EchoTests/ProductionModelInferenceTests` and run the complete §6.1 focused command. Confirm RED against zero or missing artifacts. ☐ Implement tokenizer, pooling, normalization, Core ML inference and whisper.cpp bridge without runtime conversion/download; keep spaces separate. ☐ If LLM stories remain, implement only the exact approved runtime/artifact and one-retry Language Aligner; otherwise verify no production code path references generation. ☐ Run focused tests, model regressions, all `EchoTests`, both Release builds, checksum/SBOM/license and network-denial gates. ☐ Complete every operation and acceptance check in §4.6.3; populate every provenance field, update the existing evidence index, and record only evidence-backed deferred closures. Before §6.2.2, populate this task's exact §11.1 PR-body marker block from real results, remove every placeholder, and pass extraction validation. ☐ Prepare registered worktree/branch `feature/phase3f-production-models-3F.3` through §6.2.1 and use its printed path for every later command; after implementation and verification, run the single §6.2.2 script with commit `feat(service): add offline production inference` and PR `feat(service): add offline production inference [3F.3]`.

**Expected evidence:** Bundle count 100% of revised manifest; hashes and licenses; non-zero deterministic E5 vector; SigLIP2 reference tolerance; real audio transcript; US-SRC-011 model-semantics trace; corrupt-model L3 recovery; zero network requests; optional LLM/aligner proof only when approved.

### 3F.3a: SigLIP2 Core ML 转换与视觉推理接入

> 从 3F.3 拆分（2026-08-07 规划变更）：3F.3 交付 SigLIP2 转换源（model.safetensors）与预处理修复；本任务完成 PyTorch→Core ML 转换、参考向量验证与真实视觉推理。ADR-009 决策 1（空间分离）与决策 2（未获批模型不进打包）管辖。

**Files**

- Modify: `Echo/Core/Services/SigLIP2Embedder.swift`; `Echo/Core/Actors/ModelLoaderActor.swift`; `Echo/Core/Actors/ModelManifestActor.swift`; `Echo/Core/Models/ModelManifest.swift`; `Echo.xcodeproj/project.pbxproj`; `Scripts/prepare_models.sh`; `Scripts/model_checksums.sha256`; `Echo/Resources/Models/model-manifest.json`; `Echo/Resources/Models/siglip2-reference-vectors.json`.
- Create: `Scripts/convert_siglip2.py`（PyTorch→coremltools 转换脚本）; `EchoTests/Phase3F/3F.3a_SigLIP2ConversionTests.swift`.
- Test/extend: `EchoTests/Phase3F/3F.3_ProductionModelInferenceTests.swift`（SigLIP2Preprocessing/RealInference）; `EchoTests/Phase1/ModelBundleTests.swift`.
- Modify documentation/planning: `README.md`; `docs/02-architecture/技术选型文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/decisions/ADR-009-offline-model-runtime.md`; `docs/05-planning/model-provenance-register.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`.
- Read-only documentation: `docs/05-planning/phase3f-story-matrix.md`.

**Interfaces**

- Consumes: `SigLIP2Embedder`（R-3.2 预处理）; `model-provenance-register.md` §3 转换源登记; ADR-009 决策 1/2.
- Produces: `SigLIP2BasePatch32.mlmodelc` 随包分发; 真实 768d 视觉嵌入（`vision_dense` 独立 generation）; `siglip2-reference-vectors.json` 回填确定性参考.

**AC/spec inputs:** US-ING-004 AC-3, US-RET-001（视觉通道）, US-SRC-011 model semantics, R-5.1 四类门禁（法律、转换一致性、Echo 数据集实机评测、实体设备资源门禁）.

☐ Write failing conversion-source, reference-vector tolerance (>0.995 cosine), real-vision-inference, four-gate and bundle-presence tests. ☐ Set `FOCUSED_SUITE=EchoTests/SigLIP2ConversionTests` and run the complete §6.1 focused command. Confirm RED against missing `.mlmodelc`. ☐ Implement `Scripts/convert_siglip2.py`（coremltools 转换，固定 revision，输出不可变工件 + SHA-256）; wire `SigLIP2Embedder.embedImage` to real Core ML inference; verify reference vectors against HuggingFace outputs. ☐ Pass four gates: legal（LICENSE/NOTICE/哈希登记）、conversion consistency（cosine >0.995）、Echo dataset device evaluation、physical-device resource gate. ☐ Run focused tests, model regressions, all `EchoTests`, Release builds, checksum/SBOM/license and network-denial gates. ☐ Complete every operation and acceptance check in §4.6.3a; update evidence index and model-provenance-register §3（`pending-conversion-and-approval` → approved）. Before §6.2.2, populate this task's exact §11.1 PR-body marker block, remove placeholders, pass extraction validation. ☐ Prepare registered worktree/branch `feature/phase3f-siglip2-conversion-3F.3a` through §6.2.1; run the single §6.2.2 script with commit `feat(service): add SigLIP2 core ML vision inference` and PR `feat(service): add SigLIP2 core ML vision inference [3F.3a]`.

**Expected evidence:** converted `.mlmodelc` in bundle; SHA-256 in model_checksums.sha256 + provenance register; reference-vector cosine >0.995; real 768d non-zero vision embedding; four-gate approval record; zero network requests.

### 3F.3b: whisper.cpp 运行时接入与真实转写

> 从 3F.3 拆分（2026-08-07 规划变更）：3F.3 交付 GGUF 工件与 fail-closed 桥接（`WhisperRuntimeBridge.runtimeNotLinked`）；本任务引入 whisper.cpp 运行时（AGENTS.md §2.2 白名单审批）、实现 C 互操作与真实转写。关闭 DEF-51-002 ASR 契约。
>
> ✅ **已交付（2026-08-09）**：whisper.cpp v1.9.2 vendored 本地 SPM 包（固定 revision 306c88f4d1）；`NativeWhisperCInterop` 真实转写；`WhisperRuntimeBridge` 默认接线 + GGUF SHA-256 校验；`WhisperASREngine.transcribe` 完整实现；`ASREngineProtocol.transcribeFile(at:)` 文件输入契约（DEF-51-002 ASR 部分关闭）；参考转写回填（jfk CER=0.0）。证据见 phase3f-evidence-index §3F.3b。

**Files**

- Modify: `Echo/Core/Services/WhisperRuntimeBridge.swift`; `Echo/Core/Services/WhisperASREngine.swift`; `Echo/Core/Actors/ModelLoaderActor.swift`; `Echo.xcodeproj/project.pbxproj`; `Package.swift`（或 SPM 依赖清单，需 §2.2 白名单）; `Scripts/model_checksums.sha256`; `Echo/Resources/Models/whisper-reference-transcripts.json`.
- Create: `Echo/Core/Services/NativeWhisperCInterop.swift`（whisper_init_from_file + whisper_full 实现）; `EchoTests/Phase3F/3F.3b_WhisperRuntimeTests.swift`.
- Test/extend: `EchoTests/Phase3F/3F.3_ProductionModelInferenceTests.swift`（WhisperBridge）; `EchoTests/Phase2/2.5_IngestPipelineTextTests.swift`.
- Modify documentation/planning: `README.md`; `docs/02-architecture/技术选型文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/decisions/ADR-009-offline-model-runtime.md`; `docs/05-planning/model-provenance-register.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`.
- Read-only documentation: `docs/05-planning/phase3f-story-matrix.md`.

**Interfaces**

- Consumes: `WhisperRuntimeBridge`（R-3.3 桥接）; GGUF 工件（model-provenance-register §2）; ADR-009 决策 2/3.
- Produces: whisper.cpp 静态库随包链接; `NativeWhisperCInterop` 真实转写; `whisper-reference-transcripts.json` 回填（CER/WER 阈值）; DEF-51-002 ASR 文件输入契约重设计.

**AC/spec inputs:** US-ING-003 AC-1（转写）, US-ING-005 AC-2（视频音频转写）, US-SRC-011 model semantics, R-5.4（tiny 批准）, AGENTS.md §2.2（依赖白名单）.

☐ Write failing runtime-linked, real-transcript, reference-CER/WER, GGUF-hash and DEF-51-002 contract tests. ☐ Set `FOCUSED_SUITE=EchoTests/WhisperRuntimeTests` and run the complete §6.1 focused command. Confirm RED against `runtimeNotLinked`. ☐ Obtain §2.2 dependency whitelist approval for whisper.cpp; add SPM/static-library dependency with SBOM/NOTICE/license registration. ☐ Implement `NativeWhisperCInterop`（Sendable-safe C 包装，禁止 `nonisolated(unsafe)`）; wire `WhisperRuntimeBridge.transcribe` to real inference; backfill reference transcripts with CER/WER verification. ☐ Run focused tests, model regressions, all `EchoTests`, Release builds, checksum/SBOM/license and network-denial gates. ☐ Complete every operation and acceptance check in §4.6.3b; update evidence index and model-provenance-register §2（`pending-runtime-integration` → approved）. Before §6.2.2, populate this task's exact §11.1 PR-body marker block, remove placeholders, pass extraction validation. ☐ Prepare registered worktree/branch `feature/phase3f-whisper-runtime-3F.3b` through §6.2.1; run the single §6.2.2 script with commit `feat(service): link whisper.cpp real transcription` and PR `feat(service): link whisper.cpp real transcription [3F.3b]`.

**Expected evidence:** whisper.cpp linked and loaded in bundle; real transcript from 16kHz mono PCM; reference-transcript CER/WER within threshold; GGUF SHA-256 verified; DEF-51-002 ASR 文件输入契约重设计关闭（App Group 持久化生产者路径由 3F.5 完成并验证 E2E）; zero network requests.

### 3F.4: Canonical storage 与 generation 生命周期

**Files**

- Modify: `Echo/Core/Models/CanonicalMemory.swift`, `Echo/Core/Models/Memory.swift`, `Echo/Core/Models/IndexGeneration.swift`, `Echo/Core/Models/ActiveRouteSet.swift`, `Echo/Core/Models/ModelManifest.swift`, `Echo/Core/Actors/DatabaseManager.swift`, `Echo/Core/Actors/GenerationRegistryActor.swift`, `Echo/Core/Actors/VectorStoreActor.swift`, `Echo/Core/Actors/FeedbackActor.swift`.
- Create: `Echo/Core/Actors/CanonicalMemoryRepositoryActor.swift`; `Echo/Core/Actors/DatabaseMigrationActor.swift`; `EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift`.
- Test/extend: `EchoTests/Phase2/RA_CanonicalModelTests.swift`; `EchoTests/Phase2/RA_GenerationRegistryTests.swift`; `EchoTests/Phase2/RA_DataCorrectnessTests.swift`.
- Modify documentation/planning: `README.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/decisions/ADR-010-canonical-generation-lifecycle.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`.
- Read-only documentation: `docs/05-planning/phase3f-story-matrix.md`.

**Interfaces**

- Consumes: canonical repository contract, `registerGeneration`, `vectorStore(for:)`, `publishRoute`, `loadActiveRoute`.
- Produces: deterministic Memory/Representation IDs; transactional CRUD; manifest-linked per-generation stores; active route restore, shadow build, atomic publish, rollback, generation-aware feedback/delete.

**AC/spec inputs:** US-ING-006, US-PRV-004/006/007, US-AWK-007, US-FBK-001/002/003, AGENTS D-002/D-003/D-004/D-005 and §5 storage contracts.

☐ Write failing tests for deterministic IDs, atomic canonical/vector/FTS writes, crash points, restart restore, route publish, old-generation rollback, feedback generation identity and full deletion boundary. ☐ Set `FOCUSED_SUITE=EchoTests/CanonicalGenerationTests` and run the complete §6.1 focused command. Confirm RED. ☐ Implement the accepted repository and generation lifecycle; remove 384→512 padding and single-store production routing. ☐ Inject faults before/after each transaction boundary and prove no half-write or mixed-generation route. ☐ Run focused, all R-A tests, cumulative tests, Release builds and SQLite/vector/static gates. ☐ Complete every operation and acceptance check in §4.6.4; update the existing evidence index and close DEF-38-001/002 only with evidence. Before §6.2.2, populate this task's exact §11.1 PR-body marker block from real results, remove every placeholder, and pass extraction validation. ☐ Prepare registered worktree/branch `feature/phase3f-canonical-generations-3F.4` through §6.2.1 and use its printed path for every later command; after implementation and verification, run the single §6.2.2 script with commit `feat(actor): add canonical generation lifecycle` and PR `feat(actor): add canonical generation lifecycle [3F.4]`.

> ✅ **3F.4 完成（2026-08-09）**：CanonicalMemoryRepositoryActor（确定性 ID + 事务 CRUD + 补偿回滚 + 全删除边界 + 级联删除）、DatabaseMigrationActor、GenerationRegistryActor 生命周期（shadow build/原子发布/回滚/重启恢复/持久化）、FeedbackStore.generationId、Memory 编辑字段持久化。focused 28/28，全量 893 tests / 113 suites 0 失败（三轮 CodeRabbit 修复后最终计数）。DEF-38-001 关闭、DEF-38-002 partial（持久化已交付，SyncPipeline 行为延后 3F.7）。PR `feat(actor): add canonical generation lifecycle [3F.4]` 已创建。SearchPipeline/IngestPipeline 单 store 路由移除由 3F.5/3F.6 消费 generation registry 时完成。

**Expected evidence:** migration/rollback logs, DB snapshots, route versions before/after restart, per-generation file inventory, fault-injection matrix, deletion inventory.

> ✅ **3F.5 完成（2026-08-10）**：生产摄入路径落地——`TaskQueueActor`（串行 + ProgressActor 断点续传 + 取消保留进度，ADR-011）、4 个 source extractors（PhotoAsset/VideoAsset/SharedText/SharedAudio）、`IngestPipeline.ingestProductionPhoto/Video/SharedText/SharedAudio`（经 `CanonicalMemoryRepositoryActor.commit` 单事务 canonical + 每代向量 + FTS，ADR-010 活跃路由）、`SyncPipeline` 生产替换/删除路由（CR-3 方案A：canonical 确定性 ID upsert + 活跃路由向量，不再写单一遗留 store）、AppDelegate 装配真实 E5/SigLIP2/Whisper。focused 15/15，全量 937 tests 0 失败（含 2 个 CodeRabbit 修复新增用例：video-no-ASR L2、canonical-delete-fault）。DEF-51-001 关闭。PR `feat(pipeline): add production ingestion [3F.5]` #57。

### 3F.5: Production ingestion

**Files**

- Modify: `Echo/Core/Pipelines/IngestPipeline.swift`; `Echo/Core/Pipelines/SyncPipeline.swift`; `Echo/Core/Services/OCREngine.swift`; `Echo/Core/Services/E5Embedder.swift`; `Echo/Core/Services/SigLIP2Embedder.swift`; `Echo/Core/Services/WhisperASREngine.swift`; `Echo/Core/Sources/PhotoKitSourceAdapter.swift`; `Echo/Core/Actors/SharedImportQueueActor.swift`; `Echo/Core/Models/Memory.swift`.
- Create: `Echo/Core/Actors/TaskQueueActor.swift`; `Echo/Core/Sources/PhotoAssetExtractor.swift`; `Echo/Core/Sources/VideoAssetExtractor.swift`; `Echo/Core/Sources/SharedTextExtractor.swift`; `Echo/Core/Sources/SharedAudioExtractor.swift`; `EchoTests/Phase3F/3F.5_ProductionIngestionTests.swift`.
- Test/extend: `EchoTests/Phase2/IngestPipelineImageTests.swift`; `EchoTests/Phase2/2.4_IngestPipelineVideoTests.swift`; `EchoTests/Phase2/2.5_IngestPipelineTextTests.swift`; `EchoTests/Phase2/Phase2IntegrationTests.swift`.
- Modify documentation/planning: `README.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/decisions/ADR-011-task-progress-boundary.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`.
- Read-only documentation: `docs/05-planning/phase3f-story-matrix.md`.

**Interfaces**

- Consumes: current `ingestImage/video/text/voice`, real source/model services (E5 from 3F.3; SigLIP2 real vision from 3F.3a; Whisper real transcription from 3F.3b), canonical repository, active routes, approved TaskQueue, ProgressActor and PrivacyActor.
- Produces: canonical/generation ingestion result with trace/audit/progress, cancellation/resume and classified L1-L4 failures.

**AC/spec inputs:** US-ING-001/002/003/004/005/006, US-SRC-012/013, US-SYS-001, US-RES-001/002/003/004.

☐ Write failing no-stub tests for one real photo, video, shared text and shared audio (real vision/audio inference supplied by 3F.3a/3F.3b, which 3F.5 depends on); add OCR/frame/audio, cancel/resume, disk-full, corrupt-model and rollback cases. ☐ Set `FOCUSED_SUITE=EchoTests/ProductionIngestionTests` and run the complete §6.1 focused command. Confirm RED. ☐ Implement one source at a time through extraction→inference→canonical transaction→generation indexes→audit/progress. ☐ Ensure every Pipeline entry begins with PrivacyCheckpoint and every long write runs through TaskQueue with persisted ProgressActor state. ☐ Run focused, all ingest/Phase2 integration, cumulative, Release and static/privacy tests. ☐ Complete every operation and acceptance check in §4.6.5 and update the existing evidence index in the same PR. Before §6.2.2, populate this task's exact §11.1 PR-body marker block from real results, remove every placeholder, and pass extraction validation. ☐ Prepare registered worktree/branch `feature/phase3f-production-ingestion-3F.5` through §6.2.1 and use its printed path for every later command; after implementation and verification, run the single §6.2.2 script with commit `feat(pipeline): add production ingestion` and PR `feat(pipeline): add production ingestion [3F.5]`.

**Expected evidence:** four real-source traces sharing trace IDs; canonical/vector/FTS counts; cancel/relaunch/resume; fault rollback; no `StubEmbedder`/`StubASR` in production proof.

> ✅ **3F.6 完成（2026-08-11）**：生产检索与反馈闭环落地——`SearchChannelAdapters`（`GenerationRoutedChannelAdapter` 多通道 generation 路由：text_dense E5 384d / vision_dense SigLIP2 768d / ocr_text / lexical 经 `ActiveRouteSet` 独立向量空间，RRF 融合 + ID-keyed `metadataByID` 回填 DEF-34-001，通道超时/空索引 → `timedOut` 部分结果 US-RET-008、L3 路由缺失以 error 区分 DEF-34-002）、`SearchResultCacheActor`（policy-aware TTL 缓存，键含 policyVersion/modelVersion/queryHash，US-RET-007）、`SearchPipeline` 追问（FIFO ≤10 + memoryIds 隐式过滤 + `.followUpQuery` 审计，US-RET-005 AC-1/2/4/5，AC-3 延后 DEF-58-001）、`FeedbackActor` query-conditioned 重排（US-FBK-001 AC-4）+ `FeedbackPipeline` 活跃 generationId 传递（DEF-56-005 / ADR-010 决策 4）、L2 反馈失败 → `PendingOperations`（DEF-37-001，可见 + 手动重试）、`CrossAppIntentParser` + `CrossAppFusionEngine`（US-SRC-010 逐源授权 / 时间对齐 / 来源标签 / `.crossAppSearch` 审计，live HealthKit provider 属 3F.8）、`BoundedReranker` 主观有界重排（US-SRC-011）、`searchCanonical` ORDER BY rank（DEF-56-006）。focused 45/45（ProductionSearchFeedbackTests 30 + CrossAppSearchTests 15），全量 962 tests 0 失败。DEF-34-001/002、DEF-37-001、DEF-56-005/006 关闭。PR `feat(pipeline): add production search and feedback [3F.6]`。

### 3F.6: Production search 与 feedback

**Files**

- Modify: `Echo/Core/Pipelines/SearchPipeline.swift`, `Echo/Core/Pipelines/FeedbackPipeline.swift`, `Echo/Core/Actors/FeedbackActor.swift`, `Echo/Core/Actors/PendingOpsActor.swift`, `Echo/Core/Actors/GenerationRegistryActor.swift`, `Echo/Core/Services/LexicalEngine.swift`, `Echo/UI/Search/SearchViewModel.swift`.
- Create: `Echo/Core/Services/SearchChannelAdapters.swift`; `Echo/Core/Services/BoundedReranker.swift`; `Echo/Core/Actors/SearchResultCacheActor.swift`; `Echo/Core/Services/CrossAppIntentParser.swift`; `EchoTests/Phase3F/3F.6_ProductionSearchFeedbackTests.swift`; `EchoTests/Phase3F/3F.6_CrossAppSearchTests.swift`.
- Test/extend: `EchoTests/Phase2/SearchPipelineTests.swift`; `EchoTests/Phase2/SearchWithFeedbackTests.swift`; `EchoTests/Phase2/FeedbackPipelineTests.swift`; `EchoTests/Phase3/SearchViewModelTests.swift`.
- Modify documentation/planning: `README.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/decisions/ADR-010-canonical-generation-lifecycle.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`.
- Read-only documentation: `docs/05-planning/phase3f-story-matrix.md`; `docs/ui/echo-memory-canvas-style.md`.
- Modify UIAutomation: `UIAutomation/Contracts/instances/search-surface.json`; `UIAutomation/Contracts/instances/search-journey-basic.json`; `UIAutomation/Contracts/instances/search-state-idle.json`; `UIAutomation/Contracts/instances/search-state-loading.json`; `UIAutomation/Contracts/instances/search-state-loaded.json`; `UIAutomation/Contracts/instances/search-state-empty.json`; `UIAutomation/Contracts/instances/search-state-error.json`; `UIAutomation/Contracts/instances/search-state-lowconfidence.json`; `UIAutomation/Contracts/instances/search-action-submit.json`; `UIAutomation/Contracts/instances/search-action-retry.json`; `UIAutomation/Contracts/instances/search-action-like.json`; `UIAutomation/Contracts/instances/search-action-dislike.json`; `UIAutomation/Contracts/instances/search-action-badcase.json`; `UIAutomation/Fixtures/search/search-loaded.json`; `UIAutomation/Fixtures/search/search-empty.json`; `UIAutomation/Fixtures/search/search-lowconfidence.json`; `UIAutomation/Fixtures/search/search-multitype.json`.
- Create UIAutomation: `UIAutomation/Contracts/instances/search-state-partial-results.json`; `UIAutomation/Contracts/instances/search-journey-partial-results.json`; `UIAutomation/Fixtures/search/search-partial-results.json`.

**Interfaces**

- Consumes: `SearchPipeline.search`, FeedbackPipeline methods, ActiveRouteSet, canonical metadata, E5/vision/OCR/lexical generations and injected source-provider protocols for health, memory, location and photo.
- Produces: authorized multi-channel result with timeout/partial/RRF/filter/rerank/low-confidence provenance; `CrossAppIntentParser` intent for health+memory and location+photo; temporal-aligned multi-source fusion with source labels; `.crossAppSearch` audit carrying the authorized source list; query-conditioned persisted feedback and manual-retry PendingOperations.

**AC/spec inputs:** US-RET-001/002/003/004/005/006/007/008 after 3F.0 amendments, US-FBK-001/002/003, US-PRV-001, US-SRC-010 search contract, US-SRC-011 subjective ranking/feedback, AGENTS feedback threshold/decay/clamp contract.

☐ Write failing tests for each channel, generation routing, channel timeout, RRF, metadata lookup, feasible filters, bounded reranker, low confidence, cache invalidation, authorization and same-query feedback rank change. In `EchoTests/Phase3F/3F.6_CrossAppSearchTests.swift`, fail health+memory and location+photo intent parsing, each-source authorization denial, temporal alignment, source labels and `.crossAppSearch` source-list audit before implementation. ☐ Write failing feedback persistence test proving L2 is visible and manually retryable rather than swallowed. ☐ Immediately after writing tests, run the complete §6.1 command for `EchoTests/ProductionSearchFeedbackTests` separately, require XCTest executed test count > 0, fail the step if the suite is empty/not found, and record the observed RED:

```
xcodebuild test \
  -project Echo.xcodeproj \
  -scheme Echo \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:EchoTests/ProductionSearchFeedbackTests
```

☐ Then run the complete §6.1 command for `EchoTests/CrossAppSearchTests` separately, require XCTest executed test count > 0, fail the step if the suite is empty/not found, and record the observed RED:

```
xcodebuild test \
  -project Echo.xcodeproj \
  -scheme Echo \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:EchoTests/CrossAppSearchTests
```

☐ Require observed RED from both exact suites before any 3F.6 implementation. A missing run, green-before-implementation result or failure unrelated to the intended absent behavior blocks implementation until corrected and rerun. ☐ Implement minimal channels and fusion while preserving separated vector spaces and trace provenance. Define injected provider protocols in 3F.6; never instantiate live HealthKit here. Parse only the accepted health+memory and location+photo intent forms, authorize every requested source before invoking providers, align results by the parsed temporal window, preserve source labels and emit `.crossAppSearch` with the actual authorized source list. ☐ Run focused/search/feedback regressions, cumulative, Release, privacy and deterministic-ranking gates. ☐ Complete every operation and acceptance check in §4.6.6; update the existing evidence index and close DEF-34-001/002 and DEF-37-001 only with evidence. Before §6.2.2, populate this task's exact §11.1 PR-body marker block from real results, remove every placeholder, and pass extraction validation. ☐ Prepare registered worktree/branch `feature/phase3f-search-feedback-3F.6` through §6.2.1 and use its printed path for every later command; after implementation and verification, run the single §6.2.2 script with commit `feat(pipeline): add production search feedback` and PR `feat(pipeline): add production search and feedback [3F.6]`.

**Expected evidence:** separate complete command logs, XCTest executed test counts > 0 and intended RED failure output for `EchoTests/ProductionSearchFeedbackTests` and `EchoTests/CrossAppSearchTests` before implementation; no empty/not-found suite accepted; default-pipeline query over data ingested in 3F.5; per-channel provenance; forced-timeout partial results; health+memory and location+photo parser cases; injected-provider fusion; denied-source non-invocation; temporal-alignment output; source labels; `.crossAppSearch` source-list audit; US-SRC-011 subjective-ranking and feedback cases; filter explanation; before/after same-query ranking; PendingOperations retry trace.

### 3F.7: UI 到 Core 全域接线

**Files**

- Modify: `Echo/UI/AppShell/AppRootView.swift`, `Echo/UI/AppShell/AppViewModel.swift`, `Echo/UI/Home/HomeView.swift`, `Echo/UI/Home/HomeViewModel.swift`, `Echo/UI/Search/SearchView.swift`, `Echo/UI/Search/SearchViewModel.swift`, `Echo/UI/Detail/MemoryDetailView.swift`, `Echo/UI/Detail/MemoryDetailViewModel.swift`, `Echo/UI/Settings/SettingsView.swift`, `Echo/UI/Settings/SettingsViewModel.swift`, `Echo/UI/BackgroundTask/BackgroundTaskPanelView.swift`, `Echo/UI/BackgroundTask/BackgroundTaskViewModel.swift`, `Echo/UI/ResumeProgress/ResumeProgressPromptView.swift`, `Echo/UI/ResumeProgress/ResumeProgressViewModel.swift`, `Echo/UI/Degradation/DegradationBannerView.swift`, `Echo/UI/Degradation/DegradationBannerViewModel.swift`, `Echo/UI/Onboarding/OnboardingView.swift`, `Echo/UI/Onboarding/OnboardingViewModel.swift`, `Echo/UI/Awakening/AwakeningSettingsView.swift`, `Echo/UI/Awakening/AwakeningSettingsViewModel.swift`.
- Create: `Echo/UI/AppShell/LiveAppAdapters.swift`; `Echo/Core/Models/DeviceMigrationPackage.swift`; `Echo/Core/Services/DeviceMigrationService.swift`; `Echo/Core/Actors/DeviceMigrationActor.swift`; `Echo/Core/Services/DataOverviewService.swift`; `EchoTests/Phase3F/3F.7_UIToCoreIntegrationTests.swift`; `EchoTests/Phase3F/3F.7_DeviceMigrationTests.swift`; `EchoTests/Phase3F/3F.7_DeviceMigrationSecurityTests.swift`; `EchoTests/Phase3F/3F.7_DataOverviewTests.swift`.
- Test/extend: `EchoTests/Phase3/AppShellTests.swift`; `EchoTests/Phase3/HomeViewModelTests.swift`; `EchoTests/Phase3/SearchViewModelTests.swift`; `EchoTests/Phase3/MemoryDetailViewModelTests.swift`; `EchoTests/Phase3/SettingsViewModelTests.swift`; `EchoTests/Phase3/BackgroundTaskPanelTests.swift`; `EchoTests/Phase3/ProgressActorTests.swift`; `EchoTests/Phase3/OnboardingTests.swift`; `EchoTests/Phase3/AwakeningDeliveryTests.swift`; `EchoTests/Phase3/Phase3IntegrationTests.swift`.
- Modify documentation/planning: `AGENTS.md`; `README.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/decisions/ADR-008-source-import-boundaries.md`; `docs/decisions/ADR-010-canonical-generation-lifecycle.md`; `docs/ui/architecture.md`; `docs/ui/automation-workflow.md`; `docs/ui/testing-and-artifacts.md`; `docs/ui/echo-readiness.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`.
- Read-only documentation: `docs/05-planning/phase3f-story-matrix.md`; `docs/ui/echo-memory-canvas-style.md`.
- Modify UIAutomation: `UIAutomation/Contracts/instances/search-to-detail-journey.json`; `UIAutomation/Contracts/instances/memory-detail-surface.json`; `UIAutomation/Contracts/instances/memory-detail-journey-basic.json`; `UIAutomation/Contracts/instances/memory-detail-state-loading.json`; `UIAutomation/Contracts/instances/memory-detail-state-loaded.json`; `UIAutomation/Contracts/instances/memory-detail-state-editing.json`; `UIAutomation/Contracts/instances/memory-detail-state-translated.json`; `UIAutomation/Contracts/instances/memory-detail-state-conflict.json`; `UIAutomation/Contracts/instances/memory-detail-state-error.json`; `UIAutomation/Contracts/instances/memory-detail-action-edit.json`; `UIAutomation/Contracts/instances/memory-detail-action-save.json`; `UIAutomation/Contracts/instances/memory-detail-action-translate.json`; `UIAutomation/Contracts/instances/memory-detail-action-delete.json`; `UIAutomation/Contracts/instances/memory-detail-action-delete-original.json`; `UIAutomation/Contracts/instances/memory-detail-action-remove-from-echo.json`; `UIAutomation/Contracts/instances/memory-detail-action-keep-local.json`; `UIAutomation/Contracts/instances/memory-detail-action-keep-external.json`; `UIAutomation/Contracts/instances/memory-detail-action-retry.json`; `UIAutomation/Contracts/instances/background-tasks-surface.json`; `UIAutomation/Contracts/instances/background-tasks-journey-basic.json`; `UIAutomation/Contracts/instances/background-tasks-state-loading.json`; `UIAutomation/Contracts/instances/background-tasks-state-loaded.json`; `UIAutomation/Contracts/instances/background-tasks-state-empty.json`; `UIAutomation/Contracts/instances/background-tasks-state-error.json`; `UIAutomation/Contracts/instances/background-tasks-action-open.json`; `UIAutomation/Contracts/instances/background-tasks-action-pause.json`; `UIAutomation/Contracts/instances/background-tasks-action-cancel.json`; `UIAutomation/Contracts/instances/background-tasks-action-retry.json`; `UIAutomation/Contracts/instances/resume-progress-surface.json`; `UIAutomation/Contracts/instances/resume-progress-journey-basic.json`; `UIAutomation/Contracts/instances/resume-progress-state-none.json`; `UIAutomation/Contracts/instances/resume-progress-state-checking.json`; `UIAutomation/Contracts/instances/resume-progress-state-prompt.json`; `UIAutomation/Contracts/instances/resume-progress-state-resumed.json`; `UIAutomation/Contracts/instances/resume-progress-state-restarted.json`; `UIAutomation/Contracts/instances/resume-progress-state-error.json`; `UIAutomation/Contracts/instances/resume-progress-action-start.json`; `UIAutomation/Contracts/instances/resume-progress-action-continue.json`; `UIAutomation/Contracts/instances/resume-progress-action-restart.json`; `UIAutomation/Contracts/instances/resume-progress-action-retry.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-loaded.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-photo-loaded.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-video-loaded.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-voice-loaded.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-translated.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-conflict.json`; `UIAutomation/Fixtures/memory-detail/memory-detail-error.json`; `UIAutomation/Fixtures/background-tasks/background-tasks-loaded.json`; `UIAutomation/Fixtures/background-tasks/background-tasks-empty.json`; `UIAutomation/Fixtures/background-tasks/background-tasks-error.json`; `UIAutomation/Fixtures/resume-progress/resume-progress-none.json`; `UIAutomation/Fixtures/resume-progress/resume-progress-pending.json`; `UIAutomation/Fixtures/resume-progress/resume-progress-error.json`.
- Create UIAutomation: `UIAutomation/Contracts/instances/settings-surface.json`; `UIAutomation/Contracts/instances/settings-state-loaded.json`; `UIAutomation/Contracts/instances/settings-action-startDeviceMigration.json`; `UIAutomation/Contracts/instances/settings-action-selectMigrationStrategy.json`; `UIAutomation/Contracts/instances/settings-action-applyBatchConflictResolution.json`; `UIAutomation/Contracts/instances/settings-action-exportDataOverview.json`; `UIAutomation/Contracts/instances/settings-journey-device-migration.json`; `UIAutomation/Contracts/instances/settings-journey-data-overview.json`; `UIAutomation/Fixtures/settings/settings-loaded.json`; `UIAutomation/Fixtures/settings/settings-migration-conflicts.json`; `UIAutomation/Fixtures/settings/settings-data-overview.json`.
- Read-only UIAutomation: `UIAutomation/Contracts/instances/degradation-banner-surface.json`; `UIAutomation/Contracts/instances/degradation-banner-state-normal.json`; `UIAutomation/Contracts/instances/degradation-banner-state-lowPower.json`; `UIAutomation/Contracts/instances/degradation-banner-state-thermal.json`; `UIAutomation/Contracts/instances/degradation-banner-state-modelDegraded.json`; `UIAutomation/Fixtures/degradation-banner/degradation-normal.json`; `UIAutomation/Fixtures/degradation-banner/degradation-low-power.json`; `UIAutomation/Fixtures/degradation-banner/degradation-thermal.json`; `UIAutomation/Fixtures/degradation-banner/degradation-model-degraded.json`.

**Interfaces**

- Consumes: composition root, canonical/search/feedback/task/progress/pending/audit/model/cache operations accepted and implemented in 3F.1 through 3F.6; accepted ADR-008/ADR-010 migration boundaries.
- Produces: default non-optional production ViewModels and actions for load/search/feedback/edit/delete/conflict/settings/progress/pause/cancel/resume/degradation; canonical `ECHOMIG1`/JCS format, NFC unsigned-UTF8 record ordering, duplicate-key rejection, exact concatenated payload stream with boundary-crossing records, length/hash validation, protected staging and atomic publication through `DeviceMigrationActor`; `AES-GCM-256+HKDF-SHA256` with archive `K_transfer`, derived `K_i`, stored nonces and exact AAD; OS-backup post-restore validation without key access; live `DataOverviewService` snapshots and JSON export.

**AC/spec inputs:** US-AWK-005/007, US-PRV-002/003/004, US-SYS-001, all US-SRC-007 migration package/local-backup/conflict/integrity/reingest/ExcludedAssets/audit ACs, all US-SRC-009 data-overview/update/export/audit ACs retained after merge into US-SYS-001, US-SET-001/002/003/004, US-RES-001/002/003/004, US-RET-001/002/003/004/005/006/007/008 and US-FBK-001/002/003.

☐ Write failing default-construction and real-adapter tests; assert Release contains no fixture fallback, fabricated counts, dead actions or silent errors. In `EchoTests/Phase3F/3F.7_DeviceMigrationTests.swift`, fail target-empty restore, overwrite, merge, per-item conflict, batch conflict, deterministic-ID corruption, missing-item reingest, ExcludedAssets migration, original-file bulk-export prohibition and audit-field cases before implementation. In `EchoTests/Phase3F/3F.7_DeviceMigrationSecurityTests.swift`, add RFC 8785 and unsigned UTF-8 ordering vectors, duplicate rejection, cross-boundary records, exact concatenation, sums and per-record hash negatives. Explicitly reject `chunkCount=0`, `chunkCount=1`, `recordCount=0`, empty `records` and missing data chunk index 1. Accept the smallest valid package only when chunk 0 is the smallest syntactically valid RFC 8785 canonical manifest satisfying all six mandatory root fields and one record, `recordCount=1`, `chunkCount=2`, data-only `totalPlaintextBytes=1`, and chunk 1 is one 1-byte final data chunk. Add separate manifest-length, data-only total, overflow-safe combined-size and free-disk/package-limit tests. Retain all crypto, framing, manifest-first, resource, path, lifecycle, cleanup, rollback and OS-backup cases. In `EchoTests/Phase3F/3F.7_DataOverviewTests.swift`, fail live count/storage/vector/model-state, <=5-second update, JSON export and `.dataOverviewAccessed` cases before implementation. ☐ Immediately after writing tests, run the complete §6.1 command for `EchoTests/UIToCoreIntegrationTests` separately, require XCTest executed test count > 0, fail the step if the suite is empty/not found, and record the observed RED:

```
xcodebuild test \
  -project Echo.xcodeproj \
  -scheme Echo \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:EchoTests/UIToCoreIntegrationTests
```

☐ Then run the complete §6.1 command for `EchoTests/DeviceMigrationTests` separately, require XCTest executed test count > 0, fail the step if the suite is empty/not found, and record the observed RED:

```
xcodebuild test \
  -project Echo.xcodeproj \
  -scheme Echo \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:EchoTests/DeviceMigrationTests
```

☐ Then run the complete §6.1 command for `EchoTests/DeviceMigrationSecurityTests` separately, require XCTest executed test count > 0, fail the step if the suite is empty/not found, and record the observed RED:

```
xcodebuild test \
  -project Echo.xcodeproj \
  -scheme Echo \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:EchoTests/DeviceMigrationSecurityTests
```

☐ Then run the complete §6.1 command for `EchoTests/DataOverviewTests` separately, require XCTest executed test count > 0, fail the step if the suite is empty/not found, and record the observed RED:

```
xcodebuild test \
  -project Echo.xcodeproj \
  -scheme Echo \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:EchoTests/DataOverviewTests
```

☐ Require observed RED from all four exact suites before any 3F.7 implementation. A missing run, empty/not-found suite, zero executed tests, green-before-implementation result or failure unrelated to the intended absent behavior blocks implementation until corrected and rerun. ☐ Implement the ADR-008/ADR-010 migration-security sub-contract exactly: mandatory `recordCount >= 1`, `chunkCount >= 2`, chunk 0 manifest and present data chunk 1; unconditional rejection of manifest-only archives; canonical JCS manifest; unsigned UTF-8 ordering/duplicate rejection; exact concatenated payload stream; cross-boundary records; exact slicing; count equality; every `byteLength >= 1`; overflow-safe sum and exact data-stream length; per-record hash before validity; publish only after every record validates. Preserve all crypto, header/framing, limits, rollback and OS-backup rules. ☐ Implement one surface at a time by wiring it to composition-owned live dependencies; retain fixture loaders only behind explicit DEBUG/UI-test configuration. Implement user-mediated AirDrop/system-share encrypted package import/export and Finder/iTunes encrypted local-backup restoration without CloudKit; migrate ExcludedAssets locally; never export all original memory files. `.deviceMigrationCompleted` must contain `fromDevice`, `toDevice`, `integrityCheckPassed`, `mergeStrategy` plus required global audit fields. Implement live photo/video/note counts, storage use, vector dimensions and model states with <=5-second refresh, JSON statistics export and `.dataOverviewAccessed`. ☐ Prove edit→persist→reindex, delete→transaction boundary, migration package confidentiality/authenticity, rejection/resource/cleanup/staging rollback, restore/conflict behavior, live data overview, real settings values and task progress across relaunch. Obtain Security Engineering Lead, Privacy Engineering Lead and Architecture Lead approval for the migration-security package, OS-backup, audit and overview boundaries. ☐ Run focused, the exact Phase 3 tests in Files, affected and full XCUITests, cumulative and Release gates. Complete dual-device Live Simulator Review on iPhone 17 Pro iOS 26.5 and iPhone 16 Pro iOS 18.x, export AX trees, unified logs and the structured manifest with `visualMediaCaptured: false`. ☐ Complete every operation and acceptance check in §4.6.7; update the existing evidence index and record evidence for DEF-37-001/38-001/38-002/39-1/39-2/39-3/42-001. Before §6.2.2, populate this task's exact §11.1 PR-body marker block from real results, remove every placeholder, and pass extraction validation. ☐ Prepare registered worktree/branch `feature/phase3f-ui-core-wiring-3F.7` through §6.2.1 and use its printed path for every later command; after implementation and verification, run the single §6.2.2 script with commit `feat(viewmodel): wire live core adapters` and PR `feat(viewmodel): wire live Core adapters [3F.7]`.

**Expected evidence:** separate complete command logs, nonzero tests and intended RED for all four 3F.7 suites; RFC 8785/order/mapping/hash vectors; explicit count/records/index rejection; smallest syntactically valid six-field/one-record canonical manifest with `recordCount=1`, `chunkCount=2`, data-only `totalPlaintextBytes=1` and one-byte final data chunk; manifest-length, data-only total and combined free-disk/package-bound evidence; overflow/short/trailing/hash failures; all crypto/framing/rollback evidence; Security/Privacy/Architecture approvals; fixture isolation.

### 3F.8: Awakening 与 system adapters

> ✅ **3F.8 已交付（2026-08-11）**：ADR-012 决策-1~7 落地——`CoreLocationProvider`（CLLocationManager 地理围栏 enter/exit + 权限感知）、`HealthKitSystemProvider`（符合 `CrossAppSourceProvider` sourceType="health"，US-SRC-010 3F.6 fusion；仅最小化时序样本；denied 不查询）、`LocalNotificationAdapter` + `NotificationResponseRouter`（请求/路由分离，内容最小化）、`AwakeningCardRepositoryActor`（SQLite 持久化 + 重启去重）；AwakeningPipeline 增补 best-effort 纪念日窗口 + `.dateAwakening` 审计；Settings/Home ViewModel 与 AppDelegate 装配完成。聚焦套件 AwakeningSystemAdaptersTests 19/19 + CrossAppHealthIntegrationTests 7/7，受影响套件全量回归通过。

**Files**

- Modify: `Echo/Core/Pipelines/AwakeningPipeline.swift`; `Echo/UI/Awakening/AwakeningSettingsViewModel.swift`; `Echo/UI/Home/HomeViewModel.swift`; `Echo/App/AppDelegate.swift`; `Echo/Config/Echo-Info.plist`; `Echo/Config/Echo.entitlements`.
- Create: `Echo/Core/Services/CoreLocationProvider.swift`; `Echo/Core/Services/HealthKitSystemProvider.swift`; `Echo/Core/Services/LocalNotificationAdapter.swift`; `Echo/Core/Services/NotificationResponseRouter.swift`; `Echo/Core/Actors/AwakeningCardRepositoryActor.swift`; `EchoTests/Phase3F/3F.8_AwakeningSystemAdaptersTests.swift`; `EchoTests/Phase3F/3F.8_CrossAppHealthIntegrationTests.swift`.
- Test/extend: `EchoTests/Phase2/AwakeningGeoTests.swift`; `EchoTests/Phase2/AwakeningEmotionTests.swift`; `EchoTests/Phase3/AwakeningDeliveryTests.swift`; `EchoTests/Phase3/HomeViewModelTests.swift`.
- Modify documentation/planning: `README.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/ui/testing-and-artifacts.md`; `docs/ui/echo-readiness.md`; `docs/decisions/ADR-012-awakening-system-boundary.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`.
- Read-only documentation: `docs/05-planning/phase3f-story-matrix.md`; `docs/ui/echo-memory-canvas-style.md`.
- Modify UIAutomation: `UIAutomation/Contracts/instances/awakening-settings-surface.json`; `UIAutomation/Contracts/instances/awakening-settings-state-loading.json`; `UIAutomation/Contracts/instances/awakening-settings-state-loaded.json`; `UIAutomation/Contracts/instances/awakening-settings-state-empty-permissions.json`; `UIAutomation/Contracts/instances/awakening-settings-state-unavailable.json`.
- Create UIAutomation: `UIAutomation/Contracts/instances/awakening-settings-state-error.json`; `UIAutomation/Contracts/instances/awakening-settings-state-all-disabled.json`; `UIAutomation/Contracts/instances/awakening-settings-action-toggleGeofence.json`; `UIAutomation/Contracts/instances/awakening-settings-action-toggleEmotion.json`; `UIAutomation/Contracts/instances/awakening-settings-action-toggleAnniversary.json`; `UIAutomation/Contracts/instances/awakening-settings-action-requestNotification.json`; `UIAutomation/Contracts/instances/awakening-settings-action-openSystemSettings.json`; `UIAutomation/Contracts/instances/awakening-settings-action-showGeofenceDetail.json`; `UIAutomation/Contracts/instances/awakening-settings-action-dismissGeofenceDetail.json`; `UIAutomation/Contracts/instances/awakening-settings-journey-basic.json`; `UIAutomation/Contracts/instances/awakening-settings-journey-no-permissions.json`; `UIAutomation/Contracts/instances/awakening-settings-journey-unavailable.json`; `UIAutomation/Fixtures/awakening-settings/awakening-settings-loading.json`; `UIAutomation/Fixtures/awakening-settings/awakening-settings-loaded.json`; `UIAutomation/Fixtures/awakening-settings/awakening-settings-no-permissions.json`; `UIAutomation/Fixtures/awakening-settings/awakening-settings-unavailable.json`; `UIAutomation/Fixtures/awakening-settings/awakening-settings-error.json`; `UIAutomation/Fixtures/awakening-settings/awakening-settings-all-disabled.json`.

**Interfaces**

- Consumes: `handleGeofenceEnter`, `HealthKitProvider`, `SentimentProvider`, search, policy, canonical card repository and the 3F.6 injected health-source provider protocol.
- Produces: permission-aware best-effort system signal delivery, persisted/de-duplicated cards, local notification request and response→detail route; live `HealthKitSystemProvider` conformance supplying minimized authorized temporal samples to 3F.6 US-SRC-010 fusion.

**AC/spec inputs:** US-AWK-001/002/003/005, US-SRC-010 HealthKit adapter ownership, accepted best-effort scheduling AC, HealthKit data-minimization and notification ADR.

☐ Write failing tests for denied/accepted location and health permissions, geofence enter/exit reset, date window, sentiment fallback/debounce, card persistence/dedupe, notification scheduling and response routing. In `EchoTests/Phase3F/3F.8_CrossAppHealthIntegrationTests.swift`, fail protocol conformance, authorization denial, minimized temporal sample mapping and live-provider-to-3F.6 fusion integration before implementation. ☐ Immediately after writing tests, run the complete §6.1 command for `EchoTests/AwakeningSystemAdaptersTests` separately, require XCTest executed test count > 0, fail the step if the suite is empty/not found, and record the observed RED:

```
xcodebuild test \
  -project Echo.xcodeproj \
  -scheme Echo \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:EchoTests/AwakeningSystemAdaptersTests
```

☐ Then run the complete §6.1 command for `EchoTests/CrossAppHealthIntegrationTests` separately, require XCTest executed test count > 0, fail the step if the suite is empty/not found, and record the observed RED:

```
xcodebuild test \
  -project Echo.xcodeproj \
  -scheme Echo \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -only-testing:EchoTests/CrossAppHealthIntegrationTests
```

☐ Require observed RED from both exact suites before any 3F.8 implementation. A missing run, green-before-implementation result or failure unrelated to the intended absent behavior blocks implementation until corrected and rerun. ☐ Implement adapters without storing raw health values; separate notification scheduling from response routing. Make `HealthKitSystemProvider` conform to the 3F.6 injected protocol, return only authorized minimized values inside the parsed temporal window and preserve source identity for `.crossAppSearch`. ☐ Run focused, the exact awakening/Home tests in Files, affected and full XCUITests, cumulative, Release, entitlement and purpose-string gates. Complete dual-device Live Simulator Review, AX tree export, unified logs and the structured manifest with `visualMediaCaptured: false`. ☐ Complete every operation and acceptance check in §4.6.8 and update the existing evidence index in the same PR. Before §6.2.2, populate this task's exact §11.1 PR-body marker block from real results, remove every placeholder, and pass extraction validation. ☐ Prepare registered worktree/branch `feature/phase3f-awakening-adapters-3F.8` through §6.2.1 and use its printed path for every later command; after implementation and verification, run the single §6.2.2 script with commit `feat(pipeline): add awakening system adapters` and PR `feat(pipeline): add awakening system adapters [3F.8]`.

**Expected evidence:** separate complete command logs, XCTest executed test counts > 0 and intended RED failure output for `EchoTests/AwakeningSystemAdaptersTests` and `EchoTests/CrossAppHealthIntegrationTests` before implementation; no empty/not-found suite accepted; authorization traces; injected test system signals through production adapters; HealthKit request completion plus readable/empty sample outcomes without inferred read authorization; minimized temporal sample mapping; live HealthKit provider conformance and 3F.6 fusion integration; `.crossAppSearch` source identity; persisted card/restart dedupe; notification request and tap route; explicit best-effort timing result.

### 3F.9: Apple Translation 与 grounded creation

**Files**

- Modify: `Echo/UI/Translation/TranslationService.swift`, `Echo/UI/Translation/TranslationCache.swift`, `Echo/UI/Detail/MemoryDetailViewModel.swift`, `Echo/UI/Creation/CreationViewModel.swift`, `Echo/UI/Creation/CreationView.swift`.
- Create: `Echo/UI/Translation/AppleTranslationService.swift`; `Echo/UI/Translation/PersistentTranslationCache.swift`; `Echo/Core/Pipelines/CreativePipeline.swift`; `Echo/Core/Services/CreationExportService.swift`; `EchoTests/Phase3F/3F.9_TranslationCreationTests.swift`. `Echo/Core/Pipelines/CreativePipeline.swift` and `Echo/Core/Services/CreationExportService.swift` are created only when the human-approved 3F.0 SYN decision retains creation; otherwise they are absent, production controls are removed, and absence is asserted.
- Test/extend: `EchoTests/Phase3/TranslationServiceTests.swift`, `EchoTests/Phase3/MemoryDetailViewModelTests.swift`, `EchoTests/Phase3/CreationViewModelTests.swift`, `EchoUITests/TranslationUITests.swift`, `EchoUITests/CreationUITests.swift`.
- Modify documentation/planning: `README.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/decisions/ADR-009-offline-model-runtime.md`; `docs/decisions/ADR-013-creation-export-boundary.md`; `docs/ui/testing-and-artifacts.md`; `docs/ui/echo-readiness.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`.
- Read-only documentation: `docs/05-planning/phase3f-story-matrix.md`; `docs/ui/echo-memory-canvas-style.md`.
- Modify UIAutomation: `UIAutomation/Contracts/instances/translation-surface.json`; `UIAutomation/Contracts/instances/translation-journey-basic.json`; `UIAutomation/Contracts/instances/translation-state-original.json`; `UIAutomation/Contracts/instances/translation-state-translating.json`; `UIAutomation/Contracts/instances/translation-state-translated.json`; `UIAutomation/Contracts/instances/translation-state-cached.json`; `UIAutomation/Contracts/instances/translation-state-low-confidence.json`; `UIAutomation/Contracts/instances/translation-state-error.json`; `UIAutomation/Contracts/instances/translation-action-toggle.json`; `UIAutomation/Contracts/instances/translation-action-retry.json`; `UIAutomation/Contracts/instances/creation-surface.json`; `UIAutomation/Contracts/instances/creation-journey-generate-save-basic.json`; `UIAutomation/Contracts/instances/creation-journey-prompt-edit-confirm.json`; `UIAutomation/Contracts/instances/creation-state-idle.json`; `UIAutomation/Contracts/instances/creation-state-empty.json`; `UIAutomation/Contracts/instances/creation-state-generating.json`; `UIAutomation/Contracts/instances/creation-state-generated.json`; `UIAutomation/Contracts/instances/creation-state-share-handoff.json`; `UIAutomation/Contracts/instances/creation-state-error.json`; `UIAutomation/Contracts/instances/creation-action-select-template.json`; `UIAutomation/Contracts/instances/creation-action-edit-prompt.json`; `UIAutomation/Contracts/instances/creation-action-confirm-prompt.json`; `UIAutomation/Contracts/instances/creation-action-reset-prompt.json`; `UIAutomation/Contracts/instances/creation-action-generate.json`; `UIAutomation/Contracts/instances/creation-action-retry.json`; `UIAutomation/Contracts/instances/creation-action-copy.json`; `UIAutomation/Contracts/instances/creation-action-export.json`; `UIAutomation/Contracts/instances/creation-action-share.json`; `UIAutomation/Contracts/instances/creation-action-save-to-notes.json`; `UIAutomation/Fixtures/translation/translation-zh-en-high.json`; `UIAutomation/Fixtures/translation/translation-zh-en-low.json`; `UIAutomation/Fixtures/translation/translation-zh-en-cached.json`; `UIAutomation/Fixtures/translation/translation-error.json`; `UIAutomation/Fixtures/creation/creation-idle.json`; `UIAutomation/Fixtures/creation/creation-empty.json`; `UIAutomation/Fixtures/creation/creation-prompt-draft.json`; `UIAutomation/Fixtures/creation/creation-generated-report.json`; `UIAutomation/Fixtures/creation/creation-generated-letter.json`; `UIAutomation/Fixtures/creation/creation-share-handoff.json`; `UIAutomation/Fixtures/creation/creation-error.json`.
- Create UIAutomation: `UIAutomation/Contracts/instances/translation-state-availability-checking.json`; `UIAutomation/Contracts/instances/translation-state-unavailable.json`; `UIAutomation/Contracts/instances/translation-journey-availability-fallback.json`; `UIAutomation/Fixtures/translation/translation-availability-checking.json`; `UIAutomation/Fixtures/translation/translation-unavailable.json`.

**Interfaces**

- Consumes: `TranslationService.translate`, preferred language policy, terminology JSON, canonical/search provenance, optional approved offline LLM/aligner.
- Produces: availability-checked display translation, seven-day persistent cache, grounded output with source anchors, Markdown/PDF/share exports and user-mediated Notes handoff.

**AC/spec inputs:** US-DIS-002, the exact retained subset of US-SYN-001/002/003/004/005/006/007/008 recorded by 3F.0, accepted Notes/export and LLM decisions, AGENTS language/terminology contracts.

☐ Write failing tests for LanguageAvailability, uncertain NLTagger fallback, terminology precedence, TTL/relaunch, source anchors, language aligner retry≤1, Markdown/PDF content and share handoff. ☐ Set `FOCUSED_SUITE=EchoTests/TranslationCreationTests` and run the complete §6.1 focused command. Confirm RED. ☐ Implement Apple Translation only at display layer; never fabricate a translation quality score. ☐ If SYN remains, implement grounded generation strictly through approved offline runtime; remove `notes://echo/...` and use visible system share/export flow. If SYN is out of v1, remove unreachable production controls and prove scope consistency. ☐ Run focused, the exact translation/creation tests in Files, affected and full XCUITests, cumulative, Release and offline gates. Complete dual-device Live Simulator Review, AX tree export, unified logs and the structured manifest with `visualMediaCaptured: false`. ☐ Complete every operation and acceptance check in §4.6.9; update the existing evidence index and record evidence for DEF-43-002/003 and DEF-44-001. Before §6.2.2, populate this task's exact §11.1 PR-body marker block from real results, remove every placeholder, and pass extraction validation. ☐ Prepare registered worktree/branch `feature/phase3f-translation-creation-3F.9` through §6.2.1 and use its printed path for every later command; after implementation and verification, run the single §6.2.2 script with commit `feat(service): add translation and creation` and PR `feat(service): add translation and creation [3F.9]`.

**Expected evidence:** real supported language-pair translation; uncertain fallback; cache survives relaunch/expires at seven days; grounded anchor validation; exported Markdown/PDF; system share sheet; no fabricated Notes URL.

### 3F.10: i18n、accessibility 与 production errors

**Files**

- Modify: `Echo/UI/AppShell/AppRootView.swift`; `Echo/UI/AppShell/ContentView.swift`; `Echo/UI/AppShell/AppViewModel.swift`; `Echo/UI/Home/HomeView.swift`; `Echo/UI/Home/HomeViewModel.swift`; `Echo/UI/Search/SearchView.swift`; `Echo/UI/Search/SearchViewModel.swift`; `Echo/UI/Detail/MemoryDetailView.swift`; `Echo/UI/Detail/MemoryDetailViewModel.swift`; `Echo/UI/Settings/SettingsView.swift`; `Echo/UI/Settings/SettingsViewModel.swift`; `Echo/UI/Onboarding/OnboardingView.swift`; `Echo/UI/Onboarding/OnboardingViewModel.swift`; `Echo/UI/Awakening/AwakeningSettingsView.swift`; `Echo/UI/Awakening/AwakeningSettingsViewModel.swift`; `Echo/UI/BackgroundTask/BackgroundTaskPanelView.swift`; `Echo/UI/BackgroundTask/BackgroundTaskViewModel.swift`; `Echo/UI/Creation/CreationView.swift`; `Echo/UI/Creation/CreationViewModel.swift`; `Echo/UI/Degradation/DegradationBannerView.swift`; `Echo/UI/Degradation/DegradationBannerViewModel.swift`; `Echo/UI/ResumeProgress/ResumeProgressPromptView.swift`; `Echo/UI/ResumeProgress/ResumeProgressViewModel.swift`; `Echo/UI/Translation/TranslationService.swift`; `Echo/UI/Translation/TranslationCache.swift`; `Echo/Core/Models/ErrorEnums.swift`; `Echo/Core/Actors/PendingOpsActor.swift`; `.github/workflows/ci.yml`.
- Modify (human-approved Files-list expansion, 2026-08-12): `Echo/Core/Models/AuditEvent.swift`; `Echo/Core/Actors/DeviceMigrationActor.swift`; `Echo/Core/Actors/PrivacyActor.swift`. Strict scope annotations:
  - `Echo/Core/Models/AuditEvent.swift` — DECISION-1 (2026-08-12, human-approved): add ONLY the audit event cases the locked ACs require: `.languageUnified` (US-DIS-001 AC-5, carries `newLanguage`) and `.backgroundTaskUIAccessed` (US-SYS-001 AC-7). `.backgroundTaskInterrupted` (US-SYS-001 AC-7, AGENTS.md §7.3, fields action=pause/cancel, resumePoint, userChoiceOnRestart) already exists — verified, NOT re-added. No other modifications to this file.
  - `Echo/Core/Actors/DeviceMigrationActor.swift` + `Echo/Core/Actors/PrivacyActor.swift` — DECISION-2 (2026-08-12, human-approved): resolve DEF-59-004 ONLY — add the missing PrivacyCheckpoint on the migration export path (R-006) via a new `.migration` PrivacyOperation case and entry `validate()` in `exportPackage`; no other behavior changes to either file.
  - **Scope clarifications (2026-08-12, recorded in delivery)**: (a) `Echo/Core/Models/AuditEvent.swift` additionally gains `.degradationWarning` — the locked US-RES-002 AC-5 / US-RES-003 AC-5 require degradation audit events; hash-only content per AGENTS.md §5.4. (b) `Echo/Core/Services/LanguageAligner.swift` (DEF-52-001) and `Echo/Core/Pipelines/AwakeningPipeline.swift` (DEF-60-001 notification bodies) are modified minimally for String Catalog migration — both are the exact files the task's MUST-resolve deferred list points to; no behavior change beyond localization carrier.
- Create: `Echo/Core/Utils/SystemMonitor.swift`; `Echo/Resources/Localizable.xcstrings`; `Scripts/validate_localization.py`; `Scripts/validate_accessibility_contracts.py`; `Scripts/validate_static_bans.py`; `EchoTests/Phase3F/3F.10_LocalizationAccessibilityErrorTests.swift`; `EchoUITests/LocalizationAccessibilityUITests.swift`; `EchoUITests/DegradationUITests.swift`.
- Test/extend: `EchoTests/Phase3/ErrorHandlerUITests.swift`; `EchoUITests/OnboardingUITests.swift`; `EchoUITests/SearchJourneyUITests.swift`; `EchoUITests/MemoryDetailMediaUITests.swift`; `EchoUITests/BackgroundTaskPanelUITests.swift`; `EchoUITests/ResumeProgressPromptUITests.swift`; `EchoUITests/TranslationUITests.swift`; `EchoUITests/CreationUITests.swift`.
- Modify documentation/planning: `AGENTS.md`; `README.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/decisions/ADR-011-task-progress-boundary.md`; `docs/ui/README.md`; `docs/ui/automation-workflow.md`; `docs/ui/testing-and-artifacts.md`; `docs/ui/echo-readiness.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`.
- Read-only documentation: `docs/05-planning/phase3f-story-matrix.md`; `docs/ui/echo-memory-canvas-style.md`.
- Modify UIAutomation: `UIAutomation/Contracts/instances/degradation-banner-surface.json`; `UIAutomation/Contracts/instances/degradation-banner-state-normal.json`; `UIAutomation/Contracts/instances/degradation-banner-state-lowPower.json`; `UIAutomation/Contracts/instances/degradation-banner-state-thermal.json`; `UIAutomation/Contracts/instances/degradation-banner-state-modelDegraded.json`; `UIAutomation/Fixtures/degradation-banner/degradation-normal.json`; `UIAutomation/Fixtures/degradation-banner/degradation-low-power.json`; `UIAutomation/Fixtures/degradation-banner/degradation-thermal.json`; `UIAutomation/Fixtures/degradation-banner/degradation-model-degraded.json`.
- Create UIAutomation: `UIAutomation/Contracts/instances/degradation-banner-action-dismiss.json`; `UIAutomation/Contracts/instances/degradation-banner-action-retryModelLoad.json`; `UIAutomation/Contracts/instances/degradation-banner-action-toggleBackgroundTasks.json`; `UIAutomation/Contracts/instances/degradation-banner-action-openSettings.json`; `UIAutomation/Contracts/instances/degradation-banner-journey-lifecycle.json`; `UIAutomation/Contracts/instances/degradation-banner-state-l1Transient.json`; `UIAutomation/Contracts/instances/degradation-banner-state-l2Recoverable.json`; `UIAutomation/Contracts/instances/degradation-banner-state-l3Blocking.json`; `UIAutomation/Contracts/instances/degradation-banner-state-l4Conflict.json`; `UIAutomation/Contracts/instances/degradation-banner-action-retryL1.json`; `UIAutomation/Contracts/instances/degradation-banner-action-retryPendingOperation.json`; `UIAutomation/Contracts/instances/degradation-banner-action-openBlockingRecovery.json`; `UIAutomation/Contracts/instances/degradation-banner-action-resolveConflict.json`; `UIAutomation/Contracts/instances/degradation-banner-journey-l1-l4.json`; `UIAutomation/Fixtures/degradation-banner/degradation-l1-transient.json`; `UIAutomation/Fixtures/degradation-banner/degradation-l2-recoverable.json`; `UIAutomation/Fixtures/degradation-banner/degradation-l3-blocking.json`; `UIAutomation/Fixtures/degradation-banner/degradation-l4-conflict.json`.

**Interfaces**

- Consumes: preferred language policy, L1-L4, PendingOperations, ProcessInfo power/thermal sources and the live UI states produced by 3F.7, 3F.8 and 3F.9.
- Produces: complete zh-Hans/en-US catalog; deterministic AX labels/order/announcements; Dynamic Type/contrast/reduced-motion behavior; live degradation/error actions.

**AC/spec inputs:** US-DIS-001/003/004, US-SET-001, US-RES-001/002/003/004, US-SYS-001, US-SRC-009 merged-into-US-SYS-001 error/localization/accessibility behavior, AGENTS language and L1-L4 contracts.

☐ Write failing catalog parity/hardcoded-string tests, AX identifiers/order/announcement tests, AX5 layout tests and L1-L4/power/thermal fault tests. ☐ Set `FOCUSED_SUITE=EchoTests/LocalizationAccessibilityErrorTests` and run the complete §6.1 focused command. Confirm RED. ☐ Implement String Catalog migration for all visible copy; persist language policy and map Traditional/other Chinese to zh-Hans with one-time notice. ☐ Wire L1 retry, L2 PendingOperations/manual retry, L3 blocking recovery and L4 conflict UI; power/thermal sources must change actual runtime behavior. ☐ Run focused, the exact XCUITests in Files in zh-Hans and en-US, cumulative, Release and static gates. Complete dual-device Live Simulator Review, AX tree export, unified logs and the structured manifest with `visualMediaCaptured: false`. ☐ Complete every operation and acceptance check in §4.6.10; update the existing evidence index and record evidence for every 3F.10 deferred item listed in §4.4. Before §6.2.2, populate this task's exact §11.1 PR-body marker block from real results, remove every placeholder, and pass extraction validation. ☐ Prepare registered worktree/branch `feature/phase3f-i18n-accessibility-3F.10` through §6.2.1 and use its printed path for every later command; after implementation and verification, run the single §6.2.2 script with commit `feat(view): add production localization accessibility` and PR `feat(view): add production localization and accessibility [3F.10]`.

**Expected evidence:** catalog key parity 100%; visible hardcoded strings 0; US-SRC-009 merged-into-US-SYS-001 localized/accessible error and resume trace; zh-Hans/en-US automated assertions、AX trees 与双设备人工审批记录；AX5/reduced-motion/contrast results; L1-L4 and power/thermal action traces. 遵循 `AGENTS.md`，不生成 screenshot/video。

### 3F.11: Production E2E 与 Phase 4 准入门禁

**Files**

- Modify: `Echo.xcodeproj/project.pbxproj`; `.github/workflows/ci.yml`; `Scripts/coverage_gate.py`; `Echo/Config/Echo-Info.plist`; `Echo/Config/Echo.entitlements`; `EchoShareExtension/Info.plist`; `EchoShareExtension/EchoShareExtension.entitlements`; `Echo/Assets.xcassets/Contents.json`; `Echo/Assets.xcassets/AppIcon.appiconset/Contents.json`.
- Create: `Echo/Config/Release.xcconfig`; `Echo/Config/PrivacyInfo.xcprivacy`; `EchoTests/Phase3F/Phase3FIntegrationTests.swift`; `EchoUITests/Phase3FProductionE2ETests.swift`; `Scripts/validate_release_compliance.py`; `Scripts/validate_release_compliance_tests.py`; `CHANGELOG.md`; `docs/05-planning/app-store-privacy-disclosure.md`; `docs/05-planning/phase3f-release-checklist.md`.
- Modify documentation/planning: `AGENTS.md`; `README.md`; `docs/INDEX.md`; `docs/01-spec/用户故事与验收标准规格书.md`; `docs/02-architecture/架构设计文档.md`; `docs/02-architecture/技术选型文档.md`; `docs/02-architecture/数据流全链路技术说明文档.md`; `docs/03-implementation/双语言实现说明文档.md`; `docs/03-implementation/开发避坑与关键注意点手册.md`; `docs/05-planning/开发计划安排文档.md`; `docs/05-planning/model-provenance-register.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/task-status.json`; `docs/05-planning/deferred-items.json`; `docs/ui/testing-and-artifacts.md`; `docs/decisions/ADR-014-release-compliance-boundary.md`.
- Create documentation: `CHANGELOG.md`; `docs/05-planning/app-store-privacy-disclosure.md`; `docs/05-planning/phase3f-release-checklist.md`.
- Read-only documentation: `docs/05-planning/phase3f-story-matrix.md`.
- Test: modify no existing test file. Run the two created test files, `Scripts/validate_release_compliance_tests.py`, every existing unit/integration/UI suite, model verification, coverage, compliance and the no-fixture journey.

**Interfaces**

- Consumes: the composition and consent state from 3F.1; real source adapters from 3F.2; offline model inference from 3F.3; canonical generation lifecycle from 3F.4; production ingestion from 3F.5; search and feedback from 3F.6; live UI wiring from 3F.7; awakening adapters from 3F.8; translation/creation scope from 3F.9; localization, accessibility and error behavior from 3F.10.
- Produces: the first proof of full startup readiness with real model artifacts, reference inference, restored active route, built indexes and default App search availability; `Scripts/validate_release_compliance.py` target discovery and per-target findings for every executable app/extension target, explicitly `Echo` and `EchoShareExtension`; signed-off `3F.11` gate result; only after human merge, Phase 4 unlock/handoff.

**AC/spec inputs:** every in-scope P0/P1 AC including US-SRC-010 no-fixture E2E, AGENTS CI contract, accepted release/signing/privacy ADRs.

> **2026-08-31 范围修订**：下方 checklist 保留为 3F.11 的原始执行记录，但其中“受控签名/archive/export”和“全局 coverage >=95%”不再作为 Phase 3F 功能闭环完成证据。它们分别迁移到 Phase 4 `4.9` 与 `4.6`，且仍在 `4.10` RC 前强制通过；3F.11 以实际已取得的 unsigned Release build、临时 coverage ratchet、no-fixture 基本闭环和 per-target 合规证据完成。此修订不降低最终发布门禁。

☐ Verify all dependencies are human-merged `done`; scan every active deferral and reject the gate if any in-scope item lacks closure evidence. ☐ Write failing production E2E and compliance tests before product fixes; repair an existing test only when its assertion contradicts an accepted AC. No `-ui-fixture`, fixture loader, direct actor seeding, manual DB injection or stub model may prepare the journey. ☐ Run the complete §6.1 UI production E2E focused command with `EchoUITests/Phase3FProductionE2ETests`, then run `python3 -m unittest Scripts/validate_release_compliance_tests.py`. Compliance tests must fail when target discovery omits `Echo` or `EchoShareExtension`, when any executable app/extension target is skipped, or when one target's seeded violation is reported under another target. Confirm RED in both required gates before corrections. ☐ Implement only the product, build, test-tool or compliance corrections demonstrated by those failures; preserve every approved threshold. ☐ Execute clean install→onboarding/deny→consent→Photos/share import→real inference→canonical generation→search/filter/feedback→US-SRC-010 health+memory and location+photo intents through live providers with temporal alignment/source labels/`.crossAppSearch` source list→edit/conflict/delete→awakening→translation/creation when in scope→task cancel/restart/resume→consent revoke/purge→relaunch. The E2E must prove HealthKit request lifecycle and readable/empty sample behavior without asserting an unobservable read grant or denial. ☐ Run Release simulator and device compile; in controlled release credentials environment validate archive/export, extension/App Group provisioning and App Store distribution signing. ☐ Run `bash Scripts/prepare_models.sh --verify-only`; require revised manifest 100%, license/SBOM/checksum/reference inference and a fully approved `docs/05-planning/model-provenance-register.md`. ☐ Run focused production E2E/compliance tests, then cumulative unit/integration/UI suites with zero failures. Repair `Scripts/coverage_gate.py`; require hard global line coverage `>=95%` and changed production-file line coverage `>=95%`. Close DEF-38-003 only with the final report proving both thresholds. A temporary 3F.0 ratchet expires here and cannot satisfy this gate. ☐ Implement `Scripts/validate_release_compliance.py` so it enumerates every executable app/extension target from `Echo.xcodeproj/project.pbxproj`, explicitly asserts `Echo` and `EchoShareExtension`, resolves each built product, and scans each target independently for forbidden networking symbols/endpoints, linked analytics/cloud SDKs, embedded secrets, effective entitlements, privacy-manifest applicability, required-reason APIs and purpose strings. Aggregate output must retain target identity and fail if discovery or any target scan is incomplete. ☐ Validate `PrivacyInfo.xcprivacy`, required-reason APIs, Photo Library/Location/HealthKit/Microphone/Speech purpose strings, entitlements, Background Modes and App Icon. Release Quality Lead owns implementation/evidence; Release Manager and Privacy Engineering Lead must approve the target inventory and every per-target result. ☐ Revalidate the 3F.1 AuditLog contract in the Release product: required columns `eventType`, `timestamp`, `traceID`, `policyVersion`, `success` are non-null; persisted content is hash-only; rows older than 30 days are removed while boundary rows remain; audit storage reports `NSFileProtectionComplete`. Any failure blocks 3F.11 and requires Privacy Engineering Lead re-approval after correction. ☐ Re-run `EchoTests/DeviceMigrationSecurityTests` against the 3F.11 Release candidate with XCTest executed test count > 0 and record every result for mandatory package shape/rejections; the smallest syntactically valid RFC 8785 six-field/one-record manifest plus one one-byte final data chunk; data-only totalPlaintextBytes and exact sum/stream equality; separate manifest/data/combined resource limits; ordering/mapping/hashes; and all existing crypto, framing, filesystem, rollback and OS-backup cases. Any failed, empty or not-found suite blocks release. Attach fresh Security Engineering Lead, Privacy Engineering Lead and Architecture Lead approval after the passing result. ☐ Run static bans, PrivacyCheckpoint 100%, strict concurrency, SwiftLint, ledger validator and secret/artifact scan; attach `Echo` and `EchoShareExtension` per-target compliance reports plus the complete executable-target inventory. ☐ Create `CHANGELOG.md`, `docs/05-planning/app-store-privacy-disclosure.md` and `docs/05-planning/phase3f-release-checklist.md`; populate privacy-policy version, App Store answers, signing approver, evidence location, artifact digest and retention/expiry fields. ☐ Complete every operation and acceptance check in §4.6.11. Finalize the existing evidence index with pre-merge evidence only and set the task to `review` only after every gate passes. Before §6.2.2, populate this task's exact §11.1 PR-body marker block from real results, remove every placeholder, and pass extraction validation. ☐ Prepare registered worktree/branch `test/phase3f-production-gate-3F.11` through §6.2.1 and use its printed path for every later command; after implementation and verification, run the single §6.2.2 script with commit `test(config): add phase 3f production gate` and PR `test(config): add Phase 3F production gate [3F.11]`.

**Expected evidence:** all command logs with commit SHA/timestamp/exit 0; no-fixture run manifest; model/coverage/per-target compliance reports; complete nonzero migration-security results including minimum-shape rejection, smallest canonical manifest plus one-byte data chunk, data-only totals, separate/combined resource bounds, ordering/mapping/sums/hashes and all JCS/crypto/framing/rollback rules; Security/Privacy/Architecture approval; archive/signing report; P0/P1 zero; restart/rollback/purge evidence; Release Manager and Privacy acceptance.

## 8. Review feedback 规则

1. 拉取 PR 全部 review threads 和 CI logs；逐条分类为有效缺陷、过度建议或误报，并写技术理由。
2. 有效缺陷：先补失败测试，再修最小代码，重跑 focused→cumulative→Release→static；push 后刷新 PR AC 表、task notes、出生证明和 evidence index。
3. 过度建议/误报：以规格、代码和执行证据回复，不做迎合式改动。
4. 本 PR 不修的真实问题必须新增 deferred 条目，含 `id/pr/title/severity/location/reason/owners/target_tasks/acceptance_evidence/tracking_status/recheck_trigger/deferred_at`；in-scope P0/P1 不允许延期越过 `3F.11`。
5. Review 修复仍不得自动 merge、关闭 PR 或删除分支。

## 9. 失败恢复与停止条件

- 第一次失败：保存完整日志，形成至少三个可证伪假设，运行最小复现。
- 第二种方案失败：检查 actor 边界、schema/migration、Apple entitlement、模型 artifact 和 test isolation，避免重复同一路径。
- 第三种不同方案失败：恢复到最近绿色提交，任务改为 `blocked`，记录三次尝试、证据、影响与 2-3 个可执行决策选项，请求架构/产品裁决。
- 立即停止并阻断：规格仍矛盾、私有/不存在 API、缺少合法模型/签名资产、不可逆迁移风险、rollback 失败、隐私红线冲突、用户数据/凭据进入 artifact、依赖未 `done`。
- 禁止用删除测试、放宽断言、延长任意 sleep、切换 fixture 或降低阈值来“恢复”。

## 10. Phase 4 解锁与 handoff

`3F.11` PR 只提交 pre-merge gate evidence。实现 Agent 不得填写 merge SHA、把 `3F.11` 或 Phase 3F 写为 `done`，也不得把 `current_phase` 改为 `"4"`。只有人类实际合并 `3F.11` 后，才能由人类显式触发以下 finalizer。

> **完成记录（2026-08-31）**：PR #63 已于 2026-08-26T03:25:13Z 由 `logan-suu` 合并到 `dev-1.0`，merge commit `18784ea426d411ab539c5bd9c0eecd4548ae7e7a`，且该提交可从 `dev-1.0` 到达。人类产品负责人于 2026-08-31 明确触发 `3F.finalize`，接受“基本生产功能闭环 + no-fixture E2E + unsigned Release build + 基线质量/合规”作为 Phase 3F 完成边界。全局覆盖率 `>=95%`、受控签名/archive/export、最终 App Icon、Golden/性能、最终 RC 与 TestFlight 不被追认成 3F 已完成证据，继续由 Phase 4 的 4.1~4.14 验证。

### 10.1 Human-triggered post-merge finalizer record

- **id:** `3F.finalize`
- **title:** `Record 3F.11 merge and unlock Phase 4`
- **status before trigger:** `blocked_on_human_merge`
- **owner:** Release Manager
- **approver:** Human merge actor and Product and Architecture Lead
- **documents_required:** `docs/05-planning/task-status.json`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/开发计划安排文档.md`.
- **dependencies:** `3F.11` PR is merged into `dev-1.0`, and the host reports an immutable merge commit SHA.
- **acceptance_evidence:** 3F.11 PR URL; merge commit SHA reachable from `dev-1.0`; merged head and base identities; finalizer actor/time; Phase 4 ready-task diff; evidence-index link; proof that no branch was deleted.
- **prohibited:** Running before merge, accepting a PR head SHA as merge SHA, changing gate results, fabricating post-merge evidence, or starting Phase 4 implementation in the finalizer change.

☐ Verify the 3F.11 PR is merged into `dev-1.0` and record its immutable merge commit SHA, PR URL, merged head SHA, base, human merge actor and UTC merge time in `docs/05-planning/phase3f-evidence-index.md`. ☐ Change only `3F.11: merged → done`, Phase 3F `integration_test: passed`, Phase 3F `status: done`, and finalizer `status: done`; preserve all pre-merge evidence and append post-merge fields. ☐ Change `current_phase: "4"`; evaluate explicit `phase_order` and `entry_gate`; set only `4.1` through `4.9` to `ready`; leave `4.10` through `4.14` as `backlog`. ☐ Update `docs/05-planning/phase3f-execution-plan.md` and `docs/05-planning/开发计划安排文档.md` with the completed handoff record and exact merge SHA, without altering accepted task scope or thresholds. ☐ Confirm Phase 4 is qualification, not unfinished feature implementation; TestFlight depends on completed `4.10` Release Candidate. ☐ Preserve every local and remote branch; post the handoff comment to the 3F.11 PR or designated tracking issue; wait for a separate human Phase 4 start action.

**Finalizer result**: completed at `2026-08-31T15:42:40Z`; `3F.11`, Phase 3F and `3F.finalize` are `done`; Phase 4 is current; `4.1`~`4.9` are `ready`; `4.10`~`4.14` remain `backlog`; both local and remote `test/phase3f-production-gate-3F.11` branches are preserved. No Phase 4 implementation was started by this finalizer.

## 11. Evidence 模板

### 11.1 每任务证据

`docs/05-planning/phase3f-evidence-index.md` 中每个 3F.0 至 3F.11 task entry 必须包含一对精确 marker。写入时把 `<TASK_ID>` 替换为当前精确任务 ID，例如 `3F.6`。每项证据必须记录 §6.2.1 打印的 registered worktree path、branch 与 clean/rebase result；3F.0 还必须记录 target-machine human bootstrap approver、UTC authorization time、docs-only scope、初始原子 `in_progress` 写入和 validation 后 pre-delivery `review` transition。在单一 §6.2.2 脚本前，必须用当前任务真实 AC、测试、实现、文档、ledger、风险、deferred 与 self-check 结果替换 marker 内所有模板文本，形成完整英文 PR body；不得保留 placeholder、TODO、TBD、TBC 或 FIXME。Marker 只界定正文，不进入提取后的 PR body。§6.2.2 只接受当前任务恰好一对 marker、八个按序且非空的必需章节，以及 AC Coverage 内恰好一个精确 table header；脚本完成 PR create/update 和 ledger commit 后，只向已验证的本地 body 写入 `## Task Ledger`，完整复验后 final edit，绝不重新读取 remote PR body。

```
## Phase 3F Task Evidence
- Task / commit / branch / PR:
- Registered worktree path / ownership / clean rebase result:
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only):
- Pre-delivery task status and transition evidence:
- Quoted AC and architecture constraints:
- RED test command and observed failure:
- Focused test command / exit / passed count:
- Cumulative test command / exit / passed count:
- Release simulator and device commands / exits:
- Static/privacy/model/compliance commands / exits:
- Production path exercised:
- Files and documentation changed:
- Deferred items closed or created, with evidence links:
- Known risks that do not weaken an in-scope gate:

<!-- PR-BODY:<TASK_ID>:START -->
## Overview
<fill with the completed task overview>

## Related Specs
<fill with exact task, story, AC, ADR, and document references>

## AC Coverage
| AC # | Spec Summary | Test File | Implementation | Status |
| --- | --- | --- | --- | --- |
| <fill AC identifier> | <fill verified summary> | <fill exact test path> | <fill exact implementation path> | <fill verified status> |

## Testing
<fill with exact commands, exits, counts, and evidence links>

## Documentation and Ledger
<fill with exact documentation and ledger changes>

## Risks
<fill with verified risks or an explicit evidence-backed none statement>

## Deferred Items
<fill with evidence-backed dispositions or an explicit evidence-backed none statement>

## Self-Check
<fill with completed security, privacy, scope, and delivery checks>
<!-- PR-BODY:<TASK_ID>:END -->
```

### 11.2 3F.11 gate matrix

```
| Gate | Command/environment | Expected | Evidence | Result |
|---|---|---|---|---|
| Release simulator/device | exact xcodebuild commands | exit 0 | log + SHA | |
| Unit/integration/UI | serial full suites | 100% pass | xcresult summary | |
| Coverage | coverage_gate.py | approved contract met | report | |
| Models | prepare_models + reference inference | 100% present/valid/offline | manifest/SBOM/log | |
| No-fixture E2E | clean install journey | all steps pass | run manifest/AX tree/unified log | |
| Privacy/static | scans + purge | 100%/zero violations | report | |
| Release compliance | manifest/purpose/entitlements/signing/icon | all valid | archive checklist | |
| P0/P1/deferred | ledger validator | 0/0; no gating open | JSON report | |
```

## Appendix A: RED 基线（只用于证明为何必须执行本计划）

审计日期 2026-08-03，基线 `dev-1.0` / `ad75a203`：生产完成证据 `0/66`；16 Partial、25 Stub、9 Absent/unmapped、2 Deferred、14 Impossible/spec-invalid。Release device/simulator 均 exit 65；EchoTests 718/720、2 失败；EchoUITests 31/33、2 失败，其中 29 条旅程使用 `-ui-fixture`；纳入文件覆盖率 79.568%，Echo.app 40.943%，覆盖率脚本 exit 1；模型 Bundle 0/6；no-fixture 新装停在 “Echo is getting ready…”。这些数字仅是 RED 起点，不能被复制为完成证据；所有完成声明必须来自当前任务 commit 上的新鲜执行结果。

## Appendix B: 结构自审记录

审查对象：当前 Phase 3F 指令。审查方式是只读 Python 断言与精确文本扫描，不修改目标仓库文件。

- **Record and fence check:** 解析全部 fences，并按顺序连接 Phase 3F 与 Phase 4 JSON 数组元素。结果：pass，Phase 3F records 12，Phase 4 records 14，JSON fences 12，全部 28 个 fences 均小于 9,000 UTF-8 bytes，最大 fence 8,894 bytes，plain-text contract headings 12。
- **Exact-set check:** 对每个任务提取 §4.6 tracked `Exact paths` 并与 §4.2 `documents_required` 做集合等值比较，再验证全部 tracked contract paths 出现在同任务 Files。结果：pass，12/12 task sets equal，ignored external inputs 0，Files 缺失 0。
- **Bootstrap check:** 检查 pre-merge 当前 `AGENTS.md` 保持权威；3F.0 不被当作已存在 `ready` task，不走普通 selection；目标机器 human authorization 三字段缺失即停止；registered worktree setup 先于 task；3F.0 原子创建 records 时为 `in_progress`，docs validation 后 delivery 前为 `review`；human merge 后才启用 3F.1 至 3F.11 standing authority 与 canonical artifacts。结果：pass；bootstrap circular dependencies 0，pre-merge business/test/CI/signing edits 0。
- **Skill portability check:** 检查全部命名技能先检测 availability、均标记为可选、每项具有指向本指令的完整等价流程，并禁止缺失技能阻断或未经人类批准安装。结果：pass；external skill hard dependencies 0，required external `SKILL.md` 0。
- **Git phase check:** 分别解析 §6.2.1 与 §6.2.2。结果：pass；setup 使用 `set -euo pipefail`、required guards 与 clean repository root，先按精确 `refs/heads/$BRANCH` 解析 registered worktrees，恰好一项才复用、多项停止、零项才创建；新建路径来自 Python `tempfile.mkdtemp(prefix="echo-phase3f-worktree-")` private 0700 random base，不存在 predictable base；reuse path canonical/lstat/owner/branch checks 与新建前后 base/path lstat、no-symlink、current-owner checks 均存在；创建或复用后统一对 exact worktree path 执行 lstat directory/no-symlink/current-owner、chmod 0700、再次 lstat 并要求 `(st_mode & 0o077) == 0`，任何 chmod/stat 失败均停止，随后才 clean check 与 rebase；local/remote/new `git worktree add`、clean result 与 printed working path 保留，不切换 main worktree。delivery 仍是一个 `set -euo pipefail` bash block 和一个 EXIT trap，marker validation 先于 commit，PR create/update 后 ledger commit，再只修改本地已验证 body、复验并 final edit；remote PR body reload 0，fixed temp path 0；12/12 tasks 要求 registered worktree 与 single delivery script。
- **Concrete implementation check:** 检查 SRC-007 migration/security、SRC-009 data overview 与 SRC-010 parser/live-Health integration 的精确 source/test paths、Files、tests、interfaces、evidence、ADR 与 approval rules。结果：pass，required new source/test paths 10/10；SRC-011 owner set 未变化。
- **Per-suite RED check:** 检查 3F.6 两个、3F.7 四个、3F.8 两个新 suite 使用 XCTest class identifier 而非 task-prefixed filename identifier；各有独立完整 §6.1 `xcodebuild test` 命令、executed test count > 0、empty/not-found failure rule、明确 observed RED、all-RED implementation gate 和 evidence entry。结果：pass，valid focused identifiers 8/8，nonzero selected-test gates 8/8，implementation-before-all-RED paths 0；task-prefixed test file paths 保持不变。
- **Migration-security check:** 检查 mandatory package shape、manifest-only rejection、smallest syntactically valid RFC 8785 six-field/one-record manifest + one-byte final data chunk、data-only `totalPlaintextBytes`、exact byteLength/data-stream equality、separate manifest/data limits、overflow-safe combined free-disk/package bound、ordering/mapping/hash/crypto/framing/staging/rollback/OS-backup、negative vectors、3F.7 RED suite 与 3F.11 blocking revalidation。结果：pass，minimum-shape clauses 100%，data-only accounting clauses 100%，protocol contradictions 0，release revalidation present。
- **Explicit-Files and test-path check:** 扫描 12 个 Files block 的间接措辞与 basename-only tests。结果：pass，间接 Files 0，basename-only tests 0，task-prefixed primary tests 10/10，integration path 1/1。
- **UI/style/policy check:** 对 220 个唯一 UIAutomation path 检查 snapshot 存在性或显式 Create，并检查 Settings migration/overview、style input 与 policy README ownership。结果：pass，existing or explicit Create 220/220，explicit UIAutomation creates 61，Settings assets 11/11，unmarked missing 0，UI-owning style readers 7/7。
- **Security contract check:** 检查 3F.1 record/contract/Files/tests/evidence 与 3F.11 gate 包含 audit required fields、hash-only、30-day cleanup、`NSFileProtectionComplete`、migration 和 Privacy approval。结果：pass。
- **All-target compliance check:** 检查 executable target discovery、`Echo`/`EchoShareExtension`、network/SDK/secret/entitlement/privacy-manifest/required-reason/purpose-string per-target scans、tests、owner 与 approvers。结果：pass。
- **Story mapping check:** 从 Appendix C 解析 66 个独立 bullet records 并与 task/Phase 4 owners 和 approved deferrals 比较。结果：pass，owned 64，approved deferrals 2；US-SRC-007/009/010/011 owner sets 与 §4.2.1 完全一致且均未延期。
- **Timestamp/checklist/forbidden-text check:** 12 个 `last_updated` invalid sentinel 与原子 UTC 替换规则通过；行首普通执行项 122；DingTalk task-list syntax、未定标记与文件通配命中 0。
- **Evidence lifecycle/preservation check:** evidence index 仍仅由 3F.0 创建；每个 3F.0 至 3F.11 task entry 记录 registered worktree，3F.0 另记录 human bootstrap authorization 与 `in_progress → review` 证据；delivery 前精确 marker pair 包含完整英文 PR body，12/12 checklists 要求真实结果与 no-placeholder extraction；single delivery script 在 ledger insertion 后复验本地 body；3F.11 只 finalizes pre-merge evidence，human-triggered finalizer 才解锁 Phase 4；§5 interfaces、§6 thresholds、Phase 4 records、privacy gates 与 Appendix A 数字均保留。结果：pass。

## Appendix C: Calibrated 66-Story Completion Matrix

**Date:** 2026-08-03 **Scope:** Echo v4.6's 66 user stories. **Decision rule:** A story is **production-complete** only when every required AC is feasible, implemented on the default app path, and has appropriate verification. A source-level or fixture-tested AC is recorded in the evidence note but does not make the story complete.

### Aggregate (exclusive primary status)

| Status                                                     | Count  |
| ---------------------------------------------------------- | ------ |
| Production-complete                                        | 0      |
| Partial (substantive AC code, but not production-complete) | 16     |
| Stub (fixture/UI seam/placeholder only)                    | 25     |
| Absent/unmapped                                            | 9      |
| Deferred (explicit product deferral)                       | 2      |
| Impossible/spec-invalid                                    | 14     |
| **Total**                                                  | **66** |

`Impossible/spec-invalid` is used where a required AC cannot be accepted without a specification decision (for example, unavailable public APIs, contradictory source rules, or impossible timing guarantees). It does **not** erase any partial implementation evidence in the notes.

### Matrix

- **SRC-001 — Stub:** Onboarding has a fixture-only permission flow; no PhotoKit acquisition, Share Extension, source coordinator, or default production wiring.
- **SRC-002 — Impossible/spec-invalid:** Requires MessageUI to read iMessage history, which is not a public capability.
- **SRC-003 — Absent/unmapped:** No Share Extension target or import implementation found.
- **SRC-004 — Stub:** Settings toggles mutate fixture/UI state only; AppDelegate has no BG task registration.
- **SRC-005 — Stub:** Search scan surface is fixture-driven; no scanner/import action exists.
- **SRC-006 — Impossible/spec-invalid:** Spec/ledger explicitly defer it: PHAsset has no People identity API.
- **SRC-007 — Stub:** Migration UI/fixtures exist, but no local-transfer, restore, conflict, or integrity implementation.
- **SRC-008 — Partial:** ExcludedAssets actor has isolated behavior/tests; management, paging, source checks, reimport, and default production integration are incomplete.
- **SRC-009 — Stub:** Settings displays fabricated counts/model states from `SettingsFixtureLoader`.
- **SRC-010 — Absent/unmapped:** No intent parser or multi-source retrieval path.
- **SRC-011 — Absent/unmapped:** No working vision embedding or subjective-query Golden dataset.
- **SRC-012 — Partial:** SyncPipeline has callable isolated logic, but no registered observers, BG task, source acquisition, or default composition; Notes path conflicts with share-only rule.
- **SRC-013 — Stub:** Result surface exists but no production change detector/update flow.
- **ING-001 — Impossible/spec-invalid:** Requires automatic system Notes reads via non-public/nonexistent NoteStore/MKMapItem path and conflicts with SRC-001 share-only route.
- **ING-002 — Impossible/spec-invalid:** Inherits ING-001's unsupported automatic Notes acquisition requirement.
- **ING-003 — Impossible/spec-invalid:** Automatic Voice Memos reading conflicts with the specified share-only public route.
- **ING-004 — Impossible/spec-invalid:** Some ingest AC code is tested with StubEmbedder, but required direct text/vision-space alignment conflicts with the mandated E5/CLIP split.
- **ING-005 — Partial:** Video pipeline code and isolated tests exist, but actual asset acquisition and Whisper/SigLIP inference are scaffolded/unreachable.
- **ING-006 — Absent/unmapped:** No canonical transactional vector/text/FTS commit, fault-injection rollback, or transaction audit path.
- **RET-001 — Partial:** Search pipeline and stub-backed tests implement ranking/audit fields; default app injects no pipeline, E5 returns zeros, and no Cross-Encoder/Golden Recall gate exists.
- **RET-002 — Partial:** Same isolated stub-backed path as RET-001; no real bilingual embedding evidence.
- **RET-003 — Impossible/spec-invalid:** Text is specified as E5 while the AC requires query vectors in CLIP space.
- **RET-004 — Impossible/spec-invalid:** Some filtering code exists, but the AC retains person dimensions after person IDs were removed; actual filters are post-ANN/no-op.
- **RET-005 — Absent/unmapped:** No conversation context store, rewrite model, or parent-trace implementation.
- **RET-006 — Partial:** Low-confidence flags/banner are implemented, but no live Cross-Encoder produces the score.
- **RET-007 — Absent/unmapped:** No retrieval cache or policy-aware invalidation.
- **RET-008 — Stub:** No operational timeout/partial-result path; only UI error/fixture behavior.
- **SYN-001 — Stub:** Language picker is a fixture UI transition; no persisted policy or model prompt/retry integration.
- **SYN-002 — Stub:** Detail UI can present fixture anchors, but no generated response/provenance production path.
- **SYN-003 — Impossible/spec-invalid:** Creation UI is fixture-driven and the required direct Apple Notes creation/deep-link API is unavailable.
- **SYN-004 — Phase 3F audit result (superseded by ADR-017 and refined by ADR-021/022):** The original exact-schedule/People/Notes formulation was not implementable. Phase 4 task `4.0j` owns persisted default-on schedule switches, independent per-period-type eligibleFrom baselines, completed-calendar periods with frozen boundaries, one-period CAS claiming, bounded report/source persistence, atomic completion/audit publication, manual-only L2 retry, opportunistic BGProcessingTask handling, D-005 invalidation and a fail-closed injectable generation seam. Re-enabling one period type never changes the other type's baseline. Task `4.0k` owns the approved bundled generative runtime, LanguageAligner, true bounded source-batch/layer generation and no-fixture production E2E. ADR-023 specifies candidate/approval sequencing, token and execution limits, per-call lineage, non-publishing language fallback, checkpoint-preserving replay and separate physical-device qualification. It omits unavailable partitions and never claims exact background execution or Stub-backed production completion.
- **SYN-005 — Stub:** Prompt editor UI exists; no bounded analysis pipeline or source enforcement.
- **SYN-006 — Absent/unmapped:** No emotion-intervention synthesis/prompt implementation.
- **SYN-007 — Absent/unmapped:** No term glossary runtime or Golden validation.
- **SYN-008 — Stub:** Degradation template is display simulation, not a synthesis failure fallback.
- **AWK-001 — Partial:** Geofence orchestration is callable with test stubs, but no CLLocation integration, permission delivery, notification, persistence, or default invocation.
- **AWK-002 — Impossible/spec-invalid:** iOS cannot guarantee an exact daily 09:00 background schedule.
- **AWK-003 — Partial:** Emotion orchestration/debounce code exists with stub providers; HealthKit, live sentiment, delivery, and persistence are absent.
- **AWK-004 — Deferred:** Explicit P1 Phase-4 Widget/Live Activity deferral (DEF-001).
- **AWK-005 — Stub:** Interactive card presentation uses fixture/local state; no media/music/reaction persistence or data navigation.
- **AWK-006 — Deferred:** Explicit P1 Phase-4 Siri/App Intents deferral (DEF-002).
- **AWK-007 — Partial:** Detail editing/conflict UI mutates fixture model, but no reindexing, source preservation, userLocked behavior, or persistent conflict resolution.
- **PRV-001 — Partial:** PrivacyActor has isolated policy/checkpoint behavior; startup neither loads nor wires a deny-by-default production policy.
- **PRV-002 — Stub:** Audit rows can exist in core tests, but Settings audit viewer is not wired to live data.
- **PRV-003 — Impossible/spec-invalid:** The AC requires complete 30-day export and a <=5MB file without a limit, pagination, or split rule.
- **PRV-004 — Stub:** Delete choice UI exists, but transactional deletion/ExcludedAssets behavior is not connected to canonical storage.
- **PRV-005 — Impossible/spec-invalid:** iOS cannot guarantee cooling-period completion while the app is not running.
- **PRV-006 — Partial:** Persistence/retention intent exists in core schema and settings UI, but no production canonical-store lifecycle verifies the full deletion boundary.
- **PRV-007 — Impossible/spec-invalid:** The required 5-second cascade after original deletion cannot be guaranteed while iOS is suspended/backgrounded.
- **PRV-008 — Stub:** Onboarding consent UI is fixture/state-only; consent persistence and withdrawal/data-purge flow are deferred.
- **DIS-001 — Absent/unmapped:** No single persisted UI/AI language setting or live application-wide localization.
- **DIS-002 — Stub:** Two-string FixtureTranslationService and in-memory cache only; no Apple Translation or persistent cache.
- **DIS-003 — Stub:** State/error UI uses hardcoded English, not the required String Catalog localization.
- **DIS-004 — Stub:** Some accessibility labels exist, but no evidence of full labels, announcements, contrast, Dynamic Type, or VoiceOver-order acceptance.
- **SYS-001 — Partial:** ProgressActor has isolated persistence and panel UI exists, but panel/default app uses fixtures and has no TaskQueue/stream integration.
- **RES-001 — Stub:** Offline indicator UI exists; fully offline model/inference/search and reconnect synchronization do not.
- **RES-002 — Stub:** Low-power banner/toggle is fixture display; no lightweight visual model, queue control, recall evidence, or audit.
- **RES-003 — Stub:** Thermal banner is fixture display; no thermal monitor/degraded runtime behavior.
- **RES-004 — Partial:** ModelLoader state/retry code and tests exist, but artifacts are absent, model status is fabricated in Settings, and FTS fallback/audits are incomplete.
- **SET-001 — Stub:** Language-setting surface is not wired to a persisted policy/localized application.
- **SET-002 — Stub:** Permanent-retention UI copy exists, without production policy/audit enforcement.
- **SET-003 — Stub:** Cache/storage values and clear actions are fixture/simulated, not real cache management.
- **SET-004 — Stub:** Migration guidance UI only; executable migration contract remains unresolved.
- **FBK-001 — Partial:** Feedback pipeline/actor persist in isolated injected tests; default SearchViewModel has no pipeline and silently drops failures.
- **FBK-002 — Partial:** Threshold/decay/clamp/re-ranking logic has isolated tests; no production query path or live Settings feedback management.
- **FBK-003 — Partial:** Bad-case pipeline/actor works under injection; default UI is unwired and management/revoke surface is incomplete.

### Evidence and interpretation

- **Specifications:** `docs/01-spec/用户故事与验收标准规格书.md:45` defines the 66-story scope. Its own amendments identify SRC-006 as deferred and record model/API route problems (`:7-14`, `:181-185`).
- **Production source:** `Echo/UI/AppShell/AppRootView.swift:29-33` constructs default ViewModels; `Echo/UI/Search/SearchViewModel.swift:179-204,229-253` defaults to nil pipelines and fixture results; `Echo/UI/Home/HomeViewModel.swift:158-205` has no live card loading. `Echo/App/AppDelegate.swift:16-21` does not register background work.
- **Model/runtime source:** `E5Embedder.swift:42-44,125-143`, `SigLIP2Embedder.swift:24-29,62-69`, and `WhisperASREngine.swift:31-36,63-70` explicitly identify scaffold behavior / unavailable inference.
- **Tests:** `EchoTests/Phase3/Phase3IntegrationTests.swift:74-101` constructs a fresh VectorStore and `StubEmbedder`; `EchoTests/Phase2/IngestPipelineImageTests.swift:41-57` likewise injects `StubEmbedder`. These tests support isolated behavior, not default-app production composition.
- Fresh-run baseline embedded in this instruction: no-fixture startup remained on “Echo is getting ready…” with no initialized data; unit tests passed 718/720 with 2 failures. These observations are baseline context only, not completion evidence.

### P0/P1 blockers

#### P0 blockers

1. **Production composition and first-run initialization:** no default wiring for policy, database, model/index initialization, or pipelines (`AppRootView`, the embedded Appendix A/C baseline).
2. **Acquisition and real inference:** PhotoKit/Share source paths and E5/SigLIP2/Whisper artifacts/inference are missing/scaffolded; this blocks SRC-001 and all real ingestion/retrieval.
3. **Canonical transactional persistence:** ING-006's atomic canonical/vector/FTS lifecycle is unmapped, blocking reliable ingest, deletion, and search.
4. **Spec decisions:** SRC-006 plus Notes/Voice Memos automatic-read requirements must be resolved to public share-mediated routes; otherwise affected P0 ACs cannot be accepted.
5. **Privacy/data deletion:** no production consent persistence, transactional delete/cascade path, or feasible replacement for impossible timing guarantees.

#### P1 blockers

1. **Search runtime:** real embeddings, Cross-Encoder, filters, cache, timeout behavior, and product DI are absent.
2. **System adapters:** CLLocation/HealthKit/notifications/background scheduling and persistence are absent, blocking real awakening delivery.
3. **Creation and translation:** current paths are fixtures; Apple Translation/persistent cache and a public, user-mediated Notes export flow need requirements and implementation decisions.
4. **Explicit deferrals:** AWK-004 and AWK-006 remain Phase-4 work.

### Verdict on the prior “0 of 66 fully complete” claim

**Defensible, with a necessary qualification:** zero stories satisfy the stated production-complete bar today, because none has all feasible ACs implemented, default-wired, and appropriately verified. The prior journal was incomplete—not wrong—because it did not provide the 66-row AC matrix and did not distinguish partial code, fixtures, explicit deferrals, and invalid ACs. This matrix supplies that missing calibration.
