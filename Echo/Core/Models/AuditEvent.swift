// ==========================================
// 文件: AuditEvent.swift
// 对应规格: AGENTS.md §5.4 (审计日志契约: 强制字段 / hash-only / 30天 / NSFileProtectionComplete),
//            §7.3 (审计事件完整清单)
//            docs/decisions/ADR-007-production-composition-consent.md §决策-4 (AuditLog schema/存储迁移)
// 任务: 3F.1 - Production composition、首次启动、同意与隐私
//       3F.6 - 跟进查询审计事件（US-RET-005 AC-4）
//       4.0d - 交互式唤醒卡 hash-only action audit
//       4.0h - Structured audit for PhotoKit deletion results and exclusion cleanup notices
// AC 覆盖: AGENTS.md §5.4 (必填字段 eventType/timestamp/traceID/policyVersion/success, hash-only, 30天, 加密),
//          US-PRV-006 AC-6 (retentionPolicyEvaluated), ADR-007 §决策-3 (purgeFailed 审计),
//          US-RET-005 AC-4 ✅ (followUpQuery, 2026-08-11 3F.6), US-SRC-010 AC-5 ✅ (crossAppSearch)
// 架构约束: AGENTS.md R-007 (禁止 unchecked Sendable), 仅记录哈希摘要禁止原文
// 重要: 项目 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor，所有 struct stored/computed 需 nonisolated
// Generated: 2026-08-04 | Updated: 2026-09-05 (4.0h source lifecycle)
// ==========================================

import Foundation
import CryptoKit

// MARK: - Audit Event

/// 审计事件类型 — 对应 AGENTS.md §7.3 审计事件完整清单
public enum AuditEvent: String, Sendable, Codable {
    case dataSourceConnected
    case autoImportCompleted
    case scheduledScanCompleted
    case personSynced
    case deviceMigrationCompleted
    case permissionChanged
    case excluded
    case excludedRestored
    case excludedBatchRestored
    case excludedAutoCleaned
    case excludedChangeDetected
    case excludedRestoreFailedFileMissing
    case dataSourceChangeSynced
    case manualChangeDetectionCompleted
    /// 记忆摄入（无原文，仅 hash）— AGENTS.md §7.3
    case memoryIngested
    /// 记忆摄入事务审计 (US-ING-006 AC-5: 含 rolledBack=true/false)
    case ingestTransaction
    case imageIngested
    case videoIngested
    case voiceIngested
    case memoryDeleted
    case cascadeDeleteFromOriginal
    case memoryEdited
    case feedbackReceived
    case feedbackReset
    case feedbackRevoked
    case badCaseMarked
    case badCaseRevoked
    /// 模型加载失败 (AGENTS.md §7.3)
    case modelLoadFailed
    /// 模型加载手动重试成功 (AGENTS.md §7.3)
    case modelLoadRetrySuccess
    /// generation 向量存储从磁盘恢复失败（维度不匹配/文件损坏 → 重建空索引）— Nitpick-2 修复
    case indexRestoreFailed
    case backgroundTaskInterrupted
    case retryPending
    case syncConflict
    case reauthorized
    case retrieval
    case contextualAwakening
    case emotionalAwakening
    /// 日期/纪念日唤醒 (US-AWK-002 AC-5: triggerType=anniversary, yearsAgo=[1,3,5])
    case dateAwakening
    // 3F.1 新增 (ADR-007):
    /// 用户同意 PIPL 隐私政策 (US-PRV-008)
    case consentAccepted
    /// 用户撤回同意 / 注销 (US-PRV-005 / US-PRV-008 AC-5)
    case consentRevoked
    /// 事务性清除完成 (US-PRV-005 AC-7)
    case purgeCompleted
    /// 事务性清除失败 → blocked 状态 (ADR-007 §决策-3)
    case purgeFailed
    /// 记忆永久保留策略评估 (US-PRV-006 AC-6)
    case retentionPolicyEvaluated
    /// Share Extension 显式分享摄入 (US-SRC-003 AC-4: 含 appBundleId + contentType)
    case shareExtensionImported
    /// 跨 App 检索融合 (US-SRC-010 AC-5: sourceType 记录【实际授权】源列表，非请求列表)
    case crossAppSearch
    /// 跟进查询（对话轮次，US-RET-005 AC-4: 审计携带父轮次 traceID，sourceLanguage 含 parentTraceId）
    case followUpQuery
    /// 数据概览被访问 (US-SRC-009 AC-5, 3F.7)
    case dataOverviewAccessed
    // 3F.10 新增 (DECISION-1 human-approved 2026-08-12 — audit cases the locked ACs require):
    /// 统一语言切换 (US-DIS-001 AC-5 / US-SET-001: 含 newLanguage，记录于 sourceLanguage 列)
    case languageUnified
    /// 后台任务面板被访问 (US-SYS-001 AC-7)
    case backgroundTaskUIAccessed
    /// 降级警告 (US-RES-002 AC-5: batteryLevel/modelVersion/degradationWarningShown/backgroundTasksPaused;
    /// US-RES-003 AC-5: deviceThermalState/degradationActive/warningShown — carried hash-only in content)
    case degradationWarning
    /// grounded 合成 (US-SYN-002 AC-5: 含 citationCount, noSourceCount)
    case synthesis
    /// 创作生成 (US-SYN-003 AC-6: 含 templateType, sourceMemoryCount, exportFormat, savedToNotes)
    case creativeGeneration
    /// 合成失败模板降级 (US-SYN-008 AC-5: 含 failureReason)
    case synthesisFallback
    /// 交互式唤醒卡动作（US-AWK-005 AC-5: next/record/jump + hash-only identity）
    case cardInteraction
}

// MARK: - Audit Log Entry

/// 审计日志条目 — 对应 AGENTS.md §5.4 审计日志契约
///
/// 强制字段: eventType, timestamp, traceID, policyVersion, success
/// 可选字段: sourceType, affectedCount, excludedWritten, sourceLanguage, elapsedMs
/// 隐私保护: 仅记录哈希摘要，禁止原文（content 字段在写入时被哈希为 contentHash）
public struct AuditLogEntry: Sendable, Codable {
    public nonisolated let id: Int64
    public nonisolated let eventType: AuditEvent
    public nonisolated let timestamp: Date
    public nonisolated let traceID: String
    public nonisolated let policyVersion: Int
    public nonisolated let success: Bool
    public nonisolated let sourceType: String?
    public nonisolated let affectedCount: Int?
    public nonisolated let excludedWritten: Bool?
    public nonisolated let sourceLanguage: String?
    public nonisolated let elapsedMs: Int?
    /// 视频摄入关键帧数（US-ING-005 AC-5）
    public nonisolated let frameCount: Int?
    /// 视频音频转写字符长度（US-ING-005 AC-5）
    public nonisolated let audioTranscriptLength: Int?
    /// 视频是否含音频轨道（US-ING-005 AC-5）
    public nonisolated let hasAudio: Bool?
    /// 内容字段的 SHA-256 哈希摘要（hash-only，禁止原文）— AGENTS.md §5.4
    public nonisolated let contentHash: String?
    public nonisolated let action: String?
    public nonisolated let resumePoint: Int?
    public nonisolated let userChoiceOnRestart: String?
    public nonisolated let outcome: String?
    public nonisolated let cardIdDigest: String?
    public nonisolated let memoryIdDigest: String?
    public nonisolated let feelingAssociatedToSource: Bool?
    public nonisolated let editedFields: [String]?
    public nonisolated let reindexed: Bool?
    public nonisolated let conflictResolvedWith: String?
    public nonisolated let preservedOriginal: Bool?
    public nonisolated let sourceDeletionRequested: Bool?
    public nonisolated let sourceDeletionCompleted: Bool?
    public nonisolated let sourceDeletionOutcome: String?
    public nonisolated let excludedAutoCleaned: Bool?
    public nonisolated let userNotified: Bool?

    public nonisolated init(
        id: Int64 = 0,
        eventType: AuditEvent,
        timestamp: Date = Date(),
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
        contentHash: String? = nil,
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
        userNotified: Bool? = nil
    ) {
        self.id = id
        self.eventType = eventType
        self.timestamp = timestamp
        self.traceID = traceID
        self.policyVersion = policyVersion
        self.success = success
        self.sourceType = sourceType
        self.affectedCount = affectedCount
        self.excludedWritten = excludedWritten
        self.sourceLanguage = sourceLanguage
        self.elapsedMs = elapsedMs
        self.frameCount = frameCount
        self.audioTranscriptLength = audioTranscriptLength
        self.hasAudio = hasAudio
        self.contentHash = contentHash
        self.action = action
        self.resumePoint = resumePoint
        self.userChoiceOnRestart = userChoiceOnRestart
        self.outcome = outcome
        self.cardIdDigest = cardIdDigest
        self.memoryIdDigest = memoryIdDigest
        self.feelingAssociatedToSource = feelingAssociatedToSource
        self.editedFields = editedFields
        self.reindexed = reindexed
        self.conflictResolvedWith = conflictResolvedWith
        self.preservedOriginal = preservedOriginal
        self.sourceDeletionRequested = sourceDeletionRequested
        self.sourceDeletionCompleted = sourceDeletionCompleted
        self.sourceDeletionOutcome = sourceDeletionOutcome
        self.excludedAutoCleaned = excludedAutoCleaned
        self.userNotified = userNotified
    }

    /// 从数据库查询结果行构造 AuditLogEntry（用于 fetchAuditLogs）
    public nonisolated static func fromRow(_ row: [String: DBValue]) -> AuditLogEntry? {
        guard let etStr = row["eventType"]?.stringValue,
              let eventType = AuditEvent(rawValue: etStr),
              let ts = row["timestamp"]?.doubleValue,
              let traceID = row["traceID"]?.stringValue,
              let pv = row["policyVersion"]?.intValue,
              let successInt = row["success"]?.intValue else { return nil }
        return AuditLogEntry(
            id: row["id"]?.intValue ?? 0,
            eventType: eventType,
            timestamp: Date(timeIntervalSince1970: ts),
            traceID: traceID,
            policyVersion: Int(pv),
            success: successInt != 0,
            sourceType: row["sourceType"]?.stringValue,
            affectedCount: row["affectedCount"]?.intValue.map(Int.init),
            excludedWritten: row["excludedWritten"]?.intValue.map { $0 != 0 },
            sourceLanguage: row["sourceLanguage"]?.stringValue,
            elapsedMs: row["elapsedMs"]?.intValue.map(Int.init),
            frameCount: row["frameCount"]?.intValue.map(Int.init),
            audioTranscriptLength: row["audioTranscriptLength"]?.intValue.map(Int.init),
            hasAudio: row["hasAudio"]?.intValue.map { $0 != 0 },
            contentHash: row["contentHash"]?.stringValue,
            action: row["action"]?.stringValue,
            resumePoint: row["resumePoint"]?.intValue.map(Int.init),
            userChoiceOnRestart: row["userChoiceOnRestart"]?.stringValue,
            outcome: row["outcome"]?.stringValue,
            cardIdDigest: row["cardIdDigest"]?.stringValue,
            memoryIdDigest: row["memoryIdDigest"]?.stringValue,
            feelingAssociatedToSource: row["feelingAssociatedToSource"]?.intValue.map { $0 != 0 },
            editedFields: row["editedFields"]?.stringValue?.split(separator: ",").map(String.init),
            reindexed: row["reindexed"]?.intValue.map { $0 != 0 },
            conflictResolvedWith: row["conflictResolvedWith"]?.stringValue,
            preservedOriginal: row["preservedOriginal"]?.intValue.map { $0 != 0 },
            sourceDeletionRequested: row["sourceDeletionRequested"]?.intValue.map { $0 != 0 },
            sourceDeletionCompleted: row["sourceDeletionCompleted"]?.intValue.map { $0 != 0 },
            sourceDeletionOutcome: row["sourceDeletionOutcome"]?.stringValue,
            excludedAutoCleaned: row["excludedAutoCleaned"]?.intValue.map { $0 != 0 },
            userNotified: row["userNotified"]?.intValue.map { $0 != 0 }
        )
    }
}

// MARK: - Audit Content Hasher

/// 审计内容哈希工具 — 仅记录哈希摘要，禁止原文 (AGENTS.md §5.4)
public enum AuditContentHasher {
    /// 计算内容的 SHA-256 十六进制摘要
    public nonisolated static func sha256Hex(_ content: String) -> String {
        let data = Data(content.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - AuditSubject（WP3 步骤 3b，交接计划 §7.8）

/// memory 主体的确定性审计身份——同一 memory 的 ingest、search-result selection、
/// feedback、delete、migration 与 compensation 记录可按 subjectHash 确定性识别。
/// 不落明文；不与 payload contentHash 混淆。
public nonisolated struct AuditSubject: Sendable, Codable, Equatable {
    public nonisolated let kind: String
    public nonisolated let subjectHash: String

    public nonisolated init(kind: String, subjectHash: String) {
        self.kind = kind
        self.subjectHash = subjectHash
    }

    /// 固定输入 "memory:" + lowercase UUID，经 AuditContentHasher.sha256Hex。
    public nonisolated static func memory(_ memoryID: UUID) -> AuditSubject {
        AuditSubject(
            kind: "memory",
            subjectHash: AuditContentHasher.sha256Hex("memory:" + memoryID.uuidString.lowercased())
        )
    }
}
