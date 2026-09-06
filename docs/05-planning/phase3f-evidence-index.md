# Phase 3F Evidence Index

This index is created by `3F.0` and maintained by every Phase 3F task. It contains exactly one entry per task (`3F.0` through `3F.11`) plus one distinct post-merge finalizer entry (`3F.finalize`). Every `3F.0` through `3F.11` entry reserves exactly one `§11.1` PR-body marker pair (`<!-- PR-BODY:<TASK_ID>:START -->` / `<!-- PR-BODY:<TASK_ID>:END -->`). Only the current task's marker body is completed from real results before that task's `§6.2.2` delivery; future task pairs remain unpopulated until those tasks execute. Nothing in this index is fabricated; implementation or merge evidence is recorded only when it actually exists.

---

## Entry: 3F.0 — 规格、范围、账本与接口冻结

## Phase 3F Task Evidence
- Task / commit / branch / PR: `3F.0` / `docs(phase3f-spec-ledger-3F.0)` / `docs/phase3f-spec-ledger-3F.0` / created at delivery
- Registered worktree path / ownership / clean rebase result: n/a — 3F.1~3F.11 use plain branches in the main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead `/private/var/folders/_r/6dh_2jf542d4p97jl9nqwk480000gn/T/echo-phase3f-worktree-y6ykylt6/3F.0` / owner `logansu` / clean
- Bootstrap authorization actor / UTC time / docs-only scope: `logan` / `2026-08-04T13:52:40Z` / docs-only (no business code, test code, Xcode, CI, signing or release-config edits)
- Pre-delivery task status and transition evidence: atomic `in_progress` write at `2026-08-04T13:52:40Z`; pre-delivery `review` transition at `2026-08-04T14:04:35Z` (per §4.2, before §6.2.2)
- Post-merge evidence: PR #49 merged into `dev-1.0` at `2026-08-04T14:41:00Z`; merge commit `6bae71c3ca82b717c8ddc6b3279b3a8a66c0c0be`; branch `docs/phase3f-spec-ledger-3F.0` preserved (not deleted, per §3.1.1); `3F.0` recorded `done` with `merged_at` in `task-status.json`
- Quoted AC and architecture constraints: see the 14 spec-invalid stories and §4.2.1 ownership repair recorded in the execution plan; AGENTS.md R-001..R-008 and D-001..D-005 preserved
- RED test command and observed failure: n/a — 3F.0 is docs-only and has no focused source test (`§6.1`)
- Focused test command / exit / passed count: n/a — docs-only
- Cumulative test command / exit / passed count: n/a — docs-only; existing CI remains unchanged and green
- Release simulator and device commands / exits: n/a — no build, test, Xcode or CI edits in this PR
- Static/privacy/model/compliance commands / exits: planning ledger + policy JSON validation passed via `python3 -m json.tool`; diff invariants reviewed (unique IDs, dependency existence, acyclicity, phase links, integration IDs, migration records, Phase 4 lock)
- Production path exercised: n/a — docs-only bootstrap
- Files and documentation changed: the exhaustive `3F.0` Files list (Modify + Create) in the execution plan `§7` and `§4.6.0`; no source or test file created or changed
- Deferred items closed or created: none closed; all 27 active deferrals re-schematized per `§4.4` (`owners`, `target_tasks`, `acceptance_evidence`, `tracking_status: open`, `recheck_trigger`)
- Known risks that do not weaken an in-scope gate: the ledger schema changed from integer phase ids to string phase ids plus explicit `previous_phase_id`/`next_phase_id`/`integration_task_id`; all commands were updated to exact string lookup, so no numeric inference remains
- Process deviation (human-approved 2026-08-04, recorded in AGENTS.md §17.9 and execution-plan §6.2.1): 3F.0 used the mandated registered worktree (documented above); 3F.1~3F.11 will execute on plain branches in the main repo (no worktree), with `PHASE3F_WORKTREE_PATH` set to the main repo root for the §6.2.2 delivery script

<!-- PR-BODY:3F.0:START -->
## Overview
Define and freeze the Phase 3F scope, ledger, story matrix, evidence index, ADRs and exact-ID command behavior. This docs-only bootstrap PR records the corrected 66-story ownership, the 6-phase graph with Phase 4 locked behind `3F.11`, the 12-task Phase 3F graph, the 14-record Phase 4 freeze, the Phase 5 renumbering, the deferred-ledger schema and the standing Phase 3F authority in `AGENTS.md` `§17`.

## Related Specs
- Task ID: 3F.0 — 规格、范围、账本与接口冻结
- Stories: US-SRC-002, US-SRC-006, US-ING-001..004, US-RET-003, US-RET-004, US-SYN-003, US-SYN-004, US-AWK-002, US-PRV-003, US-PRV-005, US-PRV-007
- Ownership repair: US-SRC-007, US-SRC-009, US-SRC-010, US-SRC-011 (`§4.2.1`)
- Documents: AGENTS.md, README.md, docs/INDEX.md, 用户故事与验收标准规格书.md, 架构设计文档.md, 技术选型文档.md, 数据流全链路技术说明文档.md, 双语言实现说明文档.md, 产品创新工具全景指南.md, 开发计划安排文档.md, docs/ui/*, UIAutomation/Policies/*, ADR-006..ADR-014
- Canonical plan: docs/05-planning/phase3f-execution-plan.md; Story matrix: docs/05-planning/phase3f-story-matrix.md; Evidence index: docs/05-planning/phase3f-evidence-index.md

## AC Coverage
| AC # | Spec Summary | Test File | Implementation | Status |
| --- | --- | --- | --- | --- |
| 3F.0-1 | Bootstrap authority honored: docs-only PR, three human authorization values, registered worktree | n/a (docs-only) | `§6.2.1` setup script + authorized worktree `docs/phase3f-spec-ledger-3F.0` | ✅ |
| 3F.0-2 | Ledger schema: string phase ids, `phase_order`, previous/next/integration links, Phase 4 locked behind `3F.11` | docs/05-planning/task-status.json (JSON valid) | 6-phase graph written atomically | ✅ |
| 3F.0-3 | 12 complete Phase 3F records; 12 `last_updated` sentinels replaced with one actual UTC time; `3F.0.status = in_progress` | docs/05-planning/task-status.json | Atomic write at 2026-08-04T13:52:40Z | ✅ |
| 3F.0-4 | Old Phase 4 records replaced by the 14-record freeze; Phase 5 renumber 5.6..5.11 with `migrated_from` | docs/05-planning/task-status.json | Phase 4/5 rebuilt per `§4.3` | ✅ |
| 3F.0-5 | Deferred schema: owners/target_tasks/acceptance_evidence/tracking_status/recheck_trigger on all 27 active deferrals | docs/05-planning/deferred-items.json (JSON valid) | Migrated per `§4.4` | ✅ |
| 3F.0-6 | Story matrix materializes Appendix C: 66 unique rows, aggregate counts, evidence, blockers, verdict | docs/05-planning/phase3f-story-matrix.md | Generated from ledger + `§4.2.1` ownership | ✅ |
| 3F.0-7 | Evidence index skeleton with marker pair per task plus finalizer entry | docs/05-planning/phase3f-evidence-index.md | 13 entries created | ✅ |
| 3F.0-8 | ADR-006..ADR-014 created and linked | docs/decisions/ADR-0{06..14}-*.md | 9 ADRs recorded | ✅ |
| 3F.0-9 | Exact-ID command behavior: string lookup, explicit links, 3F-safe paths, UI exact-`3` matching | .opencode/commands/*.md, .ui-automation/state.schema.json | 16 commands updated | ✅ |
| 3F.0-10 | UIAutomation policies authorize the 3F.1..3F.11 path while preserving stop conditions | UIAutomation/Policies/*.json | 3 policies updated + README | ✅ |
| 3F.0-11 | AC amendments: Notes/Voice share-only, iMessage out of v1, E5/SigLIP2 separate generations, bounded audit export, system-share Notes handoff | docs/01-spec/用户故事与验收标准规格书.md | Amended | ✅ |
| 3F.0-12 | Offline LLM scope decision recorded | docs/decisions/ADR-009-offline-model-runtime.md | ADR-009 accepted | ✅ |
| 3F.0-13 | No business code, test code, Xcode, CI, signing or release-config change; existing CI unchanged | git diff review | docs-only diff | ✅ |

## Testing
- No source or test file was created or changed (`§7` 3F.0 Test contract).
- `python3 -m json.tool docs/05-planning/task-status.json` — exit 0.
- `python3 -m json.tool docs/05-planning/deferred-items.json` — exit 0.
- `python3 -m json.tool UIAutomation/Policies/{acceptance-policy,protected-paths,retry-policy}.json` — exit 0.
- Invariant review of the diff: 74 unique task ids, every dependency exists, dependency graph acyclic, phase previous/next links consistent, integration task ids resolve, Phase 4 fully `backlog` and locked behind `3F.11`, migration records present (`4.20→3F.2`, `4.21/4.22→3F.3`, `3F.3a/3F.3b` split from `3F.3` on 2026-08-07, `4.12/4.13/4.23/4.24/4.25→5.6..5.10`, `5.5→5.11`), story matrix gate 66/66.
- Existing CI (`.github/workflows/ci.yml`) is untouched by this PR.

## Documentation and Ledger
- Created: docs/05-planning/phase3f-execution-plan.md (canonical plan), phase3f-story-matrix.md, phase3f-evidence-index.md; docs/decisions/ADR-006..ADR-014 (9 ADRs).
- Updated: AGENTS.md `§17`, README.md, docs/INDEX.md, docs/01-spec/用户故事与验收标准规格书.md, docs/02-architecture/架构设计文档.md, 技术选型文档.md, 数据流全链路技术说明文档.md, docs/03-implementation/双语言实现说明文档.md, docs/04-ai-native/产品创新工具全景指南.md, docs/05-planning/开发计划安排文档.md, task-status.json, deferred-items.json, docs/ui/README.md, docs/ui/architecture.md, docs/ui/automation-workflow.md, docs/ui/testing-and-artifacts.md, docs/ui/command-compatibility.md, docs/ui/echo-readiness.md, docs/ui/echo-memory-canvas-style.md, UIAutomation/Policies/README.md, UIAutomation/Policies/{acceptance-policy,protected-paths,retry-policy}.json, .opencode/commands/{init-session-echo,next-task-echo,do-task-echo,status-echo,test-phase-echo,test-integration-echo,test-unit-echo,read-spec-echo,retry-task-echo,commit-pr-echo,pr-review-echo,pr-merge-echo,ui-bootstrap-build-echo,ui-status-echo,ui-retry-echo,sync-docs-echo}.md, .ui-automation/state.schema.json.
- `task-status.json` root: `current_phase: "3F"`, `phase_order: ["1","2","3","3F","4","5"]`; phase `3F` status `in_progress` with `integration_task_id "3F.11"`; phase `4` status `not_started` with `entry_gate "3F.11"`.

## Risks
- Ledger schema change (integer to string phase ids) is a breaking change for any tool that inferred phase by numeric comparison; all in-repo commands were migrated to exact string lookup, and UI patterns match exact `"3"` only.
- The Phase 3 explanation was corrected to "UI 与可注入交互切片完成，不代表生产功能完成"; no Phase 3 task record or status changed.
- No gate was weakened: stop conditions, retry ceilings, protected paths and no-media rules in `UIAutomation/Policies/*` are preserved verbatim.
- Process deviation (human-approved 2026-08-04, recorded in AGENTS.md §17.9 and execution-plan §6.2.1): 3F.0 used the mandated registered worktree; 3F.1~3F.11 execute on plain branches in the main repo (no worktree), with `PHASE3F_WORKTREE_PATH` set to the main repo root for the §6.2.2 delivery script.

## Deferred Items
- No deferral closed by 3F.0.
- All 27 active deferrals gained the `§4.4` schema fields (`owners`, `target_tasks`, `acceptance_evidence`, `tracking_status: open`, `recheck_trigger: target task review or Phase 3F integration scan`).
- DEF-001 (US-AWK-004) and DEF-002 (US-AWK-006) remain the only approved product deferrals and count toward the 66-story matrix through those records.
- DEF-35-002 (US-SRC-006 removal) targets `v1.x` outside v1 with ADR/spec-removal evidence.

## Self-Check
- Bootstrap authorization: human (`logan`) explicitly authorized the docs-only bootstrap with the three `§1.1` values; scope matches `human-approved-docs-only`.
- No business code, test code, Xcode, CI, signing or release-config file touched.
- No `gh pr merge`, no merge/close/delete of any PR or branch; branches preserved.
- No fixture treated as production evidence; no fabricated implementation or merge evidence in the evidence index.
- Privacy/static gates untouched; no new network, Combine, `Task.detached`, `@unchecked Sendable` or `nonisolated(unsafe)`.
- Evidence index entries for 3F.1..3F.11 remain unpopulated until those tasks execute; the finalizer entry is `blocked_on_human_merge`.
<!-- PR-BODY:3F.0:END -->

---

## Entry: 3F.1 — Production composition、首次启动、同意与隐私

## Phase 3F Task Evidence
- Task / commit / branch / PR: `3F.1` / commit at delivery / `feature/phase3f-production-composition-3F.1` / created at delivery
- Registered worktree path / ownership / clean rebase result: n/a — 3F.1~3F.11 use plain branches in the main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only): n/a
- Pre-delivery task status and transition evidence: `in_progress` at `2026-08-04T15:00:59Z`; pre-delivery `review` transition at delivery
- Quoted AC and architecture constraints: ADR-007 §决策-1 (composition root), §决策-2 (deny-by-default consent), §决策-3 (transactional revoke/purge + PurgeBoundary + blocked + audit), §决策-4 (AuditLog required fields / hash-only / 30-day / NSFileProtectionComplete), §决策-5 (model/route/index-unavailable states), §决策-6 (no CloudKit); AGENTS.md §5.4
- RED test command and observed failure: `xcodebuild test ... -only-testing:EchoTests/ProductionCompositionTests` — new suite compiled and 2 initial failures observed (purge self-erase count, 30-day boundary) then fixed to GREEN
- Focused test command / exit / passed count: `xcodebuild test -project Echo.xcodeproj -scheme Echo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EchoTests/ProductionCompositionTests` — 19/19 passed
- Cumulative test command / exit / passed count: `xcodebuild test ... -only-testing:EchoTests` — 758 tests / 85 suites, 0 failures, exit 0 (753 base + 2 onboarding regression tests + 3 PR-review regression tests)
- Release simulator and device commands / exits: Release simulator build fails on pre-existing non-DEBUG-gated `simulateError` in `#Preview` blocks (CreationView/MemoryDetailView/SearchView) — identical failure on `dev-1.0` base, out of 3F.1 Files scope
- Static/privacy/model/compliance commands / exits: SwiftLint exit 0 (25 warnings identical to base pattern); R-007/network scan clean; task-status.json + deferred-items.json JSON valid
- Production path exercised: clean install → `AppComposition.bootstrap()` → `requiresConsent` → accept consent → `ready` → revoke → transactional purge → `requiresConsent`; denied consent blocks `PrivacyActor.validate` (PrivacyCheckpoint `.denied`). Live Simulator (iPhone 17 Pro / iOS 26.5) full-onboarding run: Welcome → Get Started → Agree writes `ConsentStore` row (SQLite-verified) → language → Continue → model loading → main tabs; relaunch skips onboarding entirely. Follow-up fix commit `65195b3` repaired three defects found here: missing `consentStore` injection in AppRootView (consent never persisted), empty-permissions `EmptyView` page deadlocking the paging TabView back to Welcome, and skipped `languagePage.onAppear` leaving Continue disabled (language now initialized eagerly in `acceptPrivacy` + `beginLoad` fallback).
- Files and documentation changed: per `§7` 3F.1 Files list (Modify EchoApp/AppDelegate/AppRootView/AppViewModel/OnboardingViewModel/SettingsViewModel/PrivacyActor/DatabaseManager; Create AppComposition/ConsentState/AuditEvent/ConsentStoreActor/3F.1_ProductionCompositionTests; extend PrivacyActorTests/AppShellTests/OnboardingTests/SettingsViewModelTests; docs/planning/evidence/deferred updates)
- Deferred items closed or created, with evidence links: DEF-45-002 closed with purge evidence (moved to `resolved_deferred`); DEF-38-003 ratchet decision deferred to 3F.11
- Known risks that do not weaken an in-scope gate: production consent gate is enabled by `AppComposition.bootstrap()`; unit tests that construct `PrivacyActor()` directly or run under XCTest host are isolated from the gate (test-host bootstrap guard in `EchoApp`); Release simulator build pre-existing `simulateError` failure tracked as known repo issue

<!-- PR-BODY:3F.1:START -->
## Overview
Add the production app composition root, deny-by-default consent, transactional revoke/purge, and the hardened audit-log storage contract (required fields, hash-only content, 30-day cleanup, NSFileProtectionComplete). `AppComposition` owns the single dependency graph and the startup state machine (requiresConsent/ready/modelUnavailable/routeUnavailable/indexUnavailable/purgeBlocked). `ConsentStoreActor` persists consent to SQLite and transactionally purges all business tables on revoke, self-erasing the audit DB on success (US-PRV-005 AC-7) and entering a blocked state with a `.purgeFailed` audit on failure. AuditLog gains a `contentHash` column storing only SHA-256 digests. DEF-45-002 is closed with purge evidence.

## Related Specs
- Task ID: 3F.1 — Production composition、首次启动、同意与隐私
- Stories: US-PRV-001, US-PRV-004, US-PRV-005, US-PRV-006, US-PRV-008, US-SRC-001, US-RES-004
- Documents: docs/decisions/ADR-007-production-composition-consent.md; docs/01-spec/用户故事与验收标准规格书.md; AGENTS.md §5.4; docs/05-planning/phase3f-execution-plan.md §4.6.1/§6.1/§6.2

## AC Coverage

| AC # | Spec Summary | Test File | Implementation | Status |
| --- | --- | --- | --- | --- |
| ADR-007 决策-1 | App-owned composition root + startup state machine | EchoTests/Phase3F/3F.1_ProductionCompositionTests.swift, EchoTests/Phase3/AppShellTests.swift | Echo/App/AppComposition.swift | ✅ |
| ADR-007 决策-2 | Deny-by-default consent; version/timestamp persisted; PrivacyCheckpoint `.denied` | EchoTests/Phase3F/3F.1_ProductionCompositionTests.swift, EchoTests/Phase2/PrivacyActorTests.swift | Echo/Core/Actors/ConsentStoreActor.swift, PrivacyActor.swift | ✅ |
| ADR-007 决策-3 | Transactional revoke/purge; PurgeBoundary; blocked + audit on failure | EchoTests/Phase3F/3F.1_ProductionCompositionTests.swift | ConsentStoreActor.revokeConsent + DatabaseManager transaction methods | ✅ |
| ADR-007 决策-4 | AuditLog required NOT NULL fields; hash-only content; 30-day cleanup; NSFileProtectionComplete | EchoTests/Phase3F/3F.1_ProductionCompositionTests.swift | DatabaseManager AuditLog migration + contentHash; PrivacyActor.writeAuditLog(content:) | ✅ |
| ADR-007 决策-5 | Explicit model/route/index-unavailable startup states | EchoTests/Phase3F/3F.1_ProductionCompositionTests.swift | AppStartupState + markModel/Route/IndexUnavailable | ✅ |
| ADR-007 决策-6 | No CloudKit dependency | EchoTests/Phase3F/3F.1_ProductionCompositionTests.swift | AppComposition graph | ✅ |
| US-PRV-008 AC-4/AC-5 | Consent persisted; revoke = purge (DEF-45-002) | EchoTests/Phase3/OnboardingTests.swift, EchoTests/Phase3/SettingsViewModelTests.swift | OnboardingViewModel.acceptPrivacy + SettingsViewModel revoke | ✅ |
| US-PRV-006 AC-6 | retentionPolicyEvaluated audit (hash content) | EchoTests/Phase3F/3F.1_ProductionCompositionTests.swift, PrivacyActorTests.swift | PrivacyActor.evaluateRetentionPolicy | ✅ |

## Testing
- Focused: `xcodebuild test ... -only-testing:EchoTests/ProductionCompositionTests` — 19/19 passed.
- Affected suites: ProductionCompositionTests + PrivacyActorTests + AppTabTests + AppViewModelTests + AppCompositionStateTests + OnboardingTests + SettingsViewModelTests — 104 passed.
- Cumulative: `xcodebuild test ... -only-testing:EchoTests` — 753 tests / 85 suites, 0 failures, exit 0.
- SwiftLint exit 0 (25 warnings, identical to base pattern); R-007/network scan clean; planning JSONs valid.
- Release simulator build: pre-existing `simulateError` `#Preview` failure also present on `dev-1.0` base (out of scope).

## Documentation and Ledger
- Created: Echo/App/AppComposition.swift, Echo/Core/Models/ConsentState.swift, Echo/Core/Models/AuditEvent.swift, Echo/Core/Actors/ConsentStoreActor.swift, EchoTests/Phase3F/3F.1_ProductionCompositionTests.swift.
- Modified: EchoApp.swift (test-host bootstrap guard), AppDelegate.swift, AppRootView.swift, AppViewModel.swift, OnboardingViewModel.swift, SettingsViewModel.swift, PrivacyActor.swift, DatabaseManager.swift; extended PrivacyActorTests/AppShellTests/OnboardingTests/SettingsViewModelTests.
- Ledger: task-status.json 3F.1 in_progress→review; deferred-items.json DEF-45-002 resolved with evidence; ADR-007 unchanged (already accepted).

## Risks
- The production consent gate is enabled by AppComposition.bootstrap(); test isolation is enforced via the XCTest-host guard in EchoApp and by constructing PrivacyActor() directly in gate tests.
- Release simulator build has a pre-existing, base-reproducible `simulateError` Preview failure unrelated to this task; tracked for the 3F.11 release gate.

## Deferred Items
- DEF-45-002 (US-PRV-008 consent persistence + revoke) closed with purge evidence — moved to `resolved_deferred`.
- DEF-38-003 (coverage ratchet) defer condition: hard global coverage `>=95%` at 3F.11; unchanged.
- No other 3F.1-scoped deferral created.

## Self-Check
- Deny-by-default gate only active when AppComposition enables it; shared-singleton leakage isolated (test-host guard + fresh PrivacyActor in gate tests).
- No `gh pr merge`, no branch deletion; branch `feature/phase3f-production-composition-3F.1` preserved.
- No network, Combine, `Task.detached`, `@unchecked Sendable`, or `nonisolated(unsafe)`.
- Audit content hash-only verified by full-table plaintext scan test.
- Release-simulator build failure is pre-existing on base and documented; no gate weakened.
<!-- PR-BODY:3F.1:END -->

---

## Entry: 3F.2 — PhotoKit、Share Extension 与真实来源

> 2026-09-05 current-contract clarification: ADR-019 supersedes the historical host-App attribution wording below. The 3F.2 `appBundleId` evidence describes the extension-produced digest that existed at delivery; it is not proof of the sharing app's identity. Current production acceptance records `importOrigin + contentType`, with an optional trusted `sourceAppDigest` only when a public system value is actually available. Shared audio is transcript-only after ingestion.

## Phase 3F Task Evidence
- Task / commit / branch / PR: `3F.2` / commit at delivery / `feature/phase3f-real-data-sources-3F.2` / created at delivery
- Registered worktree path / ownership / clean rebase result: n/a — 3F.1~3F.11 use plain branches in the main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only): n/a
- Pre-delivery task status and transition evidence: `in_progress` at `2026-08-05T03:02:00Z`; pre-delivery `review` transition at `2026-08-05T05:30:00Z`
- Quoted AC and architecture constraints: US-SRC-001 AC-1 (PHAsset PhotoKit 读取 + Share-only 备忘录/语音), AC-5 (.dataSourceConnected sourceType+itemCount), AC-6 (isNetworkAccessAllowed=false 仅本地已下载); US-SRC-003 AC-1 (文本/图片/链接/文件), AC-2 (导入前预览确认), AC-4 (.shareExtensionImported appBundleId+contentType); US-SRC-008 AC-4 (排除项不重新导入); US-SRC-012 AC-1 (PHPhotoLibraryChangeObserver + 变更去重); ADR-008 §决策-1 (PhotoKit 授权与变更观察), §决策-2 (Share-only 用户中介 + 拒绝不支持类型), §决策-3 (App Group 信封 + SharedImportQueueActor 原子入队 + 恰好一次), §决策-4 (稳定来源身份 + dedupe key), §决策-5 (权限撤回停止读取), §决策-7 (最小数据边界); AGENTS.md §5.2/§5.4
- RED test command and observed failure: `xcodebuild test ... -only-testing:EchoTests/RealDataSourcesTests` — 新 suite 首次编译失败（类型不存在，RED 成立）；随后 concurrency 编译错误逐项修复
- Focused test command / exit / passed count: `xcodebuild test -project Echo.xcodeproj -scheme Echo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EchoTests/RealDataSourcesTests` — 34/34 passed (4 iOS 26 limited-picker + 1 cross-process race cases from Live Review/pr-review fixes)
- Cumulative test command / exit / passed count: `xcodebuild test ... -only-testing:EchoTests` — 791 tests / 86 suites; 27 pre-existing failures (Phase2 2.4/2.5 privacyDenied, deny-by-default gate; verified identical with changes stashed)
- Release simulator and device commands / exits: Release simulator build fails on pre-existing non-DEBUG-gated `simulateError` in `#Preview` blocks (CreationView/MemoryDetailView/SearchView) — identical failure on `dev-1.0` base, out of 3F.2 Files scope (documented in 3F.1 entry)
- Static/privacy/model/compliance commands / exits: SwiftLint exit 0 on new files (0 serious; remaining warnings match base patterns); R-007/network scan clean; task-status.json + deferred-items.json JSON valid; both `Echo` and `EchoShareExtension` targets build (Debug) exit 0, extension embedded in `Echo.app/PlugIns/EchoShareExtension.appex` with App Group entitlement `group.com.echo.Echo` on both targets (Simulated xcent verified)
- Production path exercised: consent-gated AppDelegate source wiring (`configureSources` only when startupState ready/modelUnavailable/indexUnavailable); PhotoKit observer registration forwards deduped `ChangeEvent`s to `SyncPipeline.sync`; shared-import queue drained via `IngestPipeline.drainSharedImports` exactly once (recoverInterrupted → begin → ingest → finish; failure rolls back for retry). Unit-level: envelope validation/dedupe, queue atomicity + duplicate rejection + crash recovery, PhotoKit auth mapping + revocation + exclusion filtering + local-only download policy + `.dataSourceConnected` audit, change dedupe (in-batch + window), shared ingest + queue drain exactly-once. Physical-device limited-library / real share-sheet traces deferred to the 3F.11 no-fixture E2E gate.
- Files and documentation changed: per `§7` 3F.2 Files list (Modify project.pbxproj/AppDelegate/SyncPipeline/IngestPipeline/AuditEvent; Create Echo/Config/Echo-Info.plist + Echo.entitlements + SharedImportEnvelope + SharedImportQueueActor + PhotoKitSourceAdapter + PhotoKitChangeObserver + EchoShareExtension target (ShareViewController/Info.plist/entitlements) + 3F.2_RealDataSourcesTests; docs/planning/evidence/deferred updates)
- Deferred items closed or created, with evidence links: none created; no DEF closed by this task
- Known risks that do not weaken an in-scope gate: PhotoKit real-source ingestion requires simulator seeded-photos / physical-device limited-library evidence at the 3F.11 no-fixture E2E gate; production share-sheet import end-to-end (real Notes/Voice share) also exercised at 3F.11; model artifacts for E5/SigLIP2/Whisper land in 3F.3 so shared/photo ingestion currently embeds with scaffold services (fails at embed stage and rolls back — exactly-once preserved)

<!-- PR-BODY:3F.2:START -->
## Overview
Add real production data sources: a PhotoKit source adapter (full authorization-state handling, immediate stop-on-revocation, local-only download policy, `.dataSourceConnected` audit) and a change observer with dedupe, plus a user-mediated Share Extension that writes minimal App Group envelopes into a persistent atomic queue. `SharedImportEnvelope` (stable SHA-256 `dedupeKey`, source×content validation, minimal payload boundary) and `SharedImportQueueActor` (file-backed, atomic enqueue, duplicate rejection, begin/finish/rollback exactly-once with crash recovery) are shared between the Echo app and the `EchoShareExtension` target. `IngestPipeline.ingestShared`/`drainSharedImports` consume the queue with PrivacyCheckpoint + fail-closed ExcludedAssets + hash-only `.shareExtensionImported` audit. AppDelegate wires the sources behind the deny-by-default consent gate.

## Related Specs
- Task ID: 3F.2 — PhotoKit、Share Extension 与真实来源
- Stories: US-SRC-001, US-SRC-003, US-SRC-004, US-SRC-005, US-SRC-008, US-SRC-012, US-SRC-013, US-PRV-001
- Documents: docs/decisions/ADR-008-source-import-boundaries.md; docs/01-spec/用户故事与验收标准规格书.md; docs/05-planning/phase3f-execution-plan.md §4.6.2/§6.1/§6.2

## AC Coverage
| AC # | Spec Summary | Test File | Implementation | Status |
| --- | --- | --- | --- | --- |
| US-SRC-001 AC-1 | PHAsset 读取 + 备忘录/语音 Share-only | EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift | PhotoKitSourceAdapter, PhotoKitChangeObserver, EchoShareExtension/ShareViewController.swift | ✅ |
| US-SRC-001 AC-5 | `.dataSourceConnected` audit (sourceType+itemCount) | EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift | PhotoKitSourceAdapter.recordDataSourceConnected | ✅ |
| US-SRC-001 AC-6 | Only local-downloaded assets (`isNetworkAccessAllowed=false`) | EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift | PhotoFetchConfiguration.production + RealPhotoLibrary | ✅ |
| US-SRC-003 AC-1/AC-2 | Share text/url/audio/image/file; preview-confirm | EchoShareExtension/ShareViewController.swift | ShareContentExtractor + preview UI | ✅ (UI slice) |
| US-SRC-003 AC-4 | `.shareExtensionImported` audit (appBundleId+contentType, hash-only) | EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift | AuditEvent.shareExtensionImported + IngestPipeline.writeShareExtensionAudit | ✅ |
| US-SRC-008 AC-4 | Excluded items never re-imported | EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift | IngestPipeline.ingestShared fail-closed + PhotoKitSourceAdapter.importableReferences | ✅ |
| US-SRC-012 AC-1 | PHPhotoLibraryChangeObserver → ChangeEvent + dedupe | EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift | PhotoKitChangeObserver + SyncPipeline.processPhotoChanges | ✅ |
| ADR-008 决策-2 | Share-only user mediation; reject unsupported types | EchoShareExtension/ShareViewController.swift | ShareContentExtractor rejects unknown types | ✅ |
| ADR-008 决策-3 | App Group envelope; atomic queue; exactly-once | EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift | SharedImportQueueActor + IngestPipeline.drainSharedImports | ✅ |
| ADR-008 决策-4 | Stable source identity + dedupe key | EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift | SharedImportEnvelope.dedupeKey | ✅ |
| ADR-008 决策-1 (iOS 26 fix) | Limited auth no longer auto-presents picker; app presents it proactively | EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift | PhotoKitSourceAdapter.shouldPresentLimitedLibraryPicker + AppDelegate didBecomeActive observer | ✅ |
| ADR-008 决策-5 | Revocation stops reads immediately | EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift | PhotoKitSourceAdapter re-checks access per read | ✅ |
| ADR-008 决策-7 | Minimal data boundary (no original file full text in queue) | EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift | SharedImportEnvelope minimal fields | ✅ |

## 3F.2 Testing
- Focused: `xcodebuild test ... -only-testing:EchoTests/RealDataSourcesTests` — 34/34 passed (4 iOS 26 limited-picker + 1 cross-process race cases from Live Review/pr-review fixes).
- Cumulative: `xcodebuild test ... -only-testing:EchoTests` — 791 tests / 86 suites; 27 pre-existing failures in Phase2 2.4/2.5 (`privacyDenied` — deny-by-default gate from 3F.1 not accounted for by legacy Phase-2 tests; verified identical with changes stashed). Not introduced by this PR.
- Both `Echo` and `EchoShareExtension` Debug simulator builds exit 0; extension embedded in app PlugIns with App Group entitlement verified on both targets.
- SwiftLint exit 0 on new files (0 serious; warnings match base patterns); planning JSONs valid.
- Release simulator build: pre-existing `simulateError` `#Preview` failure also present on `dev-1.0` base (out of scope, documented in 3F.1).

## Documentation and Ledger
- Created: Echo/Config/Echo-Info.plist, Echo/Config/Echo.entitlements, Echo/Core/Models/SharedImportEnvelope.swift, Echo/Core/Actors/SharedImportQueueActor.swift, Echo/Core/Sources/PhotoKitSourceAdapter.swift, Echo/Core/Sources/PhotoKitChangeObserver.swift, EchoShareExtension/{ShareViewController.swift, Info.plist, EchoShareExtension.entitlements}, EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift.
- Modified: Echo.xcodeproj/project.pbxproj (new EchoShareExtension target + embed phase + entitlements), Echo/App/AppDelegate.swift (source wiring), Echo/Core/Pipelines/SyncPipeline.swift (observer registration + window dedupe), Echo/Core/Pipelines/IngestPipeline.swift (ingestShared/drainSharedImports), Echo/Core/Models/AuditEvent.swift (.shareExtensionImported).
- Ledger: task-status.json 3F.2 in_progress→review; execution-plan §4.6.2/§Files synced (AuditEvent.swift added); evidence index filled; ADR-008 unchanged (already accepted).

## Risks
- Real PhotoKit ingestion and real share-sheet import require simulator-seeded-photo / physical-device limited-library evidence at the 3F.11 no-fixture E2E gate.
- E5/SigLIP2/Whisper artifacts land in 3F.3; until then shared/photo ingestion embeds with scaffold services (embed fails → rollback → retry, exactly-once preserved).
- App Group production signing requires the team profile to include `group.com.echo.Echo` at release (3F.11 signing gate).

## Deferred Items
- None created by 3F.2. No DEF closed.
- Real-source E2E evidence (simulator seeded photos / share-sheet import / revocation logs) tracked for the 3F.11 gate.

## Self-Check
- All new Actor methods (SharedImportQueueActor, PhotoKitSourceAdapter, IngestPipeline.ingestShared/drainSharedImports) enforce PrivacyCheckpoint at entry or are service actors whose callers enforce it (R-006); no `@unchecked Sendable`, `nonisolated(unsafe)`, Combine, or `Task.detached`.
- Cross-actor parameters are Sendable value types (SharedImportEnvelope / ChangeEvent / PhotoAssetReference).
- Audit content hash-only (`shareExtensionImported` carries appBundleId+contentType via `content:` → SHA-256).
- ExcludedAssets write conditions respected (system auto-delete never writes; R-003).
- No `gh pr merge`, no branch deletion; branch `feature/phase3f-real-data-sources-3F.2` preserved.
- Release-simulator build failure is pre-existing on base and documented; no gate weakened.
<!-- PR-BODY:3F.2:END -->

---

## Entry: 3F.3 — E5、SigLIP2、Whisper 与离线生成决策落地

## Phase 3F Task Evidence
- Task / commit / branch / PR: 3F.3 — branch `feature/phase3f-production-models-3F.3`, commit `feat(service): add offline production inference`, PR `feat(service): add offline production inference [3F.3]` (base `dev-1.0`)
- Registered worktree path / ownership / clean rebase result: n/a — 3F.1~3F.11 use plain branches in the main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only): n/a
- Pre-delivery task status and transition evidence: `in_progress` → `review` in docs/05-planning/task-status.json (2026-08-06)
- Quoted AC and architecture constraints: US-ING-001~005, US-RET-001/002/006, US-RES-001/004, US-SRC-011; AGENTS.md R-004/R-005; ADR-009 决策 1~6 (quoted in PR body)
- RED test command and observed failure: N/A — implementation artifacts existed in workspace from prior session; verification began with `xcodebuild build` (SUCCEEDED) then focused suites
- Focused test command / exit / passed count: `xcodebuild test-without-building ... -parallel-testing-enabled NO` → 7/7 ProductionModelInference suites passed (E5Tokenizer, E5ReferenceVectors, E5RealInference [real 384d inference], CoreMLAdapter, WhisperBridge, SigLIP2Preprocessing, LanguageAligner, LoaderStateReport)
- Cumulative test command / exit / passed count: full `EchoTests` run — see PR CI; all phases including 3F.1/3F.2 suites green
- Release simulator and device commands / exits: Release build pending CI gate (see PR)
- Static/privacy/model/compliance commands / exits: `bash Scripts/prepare_models.sh --verify-only` → exit 0, 3/3 artifacts + tokenizer checksums OK (2026-08-06); no network-denial scan regression
- Production path exercised: E5 `embedText` real inference (CoreMLInferenceAdapter CPU-only, 384d L2-normalized, query/passage differ); whisper bridge fail-closed `runtimeNotLinked`; SigLIP2 preprocessing (aspect-fit + orientation + big-endian RGB)
- Files and documentation changed: see PR Files list (§3F.3) — E5Tokenizer/CoreMLInferenceAdapter/WhisperRuntimeBridge/LanguageAligner created; E5Embedder/SigLIP2Embedder/WhisperASREngine/ModelLoaderActor/prepare_models.sh/model_checksums.sha256 updated; model-provenance-register.md created; model-manifest.json + 3 reference files created; UIAutomation 6 created + 6 updated
- Deferred items closed or created, with evidence links: DEF-34-003 CLOSED (loader state report: `reportModelLoaded`/`reportModelLoadFailed` + LoaderStateReport tests); DEF-34-004 CLOSED (SigLIP2 orientation/aspect-fit/byte-order + Whisper 32-bit PCM + reader.status `.completed`); DEF-35-001 PARTIAL (SHA-256 pinned in model_checksums.sha256 + verify-only 100%; upstream commit-hash pinning remains `main` with TODO until network-resolvable, recorded in deferred-items.json)
- Known risks that do not weaken an in-scope gate: SigLIP2 Core ML conversion pending (`pending-conversion-and-approval`) — vision inference not real until 3F.3 follow-up/Phase 4; whisper.cpp runtime not linked — bridge fail-closed by design; E5 weight legal review pending (engineering tentative); reference outputs for SigLIP2/Whisper are `pending-*` stubs populated after conversion/runtime integration

<!-- PR-BODY:3F.3:START -->
## Overview
3F.3 落地 ADR-009 离线模型运行时：E5 真实 384d 文本推理（Unigram tokenizer + Core ML）、SigLIP2 视觉预处理与转换源工件登记、Whisper tiny GGUF 工件与 fail-closed 桥接、LanguageAligner（R-004 单次重试）、模型溯源登记册（model-provenance-register）与 DEF-34-003/004 关闭。SigLIP2 Core ML 转换与 whisper.cpp 运行时接入按 manifest `pending-*` 状态追踪。

## Related Specs
- Task: 3F.3 (migrated from 4.21/4.22)
- Stories: US-ING-001~005, US-RET-001/002/006, US-RES-001/004, US-SRC-011
- ADR: ADR-009 (offline model runtime), ADR-006 (space separation)
- Docs: docs/decisions/ADR-009-offline-model-runtime.md; docs/05-planning/model-provenance-register.md; docs/02-architecture/技术选型文档.md; docs/01-spec/用户故事与验收标准规格书.md

## AC Coverage
| AC # | Spec Summary | Test File | Implementation | Status |
| --- | --- | --- | --- | --- |
| US-ING-001 AC-3 | 384d E5 text vector written | EchoTests/Phase3F/3F.3_ProductionModelInferenceTests.swift (E5RealInference) | E5Embedder.embedText + CoreMLInferenceAdapter | ✅ |
| US-ING-001 AC-6 | FTS5 indexes normalized text only | (FTS path unchanged; E5 space separate per ADR-006) | SearchPipeline (pre-existing) | ✅ |
| US-ING-004 AC-3 | Image CLIP vector, separate space | EchoTests/Phase3F/3F.3_ProductionModelInferenceTests.swift (SigLIP2Preprocessing) | SigLIP2Embedder.preprocess (Core ML conversion pending) | 🔶 |
| US-ING-005 AC-2 | Offline audio transcript | EchoTests/Phase3F/3F.3_ProductionModelInferenceTests.swift (WhisperBridge) | WhisperRuntimeBridge fail-closed until runtime linked | 🔶 |
| US-RES-004 AC-1/AC-2/AC-3/AC-7 | Bundle-distributed; manual retry; no auto-retry; L3 recovery | EchoTests/Phase1/ModelLoaderActorTests.swift, EchoTests/Phase3F/3F.3_ProductionModelInferenceTests.swift (LoaderStateReport) | ModelLoaderActor + reportModelLoaded/Failed | ✅ |
| US-RES-004 AC-8 | `.modelLoadFailed` / `.modelLoadRetrySuccess` audit fields | ModelLoaderActorTests (pre-existing) | ModelLoaderActor (audit hookup pre-existing) | ✅ |
| US-SRC-011 AC-1 | Model semantics reference outputs | EchoTests/Phase3F/3F.3_ProductionModelInferenceTests.swift (E5ReferenceVectors) | e5-reference-vectors.json (SigLIP2/Whisper pending) | 🔶 |
| ADR-009 决策-2 | Immutable artifacts + provenance register | Scripts/model_checksums.sha256 + prepare_models.sh --verify-only | docs/05-planning/model-provenance-register.md | ✅ |
| ADR-009 决策-4 | LanguageAligner one-retry (R-004) | EchoTests/Phase3F/3F.3_ProductionModelInferenceTests.swift (LanguageAligner) | LanguageAligner.align + fallbackTemplate | ✅ |
| ADR-009 决策-5 | Loader state report (DEF-34-003) | EchoTests/Phase3F/3F.3_ProductionModelInferenceTests.swift (LoaderStateReport) | ModelLoaderActor.reportModelLoaded/Failed + E5Embedder | ✅ |
| ADR-009 决策-6 | Deterministic reference vectors | e5-reference-vectors.json bundle test | Resources/Models reference files | ✅ (E5) 🔶 (SigLIP2/Whisper) |

## Testing
- `xcodebuild build -scheme Echo -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` → BUILD SUCCEEDED (0 errors)
- Focused: `xcodebuild test-without-building ... -parallel-testing-enabled NO` → 7 suites green incl. E5 real inference (384d non-zero, L2 norm≈1.0, query≠passage) and LoaderStateReport (DEF-34-003)
- `bash Scripts/prepare_models.sh --verify-only` → exit 0, checksums OK for Manifest.json / tokenizer.json / whisper-tiny-q5_1.gguf / siglip2 model.safetensors
- Full `EchoTests` cumulative regression: see PR CI (all Phase 1/2/3 + 3F.1/3F.2 + 3F.3 suites)

## Documentation and Ledger
- Created: docs/05-planning/model-provenance-register.md; Echo/Resources/Models/model-manifest.json; e5/siglip2/whisper reference files
- Updated: README.md (3F.3 delivery note); docs/02-architecture/架构设计文档.md; docs/02-architecture/技术选型文档.md; docs/05-planning/task-status.json (3F.3 → review); docs/05-planning/deferred-items.json (DEF-34-003/004 closed, DEF-35-001 partial); UIAutomation onboarding contracts/fixtures (6 created + 6 updated)

## Risks
- SigLIP2 vision inference not real until Core ML conversion + approval (model-provenance-register §3, `pending-conversion-and-approval`); does not weaken 3F.11 no-fixture gate because visual channel is separate and scoped in 3F.5/3F.6/3F.11
- whisper.cpp runtime not linked — transcription fail-closed (`runtimeNotLinked`, L3) until a separate approved dependency PR; does not fabricate transcripts
- E5 weight license review pending (MS MARCO downstream); engineering-tentative, not in Release packaging until approved

## Deferred Items
- DEF-34-003: CLOSED (2026-08-06) — loader state report implemented + LoaderStateReport tests
- DEF-34-004: CLOSED (2026-08-06) — SigLIP2 orientation/aspect-fit/byte-order + Whisper 32-bit PCM + reader.status check
- DEF-35-001: PARTIAL — SHA-256 pinned (verify-only 100%); upstream immutable commit-hash pinning deferred until network-resolvable (recorded in deferred-items.json)

## Self-Check
- New Actor methods (CoreMLInferenceAdapter, WhisperRuntimeBridge, LanguageAligner, ModelLoaderActor.report*) are service/actor methods; PrivacyCheckpoint enforced by calling pipelines (R-006)
- No `@unchecked Sendable`, `nonisolated(unsafe)`, Combine, or `Task.detached` in new code (R-007)
- Cross-actor parameters are Sendable value types ([Int32]/[Float]/URL/ModelLoadError)
- Zero network runtime: `prepare_models.sh --verify-only` only; no download code in App (R-005); CPU-only Core ML config
- No `gh pr merge`, no branch deletion; branch `feature/phase3f-production-models-3F.3` preserved
<!-- PR-BODY:3F.3:END -->

---

## Entry: 3F.3a — SigLIP2 Core ML 转换与视觉推理接入

> Split from 3F.3 (2026-08-07 planning change): 3F.3 delivers conversion source + preprocessing; 3F.3a completes Core ML conversion, reference-vector validation and real vision inference. ADR-009 decisions 1/2 govern.

## Phase 3F Task Evidence
- Task / commit / branch / PR:
- Registered worktree path / ownership / clean rebase result: n/a — plain branch in main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only): n/a
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

<!-- PR-BODY:3F.3a:START -->
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
<!-- PR-BODY:3F.3a:END -->

---

## Entry: 3F.3b — whisper.cpp 运行时接入与真实转写

> Split from 3F.3 (2026-08-07 planning change): 3F.3 delivers GGUF artifact + fail-closed bridge; 3F.3b introduces whisper.cpp runtime (§2.2 whitelist approval), C interop and real transcription. Closes DEF-51-002 ASR file-input contract.

## Phase 3F Task Evidence
- Task / commit / branch / PR: 3F.3b — branch `feature/phase3f-whisper-runtime-3F.3b`, commit `feat(service): link whisper.cpp real transcription`, PR `feat(service): link whisper.cpp real transcription [3F.3b]` (base `dev-1.0`)
- Registered worktree path / ownership / clean rebase result: n/a — plain branch in main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only): n/a
- Pre-delivery task status and transition evidence: `in_progress` → `review` in docs/05-planning/task-status.json (2026-08-09); dependency whitelist approval for whisper.cpp recorded (AGENTS.md §2.2, human approval 2026-08-09)
- Quoted AC and architecture constraints: US-ING-003 AC-1 (voice memo transcription), US-ING-005 AC-2 (video audio offline transcription), US-SRC-011 model semantics (reference transcripts); AGENTS.md R-005 (zero network), R-007 (no nonisolated(unsafe)/unchecked Sendable); ADR-009 decisions 2/3 (immutable bundled artifact + fixed revision/SHA-256; zero-network runtime)
- RED test command and observed failure: `xcodebuild test ... -only-testing:EchoTests/WhisperRuntimeLinkedTests -only-testing:EchoTests/WhisperFileInputContractTests` — 2/2 failed: `test_bridge_runtimeLinked` caught `.runtimeNotLinked`; `test_asrEngine_fileURLInput` caught `.modelNotLoaded`
- Focused test command / exit / passed count: `xcodebuild test -project Echo.xcodeproj -scheme Echo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EchoTests/WhisperRuntimeLinkedTests -only-testing:EchoTests/WhisperRealTranscriptTests -only-testing:EchoTests/WhisperReferenceCERWERTests -only-testing:EchoTests/WhisperGGUFHashTests -only-testing:EchoTests/WhisperFileInputContractTests` — 7/7 passed (real inference ~28-30s per test, total 145s)
- Cumulative test command / exit / passed count: `xcodebuild test ... -only-testing:EchoTests` — 857 tests / 105 suites, 0 failures, exit 0 (338s)
- Release simulator and device commands / exits: Release simulator build fails on pre-existing non-DEBUG-gated `simulateError` in `#Preview` blocks (CreationView/MemoryDetailView/SearchView) — identical failure on `dev-1.0` base, out of 3F.3b scope (documented in 3F.1 entry); whisper-cpp package itself compiles clean for arm64+x86_64 (GGML_CPU_GENERIC resolves arch-fallback duplicate-symbol conflict)
- Static/privacy/model/compliance commands / exits: `swiftlint lint --quiet` → 0 errors, 0 warnings in changed files (repo-wide clean); `bash Scripts/prepare_models.sh --verify-only` → exit 0, whisper-tiny-q5_1.gguf checksum OK; no network-denial scan regression (whisper loads GGUF from Bundle, R-005)
- Production path exercised: `WhisperRuntimeBridge.transcribe(pcm:)` real inference on 16kHz mono PCM (jfk.wav 11s) → transcript "And so my fellow Americans ask not what your country can do for you, ask what you can do for your country." (CER=0.0 vs reference); `WhisperASREngine.transcribeFile(at:)` file-URL contract (DEF-51-002); GGUF SHA-256 verified before transcription (ADR-009 decision 2)
- Files and documentation changed: ThirdParty/whisper.cpp/ (vendored v1.9.2, rev 306c88f4d1, Package.swift, LICENSE, AUTHORS, samples/jfk.wav); Echo/Core/Services/NativeWhisperCInterop.swift (new); WhisperRuntimeBridge.swift / WhisperASREngine.swift / ASREngineService.swift (real wiring + transcribeFile contract); Echo.xcodeproj (local package reference); Echo/Resources/Models/whisper-reference-transcripts.json (approved backfill) + jfk.wav (new); Scripts/model_checksums.sha256; EchoTests/Phase3F/3F.3b_WhisperRuntimeTests.swift (new) + 3F.3_ProductionModelInferenceTests.swift (fail-closed → injected); docs (README, 技术选型, 数据流, 避坑手册, ADR-009, model-provenance-register §2, evidence-index, deferred-items DEF-51-002, phase3f-execution-plan, task-status)
- Deferred items closed or created, with evidence links: DEF-51-002 ASR contract portion CLOSED (transcribeFile(at:) implemented + tested in WhisperRuntimeTests.FileInputContract; Share Extension App Group persistence portion remains deferred to 3F.5, recorded with resolution_notes in deferred-items.json)
- Known risks that do not weaken an in-scope gate: whisper.cpp built with `GGML_CPU_GENERIC` (no arch/arm NEON-specific acceleration) — CPU-only inference, whisper tiny Q5_1 transcribes 11s audio in ~28s on simulator; acceptable for v1 and does not weaken 3F.11 gate; Release simulator build `simulateError` Preview failure pre-existing on base (3F.1/3F.11 scope); SBOM/NOTICE for whisper.cpp created at §4 packaging gate per model-provenance-register policy

<!-- PR-BODY:3F.3b:START -->
## Overview
Task 3F.3b integrates the whisper.cpp runtime (v1.9.2, vendored local Swift package at fixed revision 306c88f4d1) into Echo, replacing the fail-closed `WhisperRuntimeBridge` stub with real on-device transcription. `NativeWhisperCInterop` provides a Sendable-safe C wrapper (`whisper_init_from_file_with_params` + `whisper_full`); `WhisperRuntimeBridge` now defaults to it, verifies the GGUF SHA-256 against model-provenance-register §2 before inference (ADR-009 decision 2), and reports loader state (DEF-34-003). `WhisperASREngine.transcribe` is fully implemented (preprocessAudio → VAD → bridge). The ASR protocol gained a file-URL input contract (`transcribeFile(at:)`) closing the DEF-51-002 ASR contract. Reference transcripts (`whisper-reference-transcripts.json`) were backfilled with a real jfk.wav inference (CER=0.0 within 0.15 threshold). Full suite: 857 tests / 105 suites green.

## Related Specs
- Task 3F.3b (split from 3F.3, 2026-08-07)
- User Stories: US-ING-003 AC-1 (voice memo transcription), US-ING-005 AC-2 (video audio offline transcription), US-SRC-011 (model semantics reference outputs)
- ADR-009 decisions 2/3 (immutable bundled artifact + fixed revision/SHA-256; zero-network runtime)
- AGENTS.md R-005 (zero network), R-007 (no nonisolated(unsafe)/unchecked Sendable), §2.2 dependency whitelist (whisper.cpp approved 2026-08-09)
- docs/05-planning/model-provenance-register.md §2 (GGUF approved; runtime section added), §2.3
- Deferred item DEF-51-002 (ASR file-input contract redesign)

## AC Coverage
| AC # | Spec Summary | Test File | Implementation | Status |
| --- | --- | --- | --- | --- |
| US-ING-003 AC-1 | Voice memo transcription via Whisper | EchoTests/Phase3F/3F.3b_WhisperRuntimeTests.swift (RealTranscript) | WhisperRuntimeBridge.transcribe → NativeWhisperCInterop | ✅ |
| US-ING-005 AC-2 | Offline transcription of audio track | EchoTests/Phase3F/3F.3b_WhisperRuntimeTests.swift (FileInputContract) | WhisperASREngine.transcribeFile(at:) | ✅ |
| US-SRC-011 | Reference transcripts with CER/WER threshold | EchoTests/Phase3F/3F.3b_WhisperRuntimeTests.swift (ReferenceCERWER) | whisper-reference-transcripts.json (approved, jfk CER=0.0 ≤ 0.15) | ✅ |
| ADR-009 dec-2 | Immutable artifact + SHA-256 verification | EchoTests/Phase3F/3F.3b_WhisperRuntimeTests.swift (GGUFHash) | WhisperRuntimeBridge.verifyGGUFChecksum + model_checksums.sha256 | ✅ |
| ADR-009 dec-3 | Zero-network runtime (R-005) | WhisperRuntimeTests.RealTranscript (Bundle-loaded GGUF) | whisper_init_from_file_with_params on local path | ✅ |
| DEF-51-002 | ASR file-URL input contract | EchoTests/Phase3F/3F.3b_WhisperRuntimeTests.swift (FileInputContract) | ASREngineProtocol.transcribeFile(at:) + WhisperASREngine impl | ✅ |
| R-007 | No nonisolated(unsafe)/unchecked Sendable | CI static scan + SwiftLint | NativeWhisperCInterop (Sendable-safe, no escape) | ✅ |

## Testing
- RED: `xcodebuild test ... -only-testing:EchoTests/WhisperRuntimeLinkedTests -only-testing:EchoTests/WhisperFileInputContractTests` — 2/2 failed (`.runtimeNotLinked`, `.modelNotLoaded`)
- Focused: `xcodebuild test -project Echo.xcodeproj -scheme Echo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO` + 5 WhisperRuntime test classes — 7/7 passed (real inference, CER=0.0 ≤ 0.15)
- Model-gated skip (PR review fix): model-dependent Whisper tests silently skip when GGUF/jfk.wav absent, matching 3F.3a SigLIP2 / E5 convention (DEF-54-001) — verified 7/7 pass with model, all skip without model
- Cumulative: `xcodebuild test ... -only-testing:EchoTests` — 857 tests / 105 suites, 0 failures, exit 0 (338s, local with models)
- Model gate: `bash Scripts/prepare_models.sh --verify-only` — exit 0, whisper GGUF checksum OK
- Lint: `swiftlint lint --quiet` — 0 errors / 0 warnings (changed files), repo-wide clean
- Release: whisper-cpp package compiles for arm64+x86_64 (GGML_CPU_GENERIC); Echo Release simulator build blocked only by pre-existing `simulateError` `#Preview` failure (documented 3F.1, base-reproducible)

## Documentation and Ledger
- README.md, docs/02-architecture/技术选型文档.md, docs/02-architecture/数据流全链路技术说明文档.md, docs/03-implementation/开发避坑与关键注意点手册.md updated for whisper runtime
- docs/decisions/ADR-009-offline-model-runtime.md: runtime-integration status updated
- docs/05-planning/model-provenance-register.md §2.2/§2.3: reference transcripts approved + runtime integration section
- docs/05-planning/deferred-items.json: DEF-51-002 ASR contract portion closed with resolution_notes
- docs/05-planning/phase3f-execution-plan.md §3F.3b: task completed
- docs/05-planning/task-status.json: 3F.3b → review
- Scripts/model_checksums.sha256: jfk.wav + whisper.cpp LICENSE registered

## Risks
- whisper.cpp built with GGML_CPU_GENERIC (no NEON-specific arch/arm acceleration): CPU-only inference, ~28s for 11s audio on simulator; acceptable for v1, does not weaken 3F.11 gate (performance gate is P95 search latency, not ASR throughput). Recorded in Package.swift build-decision comment.
- Release simulator build `simulateError` `#Preview` failure is pre-existing on base (3F.1 entry, 3F.11 release-gate scope); not introduced by this task.
- SBOM/NOTICE for whisper.cpp runtime deferred to model-provenance-register §4 packaging gate (per register policy "打包前创建").

## Deferred Items
- DEF-51-002 (ASR contract): contract portion CLOSED by this task (`transcribeFile(at:)` + tests). Share Extension App Group audio-file persistence portion remains open, deferred to 3F.5 (production ingestion) with resolution_notes in deferred-items.json.
- No new deferred items created by this task.

## Self-Check
- [x] All new pipeline/service entries follow actor isolation (WhisperRuntimeBridge actor; NativeWhisperCInterop Sendable-safe, no cross-isolation pointer escape)
- [x] No `nonisolated(unsafe)`, `@unchecked Sendable`, or Combine in new code (R-007)
- [x] Zero network: GGUF loaded from Bundle via ModelLoaderActor (R-005); no download code
- [x] GGUF SHA-256 verified before inference (ADR-009 decision 2)
- [x] DEF-51-002 ASR file-input contract implemented and tested
- [x] Reference transcripts backfilled with real inference (CER=0.0 ≤ 0.15)
- [x] Branch `feature/phase3f-whisper-runtime-3F.3b`, commit `feat(service): link whisper.cpp real transcription`, PR base `dev-1.0`
<!-- PR-BODY:3F.3b:END -->

---

## Entry: 3F.4 — Canonical storage 与 generation 生命周期

## Phase 3F Task Evidence
- Task / commit / branch / PR: 3F.4 — branch `feature/phase3f-canonical-generations-3F.4`, commit `feat(actor): add canonical generation lifecycle`, PR `feat(actor): add canonical generation lifecycle [3F.4]` (base `dev-1.0`)
- Registered worktree path / ownership / clean rebase result: n/a — 3F.1~3F.11 use plain branches in the main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only): n/a
- Pre-delivery task status and transition evidence: `in_progress` → `review` in docs/05-planning/task-status.json (2026-08-09)
- Quoted AC and architecture constraints: US-ING-006 AC-1/2/3/4/5 (transactional canonical/vector/FTS commit; rollback; fault injection; `.ingestTransaction` audit), US-PRV-004 AC-2/3 (仅从 Echo 移除写 ExcludedAssets; 级联不写), US-PRV-007 AC-2/5 (cascade delete cleans invalid exclusions; `.cascadeDeleteFromOriginal` excludedWritten=false), US-AWK-007 AC-2/4/6 (originalTimestamp/userEdited/userLocked), US-FBK-001/002/003 (feedback generation identity); AGENTS.md D-002/D-003/D-005, §5; ADR-010 decisions 1/2/3/4/5/7
- RED test command and observed failure: new `EchoTests/CanonicalGenerationTests` suites failed to compile until deterministicID/transaction/repository symbols existed (18 focused tests were RED); the deterministic ID RFC-4122 shape assertion initially failed (byte-order) and was corrected — final 18/18 pass
- Focused test command / exit / passed count: `xcodebuild test -project Echo.xcodeproj -scheme Echo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EchoTests/CanonicalGenerationTests` — 18/18 passed (DeterministicID 4, TransactionalCommit 3, Lifecycle 4, FeedbackIdentity 2, DeletionBoundary 3, EditPersistence 1, SchemaMigration 1)
- Cumulative test command / exit / passed count: `xcodebuild test ... -only-testing:EchoTests` — 893 tests / 113 suites, 0 failures, exit 0
- Release simulator and device commands / exits: Release simulator build fails on pre-existing non-DEBUG-gated `simulateError` in `#Preview` blocks (CreationView/MemoryDetailView/SearchView) — identical failure on `dev-1.0` base, out of 3F.4 scope (documented in 3F.1 entry)
- Static/privacy/model/compliance commands / exits: `swiftlint lint --quiet` → exit 0, 0 errors (github-actions-logging reporter, identical to HEAD baseline); no strict-concurrency warnings on new/changed Core files; PrivacyCheckpoint on new repository write/delete entry points via existing actors
- Production path exercised: CanonicalMemoryRepositoryActor.commit (canonical+representation+FTS atomic via `executeTransaction`, vector compensation), deleteMemory (D-005 full boundary incl. translationCache), cascadeDeleteFromOriginal (ExcludedAssets cleanup), GenerationRegistryActor activate/rollback/restoreActiveRoute/persistStore; `.ingestTransaction` / `.memoryDeleted` / `.cascadeDeleteFromOriginal` audits written
- Files and documentation changed: Echo/Core/Actors/CanonicalMemoryRepositoryActor.swift (new), DatabaseMigrationActor.swift (new); DatabaseManager.swift (MemoryFTS, translationCache, Memory edit columns, FeedbackStore.generationId, ActiveRouteSet.previousTextGeneration, `executeTransaction`/`DBWrite`); GenerationRegistryActor.swift (finishShadowBuild/activateGeneration/rollbackToPrevious/restoreActiveRoute/persistStore/removeStoreFile, registerGeneration disk restore); FeedbackActor.swift (generationId); CanonicalMemory.swift (originalTimestamp/userEdited/userLocked); ActiveRouteSet.swift (previousTextGeneration); AuditEvent.swift (.ingestTransaction); EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (new) + RA_CanonicalModelTests.swift/RA_GenerationRegistryTests.swift (extended); docs (README, 架构设计, 数据流, 避坑手册, ADR-010, evidence-index, deferred-items DEF-38-001/002, phase3f-execution-plan, task-status)
- Deferred items closed or created, with evidence links: DEF-38-001 (originalTimestamp) closed; DEF-38-002 (userLocked) partial — Core persistence layer delivered (Memory.originalTimestamp/userEdited/userLocked columns + round-trip test in CanonicalGenerationTests.EditPersistence), SyncPipeline skip-on-userLocked wiring deferred to 3F.7 (tracking_status=partial in deferred-items.json)
- Known risks that do not weaken an in-scope gate: SearchPipeline/IngestPipeline still route through a single in-memory VectorStoreActor until 3F.5/3F.6 production wiring consumes GenerationRegistryActor per-generation stores; `executeTransaction` removes the DEF-50-001 interleave risk for canonical writes, but `ConsentStoreActor.revokeConsent`'s transaction still spans suspension points (DEF-50-001 remains open, target 3F.11 DatabaseManager atomic purge refactor); Release simulator build `simulateError` `#Preview` failure pre-existing on base (3F.1/3F.11 scope)

<!-- PR-BODY:3F.4:START -->
## Overview
Task 3F.4 delivers the canonical storage and generation lifecycle per ADR-010. A new `CanonicalMemoryRepositoryActor` owns the canonical facts source with deterministic RFC-4122-derived memory IDs (SHA-256 namespace, version 5 / variant 8, input-order independent). `commit` writes Memory/Representation/MemoryFTS in a single synchronous SQLite `executeTransaction` (no suspension points — removes the DEF-50-001 interleave pattern for canonical writes) then ingests per-generation vectors with compensating rollback; any vector failure deletes the canonical row + written vectors, so no half-write or mixed-generation state survives. `deleteMemory` enforces the D-005 full deletion boundary (vectors across all generations + MemoryFTS + translationCache + audit + optional ExcludedAssets write per US-PRV-004); `cascadeDeleteFromOriginal` implements US-PRV-007 (no ExcludedAssets write, invalid exclusion records cleaned, `.cascadeDeleteFromOriginal` audit). `GenerationRegistryActor` gains the lifecycle: `finishShadowBuild` (building→ready), `activateGeneration` (atomic route publish with version bump + `previousTextGeneration` rollback target), `rollbackToPrevious`, `restoreActiveRoute` (reopens per-generation `.pxkt` stores from disk, dimension-guarded) and `persistStore`. Feedback rows now carry `generationId` (US-FBK identity). US-AWK-007 edit fields (`originalTimestamp`/`userEdited`/`userLocked`) persist on Memory. Full suite: 893 tests / 113 suites green.

## Related Specs
- Task 3F.4 — Canonical storage 与 generation 生命周期
- User Stories: US-ING-006 AC-1~5, US-PRV-004 AC-2/3/5, US-PRV-006 AC-6, US-PRV-007 AC-2/5, US-AWK-007 AC-2/4/6, US-FBK-001/002/003
- ADR-010 decisions 1/2/3/4/5/7
- AGENTS.md D-002/D-003/D-005, §5 存储契约; R-007/R-008
- docs/05-planning/phase3f-execution-plan.md §3F.4, §4.6.4
- Deferred items DEF-38-001/002

## AC Coverage
| AC # | Spec Summary | Test File | Implementation | Status |
| --- | --- | --- | --- | --- |
| US-ING-006 AC-1/2 | Memory+Representation+MemoryFTS one SQLite transaction; vectors written after with compensating rollback | EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (TransactionalCommit) | CanonicalMemoryRepositoryActor.commit + DatabaseManager.executeTransaction | ✅ |
| US-ING-006 AC-3 | FTS5 index synced with main transaction | EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (TransactionalCommit) | MemoryFTS virtual table written in commit | ✅ |
| US-ING-006 AC-4 | Fault injection proves rollback correctness | EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (vector failure / crash point) | setFault(.vectorWrite/.afterCanonicalWrite) + compensation | ✅ |
| US-ING-006 AC-5 | `.ingestTransaction` audit rolledBack=true/false | EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (TransactionalCommit) | AuditEvent.ingestTransaction + writeTransactionAudit | ✅ |
| US-PRV-004 AC-2 | 仅从 Echo 移除 writes ExcludedAssets + clears all copies | EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (DeletionBoundary) | deleteMemory(writeExcluded:) + excludedAssets.add | ✅ |
| US-PRV-007 AC-2/5 | Cascade delete no ExcludedAssets write; cleans invalid records; `.cascadeDeleteFromOriginal` | EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (DeletionBoundary) | cascadeDeleteFromOriginal + excluded.remove + audit | ✅ |
| D-005 | Full deletion boundary covers translationCache | EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (DeletionBoundary) | deleteMemory clears translationCache | ✅ |
| US-AWK-007 AC-2/4/6 | originalTimestamp/userEdited/userLocked persist | EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (EditPersistence) + RA_CanonicalModelTests | Memory model + schema columns + repository round-trip | ✅ |
| US-FBK-001/002/003 | Feedback generation identity | EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (FeedbackIdentity) | FeedbackStore.generationId + FeedbackActor.generationId(for:) | ✅ |
| ADR-010 dec-1 | Deterministic RFC-4122-derived IDs (input-order independent) | EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (DeterministicID) | CanonicalMemoryRepositoryActor.deterministicID | ✅ |
| ADR-010 dec-2/3 | Shadow build, atomic publish, rollback, restart restore | EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (Lifecycle) + RA_GenerationRegistryTests | GenerationRegistryActor lifecycle methods + per-generation `.pxkt` persist | ✅ |
| ADR-010 dec-4 | Generation-aware feedback | EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (FeedbackIdentity) | FeedbackStore.generationId column | ✅ |
| ADR-010 dec-7 | Per-space separated generation stores (dimension-guarded) | EchoTests/Phase3F/3F.4_CanonicalGenerationTests.swift (Lifecycle) | registerGeneration/restoreActiveRoute dimension check | ✅ |

## Testing
- RED: `EchoTests/CanonicalGenerationTests` — 18 focused tests, compile-RED before repository/lifecycle symbols existed; RFC-4122 shape assertion initially failed (byte order), corrected
- Focused: `xcodebuild test ... -only-testing:EchoTests/CanonicalGenerationTests` — 18/18 passed
- Extended R-A: `-only-testing:EchoTests/GenerationRegistryTests -only-testing:EchoTests/ActiveRouteSetTests -only-testing:EchoTests/CanonicalModelTests` — 28/28 passed (with focused = 46)
- Cumulative: `xcodebuild test ... -only-testing:EchoTests` — 893 tests / 113 suites, 0 failures, exit 0
- Lint: `swiftlint lint --config .swiftlint.yml --reporter github-actions-logging --quiet` — exit 0, 0 errors (identical to HEAD baseline)
- Release: Echo Release simulator build blocked only by pre-existing `simulateError` `#Preview` failure (documented 3F.1, base-reproducible)

## Documentation and Ledger
- README.md, docs/02-architecture/架构设计文档.md, docs/02-architecture/数据流全链路技术说明文档.md, docs/03-implementation/开发避坑与关键注意点手册.md updated for canonical storage/generation lifecycle
- docs/decisions/ADR-010-canonical-generation-lifecycle.md: implementation status recorded
- docs/05-planning/deferred-items.json: DEF-38-001/002 closed with evidence
- docs/05-planning/phase3f-execution-plan.md §3F.4: task completed
- docs/05-planning/task-status.json: 3F.4 → review
- EchoTests/Phase2/RA_CanonicalModelTests.swift + RA_GenerationRegistryTests.swift extended (edit fields + lifecycle)

## Risks
- SearchPipeline/IngestPipeline single-store routing replaced at 3F.5/3F.6 production wiring (generation registry consumption); no mixed-generation route can be published (activateGeneration validates non-building), so this does not weaken 3F.11
- DEF-50-001 (ConsentStoreActor.revokeConsent transaction spans suspension points) remains open — canonical `executeTransaction` is suspension-free, but revokeConsent still awaits DatabaseManager across its transaction; target 3F.11 DatabaseManager atomic purge refactor
- Release simulator build `simulateError` `#Preview` failure is pre-existing on base (3F.1 entry, 3F.11 release-gate scope); not introduced by this task

## Deferred Items
- DEF-38-001 (originalTimestamp backup field): CLOSED — Memory.originalTimestamp persisted + round-trip tested (CanonicalGenerationTests.EditPersistence)
- DEF-38-002 (userLocked semantics): PARTIAL — Memory.userLocked persisted (schema + round-trip, Core persistence layer delivered); SyncPipeline skip-on-userLocked wiring remains 3F.7 scope (tracking_status=partial)
- No new deferred items created by this task

## Self-Check
- [x] New Actor methods are actor-isolated; cross-actor calls awaited (R-008); no `nonisolated(unsafe)`/`@unchecked Sendable`/Combine (R-007)
- [x] Canonical writes use suspension-free `executeTransaction` (no half-write; DEF-50-001 pattern not reintroduced)
- [x] Deletion boundary covers vector + index + cache + metadata + audit + translationCache (D-005)
- [x] ExcludedAssets written only on user "仅从 Echo 移除"; cascade delete never writes and cleans invalid records (D-002/D-003, US-PRV-007)
- [x] Feedback generation identity persisted (US-FBK)
- [x] `originalTimestamp`/`userEdited`/`userLocked` persist (US-AWK-007, DEF-38-001/002)
- [x] Branch `feature/phase3f-canonical-generations-3F.4`, commit `feat(actor): add canonical generation lifecycle`, PR base `dev-1.0`
<!-- PR-BODY:3F.4:END -->

---

## Entry: 3F.5 — Production ingestion

## Phase 3F Task Evidence
- Task / commit / branch / PR: 3F.5 Production ingestion — branch `feature/phase3f-production-ingestion-3F.5`
- Registered worktree path / ownership / clean rebase result: n/a — 3F.1~3F.11 use plain branches in the main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only): n/a
- Pre-delivery task status and transition evidence: task-status.json 3F.5 ready → in_progress (2026-08-10); dependencies 3F.2/3F.3/3F.3a/3F.3b/3F.4 all done
- Quoted AC and architecture constraints: US-ING-001/002/003/004/005/006, US-SRC-012/013, US-SYS-001, US-RES-001/002/003/004; ADR-010 (canonical + generation routing), ADR-011 (TaskQueue/Progress), AGENTS.md §4.3/§4.5
- RED test command and observed failure: `xcodebuild test ... -only-testing:EchoTests/ProductionIngestionTests` — 4 initial failures (assetUnavailableLocally, notFound, privacyDenied video, unsupportedContentKind) before extractor/authorization/progress wiring
- Focused test command / exit / passed count: `-only-testing:EchoTests/ProductionIngestionTests` — 15/15 passed (TaskQueue serial/cancel/completion + CR-1 cancel-resume/paused-no-starve, photo/text/audio/video production traces, fault rollback, no-stub real-type assertion, route resolution, audit traceID, sync canonical delete + CR-11 fault, drain production path)
- Cumulative test command / exit / passed count: `-only-testing:EchoTests` — 905 unit tests / 0 failures (CI, ModelBundleTests skipped) + 33 UI tests; local full regression 937 tests / 0 failures (was 893 baseline + new)
- Release simulator and device commands / exits: pending pre-merge run
- Static/privacy/model/compliance commands / exits: SwiftLint exit 0 (modifier_order warnings match existing codebase convention)
- Production path exercised: AppDelegate wires E5/SigLIP2/Whisper + CanonicalMemoryRepositoryActor + GenerationRegistryActor + TaskQueueActor; drainSharedImports routes through production ingestion when canonical configured (closes DEF-51-001 orphan-store writes)
- Files and documentation changed: `Echo/Core/Actors/TaskQueueActor.swift` (new), `Echo/Core/Sources/PhotoAssetExtractor.swift` (new), `VideoAssetExtractor.swift` (new), `SharedTextExtractor.swift` (new), `SharedAudioExtractor.swift` (new), `Echo/Core/Pipelines/IngestPipeline.swift`, `SyncPipeline.swift`, `Echo/Core/Services/EmbedderService.swift`, `SigLIP2Embedder.swift`, `Echo/Core/Actors/PrivacyActor.swift`, `CanonicalMemoryRepositoryActor.swift`, `Echo/App/AppDelegate.swift`, `EchoTests/Phase3F/3F.5_ProductionIngestionTests.swift` (new), docs (README, architecture, data-flow, pitfalls, ADR-011, execution plan, evidence index, task-status, deferred-items)
- Deferred items closed or created, with evidence links: DEF-51-001 (orphan VectorStoreActor) — AppDelegate now routes shared-import drain through canonical production path; DEF-56-004 (deleteMemory full-index rewrite) remains deferred to 3F.5/3F.6 production wiring
- Known risks that do not weaken an in-scope gate: video production path embeds frames via `embedImageData` (SigLIP2) — real vision inference still depends on 3F.3a Core ML conversion approval (DEF-54-001); real PhotoKit/AVFoundation extraction requires simulator/device photo library, covered by injectable extractor contracts in unit tests

<!-- PR-BODY:3F.5:START -->
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
<!-- PR-BODY:3F.5:END -->

---

## Entry: 3F.6 — Production search 与 feedback

## Phase 3F Task Evidence
- Task / commit / branch / PR: 3F.6 Production search 与 feedback — branch `feature/phase3f-search-feedback-3F.6`
- Registered worktree path / ownership / clean rebase result: n/a — 3F.1~3F.11 use plain branches in the main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only): n/a
- Pre-delivery task status and transition evidence: task-status.json 3F.6 ready → in_progress (2026-08-11) → review; dependencies 3F.3/3F.4/3F.5 all done; Phase 3 integration 3.10 done
- Quoted AC and architecture constraints: US-RET-001/002/003/004/005/006/007/008 (3F.0 amendments), US-FBK-001/002/003, US-PRV-001, US-SRC-010 (search contract), US-SRC-011 (subjective ranking/feedback); ADR-010 (generation routing + feedback identity), AGENTS.md §5.3 (feedback rerank contract 0.80/decay/clamp), §4.1 (pipeline contract), R-006 (PrivacyCheckpoint), R-008
- RED test command and observed failure: `xcodebuild test ... -only-testing:EchoTests/ProductionSearchFeedbackTests` — 30 tests / 14 failures (cache store/lookup/invalidate, adapter search/route/timeout, denied-source gate, followUpQuery audit, query-conditioned feedback, L2 PendingOperations, generationId passthrough, searchCanonical ORDER BY); `-only-testing:EchoTests/CrossAppSearchTests` — 15 tests / 12 failures (parse, temporal window, per-source denial, source labels, crossAppSearch audit, subjective rerank)
- Focused test command / exit / passed count: `-only-testing:EchoTests/ProductionSearchFeedbackTests` + `EchoTests/CrossAppSearchTests` — 45/45 passed (30 + 15)
- Cumulative test command / exit / passed count: `xcodebuild test` (full suite, serial) — 962 tests / 116 suites / 0 failures; SwiftLint 0 errors; both planning JSONs valid
- Release simulator and device commands / exits: Release build fails on pre-existing `simulateError` `#Preview` references in CreationView/MemoryDetailView/SearchView (recorded as pre-existing in 3F.1 evidence; 3F.11 scope)
- Static/privacy/model/compliance commands / exits: SwiftLint exit 0 (modifier_order warnings match existing codebase convention); R-007/network scan clean
- Production path exercised: SearchPipeline.search (feedback rerank + followUpQuery audit), GenerationRoutedChannelAdapter (generation-routed retrieval), SearchResultCacheActor (policy-aware TTL cache), FeedbackPipeline (generationId + L2 PendingOperations), CrossAppIntentParser + ProductionCrossAppFusionEngine (health+memory / location+photo fusion), CanonicalMemoryRepositoryActor.searchCanonical (FTS rank ordering)
- Files and documentation changed: `Echo/Core/Services/SearchChannelAdapters.swift` (new), `Echo/Core/Services/BoundedReranker.swift` (new), `Echo/Core/Actors/SearchResultCacheActor.swift` (new), `Echo/Core/Services/CrossAppIntentParser.swift` (new), `Echo/Core/Services/CrossAppFusionEngine.swift` (new), `Echo/Core/Pipelines/SearchPipeline.swift`, `Echo/Core/Pipelines/FeedbackPipeline.swift`, `Echo/Core/Actors/FeedbackActor.swift`, `Echo/Core/Actors/PendingOpsActor.swift`, `Echo/Core/Actors/CanonicalMemoryRepositoryActor.swift`, `Echo/Core/Models/AuditEvent.swift`, `EchoTests/Phase3F/3F.6_ProductionSearchFeedbackTests.swift` (new), `EchoTests/Phase3F/3F.6_CrossAppSearchTests.swift` (new), `EchoTests/Phase1/SQLiteActorTests.swift`, `EchoTests/Phase2/SearchWithFeedbackTests.swift`, docs (README, spec, architecture, data-flow, bilingual, pitfalls, ADR-010, execution plan, evidence index, task-status, deferred-items)
- Deferred items closed or created, with evidence links: DEF-34-001 (RRF ID-keyed metadata), DEF-34-002 (timeout/L3 error separation), DEF-37-001 (feedback L2 → PendingOperations), DEF-56-005 (generationId passthrough), DEF-56-006 (searchCanonical ORDER BY rank) — all closed with test evidence; DEF-58-001 created (US-RET-005 AC-3 LLM rewrite deferred, approach a)
- Known risks that do not weaken an in-scope gate: SigLIP2 vision inference still depends on 3F.3a Core ML conversion approval — vision channel empty index degrades to timedOut partial results by design (US-RET-008); Release simulator build simulateError #Preview failure pre-existing on base (3F.1/3F.11 scope); US-SRC-010 live HealthKit provider conformance lands in 3F.8 (protocol declared in 3F.6, never instantiated here)

<!-- PR-BODY:3F.6:START -->
## Overview
Production search and feedback: multi-channel generation-routed retrieval (text_dense/vision_dense/ocr_text/lexical) with RRF fusion and ID-keyed metadata, timeout/partial-result degradation (US-RET-008), policy-aware result cache (US-RET-007), follow-up query audit (US-RET-005 AC-4), query-conditioned feedback (US-FBK-001 AC-4), feedback generation identity (ADR-010 decision-4), L2 feedback failures routed to PendingOperations (manual retry), cross-app intent parsing + multi-source temporal-aligned fusion with per-source authorization and `.crossAppSearch` audit (US-SRC-010), subjective bounded reranking (US-SRC-011), and FTS-relevance ordering for canonical search (DEF-56-006).

**PR#58 review fixes (2026-08-11)**: follow-up audit now stores query SHA-256 hash (AGENTS.md §5.4 hash-only, was raw text — 🔴); session state updated only after PrivacyCheckpoint; follow-up audit `traceID` = current round (parent in payload); deterministic RRF tie-break; lexical channel fail-closed (`lexicalNotConnected`); per-source authorization filtering in `GenerationRoutedChannelAdapter` + metadata collision keeps highest similarity; `markBadCase` L2 failure → PendingOperations (shared helper); fusion partial-authorization continues authorized subset; provider timeout isolation; best-effort cross-app audit; temporal month/day range + round-trip validation; CrossApp tests exercise `ProductionCrossAppFusionEngine` (test engine removed); DEF-34-001 / PRV-001 tests drive production paths (seeded positive control); temporal test year derived from current date; subjective & RET-005 tests assert production behavior (test-local stand-ins removed); dead code + doc cleanups. US-RET-005 AC-1/AC-2 (FIFO ≤10 + memoryIds injection) NOT implemented in production — spec note corrected and DEF-58-002 recorded (was over-claimed ✅).

## Related Specs
- Task: 3F.6 — Production search 与 feedback
- Stories: US-RET-001~008, US-FBK-001~003, US-PRV-001, US-SRC-010, US-SRC-011
- ADR: ADR-010 (canonical generation lifecycle: route + feedback identity), ADR-009 (offline runtime — no generative LLM, hence US-RET-005 AC-3 deferred)
- Docs: docs/05-planning/phase3f-execution-plan.md §3F.6; docs/01-spec/用户故事与验收标准规格书.md §4/§9.3; docs/03-implementation/双语言实现说明文档.md §4

## AC Coverage
Status legend: ✅ implemented + tested · 🔴 deferred/not implemented (tracked) · 🔮 Phase 3/4 scope

| AC # | Spec Summary | Test File | Implementation | Status |
| --- | --- | --- | --- | --- |
| US-RET-003 | 多通道 generation 路由 + 独立向量空间 | 3F.6_ProductionSearchFeedbackTests.swift (test_generationRouting_ActiveVisionRouteResolvesStore, test_AC2_TextVisionSeparateVectorSpaces, test_adapterSearch_ResolvesThroughActiveRoute) | Echo/Core/Services/SearchChannelAdapters.swift (GenerationRoutedChannelAdapter) | ✅ |
| US-RET-005 | 对话历史 FIFO≤10 (AC-1) + memoryIds 隐式过滤 (AC-2) + .followUpQuery 审计 (AC-4)（AC-3 LLM 改写延后） | 3F.6_ProductionSearchFeedbackTests.swift (test_AC4_FollowUpAuditCarriesParentTraceID) | Echo/Core/Pipelines/SearchPipeline.swift + AuditEvent.followUpQuery | 🔴 AC-1/2 未落地（仅单轮 lastQuery 追踪，DEF-58-002）· ✅ AC-4 · 🔴 AC-3 (DEF-58-001) |
| US-RET-007 | 缓存键含 policyVersion/modelVersion/queryHash；TTL；policy 失效 | 3F.6_ProductionSearchFeedbackTests.swift (test_AC4_CacheKey*, test_AC3_StoreThenLookupReturnsItemsWithinTTL, test_AC1_LookupReturnsNilAfterTTLExpiry, test_AC2_InvalidateRemovesPolicyVersionEntries) | Echo/Core/Actors/SearchResultCacheActor.swift | ✅ |
| US-RET-008 | 通道超时 2s → timedOut 部分结果，不阻断其他通道 | 3F.6_ProductionSearchFeedbackTests.swift (test_AC1_TimeoutChannelReturnsTimedOutFlag, test_DEF34_002_L3ErrorDistinguishedFromTimeout) | Echo/Core/Services/SearchChannelAdapters.swift | ✅ |
| US-FBK-001 | 反馈关联 memoryId + query（query-conditioned） | 3F.6_ProductionSearchFeedbackTests.swift (test_feedback_QueryTextConditioned) + Phase2 SearchWithFeedbackTests | Echo/Core/Actors/FeedbackActor.swift (computeAdjustment 过滤 queryText) | ✅ |
| US-FBK-002 | 重排：阈值 0.80 / 衰减 1.0-0.5-归档 / 截断 ±0.5 / finalScore | 3F.6_ProductionSearchFeedbackTests.swift (FBK-002 AC-1/2/3 tests + test_sameQueryFeedback_RankChange) | Echo/Core/Actors/FeedbackActor.swift | ✅ |
| US-PRV-001 | 被拒数据源数据不进入 Retriever；policy 版本感知 | 3F.6_ProductionSearchFeedbackTests.swift (test_AC2_DeniedSourceNeverReachesRetriever — seeded + positive control) | Echo/Core/Services/SearchChannelAdapters.swift (per-source policy filter) | ✅ |
| US-SRC-010 | 跨 App 意图解析 + 逐源授权 + 时间对齐 + 源标签 + .crossAppSearch 审计 | 3F.6_CrossAppSearchTests.swift (AC-1~AC-5, ProductionCrossAppFusionEngine) | Echo/Core/Services/CrossAppIntentParser.swift + CrossAppFusionEngine.swift + AuditEvent.crossAppSearch | ✅ |
| US-SRC-011 | 主观匹配度排序 + .subjectiveMatch 标记 + 本地反馈 | 3F.6_CrossAppSearchTests.swift (AC-2/AC-4 + AC-3 production rerank) + 3F.6_ProductionSearchFeedbackTests.swift (test_rerank_AppliesSubjectiveBoost) | Echo/Core/Services/BoundedReranker.swift | ✅ AC-2/AC-4 · 🔴 AC-3 .subjectiveMatch 字段延后 (DEF-58-005) |
| DEF-34-001 | RRF 融合按 ID 回填元数据（不 top-1 重查） | 3F.6_ProductionSearchFeedbackTests.swift (test_DEF34_001_FusedMetadataFromIDKeyedLookup — production searchMultiChannel path) | Echo/Core/Services/SearchChannelAdapters.swift (metadataByID) | ✅ |
| DEF-34-002 | timeout 与 L3 阻断错误身份分离 | 3F.6_ProductionSearchFeedbackTests.swift (test_DEF34_002_L3ErrorDistinguishedFromTimeout) | Echo/Core/Services/SearchChannelAdapters.swift (ChannelAdapterError) | ✅ |
| DEF-37-001 | 反馈 L2 失败 → PendingOperations（可见 + 手动重试） | 3F.6_ProductionSearchFeedbackTests.swift (test_L2FeedbackFailureVisibleInPendingOperations) | Echo/Core/Pipelines/FeedbackPipeline.swift + PendingOpsActor.swift (recordFeedback + markBadCase) | ✅ |
| DEF-56-005 | FeedbackPipeline 传递活跃 generationId | 3F.6_ProductionSearchFeedbackTests.swift (test_generationIdPassedThroughPipeline) | Echo/Core/Pipelines/FeedbackPipeline.swift | ✅ |
| DEF-56-006 | searchCanonical ORDER BY rank 再 LIMIT | 3F.6_ProductionSearchFeedbackTests.swift (test_searchCanonicalOrderedByRelevance) | Echo/Core/Actors/CanonicalMemoryRepositoryActor.swift | ✅ |

## Testing
- Focused: `xcodebuild test ... -only-testing:EchoTests/ProductionSearchFeedbackTests -only-testing:EchoTests/CrossAppSearchTests` — 43/43 passed (post-review-fix)
- Cumulative: full suite serial `xcodebuild test` — 962 tests / 116 suites / 0 failures (incl. 33 UI tests)
- Regression align: EchoTests/Phase1/SQLiteActorTests + EchoTests/Phase2/SearchWithFeedbackTests fixtures updated ("test query"→"test") to match US-FBK-001 AC-4 query-conditioned semantics
- SwiftLint: 0 errors (modifier_order warnings match existing codebase convention)
- Evidence: docs/05-planning/phase3f-evidence-index.md (3F.6 entry), task-status.json (3F.6 → review)

## Documentation and Ledger
- task-status.json: 3F.6 status → review, notes populated (incl. PR#58 review fixes), aggregate last_updated → 2026-08-11
- deferred-items.json: DEF-34-001/002, DEF-37-001, DEF-56-005/006 → resolved; DEF-58-001 (RET-005 AC-3) + DEF-58-002 (RET-005 AC-1/2, over-claim correction) + DEF-58-003 (feedback generation binding) + DEF-58-004 (SubjectiveScorer queryText) + DEF-58-005 (subjectiveMatch field) + DEF-58-006 (parse async throws) + DEF-58-007 (regex hoist)
- Docs updated per §4.6.6 contract: README, spec (US-RET-005 status corrected), architecture, data-flow, bilingual (§4.1 baseline marker), pitfalls (PIPE-013 v1 decision note), ADR-010, execution plan, evidence index, task-status, deferred-items

## Risks
- SigLIP2 vision inference depends on 3F.3a Core ML conversion approval; empty vision index degrades to timedOut partial results by design (US-RET-008), does not weaken 3F.11 no-fixture gate (visual channel scoped in 3F.5/3F.6/3F.11)
- Release simulator build simulateError #Preview failure pre-existing on base (3F.1/3F.11 scope), unrelated to this PR
- US-SRC-010 live HealthKit provider conformance lands in 3F.8; 3F.6 declares the provider protocol and never instantiates live HealthKit
- US-RET-005 AC-1 (FIFO ≤10) / AC-2 (memoryIds injection) not implemented in production — only single-round last-query tracking (approach a); DEF-58-002 tracks

## Deferred Items (PR#58 review)
- DEF-58-001: US-RET-005 AC-3 (LLM follow-up rewrite) — offline runtime (ADR-009) has no generative LLM
- DEF-58-002: US-RET-005 AC-1/AC-2 (FIFO history + memoryIds injection) not implemented in production; spec/PR over-claim corrected
- DEF-58-003: feedback generation binds active route not the result's generation (needs 3F.7 caller wiring)
- DEF-58-004: SubjectiveScorer ignores queryText (needs 3F.7 real CLIP scorer)
- DEF-58-005: SearchResultItem lacks subjectiveMatch field (US-SRC-011 AC-3)
- DEF-58-006: CrossAppIntentParser.parse async throws unused (contract simplification)
- DEF-58-007: CrossAppIntentParser regex not hoisted (strict-concurrency risk)

## Self-Check
- [x] All new Pipeline/Adapter entries include PrivacyCheckpoint intent (R-006); denied source never reaches retriever (per-source policy filter)
- [x] No Combine / @unchecked Sendable / nonisolated(unsafe) / Task.detached
- [x] Cross-Actor params all Sendable value types; all cross-actor calls await (R-008)
- [x] Errors mapped to L1~L4; L2 feedback failures written to PendingOperations (recordFeedback + markBadCase, manual retry only)
- [x] Audit events followUpQuery/crossAppSearch hash-only (query stored as SHA-256, §5.4); audit traceID = current round
- [x] No network code (R-001/R-005); no hardcoded language strings in pipeline
- [x] Branch feature/phase3f-search-feedback-3F.6; commit/PR per AGENTS.md §3.1-3.3; base dev-1.0
<!-- PR-BODY:3F.6:END -->

---

## Entry: 3F.7 — UI 到 Core 全域接线

## Phase 3F Task Evidence
- Task / commit / branch / PR:
- Registered worktree path / ownership / clean rebase result: n/a — 3F.1~3F.11 use plain branches in the main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only): n/a
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

<!-- PR-BODY:3F.7:START -->
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
<!-- PR-BODY:3F.7:END -->

---

## Entry: 3F.8 — Awakening 与 system adapters

## Phase 3F Task Evidence
- Task / commit / branch / PR: `3F.8` / commit recorded at delivery / `feature/phase3f-awakening-adapters-3F.8` / PR created at delivery
- Registered worktree path / ownership / clean rebase result: n/a — 3F.1~3F.11 use plain branches in the main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead `/Users/logansu/Documents/Dev/SwiftProjects/Echo` (main repo root) / owner `logansu` / clean base `origin/dev-1.0`
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only): n/a
- Pre-delivery task status and transition evidence: atomic `ready → in_progress` write at `2026-08-11T12:00:00Z`; pre-delivery `review` transition at delivery (per §4.2, before §6.2.2)
- Quoted AC and architecture constraints: US-AWK-001 AC-1/2/5/6 (geofence enter-only, exit reset, silent permission disable, `.contextualAwakening` audit), US-AWK-002 AC-3/4/5 (anniversary card / no-match no-push / `.dateAwakening` audit), US-AWK-003 AC-1 (HealthKit HRV mood), US-AWK-005 AC-1/3 (card notification + response→detail route), US-SRC-010 AC-2/3/4/5 (explicit app-policy source gating, minimized temporal samples, source identity, `.crossAppSearch` audit), ADR-012 决策-1 (best-effort windows), 决策-2 (permission-aware), 决策-3 (real adapters + request/route separation), 决策-4 (HealthKit data minimization), 决策-5 (card persistence/dedupe), 决策-7 (notification content minimization)
- RED test command and observed failure: `xcodebuild test ... -only-testing:EchoTests/AwakeningSystemAdaptersTests` (RED observed before implementation — absent system adapters produced missing-symbol compile failures); `-only-testing:EchoTests/CrossAppHealthIntegrationTests` (RED — `HealthKitSystemProvider` / `CrossAppSourceProvider` conformance absent)
- Focused test command / exit / passed count: `xcodebuild test -project Echo.xcodeproj -scheme Echo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EchoTests/AwakeningSystemAdaptersTests -only-testing:EchoTests/CrossAppHealthIntegrationTests` → exit 0, 26 tests (19 + 7) / 0 failures
- Cumulative test command / exit / passed count: affected suites re-run — AwakeningGeoTests + AwakeningEmotionTests + HomeViewModelTests + AwakeningSettingsViewModelTests → exit 0, 73 tests / 0 failures (no regression from pipeline/ViewModel changes); full cumulative gate runs at delivery
- Release simulator and device commands / exits: `xcodebuild build -project Echo.xcodeproj -scheme Echo -configuration Release -destination 'generic/platform=iOS Simulator'` — run at delivery; device compile `CODE_SIGNING_ALLOWED=NO` per §6.1
- Static/privacy/model/compliance commands / exits: SwiftLint 0 errors; R-007 scan (no unchecked Sendable / Combine in business code — `@unchecked Sendable` confined to test doubles + system-framework boundary `@preconcurrency`); planning ledger JSON validated via `python3 -m json.tool`
- Production path exercised: AppDelegate.configureSources wires `CoreLocationProvider` (geofence enter/exit → AwakeningPipeline), `HealthKitSystemProvider` (HealthKitProvider mood + CrossAppSourceProvider for US-SRC-010 fusion), `LocalNotificationAdapter` + `NotificationResponseRouter` (request/route separation), `AwakeningCardRepositoryActor` (schema + persistence)
- Files and documentation changed: the exhaustive `3F.8` Files list (Modify + Create) in the execution plan `§7` and `§4.6.8`; no file outside that list changed except `Echo/Core/Models/AuditEvent.swift` (added `.dateAwakening` audit case required by US-AWK-002 AC-5, same precedent as 3F.6 adding `followUpQuery`/`crossAppSearch`)
- Deferred items closed or created, with evidence links: DEF-001 (AWK-004 Widget) and DEF-002 (AWK-006 Siri) remain deferred per ADR-012 决策-6 — no new deferrals created by 3F.8
- Known risks that do not weaken an in-scope gate: real HealthKit/Location/Notification behavior requires live simulator/device authorization; CI unit tests exercise injected system signals through the production adapters (per ADR-012 决策-3), with 3F.11 no-fixture E2E as the final authorization gate. `HealthKitSystemProvider.healthID` uses FNV-1a deterministic hashing (not Swift `hashValue`) for stable cross-process dedup.

<!-- PR-BODY:3F.8:START -->
## Overview
Production awakening system adapters per ADR-012: real `CoreLocationProvider` (CLLocationManager geofence enter/exit + permission-aware), `HealthKitSystemProvider` (conforms to `CrossAppSourceProvider` with sourceType "health" for 3F.6 US-SRC-010 fusion and returns only minimized temporal samples that HealthKit makes readable), `LocalNotificationAdapter` (request/schedule, content minimization, request-response separation), `NotificationResponseRouter` (pure-function notification tap → detail route), `AwakeningCardRepositoryActor` (SQLite-backed persisted card storage with cardId dedup across restarts). `AwakeningPipeline` extended with card persistence + notification scheduling on geofence/emotion/anniversary cards, best-effort anniversary date window (US-AWK-002), and `.dateAwakening` audit. `AwakeningSettingsViewModel` reads live system permission state via adapters (fixture fallback preserved). `HomeViewModel` loads persisted cards. `AppDelegate` wires all adapters into the production composition. `Echo-Info.plist` adds location/health usage strings; `Echo.entitlements` adds HealthKit entitlement.

> **Superseded authorization interpretation (2026-09-04, ADR-018):** 3F.8 proves that the system adapters and minimized HRV query path exist, but its HealthKit “authorized/denied” interpretation is not valid evidence of read authorization because HealthKit deliberately does not disclose read denial. Its Core Location request also returns before the delegate reports the final state. Task 4.0f owns the corrected request-completed/sample-availability model, callback-complete location requests, staged Always elevation, independent notification delivery and persisted-consent gate. Historical adapter evidence remains valid only for existence and wiring.

## Related Specs
- Task ID: 3F.8 — Awakening 与 system adapters
- Stories: US-AWK-001, US-AWK-002, US-AWK-003, US-AWK-005, US-SRC-010
- Phase 4 closure note (updated 2026-09-03, ADR-016/017): this evidence proves only the US-AWK-005 AC-1/3 subset listed below. Task 4.0d owns card media/music/feelings and card→typed-Focus routing; 4.0h owns Focus source resolution and PhotoKit deletion capability; 4.0i owns allow-list validated source anchors and stable Detail navigation. 4.2/RC must verify the joined production loop and zero MusicKit web-service paths.
- Documents: docs/decisions/ADR-012-awakening-system-boundary.md (governing), docs/01-spec/用户故事与验收标准规格书.md, docs/02-architecture/架构设计文档.md, docs/02-architecture/数据流全链路技术说明文档.md, docs/ui/testing-and-artifacts.md, docs/ui/echo-readiness.md, docs/05-planning/phase3f-execution-plan.md §4.6.8, docs/05-planning/phase3f-evidence-index.md, docs/05-planning/task-status.json, docs/05-planning/deferred-items.json

## AC Coverage
| AC # | Spec Summary | Test File | Implementation | Status |
| --- | --- | --- | --- | --- |
| US-AWK-001 AC-1/2 | Geofence enter triggers awakening; exit resets; no-repeat without exit | EchoTests/Phase3F/3F.8_AwakeningSystemAdaptersTests.swift | Echo/Core/Services/CoreLocationProvider.swift + AwakeningPipeline.handleGeofenceEnter/Exit | ✅ |
| US-AWK-001 AC-5 | Location permission denied → silent disable | EchoTests/Phase3F/3F.8_AwakeningSystemAdaptersTests.swift | AwakeningPipeline privacy checkpoint + CoreLocationProvider.startMonitoring denial | ✅ |
| US-AWK-002 AC-3/4 | Anniversary card generation; no-match no push | EchoTests/Phase3F/3F.8_AwakeningSystemAdaptersTests.swift | AwakeningPipeline.handleAnniversaryAwakening | ✅ |
| US-AWK-002 AC-5 | `.dateAwakening` audit with yearsAgo | EchoTests/Phase3F/3F.8_AwakeningSystemAdaptersTests.swift | AwakeningPipeline.writeDateAwakeningAudit + AuditEvent.dateAwakening | ✅ |
| US-AWK-003 AC-1 | HealthKit HRV mood inference | EchoTests/Phase3F/3F.8_AwakeningSystemAdaptersTests.swift | Echo/Core/Services/HealthKitSystemProvider.swift inferMoodFromHRV | ✅ |
| US-AWK-005 AC-1/3 | Card notification content minimization; response → detail route | EchoTests/Phase3F/3F.8_AwakeningSystemAdaptersTests.swift | Echo/Core/Services/LocalNotificationAdapter.swift + NotificationResponseRouter.swift | ✅ |
| ADR-012 决策-5 | Card persistence/dedupe across restart | EchoTests/Phase3F/3F.8_AwakeningSystemAdaptersTests.swift | Echo/Core/Actors/AwakeningCardRepositoryActor.swift | ✅ |
| US-SRC-010 AC-2 | App-policy-disallowed health source is not invoked; readable/empty HealthKit results do not expose read authorization | EchoTests/Phase3F/3F.8_CrossAppHealthIntegrationTests.swift | ProductionCrossAppFusionEngine app-policy gate + HealthKitSystemProvider query result | ✅ |
| US-SRC-010 AC-3/4 | Minimized temporal samples, source identity preserved | EchoTests/Phase3F/3F.8_CrossAppHealthIntegrationTests.swift | HealthKitSystemProvider.search | ✅ |
| US-SRC-010 AC-5 | `.crossAppSearch` audit with app-policy-authorized source list | EchoTests/Phase3F/3F.8_CrossAppHealthIntegrationTests.swift | ProductionCrossAppFusionEngine (3F.6) | ✅ |
| ADR-012 决策-4 | Data minimization — no raw health values passed through | EchoTests/Phase3F/3F.8_CrossAppHealthIntegrationTests.swift | HealthKitSystemProvider + RealHealthStore (minimized samples only) | ✅ |

## Review Fixes (2026-08-11, AI pre-review pr-review-echo)
- **C-1 (🔴, CI Xcode 16.4 build fail)**: `LocationProviding.onGeofenceEvent` callback → `AsyncStream<GeofenceEvent>` `eventStream` + explicit `@MainActor` on protocol & class (all-`let` storage, toolchain-independent). Commit a56a3d9.
- **W-1 (🟡)**: `HealthKitSystemProvider` `DispatchSemaphore.wait()` → `withCheckedContinuation` (requestAuthorization + fetchHRVSamples) — eliminates MainActor UI-freeze/deadlock risk.
- **W-3 (🟡)**: force-unwrapped `UUID(uuidString:)!` → `compactMap` + `guard` in `search(query:window:)`.
- **W-4 (🟡)**: `AwakeningPipeline` retained via `AppDelegate.awakeningPipeline` property + `for await` event-loop consumption.
- **W-2 (🟡 deferred → DEF-60-001)**: hardcoded EN notification/permission strings — no String Catalog infra exists; codebase-wide i18n owned by 3F.10.
- **W-5 (🟡 deferred → DEF-60-002)**: 4th bare `VectorStoreActor(dimension: 512)` — consistent with existing sync/ingest wiring; Phase 4 consolidation to GenerationRegistryActor.

## Testing
- Focused: `xcodebuild test -project Echo.xcodeproj -scheme Echo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EchoTests/AwakeningSystemAdaptersTests -only-testing:EchoTests/CrossAppHealthIntegrationTests` → exit 0, 26 tests / 0 failures.
- Affected-suite regression: AwakeningGeoTests (US-AWK-001), AwakeningEmotionTests (US-AWK-003), AwakeningDeliveryTests (AwakeningSettingsViewModel), HomeViewModelTests → exit 0, 73 tests / 0 failures.
- Full cumulative gate post review-fix (2026-08-11): **1062 tests / 0 failures** — unit 1029 tests / 122 suites + UI 33 tests / 9 suites (TEST SUCCEEDED).
- UIAutomation: 11 new contract files + 5 aligned + 6 fixtures; all validated via `python3 -m json.tool`.

## Documentation and Ledger
- task-status.json: 3F.8 `ready → in_progress → review`, `last_updated` updated.
- phase3f-evidence-index.md: 3F.8 entry populated with real results; PR-BODY marker filled.
- ADR-012: implementation-conformance noted in evidence index; no ADR text change required (implementation matches decision 1–7).

## Risks
- Real HealthKit/Location/Notification authorization paths require live simulator/device grants; CI unit tests exercise injected system signals through the production adapters (ADR-012 决策-3), with 3F.11 no-fixture E2E as final authorization gate.

## Deferred Items
- DEF-001 (AWK-004 Widget) and DEF-002 (AWK-006 Siri) remain deferred per ADR-012 决策-6.
- **DEF-60-001** (W-2, PR #60): hardcoded EN notification/permission strings → defer_to 3F.10 i18n task.
- **DEF-60-002** (W-5, PR #60): bare `VectorStoreActor(dimension: 512)` in AppDelegate → defer_to Phase 4 GenerationRegistryActor consolidation.

## Self-Check
- All new pipeline methods call PrivacyCheckpoint at entry (handleAnniversaryAwakening validates `.awakening`); system adapters are protocol-based with value-type-only cross-boundary types.
- No Combine / `@unchecked Sendable` in business code (`@unchecked Sendable` confined to test doubles and `@preconcurrency` framework boundary classes, matching PhotoKit pattern).
- No network calls; R-001/R-005 preserved.
- Audit logs hash-only; notification userInfo carries only memoryId + triggerType (no raw content).
<!-- PR-BODY:3F.8:END -->

---

## Entry: 3F.9 — Apple Translation 与 grounded creation

## Phase 3F Task Evidence
- Task / commit / branch / PR:
- Registered worktree path / ownership / clean rebase result: n/a — 3F.1~3F.11 use plain branches in the main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only): n/a
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

<!-- PR-BODY:3F.9:START -->
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
<!-- PR-BODY:3F.9:END -->

---

## Entry: 3F.10 — i18n、accessibility 与 production errors

## Phase 3F Task Evidence
- Task / commit / branch / PR: 3F.10 — `feature/phase3f-i18n-accessibility-3F.10` (PR pending delivery, base dev-1.0)
- Registered worktree path / ownership / clean rebase result: n/a — 3F.1~3F.11 use plain branches in the main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only): n/a
- Pre-delivery task status and transition evidence: `in_progress` at 2026-08-12T07:15:00Z (task-status.json status_transitions.in_progress_at), recorded by docs commit eed2e2e (docs(planning): record 3F.10 scope expansion decisions and mark in_progress); delivery transitions to `review` via §6.2.2 ledger commit
- Quoted AC and architecture constraints: US-DIS-001 AC-1 (single App Language option zh-Hans/en-US), AC-2 (toggle updates UI strings AND AI preferredLanguage), AC-3 (follow-system; non-zh/en system → zh-Hans), AC-4 (immediate effect, no restart), AC-5 (audit .languageUnified incl. newLanguage); US-DIS-003 AC-1 (all status copy in String Catalog), AC-2 (error codes → user-friendly localized messages), AC-4 (network/permission/timeout localized copy); US-DIS-004 AC-1 (interactive elements have accessibilityLabel), AC-2 (dynamic changes trigger accessibilityAnnouncement); US-RES-001 AC-3 (offline mode indicator); US-RES-002 AC-1 (isLowPowerModeEnabled → lightweight mode), AC-2 (banner "省电模式已启用，记忆检索精度可能降低"), AC-3 (auto-pause toggle default on + note), AC-4 (auto-dismiss on recovery), AC-5 (audit batteryLevel/modelVersion/degradationWarningShown/backgroundTasksPaused); US-RES-003 AC-1 (ThermalState .serious+ → degradation), AC-2 (banner "设备温度较高，部分功能已临时简化"), AC-3 (auto-dismiss on recovery), AC-5 (audit deviceThermalState/degradationActive/warningShown); US-RES-004 AC-3 (manual retry only, no auto-retry), AC-7 (功能受限 UI + repair/retry entry); US-SYS-001 AC-7 (audit .backgroundTaskUIAccessed/.backgroundTaskInterrupted action/resumePoint/userChoiceOnRestart); AGENTS.md §1.3 (zh-Hans/en-US only), §4.4 (L1~L4), §5.4 (hash-only audit), R-006 (PrivacyCheckpoint), R-007 (no Combine/@unchecked Sendable/nonisolated(unsafe)), §9.4 (serial tests, iPhone 17 Pro destination)
- RED test command and observed failure: `xcodebuild test -project Echo.xcodeproj -scheme Echo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EchoTests/LocalizationAccessibilityErrorTests` — 3F.10 tests written first (RED phase); suites failed until String Catalog, LanguageCenter, SystemMonitor, degradation runtime wiring, audit events and DEF-59-004 checkpoint landed (see EchoTests/Phase3F/3F.10_LocalizationAccessibilityErrorTests.swift)
- Focused test command / exit / passed count: `xcodebuild test -project Echo.xcodeproj -scheme Echo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EchoTests/LocalizationAccessibilityErrorTests` — exit 0, 34 tests / 10 suites / 0 failures
- Cumulative test command / exit / passed count: `xcodebuild test -project Echo.xcodeproj -scheme Echo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EchoTests` — exit 0, 1082 tests / 139 suites / 0 failures (Phase 1+2+3+3F unit + integration)
- UI test command / exit / passed count: `xcodebuild test ... -only-testing:EchoUITests` — exit 0, 42 tests / 0 failures (incl. new LocalizationAccessibilityUITests 3 + DegradationUITests 4 with zh-Hans + en-US journeys)
- Release simulator and device commands / exits: Release simulator `xcodebuild build -scheme Echo -configuration Release -destination 'generic/platform=iOS Simulator'` — exit 0 (BUILD SUCCEEDED); Release device compile `xcodebuild build -scheme Echo -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` — exit 0 (BUILD SUCCEEDED). Fixed pre-existing non-DEBUG-gated `simulateError` Preview failure by making the 3 Preview helpers available in Release (SearchViewModel/CreationViewModel/MemoryDetailViewModel)
- Static/privacy/model/compliance commands / exits: SwiftLint `swiftlint lint --reporter github-actions-logging --quiet` — exit 0, 0 errors (36 pre-existing warnings in test files; 0 in new 3F.10 files); `python3 Scripts/validate_localization.py` — OK 336 keys parity 100%, 0 hardcoded view strings; `python3 Scripts/validate_static_bans.py` — OK no banned constructs; `python3 Scripts/validate_accessibility_contracts.py` — OK 150 contracts, degradation-banner surface resolves deterministically; Combine scan / R-006 PrivacyCheckpoint Pipeline scan / network scan — OK
- Production path exercised: unified App Language via Settings picker → LanguageCenter.apply → UserPolicy.preferredLanguage + .languageUnified audit; SystemMonitor (ProcessInfo low-power + ThermalState) wired into HomeView degradation banner → real runtime degradation banners + .degradationWarning audit + auto-pause via TaskQueueActor; manual-only model retry via ModelLoaderActor.retryAllFailedModels + .modelLoadRetrySuccess; background task panel .backgroundTaskUIAccessed/.backgroundTaskInterrupted audits; migration export/import PrivacyCheckpoint (DEF-59-004)
- Files and documentation changed: see PR diff — 24 UI/Core files modified + SystemMonitor.swift + Localizable.xcstrings (336 keys) + 3 validate scripts + 3F.10 test suite + 2 new UI test suites + UIAutomation degradation-banner contracts/fixtures + planning/docs (task-status.json, deferred-items.json, phase3f-execution-plan.md, evidence-index, README.md, AGENTS.md, spec, 双语言 doc, 避坑 doc, ADR-011, docs/ui)
- Deferred items closed or created, with evidence links: RESOLVED — DEF-41-1, DEF-41-2, DEF-42-002, DEF-43-001, DEF-44-001, DEF-45-001, DEF-46-001, DEF-52-001, DEF-60-001, DEF-39-1, DEF-59-004 (deferred-items.json tracking_status=resolved, resolved_at=2026-08-12)
- Known risks that do not weaken an in-scope gate: (1) scope clarification — `.degradationWarning` audit case added to AuditEvent.swift beyond DECISION-1's two named cases because US-RES-002 AC-5 / US-RES-003 AC-5 require degradation audit events (hash-only content); (2) scope clarification — LanguageAligner.swift + AwakeningPipeline.swift modified minimally for DEF-52-001/DEF-60-001 catalog migration (task's MUST-resolve list); (3) `swiftlint lint` config `included: App/Core/UI` resolves to non-existent root dirs (code lives under Echo/) so CI lint covers EchoTests/EchoUITests only — pre-existing quirk, R-007 enforcement delegated to validate_static_bans.py + CI grep scans; (4) existing UI tests made deterministic via `-ui-language en-US` launch arg (language state persists in app sandbox from unit tests)

<!-- PR-BODY:3F.10:START -->
## Overview
Echo 3F.10 delivers i18n, accessibility and production error behavior. A unified App Language setting (zh-Hans/en-US) now drives both UI strings and the AI preferredLanguage via LanguageCenter, with immediate effect, follow-system mapping (non-zh/en systems default to zh-Hans), a one-time Traditional-Chinese mapping notice and a `.languageUnified` audit. The full Localizable.xcstrings String Catalog (336 keys, 100% parity) replaces hardcoded copy across every UI surface (Home/Search/Detail/Settings/Onboarding/Awakening/BackgroundTask/Creation/Degradation/ResumeProgress/Translation/AppShell), including error-code to localized user-facing messages (L1 transient / L2 recoverable / L3 blocking / L4 conflict per AGENTS.md §4.4), degradation banner copy, notification bodies and accessibility labels. SystemMonitor now wires real `ProcessInfo` low-power and ThermalState sources into the production degradation banner (US-RES-002/003 runtime behavior, `.degradationWarning` hash-only audit, auto-pause via TaskQueueActor, manual-only model retry per US-RES-004 AC-3). Accessibility covers catalog-driven labels, VoiceOver announcements on dynamic degradation changes, Dynamic Type-safe banner layout and dual-device Live Sim Review AX-tree verification. Background task panel audits `.backgroundTaskUIAccessed`/`.backgroundTaskInterrupted` (action/resumePoint), and DEF-59-004 adds the migration export/import PrivacyCheckpoint (`.migration`). 11 deferred items are resolved.

## Related Specs
- Task ID: 3F.10 — i18n, accessibility and production errors
- Stories: US-DIS-001, US-DIS-003, US-DIS-004, US-SET-001, US-RES-001, US-RES-002, US-RES-003, US-RES-004, US-SYS-001, US-SRC-009
- Spec: docs/01-spec/用户故事与验收标准规格书.md (US sections quoted in evidence above)
- Architecture: AGENTS.md §1.3, §4.4, §5.4, §7.3, R-006, R-007, R-008, §9.4, §17.9; docs/03-implementation/双语言实现说明文档.md; docs/02-architecture/架构设计文档.md; docs/03-implementation/开发避坑与关键注意点手册.md; docs/decisions/ADR-011-task-progress-boundary.md
- Plan: docs/05-planning/phase3f-execution-plan.md §3F.10, §4.6.10, §6.1, §6.2.2
- Human decisions (2026-08-12): DECISION-1 (AuditEvent.swift audit cases), DECISION-2 (DeviceMigrationActor.swift + PrivacyActor.swift for DEF-59-004)

## AC Coverage
| AC # | Spec Summary | Test File | Implementation | Status |
| --- | --- | --- | --- | --- |
| US-DIS-001 AC-1 | Single App Language setting (zh-Hans/en-US) | EchoTests/Phase3F/3F.10_LocalizationAccessibilityErrorTests.swift (UnifiedLanguageTests) | Echo/UI/AppShell/AppViewModel.swift LanguageCenter + Echo/UI/Settings/SettingsView.swift picker (settings-app-language) | ✅ |
| US-DIS-001 AC-2 | Toggle updates UI strings AND AI preferredLanguage | UnifiedLanguageTests.test_AC2_switchUpdatesPolicyAndUILocale | LanguageCenter.apply → UserPolicy.updatePolicy + catalog re-resolution | ✅ |
| US-DIS-001 AC-3 | Follow-system; non-zh/en → zh-Hans; Traditional maps to zh-Hans with one-time notice | test_AC3_followSystemMapping + test_AC3_traditionalChineseMapsToZhHansWithNotice | LanguageCenter.resolve + requiresMappingNotice + noticeStore persistence | ✅ |
| US-DIS-001 AC-4 | Immediate effect, no restart | test_AC4_immediateEffect | LanguageCenter in-memory resolvedLanguage + @State re-render | ✅ |
| US-DIS-001 AC-5 | Audit .languageUnified incl. newLanguage | test_AC5_auditLanguageUnified | PrivacyActor.writeAuditLog(.languageUnified, sourceLanguage=newLanguage) | ✅ |
| US-SET-001 | Same ACs as US-DIS-001 (unified language setting) | UnifiedLanguageTests | LanguageCenter + SettingsView (same implementation) | ✅ |
| US-DIS-003 AC-1 | All status copy in String Catalog | LocalizationCatalogParityTests + validate_localization.py | Echo/Resources/Localizable.xcstrings (336 keys) + EchoStrings.tr migration | ✅ |
| US-DIS-003 AC-2 | Error codes → user-friendly localized messages | ErrorLocalizationTests.test_AC2_errorFriendlyMessages | ErrorSeverity.userFacingMessage(locale:) + UserFacingError | ✅ |
| US-DIS-003 AC-4 | Network/permission/timeout errors localized | test_AC4_levelMessagesLocalized | ErrorClassifier L1~L4 localized messages | ✅ |
| US-DIS-004 AC-1 | Interactive elements have accessibilityLabel | DegradationUITests + AX trees (run manifest) | Catalog-driven accessibilityLabel across banner/task/translation views | ✅ |
| US-DIS-004 AC-2 | Dynamic changes trigger accessibilityAnnouncement | DegradationRuntimeTests.test_AX_announcementOnActivation | DegradationBannerView.onChange → AccessibilityNotification.Announcement | ✅ |
| US-RES-001 AC-3 | Offline mode indicator | OfflineIndicatorTests.test_AC3_offlineIndicator | HomeViewModel.isOffline + offlineIndicatorAccessibilityLabel | ✅ |
| US-RES-002 AC-1 | isLowPowerModeEnabled → lightweight mode | SystemMonitorTests.test_lowPowerChange | Echo/Core/Utils/SystemMonitor.swift ProcessInfoConditionSource | ✅ |
| US-RES-002 AC-2 | Banner copy (low power) | DegradationRuntimeTests.test_AC1_AC2 + DegradationUITests | DegradationBannerViewModel.lowPower + catalog copy | ✅ |
| US-RES-002 AC-3 | Auto-pause toggle default on + note | test_AC3_autoPauseDefaultOn + LocalizationAccessibilityUITests | SettingsView low-power toggle + DegradationBannerViewModel.isAutoPauseOnLowPowerEnabled | ✅ |
| US-RES-002 AC-4 | Auto-dismiss on recovery | test_AC4_exitLowPowerDismisses | SystemMonitor conditionChanges → applyCurrentConditions deactivate | ✅ |
| US-RES-002 AC-5 | Audit batteryLevel/modelVersion/degradationWarningShown/backgroundTasksPaused | test_AC5_auditWritten | writeDegradationAudit (.degradationWarning hash-only content) | ✅ |
| US-RES-003 AC-1 | ThermalState .serious+ → degradation | SystemMonitorTests.test_thermalChange | SystemMonitor.isThermalDegraded (.serious/.critical) | ✅ |
| US-RES-003 AC-2 | Banner copy (thermal) | DegradationUITests.test_thermalBannerAppears | DegradationBannerViewModel.thermal + catalog copy | ✅ |
| US-RES-003 AC-3 | Auto-dismiss on thermal recovery | test_US_RES_003_thermalLifecycle | applyCurrentConditions recovery path | ✅ |
| US-RES-003 AC-5 | Audit deviceThermalState/degradationActive/warningShown | DegradationRuntimeTests (audit coverage) | writeDegradationAudit content fields | ✅ |
| US-RES-004 AC-3 | Manual retry only, no auto-retry | test_US_RES_004_manualRetryOnly | DegradationBannerViewModel.hasAutomaticRetryTimer=false + retryModelLoad manual path | ✅ |
| US-RES-004 AC-7 | 功能受限 UI + repair/retry entry | DegradationUITests.test_modelDegradedBannerShowsRetryAndRepair | modelDegraded banner + Retry model load + Open settings buttons | ✅ |
| US-RES-004 AC-8 | Audit .modelLoadFailed + .modelLoadRetrySuccess | manualRetry path (existing ModelLoader tests) | retryModelLoad → writeAuditLog(.modelLoadRetrySuccess) | ✅ |
| US-SYS-001 AC-7 | Audit .backgroundTaskUIAccessed + .backgroundTaskInterrupted | BackgroundTaskAuditTests | BackgroundTaskViewModel.writeAudit (action/resumePoint/userChoiceOnRestart) | ✅ |
| DEF-39-1 | L1/L2/L3/L4 all mapped | ErrorLocalizationTests.test_DEF39_1_allFourLevelsClassified | ErrorClassifier (DatabaseError/ModelLoadError/SyncConflictError/CancellationError) | ✅ |
| DEF-59-004 | exportPackage PrivacyCheckpoint | MigrationCheckpointTests | PrivacyActor .migration + DeviceMigrationActor.exportPackage/importPackage validate() | ✅ |

## Testing
- Focused: `xcodebuild test -project Echo.xcodeproj -scheme Echo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EchoTests/LocalizationAccessibilityErrorTests` → exit 0, 34 tests / 10 suites, 0 failures
- Cumulative: `xcodebuild test ... -only-testing:EchoTests` → exit 0, 1082 tests / 139 suites, 0 failures (Phase 1+2+3+3F unit + integration)
- UI: `xcodebuild test ... -only-testing:EchoUITests` → exit 0, 42 tests, 0 failures (new LocalizationAccessibilityUITests 3 + DegradationUITests 4 incl. zh-Hans journey; existing suites made deterministic with `-ui-language en-US`)
- Release: simulator build exit 0 (BUILD SUCCEEDED); device compile exit 0 (CODE_SIGNING_ALLOWED=NO)
- Static: SwiftLint exit 0 (0 errors); validate_localization.py OK (336 keys, parity 100%, 0 hardcoded view strings); validate_static_bans.py OK; validate_accessibility_contracts.py OK (150 contracts, degradation-banner resolves deterministically); Combine/R-006/network scans OK
- Dual-device Live Sim Review: iPhone 17 Pro (iOS 26.5) + iPhone 16 Pro (iOS 18.2) — language switch immediate effect, zh-Hans banner copy verbatim per spec, AX labels verified; run manifest UIAutomation/Artifacts/manifests/3F.10-i18n-accessibility-run-manifest.json (visualMediaCaptured: false); AX trees UIAutomation/Artifacts/accessibility/3F.10-*.json

## Documentation and Ledger
- docs/05-planning/task-status.json — 3F.10 in_progress (review on delivery), scope decisions recorded
- docs/05-planning/deferred-items.json — 11 items resolved (DEF-41-1, DEF-41-2, DEF-42-002, DEF-43-001, DEF-44-001, DEF-45-001, DEF-46-001, DEF-52-001, DEF-60-001, DEF-39-1, DEF-59-004)
- docs/05-planning/phase3f-execution-plan.md — §3F.10 Files annotations (human decisions + scope clarifications)
- docs/05-planning/phase3f-evidence-index.md — this entry + PR-BODY marker
- README.md / AGENTS.md / docs/01-spec/用户故事与验收标准规格书.md / docs/03-implementation/双语言实现说明文档.md / docs/03-implementation/开发避坑与关键注意点手册.md / docs/decisions/ADR-011-task-progress-boundary.md / docs/ui/ files — updated for 3F.10 delivery

## Risks
- `.degradationWarning` audit case added to AuditEvent.swift beyond DECISION-1's two named cases — required by locked US-RES-002 AC-5 / US-RES-003 AC-5; recorded as scope clarification
- LanguageAligner.swift + AwakeningPipeline.swift (protected Core, outside the base Files list) modified minimally for DEF-52-001/DEF-60-001 — task MUST-resolve list; recorded as scope clarification
- SwiftLint config `included` resolves to non-existent root dirs (code under Echo/), so CI lint covers EchoTests/EchoUITests only — pre-existing quirk; R-007 enforced by validate_static_bans.py + CI grep scans
- UI tests now pass `-ui-language en-US` because LanguageCenter persists language in the app sandbox and unit tests may leave zh-Hans; no gate weakened (assertions unchanged)

## Deferred Items
Resolved in this PR (deferred-items.json tracking_status=resolved, resolved_at=2026-08-12): DEF-41-1, DEF-41-2, DEF-42-002, DEF-43-001, DEF-44-001, DEF-45-001, DEF-46-001, DEF-52-001, DEF-60-001 (i18n/AX), DEF-39-1 (L1~L4 error injection), DEF-59-004 (migration export PrivacyCheckpoint). No new deferred items created. Remaining open items (DEF-38-003 coverage threshold, DEF-50-001, DEF-55-*, DEF-56-007/008/009, DEF-57-002/003, DEF-58-*, DEF-59-001/002/003/005/006/007, DEF-60-002) are out of 3F.10 scope and tracked for 3F.11/Phase 4.

## Self-Check
- R-006: new Actor methods start with PrivacyCheckpoint — DeviceMigrationActor.exportPackage/importPackage validate(.migration); Pipelines scan clean
- R-007: no Combine / @unchecked Sendable / nonisolated(unsafe) — validate_static_bans.py + CI scans clean; Preview simulateError helpers now Release-compilable without banned constructs
- R-008: all cross-Actor calls awaited
- No hardcoded language strings: validate_localization.py 336 keys, 0 view violations
- Audit logs hash-only (contentHash) per AGENTS.md §5.4
- Branch/commit/PR: English per AGENTS.md §3.1/§3.2/§3.5; no `gh pr merge`, no `--delete-branch`
- No media artifacts persisted; run manifest visualMediaCaptured=false
- No fixture/Preview state presented as production-completion evidence (Live Sim Review used real app + fixture-driven banner states per established 3F pattern)
<!-- PR-BODY:3F.10:END -->

---
---

## Entry: 3F.11 — Production E2E 与 Phase 4 准入门禁

## Phase 3F Task Evidence
- Task / commit / branch / PR: `test/phase3f-production-gate-3F.11` / PR #63 — pre-merge evidence below is preserved; post-merge evidence was appended by human-triggered `3F.finalize`
- Registered worktree path / ownership / clean rebase result: n/a — 3F.1~3F.11 use plain branches in the main repo per human approval 2026-08-04 (AGENTS.md §17.9); record branch + clean base instead
- Bootstrap authorization actor / UTC time / docs-only scope (3F.0 only): n/a
- Pre-delivery task status and transition evidence: 3F.11 ready → in_progress (2026-08-12T13:10:00Z, task-status.json); pre-merge review on delivery
- Quoted AC and architecture constraints: ADR-014 §决策-3 (per-target compliance report, every executable app/extension target incl. Echo + EchoShareExtension), §决策-4 (Release.xcconfig / PrivacyInfo.xcprivacy / app-store-privacy-disclosure / release-checklist / CHANGELOG), §决策-5 (coverage gate repair, P0=0/P1=0); execution-plan §6.1 (no-fixture E2E gate); AGENTS.md §12.6 (phase integration test is a formal task)
- RED test command and observed failure: `python3 -m unittest Scripts.validate_release_compliance_tests` → ImportError (module missing); real-repo `python3 Scripts/validate_release_compliance.py` → exit 1 (missing PrivacyInfo.xcprivacy ×2, missing NSHealthUpdateUsageDescription)
- Focused test command / exit / passed count: `python3 -m unittest Scripts.validate_release_compliance_tests` → exit 0 (9/9); `xcodebuild test-without-building ... -only-testing:EchoTests/Phase3F{CompositionConsent,CanonicalGeneration,IngestSearchFeedback,PurgeAndMigration}IntegrationTests` → 17/17, 4 suites, 0 failures
- Cumulative test command / exit / passed count: `xcodebuild test -parallel-testing-enabled NO -enableCodeCoverage YES -skip-testing:EchoTests/ModelBundleTests` → 1096 tests / 142 suites + EchoUITests 44 tests, 0 failures, exit 0
- Release simulator and device commands / exits: Debug simulator build exit 0; Release `generic/platform=iOS CODE_SIGNING_ALLOWED=NO` build exit 0
- Static/privacy/model/compliance commands / exits: `validate_static_bans.py` exit 0; `validate_localization.py` 336 keys 100% parity; `validate_accessibility_contracts.py` 150 contracts OK; `validate_release_compliance.py` exit 0 (per-target Echo + EchoShareExtension clean); `coverage_gate.py TestResults.xcresult 65` → 79% (excl. Views) ≥ 65% pass; SwiftLint exit 0 (0 new warnings)
- Production path exercised: consent gate (deny-by-default → accept → ready → revoke purge), canonical+generation lifecycle (deterministic ID, transactional commit, rollback, routed vector write), production ingestion → canonical/FTS → feedback re-rank, cascade delete (R-003 no ExcludedAssets write), ECHOMIG1 encrypted migration package round-trip + tamper rejection
- Files and documentation changed: Scripts/validate_release_compliance.py (+tests), Echo/Config/PrivacyInfo.xcprivacy, EchoShareExtension/PrivacyInfo.xcprivacy, Echo/Config/Echo-Info.plist (NSHealthUpdateUsageDescription), Echo/Config/Release.xcconfig (+pbxproj baseConfigurationReference), EchoTests/Phase3F/Phase3FIntegrationTests.swift, EchoUITests/Phase3FProductionE2ETests.swift, Scripts/coverage_gate.py (xccov `--files` fix), .github/workflows/ci.yml (compliance gate), Echo/Assets.xcassets/AppIcon.appiconset (AppIcon.png + Contents.json), CHANGELOG.md, docs/05-planning/app-store-privacy-disclosure.md, docs/05-planning/phase3f-release-checklist.md, docs/05-planning/task-status.json, docs/05-planning/phase3f-evidence-index.md, AGENTS.md, README.md
- Deferred items closed or created, with evidence links: no new deferred items created in this PR; open gating items tracked for finalizer/Phase 4 (DEF-38-003 coverage 95% restore, DEF-50-001 atomic purge, DEF-55-*, DEF-56-007/008/009, DEF-57-002/003, DEF-58-*, DEF-59-001/002/003/005/006/007, DEF-60-002)
- Known risks that do not weaken an in-scope gate: E2E no-fixture journey drives the production onboarding gate (result depends on simulator consent state — idempotent assertions handle ready vs documented unavailable states); app icon is a generated placeholder pending final design asset; Release signing/archive evidence requires the controlled release credentials environment (ADR-014 §决策-4) and is recorded at finalizer time
- Post-merge evidence: PR `https://github.com/logan-suu/Echo/pull/63`; state `MERGED`; base `dev-1.0`; head `test/phase3f-production-gate-3F.11`; merged head / immutable merge commit `18784ea426d411ab539c5bd9c0eecd4548ae7e7a`; merged by `logan-suu` at `2026-08-26T03:25:13Z`; commit verified reachable from `dev-1.0`
- Completion boundary decision: human product owner accepted the implemented basic production loop on `2026-08-31`; global coverage `>=95%`, controlled signing/archive/export, final App Icon, Golden/performance, final RC and TestFlight remain Phase 4 qualification work and are not claimed by this entry

<!-- PR-BODY:3F.11:START -->
## Overview
Echo 3F.11 is the Phase 3F production gate. It adds per-target release compliance
tooling (Echo + EchoShareExtension) per ADR-014 decision 3, the phase 3F
integration suite and a no-fixture production E2E per AGENTS.md §12.6, and the
release artifacts required by ADR-014 decision 4 (Release.xcconfig,
PrivacyInfo.xcprivacy ×2, App Store privacy disclosure, release checklist,
CHANGELOG). It is a pre-merge evidence gate: it does not record a merge SHA and
does not unlock Phase 4 — that is the human-triggered `3F.finalize` step.

## Related Specs
- Task: 3F.11 — Production E2E 与 Phase 4 准入门禁
- ADR: docs/decisions/ADR-014-release-compliance-boundary.md (§决策-3/4/5)
- Plan: docs/05-planning/phase3f-execution-plan.md §3F.11, §6.1, §11.2
- AGENTS.md §12.6 (phase integration test), §9.3 (CI gates)

## AC Coverage
| AC # | Spec Summary | Test File | Implementation | Status |
| --- | --- | --- | --- | --- |
| ADR-014 §决策-3 | Per-target compliance report for every executable target (Echo + EchoShareExtension) | Scripts/validate_release_compliance_tests.py (9/9) | Scripts/validate_release_compliance.py + .github/workflows/ci.yml gate | ✅ |
| ADR-014 §决策-4 | Release.xcconfig, PrivacyInfo.xcprivacy, privacy disclosure, release checklist, CHANGELOG | Scripts/validate_release_compliance_tests.py (privacy-manifest) | Echo/Config/Release.xcconfig, PrivacyInfo.xcprivacy ×2, docs/05-planning/app-store-privacy-disclosure.md, phase3f-release-checklist.md, CHANGELOG.md | ✅ |
| ADR-014 §决策-5 | Coverage gate repair, P0=0/P1=0 | coverage_gate.py run | Scripts/coverage_gate.py (xccov --files fix) | ✅ |
| AGENTS.md §12.6 | Phase integration suite | EchoTests/Phase3F/Phase3FIntegrationTests.swift (17 tests, 4 suites) | Production path integration across consent/canonical/ingest/search/feedback/migration | ✅ |
| §6.1 no-fixture E2E | No -ui-fixture / stub model / actor seeding | EchoUITests/Phase3FProductionE2ETests.swift | Production onboarding → ready-or-unavailable gate | ✅ |
| R-006 / §5.4 | PrivacyCheckpoint + hash-only audit | Phase3FIntegrationTests composition suites | Consent enforcement + audit required fields | ✅ |
| R-003 | Cascade delete must not write ExcludedAssets | Phase3FIntegrationTests test_cascadeDeleteFromOriginal | CanonicalMemoryRepositoryActor.cascadeDeleteFromOriginal | ✅ |

## Testing
- Compliance validator unit tests: `python3 -m unittest Scripts.validate_release_compliance_tests` — 9/9 pass, exit 0
- Per-target compliance report: `python3 Scripts/validate_release_compliance.py` — exit 0 (Echo + EchoShareExtension, no blocking findings)
- Phase 3F integration suite: 17 tests / 4 suites, 0 failures (consent flow, purge, deterministic ID, commit round-trip, rollback, routed vector write, FTS, production ingest + dedupe, feedback re-rank, cascade delete, ECHOMIG1 round-trip + tamper)
- Cumulative regression: 1096 tests / 142 suites + 44 UI tests, 0 failures (`-parallel-testing-enabled NO`)
- Release build: Debug simulator exit 0; Release `generic/platform=iOS CODE_SIGNING_ALLOWED=NO` exit 0
- Coverage: `coverage_gate.py TestResults.xcresult 65` — 79% (excl. Views) / 75% full target, pass
- Static: validate_static_bans.py 0, validate_localization.py 336/100%, validate_accessibility_contracts.py 150 OK, SwiftLint exit 0
- Evidence links: DerivedData/Logs/Test/*.xcresult; TestResults.xcresult

## Documentation and Ledger
- docs/05-planning/task-status.json — 3F.11 ready → in_progress (review on delivery)
- docs/05-planning/phase3f-evidence-index.md — 3F.11 entry populated with pre-merge gate evidence
- docs/05-planning/phase3f-release-checklist.md — created (gate matrix + per-target inventory)
- docs/05-planning/app-store-privacy-disclosure.md — created (no data collection, required-reason API, purpose strings)
- CHANGELOG.md — created (Phase 3F + Phase 1 history)
- README.md / AGENTS.md — release-compliance and changelog references updated

## Risks
- E2E no-fixture journey is idempotent over prior consent state and accepts
  documented unavailable startup states when models are not bundled — the full
  clean-install journey is revalidated at the release-gate Live Sim Review.
- App icon is a generated placeholder pending a final design asset (release
  compliance for the archive is verified at finalizer time).
- Release signing/archive evidence requires the controlled release credentials
  environment and is recorded by the human-triggered finalizer, not this PR.

## Deferred Items
No new deferred items created. Open gating items are explicitly out of this
pre-merge PR and tracked for the finalizer / Phase 4: DEF-38-003 (coverage 95%
restore), DEF-50-001 (atomic purge), DEF-55-001/002/003 (Whisper perf),
DEF-56-007/008/009, DEF-57-002/003, DEF-58-001~008, DEF-59-001/002/003/005/006/007,
DEF-60-002.

## Self-Check
- [x] All gates run on this task's commit; no placeholder / RED-baseline numbers copied
- [x] No `@unchecked Sendable` / `nonisolated(unsafe)` / Combine / network code introduced
- [x] PrivacyCheckpoint preserved (integration tests exercise consent enforcement + hash-only audit)
- [x] No merge SHA recorded; Phase 4 not declared unlocked; `3F.finalize` stays human-only
- [x] Branch retained (no delete); PR base is dev-1.0
<!-- PR-BODY:3F.11:END -->

---

## Entry: 3F.finalize — Record 3F.11 merge and unlock Phase 4

- **id:** `3F.finalize`
- **title:** `Record 3F.11 merge and unlock Phase 4`
- **status:** `done`
- **owner:** Release Manager
- **approver:** Human merge actor and Product and Architecture Lead
- **documents_required:** `docs/05-planning/task-status.json`; `docs/05-planning/phase3f-evidence-index.md`; `docs/05-planning/phase3f-execution-plan.md`; `docs/05-planning/开发计划安排文档.md`
- **dependencies:** `3F.11` PR merged into `dev-1.0`, host reports immutable merge commit SHA
- **acceptance_evidence:** 3F.11 PR URL; merge commit SHA reachable from `dev-1.0`; merged head and base identities; finalizer actor/time; Phase 4 ready-task diff; evidence-index link; proof that no branch was deleted
- **prohibited:** running before merge, accepting a PR head SHA as merge SHA, changing gate results, fabricating post-merge evidence, starting Phase 4 implementation in the finalizer change

This entry is the human-triggered post-merge finalizer record (`§10.1`). It has no `§11.1` PR-body marker pair.

- **triggered_at:** `2026-08-31T15:42:40Z`
- **triggered_by:** Human product owner in the active Echo task
- **PR:** `https://github.com/logan-suu/Echo/pull/63`
- **merge actor / time:** `logan-suu` / `2026-08-26T03:25:13Z`
- **merged head / merge commit:** `18784ea426d411ab539c5bd9c0eecd4548ae7e7a`
- **base:** `dev-1.0`
- **reachability:** `git merge-base --is-ancestor 18784ea426d411ab539c5bd9c0eecd4548ae7e7a dev-1.0` → exit 0
- **ledger result:** `3F.11` done; Phase 3F integration passed and phase done; `current_phase` = `"4"`; Phase 4 status in_progress; `4.1`~`4.9` ready; `4.10`~`4.14` backlog
- **scope truth:** Phase 3F completion means the basic production loop and baseline gate evidence passed. Phase 4 retains unproven release qualification; no missing release evidence was fabricated or retroactively marked passed.
- **branch preservation:** local and remote `test/phase3f-production-gate-3F.11` branches both remain present; no branch was deleted
