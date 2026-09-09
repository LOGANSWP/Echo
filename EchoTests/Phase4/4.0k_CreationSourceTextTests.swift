// ==========================================
// File: 4.0k_CreationSourceTextTests.swift
// Spec: US-SYN-003 AC-2; US-AWK-007 AC-1/2; ADR-023
// Task: 4.0k - Live creation source text boundary
// AC coverage: blank photos, persisted descriptions, and edit invalidation
// Architecture: current repository values; no UI placeholder as evidence
// Generated: 2026-09-08
// ==========================================

import Foundation
import Testing

@testable import Echo

private actor PhotoTextProvider: StructuredLLMProvider {
    let database: DatabaseManager
    let mutate: Bool
    private(set) var requests: [GenerationRequest] = []
    init(database: DatabaseManager, mutate: Bool) { self.database = database; self.mutate = mutate }
    func validateAvailability(traceID: String) async throws {}
    func tokenCount(request: GenerationRequest) async throws -> Int { 300 }
    func generate(prompt: String, preferredLanguage: String) async throws -> String {
        throw GenerationRuntimeError.invalidRequest
    }
    func generate(request: GenerationRequest) async throws -> GenerationResult {
        requests.append(request)
        if mutate {
            try await database.executeWrite(sql: "UPDATE MemoryUserEdit SET description = 'Changed description'", bindings: [])
        }
        let id = try #require(request.allowedMemoryIDs.first)
        return GenerationResult(
            envelope: "{\"schemaVersion\":1,\"paragraphs\":[{\"text\":\"The family walked together in the garden during the afternoon.\",\"sourceMemoryIDs\":[\"\(id.uuidString)\"]}]}",
            inputTokenCount: 300, outputTokenCount: 60, predictionCount: 359,
            elapsedSeconds: 1, artifactIdentity: "test-double")
    }
}

@Suite("4.0k Creation Source Text", .serialized)
@MainActor
struct CreationSourceTextTests {
    enum Scenario: CaseIterable { case blank, whitespace, description, editedDuringGeneration }

    @Test("AC-2: use current persisted photo text or return an honest source empty state", arguments: Scenario.allCases)
    func test_AC2_photoSourceText(_ scenario: Scenario) async throws {
        let database = DatabaseManager(databaseURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("creation-photo-\(UUID().uuidString).sqlite"))
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["photo"]))
        let id = UUID()
        try await database.executeWrite(
            sql: "INSERT INTO Memory (memoryId, sourceLocator, canonicalText, sourceType, createdAt, updatedAt, recoverability) VALUES (?, '', ?, 'photo', 1, 1, 'full')",
            bindings: [.text(id.uuidString), scenario == .whitespace ? .text(" \n\t ") : .null])
        if scenario == .description || scenario == .editedDuringGeneration {
            try await database.executeWrite(
                sql: "INSERT INTO MemoryUserEdit (memoryId, title, description, tagsJSON, updatedAt) VALUES (?, 'Garden walk', 'The family walked together in the garden during the afternoon.', '[]', 2)",
                bindings: [.text(id.uuidString)])
        }
        let provider = PhotoTextProvider(database: database, mutate: scenario == .editedDuringGeneration)
        let pipeline = CreativePipeline(
            llmProvider: provider, aligner: LanguageAligner(llmProvider: provider),
            privacyActor: privacy, canonicalRepository: CanonicalMemoryRepositoryActor(db: database, privacyActor: privacy))
        let source = CreativeSource(memoryID: id, assetID: "", sourceType: "photo", text: "A photo memory", timestamp: 1)
        switch scenario {
        case .blank, .whitespace:
            await #expect(throws: CreativeError.noSources) {
                _ = try await pipeline.generate(template: .report, sources: [source], traceID: "blank-photo")
            }
            #expect(await provider.requests.isEmpty)
            let model = CreationViewModel(creativePipeline: pipeline)
            model.loadSourceMemories([source])
            model.selectTemplate(.report)
            model.generate()
            for _ in 0..<100 where model.viewState == .generating {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(model.viewState == .empty)
            #expect(model.requiresSourceText)

        case .description:
            let output = try await pipeline.generate(template: .report, sources: [source], traceID: "photo-description")
            #expect(output.sourceMemoryCount == 1)
            let request = try #require(await provider.requests.first)
            #expect(request.user.contains("Garden walk"))
            #expect(!request.user.contains("A photo memory"))

        case .editedDuringGeneration:
            await #expect(throws: GenerationRuntimeError.privacyDenied) {
                _ = try await pipeline.generate(template: .report, sources: [source], traceID: "edited-photo-description")
            }
            #expect(await provider.requests.count == 1)
        }
    }
}
