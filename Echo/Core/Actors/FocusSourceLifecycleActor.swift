// ==========================================
// File: FocusSourceLifecycleActor.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md → US-AWK-005, US-PRV-004/007
//           docs/decisions/ADR-019-photokit-source-deletion-recovery.md
// Task: 4.0h - Live source resolution and PhotoKit deletion saga
// AC coverage: orthogonal source facets, PhotoKit deletion capability gate, confirmed-only D-005,
//              tracked-ID foreground reconciliation, active-intent isolation, per-journal L2,
//              visible-source audit suppression, non-PhotoKit D-005 recovery, hash-only identity,
//              and structured audit
// Architecture: AGENTS.md §4.2 actor isolation, R-001/R-005/R-006, D-002/D-003/D-005
// Generated: 2026-09-05 | Updated: 2026-09-06 (PR #76 review)
// ==========================================

import Foundation

public nonisolated enum FocusContentAvailability: String, Sendable, Codable, Equatable {
    case available
    case offlineUnavailable
    case authorizationDenied
    case limitedScopeHidden
    case missing
    case unsupported
}

public nonisolated enum FocusSourcePresentation: String, Sendable, Codable, Equatable {
    case photo
    case video
    case canonicalText
    case transcriptText
    case unavailable
}

public nonisolated enum FocusSourceDeletionCapability: String, Sendable, Codable, Equatable {
    case photoLibraryDeletable
    case unavailable
}

public nonisolated struct FocusSourceResolution: Sendable, Equatable {
    public nonisolated let memoryID: UUID
    public nonisolated let sourceType: String
    public nonisolated let contentAvailability: FocusContentAvailability
    public nonisolated let presentation: FocusSourcePresentation
    public nonisolated let sourceDeletionCapability: FocusSourceDeletionCapability

    public nonisolated init(
        memoryID: UUID,
        sourceType: String,
        contentAvailability: FocusContentAvailability,
        presentation: FocusSourcePresentation,
        sourceDeletionCapability: FocusSourceDeletionCapability
    ) {
        self.memoryID = memoryID
        self.sourceType = sourceType
        self.contentAvailability = contentAvailability
        self.presentation = presentation
        self.sourceDeletionCapability = sourceDeletionCapability
    }
}

public nonisolated enum FocusSourceDeletionResult: Sendable, Equatable {
    case deleted
    case retained(SourceDeletionOutcome)
    case pendingRecovery(SourceDeletionOutcome)
}

public nonisolated struct FocusSourceRecoveryResult: Sendable, Equatable {
    public nonisolated let deletedMemoryIDs: [UUID]
    public nonisolated let retainedMemoryIDs: [UUID]
    public nonisolated let pendingMemoryIDs: [UUID]

    public nonisolated init(
        deletedMemoryIDs: [UUID],
        retainedMemoryIDs: [UUID],
        pendingMemoryIDs: [UUID]
    ) {
        self.deletedMemoryIDs = deletedMemoryIDs.sorted { $0.uuidString < $1.uuidString }
        self.retainedMemoryIDs = retainedMemoryIDs.sorted { $0.uuidString < $1.uuidString }
        self.pendingMemoryIDs = pendingMemoryIDs.sorted { $0.uuidString < $1.uuidString }
    }
}

public nonisolated struct PhotoSourceMemoryReference: Sendable, Equatable {
    public nonisolated let memoryID: UUID
    public nonisolated let sourceLocator: String
    public nonisolated let sourceType: String

    public nonisolated init(memoryID: UUID, sourceLocator: String, sourceType: String) {
        self.memoryID = memoryID
        self.sourceLocator = sourceLocator
        self.sourceType = sourceType
    }
}

public nonisolated enum FocusSourceLifecycleError: Error, LocalizedError, Sendable, Equatable {
    case privacyDenied
    case memoryMissing
    case sourceDeletionUnavailable

    public nonisolated var errorDescription: String? {
        switch self {
        case .privacyDenied: "The current privacy policy does not permit this operation."
        case .memoryMissing: "The memory no longer exists."
        case .sourceDeletionUnavailable: "The original source cannot be deleted from Echo."
        }
    }
}

/// Composition-owned coordinator. It never persists PHAsset and never treats visibility loss
/// under limited authorization as proof that PhotoKit deleted an asset.
public actor FocusSourceLifecycleActor {
    private let repository: CanonicalMemoryRepositoryActor
    private let database: DatabaseManager
    private let photoLibrary: any PhotoSourceLifecycleServing
    private let privacyActor: PrivacyActor
    private let pendingOps: PendingOpsActor
    private var activeDeletionMemoryIDs: Set<UUID> = []

    public init(
        repository: CanonicalMemoryRepositoryActor,
        database: DatabaseManager,
        photoLibrary: any PhotoSourceLifecycleServing = RealPhotoLibrary(),
        privacyActor: PrivacyActor,
        pendingOps: PendingOpsActor
    ) {
        self.repository = repository
        self.database = database
        self.photoLibrary = photoLibrary
        self.privacyActor = privacyActor
        self.pendingOps = pendingOps
    }

    public func resolveSource(
        memoryID: UUID,
        traceID: String
    ) async throws -> FocusSourceResolution {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.decision == .allowed else { throw FocusSourceLifecycleError.privacyDenied }
        guard let memory = try await repository.loadMemory(memoryId: memoryID) else {
            throw FocusSourceLifecycleError.memoryMissing
        }
        let sourceCheckpoint = await privacyActor.validate(
            operation: .search,
            traceID: traceID,
            sourceTypes: [memory.sourceType]
        )
        guard sourceCheckpoint.decision == .allowed else {
            return FocusSourceResolution(
                memoryID: memoryID,
                sourceType: memory.sourceType,
                contentAvailability: .authorizationDenied,
                presentation: Self.presentation(for: memory.sourceType),
                sourceDeletionCapability: .unavailable
            )
        }

        switch memory.sourceType {
        case "photo", "video":
            return await resolvePhotoMemory(memory)
        case "voice":
            return FocusSourceResolution(
                memoryID: memoryID,
                sourceType: memory.sourceType,
                contentAvailability: memory.canonicalText == nil ? .missing : .available,
                presentation: .transcriptText,
                sourceDeletionCapability: .unavailable
            )
        case "note", "thirdParty":
            return FocusSourceResolution(
                memoryID: memoryID,
                sourceType: memory.sourceType,
                contentAvailability: memory.canonicalText == nil ? .missing : .available,
                presentation: .canonicalText,
                sourceDeletionCapability: .unavailable
            )
        default:
            return FocusSourceResolution(
                memoryID: memoryID,
                sourceType: memory.sourceType,
                contentAvailability: .unsupported,
                presentation: .unavailable,
                sourceDeletionCapability: .unavailable
            )
        }
    }

    public func deletePhotoLibraryOriginal(
        memoryID: UUID,
        traceID: String
    ) async throws -> FocusSourceDeletionResult {
        let checkpoint = await privacyActor.validate(operation: .delete, traceID: traceID)
        guard checkpoint.decision == .allowed else { throw FocusSourceLifecycleError.privacyDenied }
        guard activeDeletionMemoryIDs.insert(memoryID).inserted else {
            throw FocusSourceLifecycleError.sourceDeletionUnavailable
        }
        defer { activeDeletionMemoryIDs.remove(memoryID) }
        let resolution = try await resolveSource(memoryID: memoryID, traceID: traceID)
        guard resolution.sourceDeletionCapability == .photoLibraryDeletable,
              let memory = try await repository.loadMemory(memoryId: memoryID) else {
            throw FocusSourceLifecycleError.sourceDeletionUnavailable
        }
        _ = try await repository.preparePhotoLibraryDeletion(memoryId: memoryID, traceID: traceID)

        switch await photoLibrary.deleteAsset(assetID: memory.sourceLocator) {
        case .confirmedDeleted:
            _ = try await repository.updatePhotoLibraryDeletion(
                memoryId: memoryID,
                state: .confirmedDeleted,
                outcome: .confirmedDeleted
            )
            _ = try await repository.deleteMemory(
                memoryId: memoryID,
                sourceLocator: memory.sourceLocator,
                sourceType: memory.sourceType,
                writeExcluded: false,
                traceID: traceID
            )
            try? await removePending(memoryID)
            return .deleted

        case .notDeleted(let outcome):
            _ = try await repository.updatePhotoLibraryDeletion(
                memoryId: memoryID, state: .notDeleted, outcome: outcome
            )
            try await writeDeletionAudit(
                memoryID: memoryID,
                sourceType: memory.sourceType,
                traceID: traceID,
                completed: false,
                outcome: outcome
            )
            try await repository.abandonPhotoLibraryDeletion(memoryId: memoryID)
            try? await removePending(memoryID)
            return .retained(outcome)

        case .indeterminate(let outcome):
            _ = try await repository.updatePhotoLibraryDeletion(
                memoryId: memoryID, state: .indeterminate, outcome: outcome
            )
            try await enqueuePending(memoryID: memoryID, outcome: outcome)
            try await writeDeletionAudit(
                memoryID: memoryID,
                sourceType: memory.sourceType,
                traceID: traceID,
                completed: false,
                outcome: outcome
            )
            return .pendingRecovery(outcome)
        }
    }

    /// Launch and foreground recovery share one matrix; only full authorization plus absence confirms deletion.
    public func recoverPendingPhotoLibraryDeletions(
        traceID: String
    ) async throws -> FocusSourceRecoveryResult {
        let checkpoint = await privacyActor.validate(operation: .delete, traceID: traceID)
        guard checkpoint.decision == .allowed else { throw FocusSourceLifecycleError.privacyDenied }
        let allJournals = try await database.loadAllDeletionJournals()
        let journalMemoryIDs = Set(allJournals.map(\.memoryID))
        let journals = allJournals.filter {
            $0.intentKind == .photoLibraryAndEcho
                && !activeDeletionMemoryIDs.contains($0.memoryID)
        }
        var deleted: [UUID] = []
        var retained: [UUID] = []
        var pending: [UUID] = []

        for journal in journals {
            do {
                switch try await recover(journal: journal) {
                case .deleted:
                    Self.appendUnique(journal.memoryID, to: &deleted)
                case .retained:
                    Self.appendUnique(journal.memoryID, to: &retained)
                case .pending:
                    Self.appendUnique(journal.memoryID, to: &pending)
                }
            } catch {
                // A damaged or temporarily unwritable row is L2 for that memory only.
                // Preserve the journal and continue so it cannot starve later recoveries.
                try? await enqueuePending(
                    memoryID: journal.memoryID,
                    outcome: .systemResultUnknown
                )
                Self.appendUnique(journal.memoryID, to: &pending)
            }
        }

        for journal in allJournals where journal.intentKind != .photoLibraryAndEcho {
            guard !activeDeletionMemoryIDs.contains(journal.memoryID) else { continue }
            do {
                _ = try await repository.deleteMemory(
                    memoryId: journal.memoryID,
                    sourceLocator: journal.sourceLocator,
                    sourceType: journal.sourceType,
                    writeExcluded: journal.writeExcluded ?? (journal.intentKind == .echoOnly),
                    traceID: journal.traceID
                )
                try? await removePending(journal.memoryID)
                Self.appendUnique(journal.memoryID, to: &deleted)
            } catch {
                try? await enqueuePending(
                    memoryID: journal.memoryID,
                    outcome: .systemResultUnknown
                )
                Self.appendUnique(journal.memoryID, to: &pending)
            }
        }

        try await reconcileTrackedPhotoSources(
            traceID: traceID,
            excluding: journalMemoryIDs,
            deleted: &deleted,
            pending: &pending
        )
        return FocusSourceRecoveryResult(
            deletedMemoryIDs: deleted,
            retainedMemoryIDs: retained,
            pendingMemoryIDs: pending
        )
    }

    /// Cascade entry point for deletions already confirmed by a trusted PhotoKit change event.
    public func handleConfirmedPhotoLibraryCascade(
        assetID: String,
        sourceType: String,
        traceID: String
    ) async throws -> CascadeDeleteResult {
        let checkpoint = await privacyActor.validate(
            operation: .delete, traceID: traceID, sourceTypes: [sourceType]
        )
        guard checkpoint.decision == .allowed else { throw FocusSourceLifecycleError.privacyDenied }
        guard sourceType == "photo" || sourceType == "video" else {
            throw FocusSourceLifecycleError.sourceDeletionUnavailable
        }
        return try await repository.cascadeDeleteFromOriginal(
            assetId: assetID, sourceType: sourceType, traceID: traceID
        )
    }

    private func resolvePhotoMemory(_ memory: Memory) async -> FocusSourceResolution {
        let (access, snapshot) = await photoLibraryEvidence(assetID: memory.sourceLocator)
        guard access == .authorized || access == .limited else {
            return FocusSourceResolution(
                memoryID: memory.memoryId,
                sourceType: memory.sourceType,
                contentAvailability: .authorizationDenied,
                presentation: Self.presentation(for: memory.sourceType),
                sourceDeletionCapability: .unavailable
            )
        }
        guard let snapshot else {
            return FocusSourceResolution(
                memoryID: memory.memoryId,
                sourceType: memory.sourceType,
                contentAvailability: access == .limited ? .limitedScopeHidden : .missing,
                presentation: Self.presentation(for: memory.sourceType),
                sourceDeletionCapability: .unavailable
            )
        }
        return FocusSourceResolution(
            memoryID: memory.memoryId,
            sourceType: memory.sourceType,
            contentAvailability: snapshot.isLocallyAvailable ? .available : .offlineUnavailable,
            presentation: snapshot.mediaType == .video ? .video : .photo,
            sourceDeletionCapability: snapshot.canDelete ? .photoLibraryDeletable : .unavailable
        )
    }

    private enum RecoveryDisposition {
        case deleted
        case retained
        case pending
    }

    private struct PhotoSourceKey: Hashable {
        let sourceLocator: String
        let sourceType: String
    }

    private func recover(journal: MemoryDeletionJournal) async throws -> RecoveryDisposition {
        if journal.sourceDeletionState == .confirmedDeleted {
            _ = try await repository.deleteMemory(
                memoryId: journal.memoryID, writeExcluded: false, traceID: journal.traceID
            )
            try? await removePending(journal.memoryID)
            return .deleted
        }
        guard let locator = journal.sourceLocator else {
            _ = try await repository.updatePhotoLibraryDeletion(
                memoryId: journal.memoryID,
                state: .indeterminate,
                outcome: .sourceUnavailable
            )
            try await enqueuePending(memoryID: journal.memoryID, outcome: .sourceUnavailable)
            return .pending
        }

        let (access, snapshot) = await photoLibraryEvidence(assetID: locator)
        switch (access, snapshot) {
        case (.authorized, .none):
            _ = try await repository.updatePhotoLibraryDeletion(
                memoryId: journal.memoryID,
                state: .confirmedDeleted,
                outcome: .reconciledAbsent
            )
            _ = try await repository.deleteMemory(
                memoryId: journal.memoryID, writeExcluded: false, traceID: journal.traceID
            )
            try? await removePending(journal.memoryID)
            return .deleted

        case (.authorized, .some), (.limited, .some):
            _ = try await repository.updatePhotoLibraryDeletion(
                memoryId: journal.memoryID,
                state: .notDeleted,
                outcome: .assetVisible
            )
            try await repository.abandonPhotoLibraryDeletion(memoryId: journal.memoryID)
            try? await removePending(journal.memoryID)
            return .retained

        case (.limited, .none):
            _ = try await repository.updatePhotoLibraryDeletion(
                memoryId: journal.memoryID,
                state: .indeterminate,
                outcome: .limitedScopeHidden
            )
            try await enqueuePending(memoryID: journal.memoryID, outcome: .limitedScopeHidden)
            return .pending

        case (.denied, _), (.notDetermined, _):
            _ = try await repository.updatePhotoLibraryDeletion(
                memoryId: journal.memoryID,
                state: .indeterminate,
                outcome: .authorizationDenied
            )
            try await enqueuePending(memoryID: journal.memoryID, outcome: .authorizationDenied)
            return .pending

        case (.restricted, _):
            _ = try await repository.updatePhotoLibraryDeletion(
                memoryId: journal.memoryID,
                state: .indeterminate,
                outcome: .accessRestricted
            )
            try await enqueuePending(memoryID: journal.memoryID, outcome: .accessRestricted)
            return .pending
        }
    }

    private func reconcileTrackedPhotoSources(
        traceID: String,
        excluding journalMemoryIDs: Set<UUID>,
        deleted: inout [UUID],
        pending: inout [UUID]
    ) async throws {
        guard await photoLibrary.currentAccess() == .authorized else { return }
        let references = try await repository.loadPhotoSourceReferences()
        let trackedAssetIDs = Set(references.map(\.sourceLocator))
        let visibleAssetIDs = await photoLibrary.visibleAssetIDs(trackedAssetIDs: trackedAssetIDs)
        // The full-scope set is deletion evidence only if authorization is still full
        // after enumeration; a concurrent downgrade must fail closed.
        guard await photoLibrary.currentAccess() == .authorized else { return }
        let groups = Dictionary(grouping: references) {
            PhotoSourceKey(sourceLocator: $0.sourceLocator, sourceType: $0.sourceType)
        }
        for (key, group) in groups.sorted(by: {
            ($0.key.sourceType, $0.key.sourceLocator) < ($1.key.sourceType, $1.key.sourceLocator)
        }) {
            let candidates = group.filter {
                !journalMemoryIDs.contains($0.memoryID)
                    && !activeDeletionMemoryIDs.contains($0.memoryID)
            }
            guard !candidates.isEmpty else { continue }
            guard !visibleAssetIDs.contains(key.sourceLocator) else { continue }
            let sourceCheckpoint = await privacyActor.validate(
                operation: .delete,
                traceID: traceID,
                sourceTypes: [key.sourceType]
            )
            guard sourceCheckpoint.decision == .allowed else { continue }

            let reserved = candidates.filter {
                activeDeletionMemoryIDs.insert($0.memoryID).inserted
            }
            guard reserved.count == candidates.count else {
                reserved.forEach { activeDeletionMemoryIDs.remove($0.memoryID) }
                continue
            }
            defer { reserved.forEach { activeDeletionMemoryIDs.remove($0.memoryID) } }
            do {
                let result = try await repository.cascadeDeleteFromOriginal(
                    assetId: key.sourceLocator,
                    sourceType: key.sourceType,
                    traceID: traceID
                )
                if result.deletedCount > 0 {
                    candidates.forEach { Self.appendUnique($0.memoryID, to: &deleted) }
                }
            } catch {
                for candidate in candidates {
                    try? await enqueuePending(
                        memoryID: candidate.memoryID,
                        outcome: .systemResultUnknown
                    )
                    Self.appendUnique(candidate.memoryID, to: &pending)
                }
            }
        }
    }

    /// Rechecks authorization after a nil fetch so revocation cannot be mistaken for absence.
    private func photoLibraryEvidence(
        assetID: String
    ) async -> (PhotoAccess, PhotoSourceSnapshot?) {
        let accessBeforeFetch = await photoLibrary.currentAccess()
        guard accessBeforeFetch == .authorized || accessBeforeFetch == .limited else {
            return (accessBeforeFetch, nil)
        }
        let snapshot = await photoLibrary.assetSnapshot(assetID: assetID)
        guard snapshot == nil else { return (accessBeforeFetch, snapshot) }
        return (await photoLibrary.currentAccess(), nil)
    }

    private nonisolated static func appendUnique(_ memoryID: UUID, to values: inout [UUID]) {
        guard !values.contains(memoryID) else { return }
        values.append(memoryID)
    }

    private nonisolated static func presentation(for sourceType: String) -> FocusSourcePresentation {
        switch sourceType {
        case "photo": .photo
        case "video": .video
        case "voice": .transcriptText
        case "note", "thirdParty": .canonicalText
        default: .unavailable
        }
    }

    private func enqueuePending(memoryID: UUID, outcome: SourceDeletionOutcome) async throws {
        let operationID = pendingOperationID(memoryID)
        if try await pendingOps.load(operationId: operationID) != nil {
            try await pendingOps.updateRetry(operationId: operationID, lastError: outcome.rawValue)
            return
        }
        let payload = try JSONEncoder().encode([
            "memoryIdDigest": AuditContentHasher.sha256Hex(memoryID.uuidString.lowercased()),
            "outcome": outcome.rawValue,
        ])
        try await pendingOps.add(operation: PendingOperation(
            operationId: operationID,
            operationType: "photoSourceDeletionRecovery",
            retryCount: 0,
            parameters: payload,
            lastError: outcome.rawValue
        ))
    }

    private func removePending(_ memoryID: UUID) async throws {
        _ = try await pendingOps.remove(operationId: pendingOperationID(memoryID))
    }

    private nonisolated func pendingOperationID(_ memoryID: UUID) -> String {
        let digest = AuditContentHasher.sha256Hex(memoryID.uuidString.lowercased())
        return "photo-delete-recovery-\(digest.prefix(24))"
    }

    private func writeDeletionAudit(
        memoryID: UUID,
        sourceType: String,
        traceID: String,
        completed: Bool,
        outcome: SourceDeletionOutcome
    ) async throws {
        let policy = await privacyActor.getPolicy()
        try await privacyActor.writeAuditLog(
            eventType: .memoryDeleted,
            traceID: traceID,
            policyVersion: policy.policyVersion,
            success: completed,
            sourceType: sourceType,
            excludedWritten: false,
            subjectKind: "memory",
            subjectHash: AuditContentHasher.sha256Hex(memoryID.uuidString.lowercased()),
            preservedOriginal: !completed,
            sourceDeletionRequested: true,
            sourceDeletionCompleted: completed,
            sourceDeletionOutcome: outcome.rawValue
        )
    }
}
