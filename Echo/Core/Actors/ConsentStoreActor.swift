// ==========================================
// 文件: ConsentStoreActor.swift
// 对应规格: docs/decisions/ADR-007-production-composition-consent.md §决策-2 (deny-by-default 同意),
//            §决策-3 (事务性撤回/清除, PurgeBoundary), §决策-4 (审计 hash-only)
//            docs/01-spec/用户故事与验收标准规格书.md → US-PRV-008 (PIPL 同意),
//            US-PRV-005 (撤回=注销, 事务清除), US-PRV-004 (删除时事务性清除)
// Task: 3F.1 + 4.0f - Production consent and progressive permission cleanup
// AC 覆盖: ADR-007 §决策-2 (同意版本与时间戳持久化), §决策-3 (事务清除 + blocked + 审计),
//          US-PRV-005 AC-5/AC-7 (冷却期满异步擦除 + 审计自擦除), US-PRV-008 AC-4/AC-5,
//          4.0f AC-3 (consent revocation also purges persisted awakening preferences),
//          4.0j AC-7 (consent revocation purges all persisted narrative-report state)
// 架构约束: AGENTS.md §4.2 (Actor 隔离), §5.4 (审计 hash-only), R-007 (禁止 unchecked Sendable)
// Generated: 2026-08-04; updated: 2026-09-04 (4.0f)
// ==========================================

import Foundation

/// 同意状态存储与事务性撤回/清除 Actor（3F.1）。
///
/// ## 职责
/// - deny-by-default 同意状态持久化（ConsentStore SQLite 表）
/// - 同意 / 拒绝 / 撤回（= 注销清除）
/// - 事务性清除（向量、索引、缓存、元数据、审计日志、translationCache）
///
/// ## 事务语义 (ADR-007 §决策-3)
/// - 成功: BEGIN → 清除全部业务表 → 自擦除审计 → 重置同意 → COMMIT
/// - 失败: ROLLBACK，保留业务数据，写入 `.purgeFailed` 审计，进入 blocked 状态
public actor ConsentStoreActor {

    // MARK: - Singleton

    public static let shared = ConsentStoreActor()

    // MARK: - Properties

    private let db: DatabaseManager
    private let privacy: PrivacyActor

    /// 当前同意状态（内存副本，SQLite 为事实源）
    private var state: ConsentState = .notConsented

    /// 是否已从数据库加载
    private var loaded = false

    /// 测试用故障注入（非生产路径）
    internal var injectedPurgeFault: PurgeFault?

    /// 测试用故障注入：acceptConsent 写库失败（非生产路径）
    internal var injectedConsentWriteFault = false

    /// Purge fault injection point
    internal enum PurgeFault: Sendable {
        case failBeforeCommit
    }

    /// Injected consent-write error (test-only)
    internal enum ConsentWriteError: Error {
        case injectedWriteFault
    }

    /// Inject/clear the purge fault (test-only; actor isolation so accessed via methods)
    internal func setPurgeFault(_ fault: PurgeFault?) {
        injectedPurgeFault = fault
    }

    /// Inject/clear the consent-write fault (test-only)
    internal func setConsentWriteFault(_ enabled: Bool) {
        injectedConsentWriteFault = enabled
    }

    // MARK: - Initialization

    public init(db: DatabaseManager = .shared, privacyActor: PrivacyActor = .shared) {
        self.db = db
        self.privacy = privacyActor
    }

    // MARK: - State Loading

    /// 从 SQLite ConsentStore 加载同意状态（首次启动无记录 → 默认 deny-by-default 未同意）
    public func loadState() async throws {
        let rows = try await db.executeQuery(
            sql: "SELECT hasConsented, consentVersion, consentedAt, policyVersion FROM ConsentStore WHERE id = 1",
            bindings: []
        )
        if let row = rows.first {
            state = ConsentState(
                hasConsented: (row["hasConsented"]?.intValue ?? 0) != 0,
                consentVersion: Int(row["consentVersion"]?.intValue ?? 1),
                consentedAt: row["consentedAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) },
                policyVersion: Int(row["policyVersion"]?.intValue ?? 1)
            )
        } else {
            state = .notConsented
        }
        loaded = true
    }

    /// 当前同意状态
    public func getState() async -> ConsentState {
        if !loaded { try? await loadState() }
        return state
    }

    /// 是否已同意（deny-by-default 检查点）
    public func hasConsented() async -> Bool {
        await getState().hasConsented
    }

    // MARK: - Consent Actions

    /// 用户同意 PIPL 隐私政策并持久化 (US-PRV-008 AC-4, ADR-007 §决策-2)
    public func acceptConsent(consentVersion: Int, policyVersion: Int) async throws {
        if injectedConsentWriteFault {
            throw ConsentWriteError.injectedWriteFault
        }
        let newState = ConsentState(
            hasConsented: true,
            consentVersion: consentVersion,
            consentedAt: Date(),
            policyVersion: policyVersion
        )
        try await db.executeWrite(
            sql: """
                INSERT OR REPLACE INTO ConsentStore (id, hasConsented, consentVersion, consentedAt, policyVersion, updatedAt)
                VALUES (1, ?, ?, ?, ?, ?)
                """,
            bindings: [
                .int(newState.hasConsented ? 1 : 0),
                .int(Int64(newState.consentVersion)),
                newState.consentedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
                .int(Int64(newState.policyVersion)),
                .double(Date().timeIntervalSince1970),
            ]
        )
        // Update in-memory state only after the write succeeds, so a failed write
        // cannot diverge memory from SQLite
        state = newState
        try? await privacy.writeAuditLog(
            eventType: .consentAccepted,
            traceID: UUID().uuidString,
            policyVersion: policyVersion,
            success: true,
            sourceType: "consent"
        )
    }

    /// 撤回同意 = 注销清除（US-PRV-008 AC-5, US-PRV-005, ADR-007 §决策-3）
    ///
    /// - Parameter boundary: 清除边界（默认 `.full`）
    /// - Returns: 清除结果；失败时进入 blocked 状态并写入 `.purgeFailed` 审计
    public func revokeConsent(boundary: PurgeBoundary = .full) async throws -> PurgeResult {
        if !loaded { try? await loadState() }

        let traceID = UUID().uuidString
        let policyVersion = state.policyVersion

        try await db.beginTransaction()
        do {
            // Record the revocation audit (self-erased with AuditLog on full purge per
            // US-PRV-005 AC-7; kept on partial boundaries to preserve the revocation event)
            try? await privacy.writeAuditLog(
                eventType: .consentRevoked,
                traceID: traceID,
                policyVersion: policyVersion,
                success: true,
                sourceType: "consent"
            )
            var affected = 0
            if boundary.purgeMetadata {
                affected += try await purgeTable("NarrativeReportSource")
                affected += try await purgeTable("NarrativeReport")
                affected += try await purgeTable("NarrativeReportPeriod")
                affected += try await purgeTable("NarrativeReportSchedule")
                affected += try await purgeTable("Memory")
                affected += try await purgeTable("Representation")
                affected += try await purgeTable("ExcludedAssets")
                affected += try await purgeTable("FeedbackStore")
                affected += try await purgeTable("TaskProgress")
                affected += try await purgeTable("PendingOperations")
                affected += try await purgeTable("UserPolicyStore")
                affected += try await purgeTable("AwakeningPreference")
            }
            if boundary.purgeIndexes {
                affected += try await purgeTable("IndexGeneration")
                affected += try await purgeTable("IndexBuildItem")
                affected += try await purgeTable("ActiveRouteSet")
            }
            if boundary.purgeVectors {
                affected += try await purgeTable("IndexGeneration")
            }
            if boundary.purgeCaches {
                affected += try await purgeTable("TaskProgress")
            }
            if boundary.purgeAuditLog {
                // 先写清除完成审计，再在事务内自擦除审计库（US-PRV-005 AC-7）
                try? await privacy.writeAuditLog(
                    eventType: .purgeCompleted,
                    traceID: traceID,
                    policyVersion: policyVersion,
                    success: true,
                    sourceType: "consent",
                    affectedCount: affected
                )
                affected += try await purgeTable("AuditLog")
            }
            // translationCache 为内存层，此处仅重置同意状态（持久化由 UI 层负责）

            // 删除同意记录（持久化）
            try await db.executeWrite(sql: "DELETE FROM ConsentStore", bindings: [])

            if injectedPurgeFault != nil {
                throw PurgeError.purgeFailed(reason: "injected fault before commit")
            }

            try await db.commitTransaction()
            // Reset in-memory state only after the transaction commits, so a rollback
            // keeps memory consistent with SQLite (no divergence)
            state = .notConsented
            return PurgeResult(success: true, blocked: false, affectedCount: affected)
        } catch {
            try? await db.rollbackTransaction()
            // 回滚后写入失败审计（审计库此时未被清除，保留 blocked 证据）
            try? await privacy.writeAuditLog(
                eventType: .purgeFailed,
                traceID: traceID,
                policyVersion: policyVersion,
                success: false,
                sourceType: "consent",
                content: "revoke/purge failed, transaction rolled back"
            )
            return PurgeResult.failed
        }
    }

    // MARK: - Purge Helpers

    private func purgeTable(_ table: String) async throws -> Int {
        let changes = try await db.executeWrite(sql: "DELETE FROM \(table)", bindings: [])
        return Int(changes)
    }
}
