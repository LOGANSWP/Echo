// ==========================================
// File: 4.0h_FocusSourceLifecycleTests.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md → US-AWK-005, US-PRV-004/007
// Task: 4.0h - Real source resolution and PhotoKit deletion saga
// AC coverage: typed source facets, PhotoKit capability gate, confirmed-delete D-005 gate,
//              recovery matrix, cascade cleanup notice, structured hash-only audit
// Architecture: ADR-019; AGENTS.md R-001/R-005/R-006 and D-002/D-003/D-005
// Generated: 2026-09-05
// ==========================================

import Foundation
import Testing
@testable import Echo

private actor FocusSourcePhotoLibraryFake: PhotoSourceLifecycleServing {
    private var access: PhotoAccess
    private var snapshots: [String: PhotoSourceSnapshot]
    private var deletionResult: PhotoLibraryDeletionResult
    private var deleteCalls: [String] = []

    init(
        access: PhotoAccess,
        snapshots: [String: PhotoSourceSnapshot] = [:],
        deletionResult: PhotoLibraryDeletionResult = .confirmedDeleted
    ) {
        self.access = access
        self.snapshots = snapshots
        self.deletionResult = deletionResult
    }

    func currentAccess() async -> PhotoAccess { access }

    func assetSnapshot(assetID: String) async -> PhotoSourceSnapshot? {
        snapshots[assetID]
    }

    func deleteAsset(assetID: String) async -> PhotoLibraryDeletionResult {
        deleteCalls.append(assetID)
        return deletionResult
    }

    func setAccess(_ value: PhotoAccess) { access = value }
    func setSnapshot(_ value: PhotoSourceSnapshot?, for assetID: String) { snapshots[assetID] = value }
    func setDeletionResult(_ value: PhotoLibraryDeletionResult) { deletionResult = value }
    func deletionCalls() -> [String] { deleteCalls }
}

private actor FocusSourceLifecycleServiceFake: FocusSourceLifecycleServicing {
    private let resolution: FocusSourceResolution
    private let deletionResult: FocusSourceDeletionResult
    private var deleteCalls = 0

    init(resolution: FocusSourceResolution, deletionResult: FocusSourceDeletionResult) {
        self.resolution = resolution
        self.deletionResult = deletionResult
    }

    func resolveSource(memoryID: UUID, traceID: String) async throws -> FocusSourceResolution {
        resolution
    }

    func deletePhotoLibraryOriginal(
        memoryID: UUID,
        traceID: String
    ) async throws -> FocusSourceDeletionResult {
        deleteCalls += 1
        return deletionResult
    }

    func deletionCallCount() -> Int { deleteCalls }
}

private actor FocusMemoryDetailRepositoryFake: MemoryDetailRepository {
    private let memory: Memory

    init(memory: Memory) {
        self.memory = memory
    }

    func loadMemory(memoryId: UUID) async throws -> Memory? {
        memory.memoryId == memoryId ? memory : nil
    }

    func deleteMemory(
        memoryId: UUID,
        sourceLocator: String?,
        sourceType: String?,
        writeExcluded: Bool,
        traceID: String
    ) async throws -> Bool {
        memory.memoryId == memoryId
    }
}

@Suite("FocusSourceLifecycleTests", .serialized)
@MainActor
struct FocusSourceLifecycleTests {
    private struct System {
        let db: DatabaseManager
        let privacy: PrivacyActor
        let excluded: ExcludedAssetsActor
        let pending: PendingOpsActor
        let repository: CanonicalMemoryRepositoryActor
        let library: FocusSourcePhotoLibraryFake
        let lifecycle: FocusSourceLifecycleActor
    }

    private func makeSystem(
        access: PhotoAccess = .authorized,
        snapshots: [String: PhotoSourceSnapshot] = [:],
        deletionResult: PhotoLibraryDeletionResult = .confirmedDeleted
    ) async throws -> System {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-4.0h-\(UUID().uuidString).sqlite")
        let db = DatabaseManager(databaseURL: url)
        try await db.open()
        let privacy = PrivacyActor(
            db: db,
            policy: UserPolicy(
                preferredLanguage: "en-US",
                authorizedSourceTypes: ["photo", "video", "note", "voice", "thirdParty"],
                policyVersion: 40
            )
        )
        let excluded = ExcludedAssetsActor(db: db, privacyActor: privacy)
        let pending = PendingOpsActor(db: db)
        let registry = GenerationRegistryActor(db: db)
        let repository = CanonicalMemoryRepositoryActor(
            db: db,
            generationRegistry: registry,
            excludedAssets: excluded,
            privacyActor: privacy
        )
        let library = FocusSourcePhotoLibraryFake(
            access: access,
            snapshots: snapshots,
            deletionResult: deletionResult
        )
        let lifecycle = FocusSourceLifecycleActor(
            repository: repository,
            database: db,
            photoLibrary: library,
            privacyActor: privacy,
            pendingOps: pending
        )
        return System(
            db: db,
            privacy: privacy,
            excluded: excluded,
            pending: pending,
            repository: repository,
            library: library,
            lifecycle: lifecycle
        )
    }

    private func seedMemory(
        _ db: DatabaseManager,
        id: UUID = UUID(),
        sourceLocator: String,
        sourceType: String,
        text: String? = "source text"
    ) async throws -> UUID {
        let now = Date().timeIntervalSince1970
        try await db.executeWrite(
            sql: """
                INSERT INTO Memory
                    (memoryId, sourceLocator, canonicalText, sourceType, createdAt, updatedAt,
                     recoverability, originalTimestamp, userEdited, userLocked)
                VALUES (?, ?, ?, ?, ?, ?, 'full', NULL, 0, 0)
                """,
            bindings: [
                .text(id.uuidString), .text(sourceLocator), text.map(DBBinding.text) ?? .null,
                .text(sourceType), .double(now), .double(now),
            ]
        )
        if let text {
            try await db.executeWrite(
                sql: "INSERT INTO MemoryFTS (memoryId, canonicalText, sourceType) VALUES (?, ?, ?)",
                bindings: [.text(id.uuidString), .text(text), .text(sourceType)]
            )
        }
        return id
    }

    @Test("AC-1: source resolution returns independent availability, presentation, and deletion facets")
    func test_AC1_typedSourceResolution() async throws {
        let assetID = "asset-visible"
        let system = try await makeSystem(snapshots: [
            assetID: PhotoSourceSnapshot(
                assetID: assetID,
                mediaType: .photo,
                isLocallyAvailable: false,
                canDelete: true
            ),
        ])
        let photoID = try await seedMemory(
            system.db, sourceLocator: assetID, sourceType: "photo"
        )
        let noteID = try await seedMemory(
            system.db, sourceLocator: "share-note", sourceType: "note"
        )
        let voiceID = try await seedMemory(
            system.db, sourceLocator: "share-voice", sourceType: "voice", text: "transcript"
        )

        let photo = try await system.lifecycle.resolveSource(
            memoryID: photoID, traceID: "resolve-photo"
        )
        #expect(photo.contentAvailability == .offlineUnavailable)
        #expect(photo.presentation == .photo)
        #expect(photo.sourceDeletionCapability == .photoLibraryDeletable)

        let note = try await system.lifecycle.resolveSource(
            memoryID: noteID, traceID: "resolve-note"
        )
        #expect(note.contentAvailability == .available)
        #expect(note.presentation == .canonicalText)
        #expect(note.sourceDeletionCapability == .unavailable)

        let voice = try await system.lifecycle.resolveSource(
            memoryID: voiceID, traceID: "resolve-voice"
        )
        #expect(voice.contentAvailability == .available)
        #expect(voice.presentation == .transcriptText)
        #expect(voice.sourceDeletionCapability == .unavailable)
        #expect(await system.library.deletionCalls().isEmpty)
    }

    @Test("AC-2: only a confirmed PhotoKit deletion unlocks D-005 and never writes ExcludedAssets")
    func test_AC2_confirmedDeletionUnlocksD005() async throws {
        let assetID = "asset-delete-success"
        let system = try await makeSystem(snapshots: [
            assetID: PhotoSourceSnapshot(
                assetID: assetID, mediaType: .photo, isLocallyAvailable: true, canDelete: true
            ),
        ])
        let memoryID = try await seedMemory(
            system.db, sourceLocator: assetID, sourceType: "photo"
        )

        let result = try await system.lifecycle.deletePhotoLibraryOriginal(
            memoryID: memoryID, traceID: "delete-confirmed"
        )

        #expect(result == .deleted)
        #expect(try await system.repository.loadMemory(memoryId: memoryID) == nil)
        #expect(try await system.excluded.contains(assetId: assetID) == false)
        #expect(try await system.db.loadDeletionJournals(memoryId: memoryID).isEmpty)
        let rows = try await system.db.executeQuery(
            sql: "SELECT * FROM AuditLog WHERE eventType = 'memoryDeleted' AND traceID = ?",
            bindings: [.text("delete-confirmed")]
        )
        let row = try #require(rows.last)
        #expect(row["preservedOriginal"]?.intValue == 0)
        #expect(row["sourceDeletionRequested"]?.intValue == 1)
        #expect(row["sourceDeletionCompleted"]?.intValue == 1)
        #expect(row["sourceDeletionOutcome"]?.stringValue == "confirmedDeleted")
        #expect(row["excludedWritten"]?.intValue == 0)
    }

    @Test("AC-2: cancellation closes the intent and retains all Echo data")
    func test_AC2_cancelledDeletionRetainsMemory() async throws {
        let assetID = "asset-delete-cancelled"
        let system = try await makeSystem(
            snapshots: [
                assetID: PhotoSourceSnapshot(
                    assetID: assetID, mediaType: .photo, isLocallyAvailable: true, canDelete: true
                ),
            ],
            deletionResult: .notDeleted(.userCancelled)
        )
        let memoryID = try await seedMemory(
            system.db, sourceLocator: assetID, sourceType: "photo"
        )

        let result = try await system.lifecycle.deletePhotoLibraryOriginal(
            memoryID: memoryID, traceID: "delete-cancelled"
        )

        #expect(result == .retained(.userCancelled))
        #expect(try await system.repository.loadMemory(memoryId: memoryID) != nil)
        #expect(try await system.db.loadDeletionJournals(memoryId: memoryID).isEmpty)
        let rows = try await system.db.executeQuery(
            sql: "SELECT * FROM AuditLog WHERE eventType = 'memoryDeleted' AND traceID = ?",
            bindings: [.text("delete-cancelled")]
        )
        let row = try #require(rows.last)
        #expect(row["preservedOriginal"]?.intValue == 1)
        #expect(row["sourceDeletionRequested"]?.intValue == 1)
        #expect(row["sourceDeletionCompleted"]?.intValue == 0)
        #expect(row["sourceDeletionOutcome"]?.stringValue == "userCancelled")
    }

    @Test("AC-3: limited-hidden recovery is indeterminate, preserves data, and creates L2 work")
    func test_AC3_limitedHiddenRecoveryIsFailClosed() async throws {
        let assetID = "asset-limited-hidden"
        let system = try await makeSystem(
            access: .authorized,
            snapshots: [
                assetID: PhotoSourceSnapshot(
                    assetID: assetID, mediaType: .video, isLocallyAvailable: true, canDelete: true
                ),
            ],
            deletionResult: .indeterminate(.systemResultUnknown)
        )
        let memoryID = try await seedMemory(
            system.db, sourceLocator: assetID, sourceType: "video"
        )
        #expect(try await system.lifecycle.deletePhotoLibraryOriginal(
            memoryID: memoryID, traceID: "delete-unknown"
        ) == .pendingRecovery(.systemResultUnknown))

        await system.library.setAccess(.limited)
        await system.library.setSnapshot(nil, for: assetID)
        let recovery = try await system.lifecycle.recoverPendingPhotoLibraryDeletions(
            traceID: "recover-limited"
        )

        #expect(recovery.pendingMemoryIDs == [memoryID])
        #expect(recovery.deletedMemoryIDs.isEmpty)
        #expect(try await system.repository.loadMemory(memoryId: memoryID) != nil)
        #expect(try await system.db.loadDeletionJournals(memoryId: memoryID).first?.sourceDeletionState == .indeterminate)
        let pending = try await system.pending.listAll()
        #expect(pending.contains { $0.operationType == "photoSourceDeletionRecovery" })
        #expect(!pending.description.contains(assetID))
    }

    @Test("AC-3: fully authorized absence reconciles as confirmed and resumes D-005")
    func test_AC3_authorizedMissingRecoveryCompletesDeletion() async throws {
        let assetID = "asset-missing-after-restart"
        let system = try await makeSystem(
            access: .authorized,
            snapshots: [
                assetID: PhotoSourceSnapshot(
                    assetID: assetID, mediaType: .photo, isLocallyAvailable: true, canDelete: true
                ),
            ],
            deletionResult: .indeterminate(.systemResultUnknown)
        )
        let memoryID = try await seedMemory(
            system.db, sourceLocator: assetID, sourceType: "photo"
        )
        _ = try await system.lifecycle.deletePhotoLibraryOriginal(
            memoryID: memoryID, traceID: "delete-before-restart"
        )
        await system.library.setSnapshot(nil, for: assetID)

        let recovery = try await system.lifecycle.recoverPendingPhotoLibraryDeletions(
            traceID: "recover-authorized"
        )

        #expect(recovery.deletedMemoryIDs == [memoryID])
        #expect(recovery.pendingMemoryIDs.isEmpty)
        #expect(try await system.repository.loadMemory(memoryId: memoryID) == nil)
        #expect(try await system.db.loadDeletionJournals(memoryId: memoryID).isEmpty)
    }

    @Test("AC-4: external cascade cleanup is pending until the notice is actually presented")
    func test_AC4_cascadeCleanupNoticeIsTruthful() async throws {
        let assetID = "asset-cascade"
        let system = try await makeSystem()
        _ = try await seedMemory(
            system.db, sourceLocator: assetID, sourceType: "photo"
        )
        try await system.excluded.add(
            assetId: assetID, sourceType: "photo", traceID: "exclude-before-cascade"
        )

        let cascade = try await system.lifecycle.handleConfirmedPhotoLibraryCascade(
            assetID: assetID, sourceType: "photo", traceID: "cascade"
        )
        #expect(cascade.deletedCount == 1)
        #expect(cascade.excludedAutoCleaned)
        #expect(try await system.excluded.contains(assetId: assetID) == false)
        #expect(try await system.excluded.pendingCleanupNoticeCount() == 1)
        let before = try await system.db.executeQuery(
            sql: "SELECT * FROM AuditLog WHERE eventType = 'cascadeDeleteFromOriginal' AND traceID = ?",
            bindings: [.text("cascade")]
        )
        #expect(before.last?["excludedAutoCleaned"]?.intValue == 1)
        #expect(before.last?["userNotified"]?.intValue == 0)

        #expect(try await system.excluded.markCleanupNoticesPresented(traceID: "notice-presented") == 1)
        #expect(try await system.excluded.pendingCleanupNoticeCount() == 0)
        let presented = try await system.db.executeQuery(
            sql: "SELECT * FROM AuditLog WHERE eventType = 'excludedAutoCleaned' AND traceID = ?",
            bindings: [.text("notice-presented")]
        )
        #expect(presented.last?["userNotified"]?.intValue == 1)
    }

    @Test("AC-5: one memory has one active deletion intent with an orthogonal external-result state")
    func test_AC5_singleActiveDeletionIntent() async throws {
        let assetID = "asset-one-intent"
        let system = try await makeSystem(snapshots: [
            assetID: PhotoSourceSnapshot(
                assetID: assetID, mediaType: .photo, isLocallyAvailable: true, canDelete: true
            ),
        ])
        let memoryID = try await seedMemory(
            system.db, sourceLocator: assetID, sourceType: "photo"
        )

        let first = try await system.repository.preparePhotoLibraryDeletion(
            memoryId: memoryID, traceID: "prepare-one"
        )
        let second = try await system.repository.preparePhotoLibraryDeletion(
            memoryId: memoryID, traceID: "prepare-two"
        )

        #expect(first.operationID == second.operationID)
        #expect(first.intentKind == .photoLibraryAndEcho)
        #expect(first.sourceDeletionState == .prepared)
        #expect(try await system.db.loadDeletionJournals(memoryId: memoryID).count == 1)
        let error = await #expect(throws: CanonicalRepositoryError.self) {
            try await system.repository.deleteMemory(
                memoryId: memoryID, writeExcluded: false, traceID: "must-not-delete"
            )
        }
        guard case .externalDeletionNotConfirmed(let blockedID) = error else {
            Issue.record("Expected the external deletion confirmation gate")
            return
        }
        #expect(blockedID == memoryID.uuidString)
        #expect(try await system.repository.loadMemory(memoryId: memoryID) != nil)
    }

    @Test("AC-4: PhotoKit removed events bypass exclusion filtering and run the cascade cleanup")
    func test_AC4_syncRemovedEventCleansInvalidExclusion() async throws {
        let assetID = "asset-sync-cascade"
        let system = try await makeSystem()
        let memoryID = try await seedMemory(
            system.db, sourceLocator: assetID, sourceType: "photo"
        )
        try await system.excluded.add(
            assetId: assetID, sourceType: "photo", traceID: "exclude-sync-cascade"
        )
        let pipeline = SyncPipeline(
            embedder: StubEmbedder(),
            privacyActor: system.privacy,
            vectorStore: VectorStoreActor(dimension: 512),
            excludedAssets: system.excluded,
            canonicalRepository: system.repository,
            generationRegistry: GenerationRegistryActor(db: system.db)
        )

        let result = try await pipeline.sync(
            changes: [ChangeEvent(assetId: assetID, source: .photo, changeType: .removed)],
            traceID: "sync-cascade"
        )

        #expect(result.replacedCount == 1)
        #expect(result.failedCount == 0)
        #expect(try await system.repository.loadMemory(memoryId: memoryID) == nil)
        #expect(try await system.excluded.contains(assetId: assetID) == false)
        #expect(try await system.excluded.pendingCleanupNoticeCount() == 1)
    }

    @Test("AC-1/2: Detail maps live source facets and routes confirmed original deletion")
    func test_AC1_AC2_detailUsesLiveSourceLifecycle() async throws {
        let memoryID = UUID()
        let memory = Memory(
            memoryId: memoryID,
            sourceLocator: "asset-detail",
            canonicalText: "Detail text",
            sourceType: "photo"
        )
        let lifecycle = FocusSourceLifecycleServiceFake(
            resolution: FocusSourceResolution(
                memoryID: memoryID,
                sourceType: "photo",
                contentAvailability: .available,
                presentation: .photo,
                sourceDeletionCapability: .photoLibraryDeletable
            ),
            deletionResult: .deleted
        )
        let viewModel = MemoryDetailViewModel(
            translationService: FixtureTranslationService(),
            translationCache: TranslationCache(),
            canonicalRepository: FocusMemoryDetailRepositoryFake(memory: memory),
            sourceLifecycleService: lifecycle
        )

        viewModel.load(memoryId: memoryID)
        for _ in 0..<100 where viewModel.viewState == .loading {
            await Task.yield()
        }
        #expect(viewModel.viewState == .completed)
        #expect(viewModel.memory?.contentAvailability == .available)
        #expect(viewModel.canDeleteOriginal)

        viewModel.deleteOriginal()
        for _ in 0..<100 where !viewModel.hasRemovedMemory {
            await Task.yield()
        }
        #expect(viewModel.hasRemovedMemory)
        #expect(viewModel.memory == nil)
        #expect(await lifecycle.deletionCallCount() == 1)
    }

    @Test("AC-4: Excluded Items adapter acknowledges cleanup only through its presentation action")
    func test_AC4_excludedItemsPresentationAdapter() async throws {
        let assetID = "asset-settings-notice"
        let system = try await makeSystem()
        try await system.excluded.add(
            assetId: assetID, sourceType: "photo", traceID: "settings-exclude"
        )
        #expect(try await system.excluded.recordCascadeCleanup(
            assetId: assetID, sourceType: "photo", traceID: "settings-cascade"
        ))
        let viewModel = ExcludedItemsViewModel(excludedAssets: system.excluded)

        await viewModel.load()
        #expect(viewModel.state == .completed(
            pendingCleanupCount: 1,
            wasPresentedThisSession: false
        ))
        await viewModel.markCleanupNoticePresented(visibleCount: 1)
        #expect(viewModel.state == .completed(
            pendingCleanupCount: 1,
            wasPresentedThisSession: true
        ))
        #expect(try await system.excluded.pendingCleanupNoticeCount() == 0)
    }
}
