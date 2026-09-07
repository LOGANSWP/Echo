# Phase 3F Story Matrix (Calibrated 66-Story Completion Matrix)

**Date:** 2026-08-03 **Scope:** Echo v4.6's 66 user stories. **Decision rule:** A story is **production-complete** only when every required AC is feasible, implemented on the default app path, and has appropriate verification. A source-level or fixture-tested AC is recorded in the evidence note but does not make the story complete.

This file is the materialized `Appendix C` of the Phase 3F execution plan (`docs/05-planning/phase3f-execution-plan.md`). It is read-only for 3F.1 through 3F.11; any scope change requires a human-approved scope PR.

> **Post-3F handoff note (2026-08-31):** DEF-001 / US-AWK-004 and DEF-002 / US-AWK-006 remain unresolved product-scope decisions. They have no Phase 4 implementation task today, so `4.10` Release Candidate is blocked until approved implementation tasks exist or the stories are formally moved out of v1 with this matrix and the specification updated together.

> **Phase 4 reasonableness update (2026-09-02):** Task-surface review corrected the launch permission sequence and the persisted-task recovery contract. `4.0f` now owns consent-first contextual permission requests; `4.0g` owns production task reconstruction and truthful Continue/Restart. Baseline labels below are retained for audit history, while owner/evidence notes reflect the current handoff.

## Ownership Repair (§4.2.1)

| Story | Owner Task(s) | Disposition |
| --- | --- | --- |
| US-SRC-007 | 3F.7 | Encrypted user-mediated migration package export/import, Finder/iTunes encrypted local-backup restore, merge/conflict/integrity/reingest/ExcludedAssets behavior and live Settings integration. Not deferred. |
| US-SRC-009 | 3F.7, 3F.10 | Specification merged into US-SYS-001 with every original AC retained; 3F.7 owns live data-overview service, JSON export and Settings integration; 3F.10 owns production error, localization and accessibility behavior. Not deferred. |
| US-SRC-010 | 3F.6, 3F.8, 3F.11 | 3F.6 owns the search contract, 3F.8 owns HealthKit-backed system adaptation, 3F.11 owns no-fixture production E2E. Not deferred. |
| US-SRC-011 | 3F.3, 3F.3a, 3F.3b, 3F.6, 4.1 | 3F.3 owns E5 model semantics; 3F.3a owns SigLIP2 reference vectors; 3F.3b owns Whisper reference transcripts; 3F.6 owns subjective ranking and feedback behavior; Phase 4 4.1 owns Golden validation. Not deferred. |
| US-AWK-004 | DEF-001 | Approved product deferral (Widget / Live Activity). Counts toward the matrix only through the approved record. |
| US-AWK-006 | DEF-002 | Approved product deferral (Siri Shortcuts / App Intents). Counts toward the matrix only through the approved record. |

> Matrix gate: passes only when all 66 unique story IDs have at least one explicit owner or an approved non-v1 removal record. US-SRC-007/009/010/011 may not use the deferral path.

## Aggregate (exclusive primary status, baseline 2026-08-03)

| Status | Count |
| --- | --- |
| Production-complete | 0 |
| Partial | 21 |
| Stub | 22 |
| Absent/unmapped | 9 |
| Deferred | 2 |
| Impossible/spec-invalid | 12 |
| **Total** | **66** |

`Impossible/spec-invalid` is used where a required AC cannot be accepted without a specification decision (for example, unavailable public APIs, contradictory source rules, or impossible timing guarantees). It does **not** erase any partial implementation evidence in the notes.

## Matrix

| Story | Baseline Status (2026-08-03) | Owner Task(s) | Baseline Evidence Note |
| --- | --- | --- | --- |
| SRC-001 | Partial | 3F.1, 3F.2, 4.0f, 4.2 | PhotoKit acquisition and production source wiring exist, but launch-time permission chaining and a consent-persistence race remain. 4.0f owns persisted-consent-first gating, the explicit Connect Photos trigger, Not Now zero-call behavior and limited/full/denied/restricted paths. |
| SRC-002 | Impossible/spec-invalid | 3F.0 | Requires MessageUI to read iMessage history, which is not a public capability. |
| SRC-003 | Absent/unmapped | 3F.2, 4.2 | No Share Extension target or import implementation found. |
| SRC-004 | Stub | 3F.2, 4.2 | Settings toggles mutate fixture/UI state only; AppDelegate has no BG task registration. |
| SRC-005 | Stub | 3F.2, 4.2 | Search scan surface is fixture-driven; no scanner/import action exists. |
| SRC-006 | Impossible/spec-invalid | 3F.0 | Spec/ledger explicitly defer it: PHAsset has no People identity API. |
| SRC-007 | Stub | 3F.7 | Migration UI/fixtures exist, but no local-transfer, restore, conflict, or integrity implementation. |
| SRC-008 | Partial | 3F.2, 4.2, 4.5 | ExcludedAssets actor has isolated behavior/tests; management, paging, source checks, reimport, and default production integration are incomplete. |
| SRC-009 | Stub | 3F.7, 3F.10 | Settings displays fabricated counts/model states from SettingsFixtureLoader. |
| SRC-010 | Absent/unmapped | 3F.6, 3F.8, 3F.11 | No intent parser or multi-source retrieval path. |
| SRC-011 | Absent/unmapped | 3F.3, 3F.3a, 3F.3b, 3F.6, 4.1 | No working vision embedding or subjective-query Golden dataset. 3F.3a/3F.3b backfill reference vectors/transcripts. |
| SRC-012 | Partial | 3F.2, 3F.5, 4.2, 4.5 | SyncPipeline has callable isolated logic, but no registered observers, BG task, source acquisition, or default composition; Notes path conflicts with share-only rule. |
| SRC-013 | Stub | 3F.2, 3F.5, 4.2 | Result surface exists but no production change detector/update flow. |
| ING-001 | Impossible/spec-invalid | 3F.0, 3F.3, 3F.5, 4.2 | Requires automatic system Notes reads via non-public/nonexistent NoteStore/MKMapItem path and conflicts with SRC-001 share-only route. |
| ING-002 | Impossible/spec-invalid | 3F.0, 3F.3, 3F.5, 4.2 | Inherits ING-001's unsupported automatic Notes acquisition requirement. |
| ING-003 | Impossible/spec-invalid | 3F.0, 3F.3, 3F.3b, 3F.5, 4.2 | Automatic Voice Memos reading conflicts with the specified share-only public route. 3F.3b owns whisper.cpp real transcription. |
| ING-004 | Impossible/spec-invalid | 3F.0, 3F.3, 3F.3a, 3F.5, 4.2 | Some ingest AC code is tested with StubEmbedder, but required direct text/vision-space alignment conflicts with the mandated E5/CLIP split. 3F.3a owns SigLIP2 Core ML conversion and real vision inference. |
| ING-005 | Partial | 3F.3, 3F.3a, 3F.3b, 3F.5, 4.2 | Video pipeline code and isolated tests exist, but actual asset acquisition and Whisper/SigLIP inference are scaffolded/unreachable. 3F.3a/3F.3b provide real vision/audio inference. |
| ING-006 | Absent/unmapped | 3F.4, 3F.5, 4.2 | No canonical transactional vector/text/FTS commit, fault-injection rollback, or transaction audit path. |
| RET-001 | Partial | 3F.3, 3F.6, 4.1, 4.2, 4.3 | Search pipeline and stub-backed tests implement ranking/audit fields; default app injects no pipeline, E5 returns zeros, and no Cross-Encoder/Golden Recall gate exists. |
| RET-002 | Partial | 3F.3, 3F.6, 4.1, 4.2 | Same isolated stub-backed path as RET-001; no real bilingual embedding evidence. |
| RET-003 | Impossible/spec-invalid | 3F.0, 3F.6, 4.1, 4.2 | Text is specified as E5 while the AC requires query vectors in CLIP space. |
| RET-004 | Impossible/spec-invalid | 3F.0, 3F.6, 4.1, 4.2 | Some filtering code exists, but the AC retains person dimensions after person IDs were removed; actual filters are post-ANN/no-op. |
| RET-005 | Absent/unmapped | 3F.6, 4.1, 4.2 | No conversation context store, rewrite model, or parent-trace implementation. |
| RET-006 | Partial | 3F.3, 3F.6, 4.1, 4.2 | Low-confidence flags/banner are implemented, but no live Cross-Encoder produces the score. |
| RET-007 | Absent/unmapped | 3F.6, 4.1, 4.2 | No retrieval cache or policy-aware invalidation. |
| RET-008 | Stub | 3F.6, 4.1, 4.2 | No operational timeout/partial-result path; only UI error/fixture behavior. |
| SYN-001 | Stub | 3F.9, 4.2 | Language picker is a fixture UI transition; no persisted policy or model prompt/retry integration. |
| SYN-002 | Partial | 3F.9, 4.0i, 4.2 | 3F.9 renders anchors but assigns them by paragraph position. ADR-020 requires 4.0i to parse a versioned bounded JSON envelope, accept only model-emitted opaque source IDs from the exact currently authorized submitted-input allow-list, express multiple anchors plus cited/noSource/partialNoSource, and route anchors through current-policy revalidation. Provenance membership is not presented as automatic fact verification. |
| SYN-003 | Partial | 3F.0, 3F.9, 4.0i, 4.2 | Private Notes creation/deep-link was replaced by user-mediated system share/export. 4.0i owns current-policy revalidation for copy/export/share, citation-preserving plain text/Markdown/multipage PDF, actual share-controller presentation evidence, and dedicated typed creation/share audit fields. |
| SYN-004 | Partial | 3F.0, 3F.9, 4.0i, 4.0j, 4.2 | 4.0i owns provenance-honest report citations and authorized share handoff; 4.0j owns persistent earliest-eligible monthly/yearly scheduling, idempotency and narrativeReportGenerated audit. Fixture reports are not production evidence. |
| SYN-005 | Stub | 3F.9, 4.2 | Prompt editor UI exists; no bounded analysis pipeline or source enforcement. |
| SYN-006 | Absent/unmapped | 3F.9, 4.2 | No emotion-intervention synthesis/prompt implementation. |
| SYN-007 | Absent/unmapped | 3F.9, 4.2 | No term glossary runtime or Golden validation. |
| SYN-008 | Stub | 3F.9, 4.2 | Degradation template is display simulation, not a synthesis failure fallback. |
| AWK-001 | Partial | 3F.8, 4.0f, 4.2 | Production geofence and notification adapters exist; 4.0f owns staged When In Use → separately confirmed Always authorization, callback-complete state updates, independent notification delivery opt-in and denial-safe behavior. |
| AWK-002 | Partial | 3F.0, 3F.8, 4.0f, 4.2 | The exact 09:00 promise was corrected to an earliest-eligible best-effort window; 4.0f keeps anniversary enablement permission-free and notification delivery behind a separate explicit opt-in. |
| AWK-003 | Partial | 3F.8, 4.0f, 4.2 | Production HealthKit and awakening adapters exist but currently misread write authorization as read authorization. 4.0f owns explicit HRV-read opt-in, request-completed/data-availability state and no-readable-sample fallback. |
| AWK-004 | Deferred | DEF-001 (approved deferral) | Explicit P1 Phase-4 Widget/Live Activity deferral (DEF-001). |
| AWK-005 | Partial | 3F.7, 3F.8, 4.0d, 4.0h, 4.0i, 4.2 | 4.0d owns real card media/music/feelings and card→typed-Focus routing. ADR-019 assigns typed Focus source resolution and PhotoKit deletion capability to 4.0h; Share audio is transcript-only because the original is not persisted. 4.0i owns current-policy-revalidated source-anchor navigation without claiming semantic fact proof, and 4.2 verifies the joined loop. |
| AWK-006 | Deferred | DEF-002 (approved deferral) | Explicit P1 Phase-4 Siri/App Intents deferral (DEF-002). |
| AWK-007 | Partial | 3F.4, 3F.7, 4.0e, 4.2 | Detail editing/conflict UI mutates fixture model; ADR-017 narrows 4.0e to MemoryUserEdit, safe reindex publication, source preservation, userLocked sync behavior and persistent MemoryEditConflict resolution. |
| PRV-001 | Partial | 3F.1, 3F.2, 3F.6, 4.2, 4.5, 4.9 | PrivacyActor has isolated policy/checkpoint behavior; startup neither loads nor wires a deny-by-default production policy. |
| PRV-002 | Stub | 3F.7 | Audit rows can exist in core tests, but Settings audit viewer is not wired to live data. |
| PRV-003 | Impossible/spec-invalid | 3F.0, 3F.7 | The AC requires complete 30-day export and a <=5MB file without a limit, pagination, or split rule. |
| PRV-004 | Partial | 3F.1, 3F.4, 3F.7, 4.0h, 4.2, 4.5, 4.9 | Remove-from-Echo is connected. ADR-019 limits source deletion to visible PhotoKit photo/video that pass `canPerform(.delete)` and requires a persisted external-result gate before D-005; limited-hidden and revoked sources cannot be inferred deleted. Share Extension sources cannot be deleted by Echo. |
| PRV-005 | Impossible/spec-invalid | 3F.0, 3F.1, 4.2, 4.9 | iOS cannot guarantee cooling-period completion while the app is not running. |
| PRV-006 | Partial | 3F.1, 3F.4, 4.2, 4.9 | Persistence/retention intent exists in core schema and settings UI, but no production canonical-store lifecycle verifies the full deletion boundary. |
| PRV-007 | Impossible/spec-invalid | 3F.0, 3F.4, 4.0h, 4.2, 4.5, 4.9 | The immutable 2026-08-03 baseline reflects the former impossible five-second wall-clock promise. ADR-019 now replaces it with verifiable PhotoKit delivery/full-scope reconciliation and recoverable D-005 cleanup; current delivery is Partial. Share Extension originals remain unobservable and limited-hidden is not deletion evidence. |
| PRV-008 | Partial | 3F.1, 4.0f, 4.2, 4.9 | Consent persistence and withdrawal/purge exist; 4.0f owns the corrected consent-first permission order and verifies equally prominent, unselected Agree/Decline choices without dark patterns. |
| DIS-001 | Absent/unmapped | 3F.10, 4.7 | No single persisted UI/AI language setting or live application-wide localization. |
| DIS-002 | Stub | 3F.9, 4.7 | Two-string FixtureTranslationService and in-memory cache only; no Apple Translation or persistent cache. |
| DIS-003 | Stub | 3F.10, 4.7 | State/error UI uses hardcoded English, not the required String Catalog localization. |
| DIS-004 | Stub | 3F.10, 4.7 | Some accessibility labels exist, but no evidence of full labels, announcements, contrast, Dynamic Type, or VoiceOver-order acceptance. |
| SYS-001 | Partial | 3F.5, 3F.7, 3F.10, 4.0g, 4.2, 4.4 | Live panel/TaskQueue/Progress wiring and audits exist, but persisted progress cannot reconstruct an executable job after restart. 4.0g owns versioned task launcher resolution and truthful Continue/Restart. |
| RES-001 | Stub | 3F.3, 3F.5, 3F.7, 3F.10, 4.3, 4.4, 4.7 | Offline indicator UI exists; fully offline model/inference/search and reconnect synchronization do not. |
| RES-002 | Stub | 3F.5, 3F.7, 3F.10, 4.4, 4.7 | Low-power banner/toggle is fixture display; no lightweight visual model, queue control, recall evidence, or audit. |
| RES-003 | Stub | 3F.5, 3F.7, 3F.10, 4.4, 4.7 | Thermal banner is fixture display; no thermal monitor/degraded runtime behavior. |
| RES-004 | Partial | 3F.1, 3F.3, 3F.5, 3F.7, 3F.10, 4.3, 4.4, 4.7 | ModelLoader state/retry code and tests exist, but artifacts are absent, model status is fabricated in Settings, and FTS fallback/audits are incomplete. |
| SET-001 | Stub | 3F.7, 3F.10, 4.7 | Language-setting surface is not wired to a persisted policy/localized application. |
| SET-002 | Stub | 3F.7 | Permanent-retention UI copy exists, without production policy/audit enforcement. |
| SET-003 | Stub | 3F.7 | Cache/storage values and clear actions are fixture/simulated, not real cache management. |
| SET-004 | Partial | 3F.7, 4.0c, 4.2 | ECHOMIG1 encrypted export/import exists. The 2026-09-02 review aligned the story with that user-mediated package, explicitly excluding raw original media; 4.0c owns truthful Settings presentation and 4.2 verifies the production round-trip. |
| FBK-001 | Partial | 3F.4, 3F.6, 4.1, 4.2 | Feedback pipeline/actor persist in isolated injected tests; default SearchViewModel has no pipeline and silently drops failures. |
| FBK-002 | Partial | 3F.4, 3F.6, 4.1, 4.2 | Threshold/decay/clamp/re-ranking logic has isolated tests; no production query path or live Settings feedback management. |
| FBK-003 | Partial | 3F.4, 3F.6, 4.1, 4.2 | Bad-case pipeline/actor works under injection; default UI is unwired and management/revoke surface is incomplete. |

## Evidence and interpretation

- **Specifications:** `docs/01-spec/用户故事与验收标准规格书.md:45` defines the 66-story scope. Its own amendments identify SRC-006 as deferred and record model/API route problems (`:7-14`, `:181-185`).
- **Production source:** `Echo/UI/AppShell/AppRootView.swift:29-33` constructs default ViewModels; `Echo/UI/Search/SearchViewModel.swift:179-204,229-253` defaults to nil pipelines and fixture results; `Echo/UI/Home/HomeViewModel.swift:158-205` has no live card loading. `Echo/App/AppDelegate.swift:16-21` does not register background work.
- **Model/runtime source:** `E5Embedder.swift:42-44,125-143`, `SigLIP2Embedder.swift:24-29,62-69`, and `WhisperASREngine.swift:31-36,63-70` explicitly identify scaffold behavior / unavailable inference.
- **Tests:** `EchoTests/Phase3/Phase3IntegrationTests.swift:74-101` constructs a fresh VectorStore and `StubEmbedder`; `EchoTests/Phase2/IngestPipelineImageTests.swift:41-57` likewise injects `StubEmbedder`. These tests support isolated behavior, not default-app production composition.
- Fresh-run baseline embedded in the execution plan: no-fixture startup remained on "Echo is getting ready…" with no initialized data; unit tests passed 718/720 with 2 failures. These observations are baseline context only, not completion evidence.

## P0/P1 blockers (baseline)

### P0 blockers

1. **Production composition and first-run initialization:** no default wiring for policy, database, model/index initialization, or pipelines (`AppRootView`, the embedded Appendix A/C baseline).
2. **Acquisition and real inference:** PhotoKit/Share source paths and E5/SigLIP2/Whisper artifacts/inference are missing/scaffolded; this blocks SRC-001 and all real ingestion/retrieval.
3. **Canonical transactional persistence:** ING-006's atomic canonical/vector/FTS lifecycle is unmapped, blocking reliable ingest, deletion, and search.
4. **Spec decisions:** SRC-006 plus Notes/Voice Memos automatic-read requirements must be resolved to public share-mediated routes; otherwise affected P0 ACs cannot be accepted.
5. **Privacy/data deletion:** no production consent persistence, transactional delete/cascade path, or feasible replacement for impossible timing guarantees.

### P1 blockers

1. **Search runtime:** real embeddings, Cross-Encoder, filters, cache, timeout behavior, and product DI are absent.
2. **System adapters:** CLLocation/HealthKit/notifications/background scheduling and persistence are absent, blocking real awakening delivery.
3. **Creation and translation:** current paths are fixtures; Apple Translation/persistent cache and a public, user-mediated Notes export flow need requirements and implementation decisions.
4. **Explicit deferrals:** AWK-004 and AWK-006 remain Phase-4 work.

## Verdict on the prior "0 of 66 fully complete" claim

**Defensible, with a necessary qualification:** zero stories satisfy the stated production-complete bar today, because none has all feasible ACs implemented, default-wired, and appropriately verified. The prior journal was incomplete—not wrong—because it did not provide the 66-row AC matrix and did not distinguish partial code, fixtures, explicit deferrals, and invalid ACs. This matrix supplies that missing calibration.
