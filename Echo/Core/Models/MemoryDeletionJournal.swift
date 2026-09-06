// ==========================================
// 文件: MemoryDeletionJournal.swift
// Spec: Photo text-search handoff plan §7.8 (D-005 recoverable deletion contract);
//           docs/decisions/ADR-019-photokit-source-deletion-recovery.md
// Task: WP3 - Canonical identity, deletion, compensation, and route rollback; 4.0h - PhotoKit deletion recovery
// 架构约束: SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 下值契约显式 nonisolated；
//           journal 先于副作用持久化，任一阶段失败保留 journal 写 PendingOperations，
//           启动恢复从已持久化 phase 重放幂等步骤（D-005）。
// AC coverage: D-005 phase/vector/exclusion intent; 4.0h external-result gate and one active intent.
// Generated: 2026-08-25 | Updated: 2026-09-05 (4.0h)
// ==========================================

import Foundation

/// D-005 删除阶段机——严格顺序推进，失败停在当前阶段等待恢复重放。
public nonisolated enum MemoryDeletionPhase: String, Sendable, Codable, Equatable {
    case planned
    case cacheInvalidated
    case vectorsDeleted
    case auditPurged
    case canonicalDeleted
    case completed

    nonisolated var ordinal: Int {
        switch self {
        case .planned: 0
        case .cacheInvalidated: 1
        case .vectorsDeleted: 2
        case .auditPurged: 3
        case .canonicalDeleted: 4
        case .completed: 5
        }
    }
}

/// Keeps deletion intent independent from D-005 so a PhotoKit request is not treated as confirmation.
public nonisolated enum MemoryDeletionIntentKind: String, Sendable, Codable, Equatable {
    case echoOnly
    case externalCascade
    case photoLibraryAndEcho
}

/// External source deletion state. Only `confirmedDeleted` unlocks D-005.
public nonisolated enum SourceDeletionState: String, Sendable, Codable, Equatable {
    case notApplicable
    case prepared
    case confirmedDeleted
    case notDeleted
    case indeterminate
}

/// Structured external deletion outcome; state must not be inferred from error prose.
public nonisolated enum SourceDeletionOutcome: String, Sendable, Codable, Equatable {
    case notRequested
    case confirmedDeleted
    case reconciledAbsent
    case userCancelled
    case authorizationDenied
    case accessRestricted
    case assetNotDeletable
    case assetVisible
    case limitedScopeHidden
    case systemResultUnknown
    case sourceUnavailable
}

/// 单个 generation 内待删除的向量 ID 清单。
public nonisolated struct GenerationVectorIDs: Sendable, Codable, Equatable {
    public nonisolated let generationID: String
    public nonisolated let vectorIDs: [UUID]

    public nonisolated init(generationID: String, vectorIDs: [UUID]) {
        self.generationID = generationID
        self.vectorIDs = vectorIDs
    }
}

/// 可恢复删除日志——先于任何副作用持久化（.planned），
/// 逐阶段推进并在成功后于 .completed 时移除自身。
public nonisolated struct MemoryDeletionJournal: Sendable, Codable, Equatable {
    public nonisolated let operationID: String
    public nonisolated let memoryID: UUID
    public nonisolated let auditSubjectHash: String
    public nonisolated let traceID: String
    public nonisolated let phase: MemoryDeletionPhase
    public nonisolated let vectorIDsByGeneration: [GenerationVectorIDs]
    /// The original deletion intent must survive removal of the canonical row.
    public nonisolated let sourceLocator: String?
    public nonisolated let sourceType: String?
    public nonisolated let writeExcluded: Bool?
    public nonisolated let intentKind: MemoryDeletionIntentKind
    public nonisolated let sourceDeletionState: SourceDeletionState
    public nonisolated let sourceDeletionOutcome: SourceDeletionOutcome

    public nonisolated init(
        operationID: String,
        memoryID: UUID,
        auditSubjectHash: String,
        traceID: String,
        phase: MemoryDeletionPhase,
        vectorIDsByGeneration: [GenerationVectorIDs],
        sourceLocator: String? = nil,
        sourceType: String? = nil,
        writeExcluded: Bool? = nil,
        intentKind: MemoryDeletionIntentKind? = nil,
        sourceDeletionState: SourceDeletionState? = nil,
        sourceDeletionOutcome: SourceDeletionOutcome? = nil
    ) {
        self.operationID = operationID
        self.memoryID = memoryID
        self.auditSubjectHash = auditSubjectHash
        self.traceID = traceID
        self.phase = phase
        self.vectorIDsByGeneration = vectorIDsByGeneration
        self.sourceLocator = sourceLocator
        self.sourceType = sourceType
        self.writeExcluded = writeExcluded
        let inferredIntent = intentKind ?? (writeExcluded == true ? .echoOnly : .externalCascade)
        self.intentKind = inferredIntent
        self.sourceDeletionState = sourceDeletionState
            ?? (inferredIntent == .echoOnly ? .notApplicable : .confirmedDeleted)
        self.sourceDeletionOutcome = sourceDeletionOutcome
            ?? (inferredIntent == .echoOnly ? .notRequested : .confirmedDeleted)
    }
}
