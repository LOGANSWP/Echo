// ==========================================
// File: 4.0l_PhotoPreparationQueueTests.swift
// Spec: US-ING-004 AC-6/7/8; ADR-025
// Task: 4.0l - Preparation scheduling and source publication contracts
// Evidence: injected unit seams only; real pixel/model validation is separate
// Generated: 2026-09-09
// ==========================================

import Foundation
import Testing

@testable import Echo

private actor PreparationPixelSource: PhotoPixelSourceReading {
    func currentRevision(assetID: String) async throws -> String { "asset-revision-1" }
    func read(assetID: String, expectedRevision: String) async throws -> Data { Data([1, 2, 3]) }
}

private actor PreparationCaptionProvider: PhotoCaptionGenerating {
    private(set) var callCount = 0
    private var held = false
    private var fails = false
    private var defers = false
    func setDeferred(_ value: Bool) { defers = value }
    func hold() { held = true }
    func release(failing: Bool = false) {
        held = false
        fails = failing
    }
    func describe(imageData: Data, traceID: String) async throws -> PhotoCaptionOutput {
        callCount += 1
        while held { try await Task.sleep(for: .milliseconds(10)) }
        if defers { throw NarrativeReportError.resourceDeferred }
        if fails { throw GenerationRuntimeError.outputLimit }
        return PhotoCaptionOutput(text: "A red circle", language: "en-US", outputTokenCount: 4)
    }
}

private actor PreparationOCR: PhotoOCRService {
    func recognizeText(imageData: Data, preferredLanguages: [String], traceID: String) async throws -> OCRDocument? {
        OCRDocument(normalizedText: "OPEN", locale: "en-US", observationCount: 1, contentHash: "ocr-hash")
    }
}

private actor PreparationQueueGate {
    private var held = true
    func release() { held = false }
    func wait() async throws {
        while held { try await Task.sleep(for: .milliseconds(10)) }
    }
}

@Suite("4.0l Photo Preparation Queue", .serialized)
struct PhotoPreparationQueueTests {
    nonisolated enum Interruption: CaseIterable, Sendable {
        case revoked, queuedRevoked, deleted, changed, cancelled, failed
    }

    @Test("AC-8: interrupted inference never publishes stale material", arguments: Interruption.allCases)
    func test_AC8_interruption(_ interruption: Interruption) async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("photo-interrupt-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path.path + suffix) }
        }
        let db = DatabaseManager(databaseURL: path)
        try await db.open()
        let privacy = PrivacyActor(db: db)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["photo"]))
        let progress = ProgressActor(db: db)
        let queue = TaskQueueActor(progressActor: progress)
        let provider = PreparationCaptionProvider()
        await provider.hold()
        let preparation = PhotoUnderstandingActor(
            database: db,
            privacy: privacy,
            queue: queue,
            progress: progress,
            pixelSource: PreparationPixelSource(),
            provider: provider,
            ocr: PreparationOCR()
        )
        let gate = PreparationQueueGate()
        if interruption == .queuedRevoked {
            try await queue.enqueue(
                TaskQueueActor.QueuedJob(
                    taskId: "test-blocker",
                    taskType: .fullIndex,
                    totalCount: 0
                ) { _ in try await gate.wait() }
            )
        }
        let id = UUID()
        let taskID = "photo-understanding-\(id.uuidString.lowercased())"
        try await db.executeWrite(
            sql:
                "INSERT INTO Memory (memoryId, sourceLocator, sourceType, createdAt, updatedAt) VALUES (?, 'photo:test', 'photo', 1, 1)",
            bindings: [.text(id.uuidString)]
        )
        try await db.executeWrite(
            sql: "INSERT INTO Representation VALUES (?, ?, 'visionDense', 'siglip2-v1', 'source-v1')",
            bindings: [.text(UUID().uuidString), .text(id.uuidString)]
        )
        #expect(try await preparation.schedule(memoryID: id, traceID: "interruption"))
        if interruption != .queuedRevoked {
            for _ in 0..<200 {
                if await provider.callCount == 1 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(await provider.callCount == 1)
        }
        switch interruption {
        case .revoked, .queuedRevoked:
            try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: []))

        case .deleted:
            try await db.executeWrite(sql: "DELETE FROM Memory WHERE memoryId = ?", bindings: [.text(id.uuidString)])

        case .changed:
            try await db.executeWrite(
                sql: "UPDATE Representation SET contentHash = 'source-v2' WHERE memoryId = ?",
                bindings: [.text(id.uuidString)]
            )

        case .cancelled:
            #expect(await queue.cancel(taskId: taskID))

        case .failed: break
        }
        await gate.release()
        await provider.release(failing: interruption == .failed)
        for _ in 0..<200 {
            if await queue.ownedTaskIDs().isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try await db.executeQuery(sql: "SELECT 1 FROM PhotoDerivedContent", bindings: []).isEmpty)
        let pending = try await db.executeQuery(
            sql: "SELECT 1 FROM PendingOperations WHERE operationId = ?",
            bindings: [.text(taskID)]
        )
        if interruption == .cancelled {
            #expect(try await progress.load(taskId: taskID)?.lastProcessedIndex == 0)
            #expect(pending.isEmpty)
        } else if interruption == .deleted {
            #expect(try await db.photoJobRow(memoryID: id) == nil)
            #expect(try await progress.loadAll().isEmpty)
            #expect(pending.isEmpty)
        } else {
            #expect(pending.count == 1)
            try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["photo"]))
            _ = try await preparation.schedule(memoryID: id, traceID: "no-automatic-replay")
            #expect(await provider.callCount == (interruption == .queuedRevoked ? 0 : 1))
        }
        await db.close()
    }

    @Test("AC-8: resource deferral becomes selectable for explicit recovery")
    @MainActor func test_AC8_resourceRecovery() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("photo-resource-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path.path + suffix) }
        }
        let db = DatabaseManager(databaseURL: path)
        try await db.open()
        let privacy = PrivacyActor(db: db)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["photo"]))
        let progress = ProgressActor(db: db)
        let queue = TaskQueueActor(progressActor: progress)
        let provider = PreparationCaptionProvider()
        await provider.setDeferred(true)
        let service = PhotoUnderstandingActor(
            database: db, privacy: privacy, queue: queue, progress: progress,
            pixelSource: PreparationPixelSource(), provider: provider, ocr: PreparationOCR()
        )
        let id = UUID()
        try await db.executeWrite(
            sql: "INSERT INTO Memory (memoryId, sourceLocator, sourceType, createdAt, updatedAt) VALUES (?, 'photo:resource', 'photo', 1, 1)",
            bindings: [.text(id.uuidString)]
        )
        try await db.executeWrite(
            sql: "INSERT INTO Representation VALUES (?, ?, 'visionDense', 'siglip2-v1', 'source-v1')",
            bindings: [.text(UUID().uuidString), .text(id.uuidString)]
        )
        let model = PhotoPreparationViewModel(memoryID: id, service: service)
        await model.prepareOnAccess()
        for _ in 0..<200 {
            if await queue.ownedTaskIDs().isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await model.refresh()
        #expect(model.state == .completed(.unprepared))
        #expect(try await progress.loadAll().isEmpty)
        #expect(try await db.executeQuery(sql: "SELECT 1 FROM PendingOperations", bindings: []).isEmpty)
        #expect(await provider.callCount == 1)
        await provider.setDeferred(false)
        await model.prepare()
        for _ in 0..<200 {
            if await queue.ownedTaskIDs().isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await model.refresh()
        #expect(model.state == .completed(.ready))
        #expect(model.canCreate)
        #expect(await provider.callCount == 2)
        await db.close()
    }

    @Test("AC-6/8: duplicate scheduling owns one queued job and publishes separate material")
    func test_AC8_idempotentPreparation() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("photo-queue-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path.path + suffix) }
        }
        let db = DatabaseManager(databaseURL: path)
        try await db.open()
        let privacy = PrivacyActor(db: db)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["photo"]))
        let progress = ProgressActor(db: db)
        let queue = TaskQueueActor(progressActor: progress)
        let provider = PreparationCaptionProvider()
        let preparation = PhotoUnderstandingActor(
            database: db,
            privacy: privacy,
            queue: queue,
            progress: progress,
            pixelSource: PreparationPixelSource(),
            provider: provider,
            ocr: PreparationOCR()
        )
        let id = UUID()
        try await db.executeWrite(
            sql:
                "INSERT INTO Memory (memoryId, sourceLocator, sourceType, createdAt, updatedAt) VALUES (?, 'photo:test', 'photo', 1, 1)",
            bindings: [.text(id.uuidString)]
        )
        try await db.executeWrite(
            sql: "INSERT INTO Representation VALUES (?, ?, 'visionDense', 'siglip2-v1', 'source-v1')",
            bindings: [.text(UUID().uuidString), .text(id.uuidString)]
        )
        #expect(try await preparation.schedule(memoryID: id, traceID: "photo-first"))
        #expect(try await !preparation.schedule(memoryID: id, traceID: "photo-duplicate"))
        for _ in 0..<200 {
            if await queue.ownedTaskIDs().isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await provider.callCount == 1)
        #expect(try await preparation.status(memoryID: id, traceID: "photo-status") == .ready)
        let repo = CanonicalMemoryRepositoryActor(db: db, privacyActor: privacy)
        let source = try #require(await repo.loadCreationSource(memoryID: id))
        #expect(source.text == "A red circle\nOPEN")
        #expect(try await repo.loadMemory(memoryId: id)?.canonicalText == nil)
        #expect(try await progress.loadAll().isEmpty)
        // A crash after publication may leave an index-zero checkpoint behind.
        let item = PhotoUnderstandingWorkItem(
            memoryID: id,
            sourceVersion: "source-v1",
            assetRevision: "asset-revision-1",
            modelVersion: ApprovedPhotoUnderstandingArtifact.identity,
            processingVersion: ApprovedPhotoUnderstandingArtifact.processingVersion
        )
        let descriptor = TaskResumeDescriptor(
            operation: .ingest,
            sourceTypes: ["photo"],
            payload: try JSONEncoder().encode(item)
        )
        try await db.failPhotoJob(
            item,
            taskID: "photo-understanding-\(id.uuidString.lowercased())",
            state: "failed",
            resumeData: try descriptor.encoded(),
            errorCode: "progress-write-failed"
        )
        #expect(try await preparation.status(memoryID: id, traceID: "published-material-remains-ready") == .ready)
        let visible = try #require(await preparation.readMaterial(memoryID: id, traceID: "visible-material"))
        #expect(visible.caption == "A red circle")
        #expect(visible.ocrText == "OPEN")
        #expect(visible.captionLanguage == "en-US")
        #expect(try await db.executeQuery(sql: "SELECT 1 FROM PendingOperations", bindings: []).isEmpty)
        let orphan = TaskProgress(
            taskId: "photo-understanding-\(id.uuidString.lowercased())",
            rawTaskType: "photoUnderstanding",
            lastProcessedIndex: 0,
            totalCount: 1,
            lastProcessedId: nil,
            resumeData: try descriptor.encoded(),
            updatedAt: Date(),
            createdAt: Date()
        )
        try await progress.save(progress: orphan)
        let recovered = try await preparation.makeRecoveryJob(
            for: TaskRecoveryRequest(
                progress: orphan,
                descriptor: descriptor,
                choice: .continue
            )
        )
        try await queue.enqueue(recovered, progressPolicy: .preserveExisting)
        for _ in 0..<200 {
            if await queue.ownedTaskIDs().isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await provider.callCount == 1)
        #expect(try await progress.loadAll().isEmpty)
        try await db.executeWrite(
            sql: "UPDATE PhotoUnderstandingJob SET modelVersion = 'previous-approved-model' WHERE memoryId = ?",
            bindings: [.text(id.uuidString)]
        )
        try await db.executeWrite(
            sql: "UPDATE PhotoDerivedContent SET modelVersion = 'previous-approved-model' WHERE memoryId = ?",
            bindings: [.text(id.uuidString)]
        )
        _ = try await preparation.schedule(memoryID: id, traceID: "upgrade-material")
        for _ in 0..<200 {
            if await queue.ownedTaskIDs().isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await provider.callCount == 2)
        #expect(try await preparation.status(memoryID: id, traceID: "upgraded-material") == .ready)
        await db.close()
    }
}
