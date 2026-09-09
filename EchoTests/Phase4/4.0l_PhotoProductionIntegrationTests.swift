// Task 4.0l; US-ING-004 AC-6/7/8 and US-SYN-003 AC-7.
// Real PhotoKit, SigLIP, bundled visual/text models and production composition.
// Synthetic pixels only; no handwritten description or fixture generator.
import Foundation
import Photos
import Synchronization
import Testing

@testable import Echo

@Suite("4.0l Photo Production", .serialized)
struct PhotoProductionIntegrationTests {
    @Test("AC-7: a real uncaptioned PhotoKit asset reaches grounded creation")
    @MainActor func test_AC7_photoToCreation() async throws {
        try await withSyntheticAsset(duplicateSync: false)
    }

    @Test("AC-8: duplicate source notifications retain queued photo preparation")
    @MainActor func test_AC8_queuedSyncPreservesIntent() async throws {
        try await withSyntheticAsset(duplicateSync: true)
    }

    @MainActor private func withSyntheticAsset(duplicateSync: Bool) async throws {
        let access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        try #require(access == .authorized)
        let pixels = try PhotoRuntimeTests.image()
        let identifier = Mutex<String?>(nil)
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            let request = PHAssetCreationRequest.forAsset()
            request.creationDate = Date(timeIntervalSince1970: 1_764_892_800)
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = "public.tiff"
            request.addResource(with: .photo, data: pixels, options: options)
            identifier.withLock { $0 = request.placeholderForCreatedAsset?.localIdentifier }
        }
        let assetID = try #require(identifier.withLock { $0 })
        do { try await run(assetID: assetID, duplicateSync: duplicateSync) } catch {
            try await removeSyntheticAsset(assetID)
            throw error
        }
        try await removeSyntheticAsset(assetID)
    }

    @MainActor private func run(assetID: String, duplicateSync: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("photo-production-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = DatabaseManager(databaseURL: directory.appendingPathComponent("test.sqlite"))
        try await db.open()
        let privacy = PrivacyActor(db: db)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["photo"]))
        let consent = ConsentStoreActor(db: db, privacyActor: privacy)
        try await consent.acceptConsent(consentVersion: 1, policyVersion: 1)
        await privacy.enableConsentEnforcement(consentStore: consent)
        let registry = GenerationRegistryActor(db: db, storeDirectory: directory.appendingPathComponent("indexes"))
        try await registry.ensureInitialGenerations()
        let progress = ProgressActor(db: db)
        let queue = TaskQueueActor(progressActor: progress)
        let composition = AppComposition(
            databaseManager: db,
            privacyActor: privacy,
            consentStore: consent,
            generationRegistry: registry,
            taskQueue: queue,
            progressActor: progress
        )
        let route = try #require(await registry.loadActiveRoute())
        let store = try #require(await registry.vectorStore(for: route.textGeneration))
        let ingest = IngestPipeline(
            embedder: composition.textEmbedder,
            privacyActor: privacy,
            vectorStore: store,
            excludedAssets: composition.excludedAssetsActor,
            canonicalRepository: composition.canonicalRepository,
            generationRegistry: registry,
            taskQueue: queue,
            progressActor: progress,
            visionEmbedder: composition.visionEmbedder
        )
        let sync = SyncPipeline(
            embedder: composition.visionEmbedder,
            privacyActor: privacy,
            vectorStore: store,
            excludedAssets: composition.excludedAssetsActor,
            progressActor: progress,
            canonicalRepository: composition.canonicalRepository,
            generationRegistry: registry,
            photoPreparation: composition.photoUnderstandingActor
        )
        let id = CanonicalMemoryRepositoryActor.deterministicID(sourceLocator: assetID, sourceType: "photo")
        if duplicateSync {
            try await queue.enqueueAndWait(
                TaskQueueActor.QueuedJob(taskId: "duplicate-photo-sync", taskType: .dataSourceSync, totalCount: 2) { _ in
                    for index in 0..<2 {
                        let result = try await sync.sync(changes: [
                            ChangeEvent(assetId: assetID, source: .photo, changeType: .added)
                        ])
                        try #require(result.failedCount == 0)
                        if index == 0 {
                            try #require(try await db.photoJobRow(memoryID: id) == nil)
                            _ = try await composition.photoUnderstandingActor.schedule(memoryID: id, traceID: "selected-photo")
                        }
                    }
                    try #require(try await db.photoJobRow(memoryID: id)?["state"]?.stringValue == "queued")
                }
            )
        } else {
            _ = try await ingest.ingestProductionPhoto(assetId: assetID, taskID: "photo-production-ingest")
            try #require(try await db.photoJobRow(memoryID: id) == nil)
            _ = try await composition.photoUnderstandingActor.schedule(memoryID: id, traceID: "selected-photo")
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 120
        while !(await queue.ownedTaskIDs()).isEmpty, ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(
            try await composition.photoUnderstandingActor.status(memoryID: id, traceID: "photo-production-ready")
                == .ready
        )
        let source = try #require(await composition.canonicalRepository.loadCreationSource(memoryID: id))
        #expect(!(source.text ?? "").isEmpty)
        #expect(try await composition.canonicalRepository.loadMemory(memoryId: id)?.canonicalText == nil)
        try await queue.enqueueAndWait(
            TaskQueueActor.QueuedJob(
                taskId: "photo-production-sync",
                taskType: .dataSourceSync,
                totalCount: 1
            ) { _ in
                let result = try await sync.sync(changes: [
                    ChangeEvent(assetId: assetID, source: .photo, changeType: .modified)
                ])
                #expect(result.failedCount == 0)
            }
        )
        #expect(
            try await composition.canonicalRepository.loadMemory(memoryId: id)?.createdAt.timeIntervalSince1970
                == 1_764_892_800
        )
        #expect(
            try await composition.photoUnderstandingActor.status(memoryID: id, traceID: "unchanged-photo-stays-ready")
                == .ready
        )
        #expect(try await db.executeQuery(sql: "SELECT 1 FROM MemoryUserEdit", bindings: []).isEmpty)
        let output = try await composition.creativePipeline.generate(
            template: .report,
            sources: [source],
            traceID: "photo-production-create"
        )
        #expect(!output.didFallback)
        #expect(output.citationCount > 0)
        #expect(output.paragraphs.allSatisfy { LanguageAligner.bodyMatches($0.text, language: "en-US") })
        let anchor = try #require(output.paragraphs.flatMap(\.anchors).first)
        #expect(
            try await composition.creationExportCoordinator.authorizeNavigation(
                anchor: anchor,
                traceID: "photo-navigation"
            ) == id
        )
        _ = try await composition.creationExportCoordinator.authorize(output: output, traceID: "photo-copy-export")
        let baseline = Date(timeIntervalSince1970: 1_764_547_200)
        try await composition.narrativeReportActor.setEnabled(false, for: .year, at: baseline)
        try await composition.narrativeReportActor.setEnabled(false, for: .month, at: baseline)
        try await composition.narrativeReportActor.setEnabled(true, for: .month, at: baseline)
        let scheduled = try await composition.narrativeReportActor.scanAndEnqueue(
            at: Date(timeIntervalSince1970: 1_768_435_200),
            calendarContext: .init(timeZoneIdentifier: "UTC"),
            trigger: .userInitiated
        )
        guard case .enqueued(let reportTaskID, _) = scheduled else {
            Issue.record("The photo report did not enqueue: \(scheduled)")
            return
        }
        let reportDeadline = ProcessInfo.processInfo.systemUptime + 180
        while await queue.ownedTaskIDs().contains(reportTaskID), ProcessInfo.processInfo.systemUptime < reportDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let reports = try await composition.narrativeReportActor.listReports()
        #expect(reports.count == 1)
        #expect(
            try await db.executeQuery(
                sql: "SELECT 1 FROM NarrativeReportSource WHERE memoryId = ?",
                bindings: [.text(id.uuidString)]
            ).count == 1
        )
        #expect(try await db.executeQuery(sql: "SELECT 1 FROM PendingOperations", bindings: []).isEmpty)
        let evidence: [String: Any] = [
            "scope": "PhotoKit-production-ingest-real-model-creation-and-export-authorization",
            "caption": source.text ?? "", "paragraphs": output.paragraphs.map(\.text),
            "citationCount": output.citationCount,
            "handwrittenDescription": false, "systemSharePresented": false,
            "persistedMonthlyReports": reports.count,
        ]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(
                to: FileManager.default.temporaryDirectory.appendingPathComponent("echo-photo-production-evidence.json")
            )
        await db.close()
    }

    private func removeSyntheticAsset(_ identifier: String) async throws {
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil))
        }
    }
}
