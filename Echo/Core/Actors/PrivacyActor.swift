// ==========================================
// 文件: PrivacyActor.swift
// 对应规格: docs/02-architecture/架构设计文档.md §7 (隐私校验与审计追踪)
//            docs/01-spec/用户故事与验收标准规格书.md → US-PRV-001
// 任务: 1.8 - 搭建单元测试框架，编写第一个 Actor 测试用例 (Stub)
//       2.1 - PrivacyActor + UserPolicy 实现 (Full Implementation)
//       3F.1 - deny-by-default 同意闸门 (ADR-007 §决策-2)
//       4.0a - Search operation/source authorization separation
//       4.0d - Structured hash-only awakening card interaction fields
//       4.0h - Structured original-source deletion and cleanup-notice audit fields
//       4.0i - Typed grounded-generation and system-share audit fields
// AC 覆盖: US-PRV-001 AC-1 (策略即时生效), AC-2 (被拒数据不进 Retriever),
//          AC-3 (Denial Response), AC-4 (缓存失效), AC-5 (重新授权不清除排除表),
//          AC-6 (审计记录 .denied/.reauthorized),
//          AC-7 (search is an operation, not an authorized source type),
//          US-AWK-005 AC-5 (结构化卡片交互字段写入与公开读取),
//          4.0h AC-2/3/5 (structured source deletion and cascade cleanup audit),
//          PR review 修复: 同意闸门仅 .denied 短路，.allowed 落入 per-source 授权检查 (US-PRV-001)
// 架构约束: 遵循 AGENTS.md §4.2 (Actor 隔离契约), §7.1 (PrivacyCheckpoint 强制注入),
//           §7.3 (审计日志), §5.4 (30天保留), R-006 (审计强制覆盖),
//           R-007 (禁止 unchecked Sendable), R-008 (跨 Actor 调用必须 await)
// 重要: 所有 struct stored/computed properties 必须 nonisolated（项目 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor）
// Generated: 2026-07-05 (Stub), 2026-07-07 (Task 2.1 Full Implementation); Updated: 2026-09-07 (4.0i)
// ==========================================

import Foundation

// MARK: - Privacy Operation

/// Pipeline 操作类型枚举 — 对应架构文档 §7.1 中的 operation 字段
public enum PrivacyOperation: String, Sendable, Codable {
    case search
    case ingest
    case sync
    case delete
    case awakening
    case feedback
    /// 设备迁移导出/导入 (DEF-59-004, R-006; added by 3F.10 DECISION-2)
    case migration
}

// MARK: - Privacy Decision

/// 隐私校验决策结果
public enum PrivacyDecision: String, Sendable, Codable {
    /// 操作被允许
    case allowed
    /// 操作被拒绝（用户未授权相关数据源或功能）
    case denied
}

// MARK: - Privacy Checkpoint

/// 隐私校验检查点 — 每个 Pipeline Actor 方法入口必须调用 PrivacyActor.validate() 获取此对象。
///
/// 对应架构文档 §7.1 PrivacyCheckpoint 结构，包含以下字段：
/// - traceID: UUID，由 Pipeline 节点创建时生成
/// - timestamp: 当前时间
/// - operation: 操作类型枚举
/// - policyVersion: UserPolicy 版本号
/// - sourceTypes: 涉及的数据源
/// - decision: 授权结果
public struct PrivacyCheckpoint: Sendable, Codable {
    public nonisolated let traceID: String
    public nonisolated let timestamp: Date
    public nonisolated let operation: PrivacyOperation
    public nonisolated let policyVersion: Int
    public nonisolated let sourceTypes: [String]
    public nonisolated let decision: PrivacyDecision

    public nonisolated init(
        traceID: String = UUID().uuidString,
        timestamp: Date = Date(),
        operation: PrivacyOperation,
        policyVersion: Int = 1,
        sourceTypes: [String] = [],
        decision: PrivacyDecision = .allowed
    ) {
        self.traceID = traceID
        self.timestamp = timestamp
        self.operation = operation
        self.policyVersion = policyVersion
        self.sourceTypes = sourceTypes
        self.decision = decision
    }

    /// 检查点是否允许继续执行
    public nonisolated var isAllowed: Bool {
        decision == .allowed
    }
}

// MARK: - User Policy

/// 用户隐私策略配置 — 控制授权数据源、偏好语言等。
///
/// 对应 US-PRV-001，由 PrivacyActor 管理。
/// TODO (Phase 2, Task 2.1): 实现完整的策略持久化与授权管理。
public struct UserPolicy: Sendable, Codable {
    public nonisolated let preferredLanguage: String
    public nonisolated var authorizedSourceTypes: Set<String>
    public nonisolated let policyVersion: Int

    public nonisolated init(
        preferredLanguage: String = "zh-Hans",
        authorizedSourceTypes: Set<String> = ["photo", "note", "voice", "video", "thirdParty"],
        policyVersion: Int = 1
    ) {
        self.preferredLanguage = preferredLanguage
        self.authorizedSourceTypes = authorizedSourceTypes
        self.policyVersion = policyVersion
    }

    /// 检查指定数据源是否已授权
    public nonisolated func isAuthorized(sourceType: String) -> Bool {
        authorizedSourceTypes.contains(sourceType)
    }
}

// MARK: - Privacy Actor

/// 隐私校验与审计 Actor — 管理 UserPolicy，提供 Pipeline 入口的授权校验（PrivacyCheckpoint）。
///
/// ## Actor 隔离契约 (AGENTS.md §4.2)
/// - 可变状态封装: UserPolicy 封装在 Actor 中
/// - 串行执行: 同一 Actor 的操作串行执行，无数据竞争
/// - 仅值类型传递: 跨 Actor 传递均为 Sendable 值类型
///
/// ## 审计日志契约 (AGENTS.md §7.3)
/// - 强制字段: eventType, timestamp, traceID, policyVersion, success
/// - 保留期: 30 天，超期自动清理
/// - 覆盖率: CI 强制 100% (所有 Pipeline 入口必须有 Checkpoint)
///
/// ## 使用方式
/// ```swift
/// // 每个 Pipeline Actor 方法的第一个语句必须是：
/// let checkpoint = await PrivacyActor.shared.validate(
///     operation: .search,
///     traceID: traceID
/// )
/// // 若返回 .denied，立即终止并返回 Denial Response
/// guard checkpoint.isAllowed else { return }
/// ```
public actor PrivacyActor {

    // MARK: - Singleton

    public static let shared = PrivacyActor()

    // MARK: - Properties

    /// 当前用户策略 — 从 SQLite UserPolicyStore 加载，变更时持久化
    private var policy: UserPolicy

    /// 数据库管理器引用（AGENTS.md §5.1：所有 SQLite 写操作封装在 Actor 中）
    private let db: DatabaseManager

    /// 策略是否已从数据库加载
    private var policyLoaded = false

    // MARK: - Consent Gate (3F.1, ADR-007 §决策-2)

    private var consentEnforcementEnabled = false
    private var consentStore: ConsentStoreActor?

    // MARK: - Initialization

    internal init(db: DatabaseManager = .shared, policy: UserPolicy = UserPolicy()) {
        self.db = db
        self.policy = policy
    }

    // MARK: - Consent Enforcement (3F.1)

    public func enableConsentEnforcement(consentStore: ConsentStoreActor) {
        self.consentStore = consentStore
        self.consentEnforcementEnabled = true
    }

    public func disableConsentEnforcement() {
        self.consentEnforcementEnabled = false
        self.consentStore = nil
    }

    public func isConsentEnforcementEnabled() -> Bool {
        consentEnforcementEnabled
    }

    private func consentDecision() async -> PrivacyDecision? {
        guard consentEnforcementEnabled, let store = consentStore else { return nil }
        let consented = await store.hasConsented()
        return consented ? .allowed : .denied
    }

    // MARK: - Policy Persistence

    /// 从 SQLite UserPolicyStore 加载持久化的 UserPolicy（AGENTS.md §5.1）
    ///
    /// 若数据库中无记录，保留默认策略（首次启动）。
    /// AC-1: 加载的策略在下一次 validate() 调用前生效。
    public func loadPolicy() async throws {
        let rows = try await db.executeQuery(
            sql: "SELECT preferredLanguage, authorizedSourceTypes, policyVersion FROM UserPolicyStore WHERE id = 1",
            bindings: []
        )
        if let row = rows.first,
           let language = row["preferredLanguage"]?.stringValue,
           let sourcesJSON = row["authorizedSourceTypes"]?.stringValue,
           let version = row["policyVersion"]?.intValue {
            let sources: Set<String>
            if let data = sourcesJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                sources = Set(decoded)
            } else {
                sources = ["photo", "note", "voice", "video"]
            }
            self.policy = UserPolicy(
                preferredLanguage: language,
                authorizedSourceTypes: sources,
                policyVersion: Int(version)
            )
        }
        self.policyLoaded = true
    }

    /// 持久化当前 UserPolicy 到 SQLite（upsert，AGENTS.md §5.1）
    private func savePolicy() async throws {
        let sourcesData = try JSONEncoder().encode(Array(policy.authorizedSourceTypes))
        let sourcesJSON = String(data: sourcesData, encoding: .utf8) ?? "[]"
        try await db.executeWrite(
            sql: """
                INSERT OR REPLACE INTO UserPolicyStore (id, preferredLanguage, authorizedSourceTypes, policyVersion, updatedAt)
                VALUES (1, ?, ?, ?, ?)
                """,
            bindings: [
                .text(policy.preferredLanguage),
                .text(sourcesJSON),
                .int(Int64(policy.policyVersion)),
                .double(Date().timeIntervalSince1970),
            ]
        )
    }

    /// 确保策略已加载（懒加载）
    ///
    /// 区分两种场景：
    /// - 首次启动（UserPolicyStore 无记录）：静默使用默认策略 → 正常
    /// - 数据库损坏导致加载失败：标记为未加载，后续 validate() 使用默认策略
    ///   并记录错误日志（不在此层触发 L3，由 Pipeline 层统一处理）
    private func ensurePolicyLoaded() async {
        if !policyLoaded {
            do {
                try await loadPolicy()
            } catch {
                // 加载失败（数据库损坏等 L3 场景）：保留默认策略，标记已尝试
                // Pipeline 层可检测 policyVersion==1 且 loadPolicy 失败来判断是否需要 L3 处理
                policyLoaded = true
                // 写入审计日志记录加载失败（best-effort）
                try? await writeAuditLog(
                    eventType: .modelLoadFailed,
                    traceID: "policy-load-\(UUID().uuidString.prefix(8))",
                    policyVersion: 1,
                    success: false,
                    sourceType: "UserPolicy",
                    sourceLanguage: nil,
                    elapsedMs: nil
                )
            }
        }
    }

    // MARK: - Privacy Checkpoint Validation

    /// 对 Pipeline 操作执行隐私校验，返回 PrivacyCheckpoint 并写入审计日志。
    ///
    /// 对应架构文档 §7.2 强制校验流程：
    /// 1. 生成 traceID（由调用方传入）
    /// 2. 执行授权检查（基于 UserPolicy.authorizedSourceTypes）
    /// 3. 返回 PrivacyCheckpoint（含 decision: .allowed / .denied）
    /// 4. **写入审计日志到 AuditLog SQLite 表**（AGENTS.md §7.3）
    ///    - 允许: 记录 eventType=checkpoint, success=true
    ///    - 拒绝: 记录 eventType=checkpoint, success=false（AC-6: 记录 decision=.denied + policyVersion）
    ///
    /// R-006: 所有异步操作必须包含 PrivacyCheckpoint — 此方法即为 Checkpoint 入口。
    ///
    /// - Parameters:
    ///   - operation: 当前 Pipeline 操作类型
    ///   - traceID: 由 Pipeline 节点生成的 UUID 字符串
    ///   - sourceTypes: 涉及的数据源列表（用于授权匹配）
    /// - Returns: PrivacyCheckpoint 包含授权决策
    public func validate(
        operation: PrivacyOperation,
        traceID: String,
        sourceTypes: [String] = []
    ) async -> PrivacyCheckpoint {
        let startTime = Date()
        await ensurePolicyLoaded()

        // deny-by-default 同意闸门 (3F.1, ADR-007 §决策-2)
        // deny-by-default consent gate (3F.1, ADR-007 §决策-2).
        // Only .denied short-circuits: not-consented rejects all business access and
        // writes a denial audit (AC-6 decision=.denied). .allowed falls through to the
        // per-source authorization check (US-PRV-001) so the gate never bypasses it.
        if let consentDecision = await consentDecision(), consentDecision == .denied {
            let checkpoint = PrivacyCheckpoint(
                traceID: traceID,
                timestamp: Date(),
                operation: operation,
                policyVersion: policy.policyVersion,
                sourceTypes: sourceTypes,
                decision: .denied
            )
            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
            try? await writeAuditLog(
                eventType: .permissionChanged,
                traceID: traceID,
                policyVersion: policy.policyVersion,
                success: false,
                sourceType: sourceTypes.isEmpty ? "consent" : sourceTypes.joined(separator: ","),
                elapsedMs: elapsedMs
            )
            return checkpoint
        }

        // 检查所有涉及的数据源是否均已授权
        let allAuthorized = sourceTypes.isEmpty || sourceTypes.allSatisfy { policy.isAuthorized(sourceType: $0) }
        let decision: PrivacyDecision = allAuthorized ? .allowed : .denied

        let checkpoint = PrivacyCheckpoint(
            traceID: traceID,
            timestamp: Date(),
            operation: operation,
            policyVersion: policy.policyVersion,
            sourceTypes: sourceTypes,
            decision: decision
        )

        // 写入审计日志（best-effort：审计写入失败不阻断 Pipeline）
        // 注意：此处的 event 映射为最近似的事件类型，Pipeline 特有事件（如图片/视频摄入）
        // 应由具体 Pipeline 在操作成功后通过 writeAuditLog() 单独写入。
        let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let event: AuditEvent = switch operation {
        case .search:    .retrieval
        case .ingest:    .memoryIngested
        case .sync:      .dataSourceChangeSynced
        case .delete:    .memoryDeleted
        case .awakening: .scheduledScanCompleted
        case .feedback:  .feedbackReceived
        case .migration: .deviceMigrationCompleted
        }
        try? await writeAuditLog(
            eventType: event,
            traceID: traceID,
            policyVersion: policy.policyVersion,
            success: decision == .allowed,
            sourceType: sourceTypes.isEmpty ? nil : sourceTypes.joined(separator: ","),
            elapsedMs: elapsedMs
        )

        return checkpoint
    }

    // MARK: - Audit Log (AGENTS.md §7.3 / §5.4)

    /// 写入一条审计日志条目到 AuditLog 表
    ///
    /// 隐私保护：仅记录哈希摘要，禁止原文（调用方负责确保 sourceType/affectedCount 等不含敏感数据）
    public func writeAuditLog(
        eventType: AuditEvent,
        traceID: String,
        policyVersion: Int,
        success: Bool = true,
        sourceType: String? = nil,
        affectedCount: Int? = nil,
        excludedWritten: Bool? = nil,
        sourceLanguage: String? = nil,
        elapsedMs: Int? = nil,
        frameCount: Int? = nil,
        audioTranscriptLength: Int? = nil,
        hasAudio: Bool? = nil,
        content: String? = nil,
        subjectKind: String? = nil,
        subjectHash: String? = nil,
        action: String? = nil,
        resumePoint: Int? = nil,
        userChoiceOnRestart: String? = nil,
        outcome: String? = nil,
        cardIdDigest: String? = nil,
        memoryIdDigest: String? = nil,
        feelingAssociatedToSource: Bool? = nil,
        editedFields: [String]? = nil,
        reindexed: Bool? = nil,
        conflictResolvedWith: String? = nil,
        preservedOriginal: Bool? = nil,
        sourceDeletionRequested: Bool? = nil,
        sourceDeletionCompleted: Bool? = nil,
        sourceDeletionOutcome: String? = nil,
        excludedAutoCleaned: Bool? = nil,
        userNotified: Bool? = nil,
        templateType: String? = nil,
        sourceMemoryCount: Int? = nil,
        citationCount: Int? = nil,
        noSourceCount: Int? = nil,
        exportFormat: String? = nil,
        sharePresented: Bool? = nil,
        periodType: String? = nil
    ) async throws {
        let validExportFormats: Set<String> = ["plainText", "markdown", "pdf"]
        let validPeriodTypes: Set<String> = ["month", "year"]
        guard exportFormat.map(validExportFormats.contains) ?? true,
              periodType.map(validPeriodTypes.contains) ?? true,
              sourceMemoryCount.map({ $0 >= 0 }) ?? true,
              citationCount.map({ $0 >= 0 }) ?? true,
              noSourceCount.map({ $0 >= 0 }) ?? true,
              eventType != .creationSharePresented || (exportFormat != nil && sharePresented != nil) else {
            throw AuditValidationError.invalidCreationFields
        }
        let write = Self.makeAuditWrite(
            eventType: eventType,
            traceID: traceID,
            policyVersion: policyVersion,
            success: success,
            sourceType: sourceType,
            affectedCount: affectedCount,
            excludedWritten: excludedWritten,
            sourceLanguage: sourceLanguage,
            elapsedMs: elapsedMs,
            frameCount: frameCount,
            audioTranscriptLength: audioTranscriptLength,
            hasAudio: hasAudio,
            content: content,
            subjectKind: subjectKind,
            subjectHash: subjectHash,
            action: action,
            resumePoint: resumePoint,
            userChoiceOnRestart: userChoiceOnRestart,
            outcome: outcome,
            cardIdDigest: cardIdDigest,
            memoryIdDigest: memoryIdDigest,
            feelingAssociatedToSource: feelingAssociatedToSource,
            editedFields: editedFields,
            reindexed: reindexed,
            conflictResolvedWith: conflictResolvedWith,
            preservedOriginal: preservedOriginal,
            sourceDeletionRequested: sourceDeletionRequested,
            sourceDeletionCompleted: sourceDeletionCompleted,
            sourceDeletionOutcome: sourceDeletionOutcome,
            excludedAutoCleaned: excludedAutoCleaned,
            userNotified: userNotified,
            templateType: templateType,
            sourceMemoryCount: sourceMemoryCount,
            citationCount: citationCount,
            noSourceCount: noSourceCount,
            exportFormat: exportFormat,
            sharePresented: sharePresented,
            periodType: periodType
        )
        try await db.executeWrite(sql: write.sql, bindings: write.bindings)
    }

    nonisolated static func makeAuditWrite(
        eventType: AuditEvent,
        traceID: String,
        policyVersion: Int,
        success: Bool = true,
        sourceType: String? = nil,
        affectedCount: Int? = nil,
        excludedWritten: Bool? = nil,
        sourceLanguage: String? = nil,
        elapsedMs: Int? = nil,
        frameCount: Int? = nil,
        audioTranscriptLength: Int? = nil,
        hasAudio: Bool? = nil,
        content: String? = nil,
        subjectKind: String? = nil,
        subjectHash: String? = nil,
        action: String? = nil,
        resumePoint: Int? = nil,
        userChoiceOnRestart: String? = nil,
        outcome: String? = nil,
        cardIdDigest: String? = nil,
        memoryIdDigest: String? = nil,
        feelingAssociatedToSource: Bool? = nil,
        editedFields: [String]? = nil,
        reindexed: Bool? = nil,
        conflictResolvedWith: String? = nil,
        preservedOriginal: Bool? = nil,
        sourceDeletionRequested: Bool? = nil,
        sourceDeletionCompleted: Bool? = nil,
        sourceDeletionOutcome: String? = nil,
        excludedAutoCleaned: Bool? = nil,
        userNotified: Bool? = nil,
        templateType: String? = nil,
        sourceMemoryCount: Int? = nil,
        citationCount: Int? = nil,
        noSourceCount: Int? = nil,
        exportFormat: String? = nil,
        sharePresented: Bool? = nil,
        periodType: String? = nil,
        timestamp: Date = Date()
    ) -> DatabaseManager.DBWrite {
        // Hash content fields before persistence (AGENTS.md §5.4).
        let contentHash = content.map { AuditContentHasher.sha256Hex($0) }
        return DatabaseManager.DBWrite(
            sql: """
                INSERT INTO AuditLog (eventType, timestamp, traceID, policyVersion, success, sourceType, affectedCount, excludedWritten, sourceLanguage, elapsedMs, frameCount, audioTranscriptLength, hasAudio, contentHash, subjectKind, subjectHash, action, resumePoint, userChoiceOnRestart, outcome, cardIdDigest, memoryIdDigest, feelingAssociatedToSource, editedFields, reindexed, conflictResolvedWith, preservedOriginal, sourceDeletionRequested, sourceDeletionCompleted, sourceDeletionOutcome, excludedAutoCleaned, userNotified, templateType, sourceMemoryCount, citationCount, noSourceCount, exportFormat, sharePresented, periodType)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            bindings: [
                .text(eventType.rawValue),
                .double(timestamp.timeIntervalSince1970),
                .text(traceID),
                .int(Int64(policyVersion)),
                .int(success ? 1 : 0),
                sourceType.map { .text($0) } ?? .null,
                affectedCount.map { .int(Int64($0)) } ?? .null,
                excludedWritten.map { .int($0 ? 1 : 0) } ?? .null,
                sourceLanguage.map { .text($0) } ?? .null,
                elapsedMs.map { .int(Int64($0)) } ?? .null,
                frameCount.map { .int(Int64($0)) } ?? .null,
                audioTranscriptLength.map { .int(Int64($0)) } ?? .null,
                hasAudio.map { .int($0 ? 1 : 0) } ?? .null,
                contentHash.map { .text($0) } ?? .null,
                subjectKind.map { .text($0) } ?? .null,
                subjectHash.map { .text($0) } ?? .null,
                action.map { .text($0) } ?? .null,
                resumePoint.map { .int(Int64($0)) } ?? .null,
                userChoiceOnRestart.map { .text($0) } ?? .null,
                outcome.map { .text($0) } ?? .null,
                cardIdDigest.map { .text($0) } ?? .null,
                memoryIdDigest.map { .text($0) } ?? .null,
                feelingAssociatedToSource.map { .int($0 ? 1 : 0) } ?? .null,
                editedFields.map { .text($0.sorted().joined(separator: ",")) } ?? .null,
                reindexed.map { .int($0 ? 1 : 0) } ?? .null,
                conflictResolvedWith.map { .text($0) } ?? .null,
                preservedOriginal.map { .int($0 ? 1 : 0) } ?? .null,
                sourceDeletionRequested.map { .int($0 ? 1 : 0) } ?? .null,
                sourceDeletionCompleted.map { .int($0 ? 1 : 0) } ?? .null,
                sourceDeletionOutcome.map { .text($0) } ?? .null,
                excludedAutoCleaned.map { .int($0 ? 1 : 0) } ?? .null,
                userNotified.map { .int($0 ? 1 : 0) } ?? .null,
                templateType.map { .text($0) } ?? .null,
                sourceMemoryCount.map { .int(Int64($0)) } ?? .null,
                citationCount.map { .int(Int64($0)) } ?? .null,
                noSourceCount.map { .int(Int64($0)) } ?? .null,
                exportFormat.map { .text($0) } ?? .null,
                sharePresented.map { .int($0 ? 1 : 0) } ?? .null,
                periodType.map { .text($0) } ?? .null,
            ]
        )
    }

    /// 清理超过保留期的审计日志（AGENTS.md §5.4: 保留期 30 天）
    @discardableResult
    /// WP3 步骤 5d：consent purge 全量审计清除，返回删除前行数。
    public func purgeAllAuditRecords() async throws -> Int {
        let before = try await auditLogCount()
        try await db.execute(sql: "DELETE FROM AuditLog")
        return before
    }

    /// WP3 步骤 3h：按 subject identity 精确删除目标主体的全部审计行，
    /// 其他主体行保留；返回删除行数。
    public func purgeAuditRecords(subject: AuditSubject, traceID: String) async throws -> Int {
        let deleted = try await db.executeWrite(
            sql: "DELETE FROM AuditLog WHERE subjectKind = ? AND subjectHash = ?",
            bindings: [.text(subject.kind), .text(subject.subjectHash)]
        )
        return Int(deleted)
    }

    public func cleanupOldAuditLogs(retentionDays: Int = 30) async throws -> Int {
        let cutoff = Date().timeIntervalSince1970 - Double(retentionDays * 86400)
        let changes = try await db.executeWrite(
            sql: "DELETE FROM AuditLog WHERE timestamp < ?",
            bindings: [.double(cutoff)]
        )
        return Int(changes)
    }

    /// 查询审计日志（支持按事件类型过滤和分页）
    public func fetchAuditLogs(
        limit: Int = 100,
        offset: Int = 0,
        eventType: AuditEvent? = nil
    ) async throws -> [AuditLogEntry] {
        let sql: String
        let bindings: [DBBinding]
        if let eventType {
            sql = """
                SELECT id, eventType, timestamp, traceID, policyVersion, success,
                       sourceType, affectedCount, excludedWritten, sourceLanguage, elapsedMs,
                       frameCount, audioTranscriptLength, hasAudio, contentHash,
                       action, resumePoint, userChoiceOnRestart, outcome,
                       cardIdDigest, memoryIdDigest, feelingAssociatedToSource,
                       editedFields, reindexed, conflictResolvedWith,
                       preservedOriginal, sourceDeletionRequested, sourceDeletionCompleted,
                       sourceDeletionOutcome, excludedAutoCleaned, userNotified,
                       templateType, sourceMemoryCount, citationCount, noSourceCount,
                       exportFormat, sharePresented, periodType
                FROM AuditLog WHERE eventType = ? ORDER BY timestamp DESC LIMIT ? OFFSET ?
                """
            bindings = [.text(eventType.rawValue), .int(Int64(limit)), .int(Int64(offset))]
        } else {
            sql = """
                SELECT id, eventType, timestamp, traceID, policyVersion, success,
                       sourceType, affectedCount, excludedWritten, sourceLanguage, elapsedMs,
                       frameCount, audioTranscriptLength, hasAudio, contentHash,
                       action, resumePoint, userChoiceOnRestart, outcome,
                       cardIdDigest, memoryIdDigest, feelingAssociatedToSource,
                       editedFields, reindexed, conflictResolvedWith,
                       preservedOriginal, sourceDeletionRequested, sourceDeletionCompleted,
                       sourceDeletionOutcome, excludedAutoCleaned, userNotified,
                       templateType, sourceMemoryCount, citationCount, noSourceCount,
                       exportFormat, sharePresented, periodType
                FROM AuditLog ORDER BY timestamp DESC LIMIT ? OFFSET ?
                """
            bindings = [.int(Int64(limit)), .int(Int64(offset))]
        }
        let rows = try await db.executeQuery(sql: sql, bindings: bindings)
        return rows.compactMap { AuditLogEntry.fromRow($0) }
    }

    /// 审计日志总数
    public func auditLogCount() async throws -> Int {
        let rows = try await db.executeQuery(sql: "SELECT COUNT(*) AS cnt FROM AuditLog", bindings: [])
        return rows.first?["cnt"]?.intValue.map(Int.init) ?? 0
    }

    /// 记录记忆永久保留策略评估审计 (US-PRV-006 AC-6)。
    ///
    /// 内容以 hash-only 存储：mediaExempt=true, textExempt=true, autoExpiry=false。
    public func evaluateRetentionPolicy(traceID: String = UUID().uuidString) async throws {
        let payload = #"{"mediaExempt":true,"textExempt":true,"autoExpiry":false}"#
        try await writeAuditLog(
            eventType: .retentionPolicyEvaluated,
            traceID: traceID,
            policyVersion: policy.policyVersion,
            success: true,
            sourceType: "retention",
            content: payload
        )
    }

    // MARK: - Policy Management

    /// 获取当前 UserPolicy 的只读副本（AC-1: 确保已加载最新策略）
    public func getPolicy() async -> UserPolicy {
        await ensurePolicyLoaded()
        return policy
    }

    /// 更新用户策略并持久化到 SQLite（AC-1/AC-5/AC-6）
    ///
    /// AC-1: 策略更新后下一次检索调用前生效（调用 savePolicy 持久化）
    /// AC-5: 重新授权时检测授权变化，记录 .reauthorized 审计事件
    /// AC-6: 记录 policyVersion + 审计事件
    ///
    /// - Parameter newPolicy: 新的 UserPolicy 配置
    public func updatePolicy(_ newPolicy: UserPolicy) async throws {
        await ensurePolicyLoaded()

        let oldTypes = self.policy.authorizedSourceTypes
        let reauthorizedTypes = newPolicy.authorizedSourceTypes.subtracting(oldTypes)
        let revokedTypes = oldTypes.subtracting(newPolicy.authorizedSourceTypes)

        self.policy = newPolicy
        try await savePolicy()

        let traceID = UUID().uuidString

        // AC-5: 检测重新授权的数据源 → 记录 .reauthorized 审计
        for sourceType in reauthorizedTypes {
            try? await writeAuditLog(
                eventType: .reauthorized,
                traceID: traceID,
                policyVersion: newPolicy.policyVersion,
                success: true,
                sourceType: sourceType
            )
        }

        // 检测撤销授权的数据源 → 记录 .permissionChanged 审计
        for sourceType in revokedTypes {
            try? await writeAuditLog(
                eventType: .permissionChanged,
                traceID: traceID,
                policyVersion: newPolicy.policyVersion,
                success: true,
                sourceType: sourceType
            )
        }
    }

    /// 检查指定数据源是否已授权
    public func isSourceAuthorized(_ sourceType: String) async -> Bool {
        await ensurePolicyLoaded()
        return policy.isAuthorized(sourceType: sourceType)
    }

    /// 记录重新授权事件（AC-5/AC-6: reauthorized → sourceType + excludedBatchRestored）
    public func recordReauthorization(
        sourceType: String,
        excludedBatchRestored: Bool = false,
        traceID: String = UUID().uuidString
    ) async throws {
        await ensurePolicyLoaded()
        try await writeAuditLog(
            eventType: .reauthorized,
            traceID: traceID,
            policyVersion: policy.policyVersion,
            success: true,
            sourceType: sourceType,
            excludedWritten: excludedBatchRestored
        )
    }

    /// 记录权限变更事件
    public func recordPermissionChanged(
        sourceType: String,
        traceID: String = UUID().uuidString
    ) async throws {
        await ensurePolicyLoaded()
        try await writeAuditLog(
            eventType: .permissionChanged,
            traceID: traceID,
            policyVersion: policy.policyVersion,
            success: true,
            sourceType: sourceType
        )
    }
}
