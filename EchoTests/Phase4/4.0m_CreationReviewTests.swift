// Task 4.0m / PR #81: AC-8/9/10 deletion, source aliases and resource deferral.
import Foundation
import Testing
@testable import Echo

private actor ReviewProvider: StructuredLLMProvider {
    var held = false
    var entered = false
    var deferred = false
    func configure(held: Bool = false, deferred: Bool = false) { self.held = held; self.deferred = deferred }
    func validateAvailability(traceID: String) async throws {
        entered = true
        while held { try await Task.sleep(for: .milliseconds(1)) }
    }
    func tokenCount(request: GenerationRequest) async throws -> Int { 300 }
    func generate(prompt: String, preferredLanguage: String) async throws -> String { throw GenerationRuntimeError.invalidRequest }
    func generate(request: GenerationRequest) async throws -> GenerationResult {
        if deferred { throw NarrativeReportError.resourceDeferred }
        throw GenerationRuntimeError.deadline
    }
}

@Suite("4.0m Creation Review", .serialized)
struct CreationReviewTests {
    @Test("AC-10: authorization uses canonical source aliases", arguments: ["text", "video_frame", "video_audio"])
    func test_AC10_aliases(type: String) async throws {
        let db = DatabaseManager(databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("review-alias-\(UUID()).sqlite"))
        try await db.open()
        let privacy = PrivacyActor(db: db)
        let permission = SearchPipeline.normalizeSourceType(type)
        try await privacy.updatePolicy(UserPolicy(authorizedSourceTypes: [permission]))
        let id = UUID()
        try await db.executeWrite(sql: "INSERT INTO Memory(memoryId,sourceLocator,sourceType,canonicalText,createdAt,updatedAt) VALUES (?,'review',?,'A garden',1,1)", bindings: [.text(id.uuidString), .text(type)])
        let request = CreationLibraryRequest(id: UUID(), template: .letter, sourceIDs: [id], language: "zh-Hans")
        let checkpoint = await privacy.validate(operation: .search, traceID: "alias")
        try await db.insertCreationRequest(request, checkpoint: checkpoint, requiresConsent: false)
        #expect(try await db.creationRecords(checkpoint: checkpoint, requiresConsent: false).count == 1)
        try await privacy.updatePolicy(UserPolicy(authorizedSourceTypes: []))
        let revoked = await privacy.validate(operation: .search, traceID: "revoke")
        #expect(try await db.creationRecords(checkpoint: revoked, requiresConsent: false).isEmpty)
        await db.close()
    }

    @Test("AC-9: delete overlapping runtime retry stays deleted")
    func test_AC9_deleteDuringRetry() async throws {
        let setup = try await fixture()
        let (db, privacy, queue, provider, library, request) = setup
        let checkpoint = await privacy.validate(operation: .search, traceID: "setup")
        try await db.insertCreationRequest(request, checkpoint: checkpoint, requiresConsent: false)
        try await db.updateCreationState(id: request.id, state: .failed, errorCode: "model-unavailable")
        await provider.configure(held: true)
        let retry = Task { try await library.retry(id: request.id) }
        for _ in 0..<1000 {
            if await provider.entered { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await provider.entered)
        let release = Task {
            try await Task.sleep(for: .milliseconds(100))
            await provider.configure()
        }
        try await library.delete(id: request.id)
        try await release.value
        _ = try? await retry.value
        await drain(queue)
        #expect(try await library.list().isEmpty)
        #expect(try await db.executeQuery(sql: "SELECT * FROM PendingOperations", bindings: []).isEmpty)
        #expect(try await db.executeQuery(sql: "SELECT * FROM TaskProgress", bindings: []).isEmpty)
        #expect(try await db.executeQuery(sql: "SELECT * FROM Memory", bindings: []).count == 1)
        #expect(try await db.executeQuery(sql: "SELECT * FROM ExcludedAssets", bindings: []).isEmpty)
        await db.close()
    }

    @Test("AC-8: resource wait is not L2 and explicit continuation can fail honestly")
    @MainActor func test_AC8_resourceWait() async throws {
        let (db, _, queue, provider, library, request) = try await fixture()
        await provider.configure(deferred: true)
        try await library.submit(id: request.id, template: request.template, sourceIDs: request.sourceIDs)
        await drain(queue)
        #expect(try await library.list().first?.state.rawValue == "deferred")
        #expect(try await db.executeQuery(sql: "SELECT * FROM PendingOperations", bindings: []).isEmpty)
        let model = CreationViewModel(creationLibrary: library)
        await model.observeLibraryRequest(request.id)
        #expect(model.viewState == .waitingForResources)
        await provider.configure()
        try await library.retry(id: request.id)
        await drain(queue)
        #expect(try await library.list().first?.state == .failed)
        #expect(try await library.list().first?.errorCode == "deadline")
        #expect(try await db.executeQuery(sql: "SELECT * FROM PendingOperations", bindings: []).count == 1)
        await db.close()
    }

    private func drain(_ queue: TaskQueueActor) async {
        for _ in 0..<1000 {
            if await queue.ownedTaskIDs().isEmpty { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func fixture() async throws -> (DatabaseManager, PrivacyActor, TaskQueueActor, ReviewProvider, CreationLibraryActor, CreationLibraryRequest) {
        let db = DatabaseManager(databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("review-library-\(UUID()).sqlite"))
        try await db.open()
        let privacy = PrivacyActor(db: db)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["note"]))
        let id = UUID()
        try await db.executeWrite(sql: "INSERT INTO Memory(memoryId,sourceLocator,sourceType,canonicalText,createdAt,updatedAt) VALUES (?,'review','note','A green garden',1,1)", bindings: [.text(id.uuidString)])
        let queue = TaskQueueActor(progressActor: ProgressActor(db: db))
        let provider = ReviewProvider()
        let repository = CanonicalMemoryRepositoryActor(db: db, privacyActor: privacy)
        let pipeline = CreativePipeline(llmProvider: provider, aligner: LanguageAligner(llmProvider: provider), privacyActor: privacy, canonicalRepository: repository)
        let library = CreationLibraryActor(database: db, privacy: privacy, queue: queue, repository: repository, pipeline: pipeline)
        return (db, privacy, queue, provider, library, CreationLibraryRequest(id: UUID(), template: .letter, sourceIDs: [id], language: "en-US"))
    }
}
