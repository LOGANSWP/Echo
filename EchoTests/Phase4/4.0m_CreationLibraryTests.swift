// File: 4.0m_CreationLibraryTests.swift
// Spec: US-SYN-003 AC-8/9/10; ADR-026
// Task: 4.0m - Durable creation lifecycle and source deletion
import Foundation
import Testing
@testable import Echo

@Suite("4.0m Creation Library", .serialized)
struct CreationLibraryTests {
    @Test("AC-9/10: persistent identity, failure and complete source cleanup", arguments: ["source", "exclude", "consent"])
    func test_AC9_persistenceAndDeletion(cleanup: String) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("creation-library-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        let db = DatabaseManager(databaseURL: url)
        try await db.open()
        let sourceID = UUID()
        try await db.executeWrite(
            sql: "INSERT INTO Memory(memoryId, sourceLocator, sourceType, canonicalText, createdAt, updatedAt) VALUES (?, 'test', 'note', 'A garden', 1, 1)",
            bindings: [.text(sourceID.uuidString)]
        )
        let privacy = PrivacyActor(db: db)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["note"]))
        let checkpoint = await privacy.validate(operation: .search, traceID: "test")
        let request = CreationLibraryRequest(id: UUID(), template: .letter, sourceIDs: [sourceID], language: "en-US")
        try await db.insertCreationRequest(request, checkpoint: checkpoint, requiresConsent: false)
        try await db.insertCreationRequest(request, checkpoint: checkpoint, requiresConsent: false)
        #expect(try await db.creationRecords(checkpoint: checkpoint, requiresConsent: false).count == 1)
        try await db.updateCreationState(id: request.id, state: .failed, errorCode: "generation-failed")
        #expect(try await db.creationRecords(checkpoint: checkpoint, requiresConsent: false).first?.state == .failed)
        try await db.updateCreationState(id: request.id, state: .running)
        let output = CreativeOutput(template: .letter, title: "Garden", paragraphs: [GroundedParagraph(id: UUID(), text: "A garden grows.", anchors: [SourceAnchor(memoryID: sourceID, sourceType: "note")], groundingStatus: .cited)], sourceMemoryCount: 1, sourceTypes: ["note"])
        try await db.executeWrite(sql: "CREATE TRIGGER fail_creation_publication BEFORE UPDATE OF output ON CreationLibrary BEGIN SELECT RAISE(ABORT,'injected storage failure'); END", bindings: [])
        await #expect(throws: DatabaseError.self) {
            try await db.publishCreation(output, request: request, checkpoint: checkpoint, requiresConsent: false)
        }
        #expect(try await db.creationRecords(checkpoint: checkpoint, requiresConsent: false).first?.output == nil)
        try await db.executeWrite(sql: "DROP TRIGGER fail_creation_publication", bindings: [])
        try await db.publishCreation(output, request: request, checkpoint: checkpoint, requiresConsent: false)
        await db.close()
        try await db.open()
        #expect(try await db.creationRecords(checkpoint: checkpoint, requiresConsent: false).first?.output == output)
        try await db.updateCreationState(id: request.id, state: .failed, errorCode: "late-failure")
        #expect(try await db.creationRecords(checkpoint: checkpoint, requiresConsent: false).first?.state == .completed)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: []))
        let denied = await privacy.validate(operation: .search, traceID: "revoked")
        #expect(try await db.creationRecords(checkpoint: denied, requiresConsent: false).isEmpty)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["note"]))
        let restored = await privacy.validate(operation: .search, traceID: "restored")
        switch cleanup {
        case "exclude":
            try await db.executeWrite(sql: "INSERT INTO ExcludedAssets(assetId, sourceType, excludedAt) VALUES ('test','note',1)", bindings: [])

        case "consent":
            try await db.executeWrite(sql: "INSERT INTO ConsentStore VALUES (1,1,1,1,1,1)", bindings: [])
            try await db.executeWrite(sql: "UPDATE ConsentStore SET hasConsented=0 WHERE id=1", bindings: [])

        default:
            try await db.executeWrite(sql: "DELETE FROM Memory WHERE memoryId = ?", bindings: [.text(sourceID.uuidString)])
        }
        #expect(try await db.creationRecords(checkpoint: restored, requiresConsent: false).isEmpty)
        #expect(try await db.executeQuery(sql: "SELECT * FROM ExcludedAssets", bindings: []).count == (cleanup == "exclude" ? 1 : 0))
    }
}

private actor LibraryOutputProvider: StructuredLLMProvider {
    let fail: Bool
    let failure: GenerationRuntimeError
    init(fail: Bool, failure: GenerationRuntimeError = .deadline) {
        self.fail = fail
        self.failure = failure
    }
    func validateAvailability(traceID: String) async throws {}
    func tokenCount(request: GenerationRequest) async throws -> Int { 300 }
    func generate(prompt: String, preferredLanguage: String) async throws -> String { throw GenerationRuntimeError.invalidRequest }
    func generate(request: GenerationRequest) async throws -> GenerationResult {
        try await Task.sleep(for: .milliseconds(200))
        if fail { throw failure }
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "paragraphs": [["text": "Dear friend, the garden is green and peaceful today.", "sourceMemoryIDs": request.allowedMemoryIDs.map(\.uuidString)]]])
        return GenerationResult(envelope: try #require(String(data: data, encoding: .utf8)), inputTokenCount: 300, outputTokenCount: 90, predictionCount: 389, elapsedSeconds: 1, artifactIdentity: "test-double")
    }
}

extension CreationLibraryTests {
    @Test("AC-8: queue ownership outlives the submitting page; failure remains durable", arguments: [0, 1, 2, 4, 5])
    @MainActor
    func test_AC8_pageLifetime(mode: Int) async throws {
        let fail = mode == 1 || mode == 4
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("creation-queue-\(UUID()).sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let db = DatabaseManager(databaseURL: url)
        try await db.open()
        let sourceID = UUID()
        try await db.executeWrite(sql: "INSERT INTO Memory(memoryId,sourceLocator,sourceType,canonicalText,createdAt,updatedAt) VALUES (?,'test','note','The garden is green and peaceful today.',1,1)", bindings: [.text(sourceID.uuidString)])
        let privacy = PrivacyActor(db: db)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["note"]))
        let provider: any StructuredLLMProvider = mode == 3
            ? BundledGenerationActor(resourceRoot: Bundle.main.url(forResource: GenerationRuntimeArtifact.resourceName, withExtension: "bundle"), privacyActor: privacy, manifestActor: ModelManifestActor(db: db))
            : LibraryOutputProvider(fail: fail, failure: mode == 4 ? .outputLimit : .deadline)
        let repository = CanonicalMemoryRepositoryActor(db: db, privacyActor: privacy)
        let pipeline = CreativePipeline(llmProvider: provider, aligner: LanguageAligner(llmProvider: provider, preferredLanguage: "en-US"), privacyActor: privacy, canonicalRepository: repository)
        let queue = TaskQueueActor(progressActor: ProgressActor(db: db))
        let library = CreationLibraryActor(database: db, privacy: privacy, queue: queue, repository: repository, pipeline: pipeline)
        let vm = CreationViewModel(creativePipeline: pipeline, creationLibrary: library)
        vm.loadSourceMemories([try #require(await repository.loadCreationSource(memoryID: sourceID))])
        vm.selectTemplate(.letter)
        vm.generate()
        var id: UUID?
        for _ in 0..<100 {
            id = try await library.list().first?.id
            if id != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let requestID = try #require(id)
        vm.onDisappear()
        try await library.submit(id: requestID, template: .letter, sourceIDs: [sourceID])
        if mode == 5 {
            for _ in 0..<100 {
                if try await library.list().first?.state == .running { break }
                try await Task.sleep(for: .milliseconds(1))
            }
            #expect(try await library.list().first?.state == .running)
            try await library.delete(id: requestID)
            try await Task.sleep(for: .milliseconds(300))
            #expect(try await library.list().isEmpty)
            #expect(await queue.ownedTaskIDs().isEmpty)
            #expect(try await db.executeQuery(sql: "SELECT * FROM TaskProgress", bindings: []).isEmpty)
            #expect(try await db.executeQuery(sql: "SELECT * FROM PendingOperations", bindings: []).isEmpty)
            #expect(try await db.executeQuery(sql: "SELECT * FROM CreationLibrarySource", bindings: []).isEmpty)
            #expect(try await db.executeQuery(sql: "SELECT memoryId FROM Memory WHERE memoryId=?", bindings: [.text(sourceID.uuidString)]).count == 1)
            #expect(try await db.executeQuery(sql: "SELECT * FROM ExcludedAssets", bindings: []).isEmpty)
            return
        }
        if mode == 2 { try await library.cancel(id: requestID) }
        var final: CreationLibraryRecord?
        for _ in 0..<(mode == 3 ? 3000 : 200) {
            final = try await library.list().first
            if [.completed, .failed, .cancelled].contains(final?.state) { break }
            try await Task.sleep(for: .milliseconds(mode == 3 ? 100 : 10))
        }
        #expect(final?.state == (mode == 2 ? .cancelled : (fail ? .failed : .completed)))
        #expect((final?.output != nil) == (mode == 0 || mode == 3))
        #expect(try await library.list().count == 1)
        if fail {
            #expect(final?.errorCode == (mode == 4 ? "output-limit" : "deadline"))
            let reader = CreationViewModel(creationLibrary: library)
            let beforeOpen = try await library.list().first
            await reader.observeLibraryRequest(requestID)
            if mode == 4 {
                #expect(reader.viewState == .error(.l2Recoverable(
                    message: "The model reached the output limit before completing this creation. Please try again.")))
            }
            try await Task.sleep(for: .milliseconds(250))
            #expect(try await library.list().first == beforeOpen)
            #expect(await queue.ownedTaskIDs().isEmpty)
            reader.retry()
            #expect(reader.viewState == .generating)
            for _ in 0..<200 {
                if case .error = reader.viewState { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(try await library.list().count == 1)
            #expect(reader.libraryRequestID == requestID)
            reader.onDisappear()
        }
        #expect(try await db.executeQuery(sql: "SELECT * FROM PendingOperations WHERE operationType='manualCreation'", bindings: []).count == (fail ? 1 : 0))
    }
}


extension CreationLibraryTests {
    @Test("AC-8/9: actual bundled model completes after the submitting page leaves")
    @MainActor
    func test_AC8_realModelPersistence() async throws {
        try await test_AC8_pageLifetime(mode: 3)
    }
}
