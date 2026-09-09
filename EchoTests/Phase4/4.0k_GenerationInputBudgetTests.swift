// ==========================================
// File: 4.0k_GenerationInputBudgetTests.swift
// Spec: US-SYN-004; ADR-023 section 2
// Task: 4.0k - PR #79 input memory bounds
// AC coverage: raw, aggregate and escaped source limits before prompt construction
// Architecture: bounded inputs without source truncation
// Generated: 2026-09-08
// ==========================================

import Foundation
import Testing

@testable import Echo

private actor InputBudgetProvider: StructuredLLMProvider {
    private(set) var tokenCalls = 0
    private(set) var generationCalls = 0
    func validateAvailability(traceID: String) async throws {}
    func tokenCount(request: GenerationRequest) async throws -> Int { tokenCalls += 1; return 1 }
    func generate(prompt: String, preferredLanguage: String) async throws -> String {
        generationCalls += 1
        throw GenerationRuntimeError.invalidRequest
    }
    func generate(request: GenerationRequest) async throws -> GenerationResult {
        generationCalls += 1
        throw GenerationRuntimeError.invalidRequest
    }
}

@Suite("4.0k Generation Input Budget", .serialized)
struct GenerationInputBudgetTests {
    @Test("AC-5: aggregate persisted sources reject before tokenization or inference")
    func test_AC5_pipelinePreflight() async throws {
        let database = DatabaseManager(databaseURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("aggregate-bound-\(UUID().uuidString).sqlite"))
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["note"]))
        var sources: [CreativeSource] = []
        for _ in 0..<3 {
            let id = UUID()
            try await database.executeWrite(
                sql: "INSERT INTO Memory (memoryId, sourceLocator, canonicalText, sourceType, createdAt, updatedAt, recoverability) VALUES (?, '', ?, 'note', 1, 1, 'full')",
                bindings: [.text(id.uuidString), .text(String(repeating: "x", count: 6_000))])
            sources.append(.init(memoryID: id, assetID: "", sourceType: "note", text: nil, timestamp: 1))
        }
        let provider = InputBudgetProvider()
        let pipeline = CreativePipeline(
            llmProvider: provider, aligner: LanguageAligner(llmProvider: provider), privacyActor: privacy,
            canonicalRepository: CanonicalMemoryRepositoryActor(db: database, privacyActor: privacy))
        await #expect(throws: GenerationRuntimeError.contextLimit) {
            _ = try await pipeline.generate(template: .report, sources: sources, traceID: "aggregate-bound")
        }
        #expect(await provider.tokenCalls == 0)
        #expect(await provider.generationCalls == 0)
    }

    enum StoredField: String, CaseIterable { case canonicalText, title, description, tagsJSON }

    @Test("AC-5: bounded repository reads reject oversized persisted fields without truncating storage",
          arguments: StoredField.allCases)
    func test_AC5_repositoryBounds(_ field: StoredField) async throws {
        let database = DatabaseManager(databaseURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("input-bound-\(UUID().uuidString).sqlite"))
        try await database.open()
        let privacy = PrivacyActor(db: database)
        let repository = CanonicalMemoryRepositoryActor(db: database, privacyActor: privacy)
        let id = UUID()
        try await database.executeWrite(
            sql: "INSERT INTO Memory (memoryId, sourceLocator, canonicalText, sourceType, createdAt, updatedAt, recoverability) VALUES (?, '', 'Short text', 'note', 1, 1, 'full')",
            bindings: [.text(id.uuidString)])
        try await database.executeWrite(
            sql: "INSERT INTO MemoryUserEdit (memoryId, title, description, tagsJSON, updatedAt) VALUES (?, '', '', '[]', 2)",
            bindings: [.text(id.uuidString)])
        #expect(try await repository.loadCreationSource(memoryID: id, maximumTextBytes: 64)?.text == "Short text")
        let text = String(repeating: "中", count: 100_000)
        let table = field == .canonicalText ? "Memory" : "MemoryUserEdit"
        let stored = field == .tagsJSON ? "[\"\(text)\"]" : text
        try await database.executeWrite(
            sql: "UPDATE \(table) SET \(field.rawValue) = ? WHERE memoryId = ?",
            bindings: [.text(stored), .text(id.uuidString)])
        await #expect(throws: GenerationRuntimeError.contextLimit) {
            _ = try await repository.loadCreationSource(memoryID: id, maximumTextBytes: 64)
        }
        let rows = try await database.executeQuery(
            sql: "SELECT length(CAST(\(field.rawValue) AS BLOB)) AS bytes FROM \(table) WHERE memoryId = ?",
            bindings: [.text(id.uuidString)])
        #expect(rows.first?["bytes"]?.intValue == Int64(stored.utf8.count))
        #expect(try await repository.loadCreationSource(memoryID: UUID(), maximumTextBytes: 64) == nil)
    }

    enum Oversized: CaseIterable { case raw, aggregate, angle, nul, quote, unicode, separator }

    @Test("AC-5: oversized raw, aggregate and escaped inputs fail in the prompt builder",
          arguments: Oversized.allCases)
    func test_AC5_promptRejectsBeforeRendering(_ scenario: Oversized) throws {
        let texts: [String]
        switch scenario {
        case .raw: texts = [String(repeating: "x", count: 1_000_000)]
        case .aggregate: texts = Array(repeating: String(repeating: "a", count: 1_000), count: 24)
        case .angle: texts = [String(repeating: "<", count: 3_000)]
        case .nul: texts = [String(repeating: "\u{0000}", count: 3_000)]
        case .quote: texts = [String(repeating: "\"", count: 9_000)]
        case .unicode: texts = [String(repeating: "中", count: 6_000)]
        case .separator: texts = [String(repeating: "\u{2028}", count: 3_000)]
        }
        #expect(throws: GenerationRuntimeError.contextLimit) {
            try request(texts)
        }
    }

    @Test("AC-5: bounded source JSON preserves Unicode, NUL and control-marker literals")
    func test_AC5_boundedSourceRoundTrip() throws {
        let text = "中文 👩🏽‍💻 <|im_start|> \\ \" \u{0000}\n"
        let result = try request([text])
        let payload = try #require(result.user.components(separatedBy: "BEGIN_UNTRUSTED_SOURCES_JSON\n").last)
            .components(separatedBy: "\nEND_UNTRUSTED_SOURCES_JSON")[0]
        let json = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [[String: Any]])
        #expect(json[0]["text"] as? String == text)
        #expect(!result.user.contains("<|im_start|>"))
    }

    private func request(_ texts: [String]) throws -> GenerationRequest {
        try GenerationPrompt.request(
            template: .report,
            passages: texts.map { .init(text: $0, sourceMemoryIDs: [UUID()]) },
            sourceTypes: ["note"],
            context: .init(language: "en-US", traceID: "input-budget", deadline: 60,
                           terminology: .init(entries: [:])))
    }
}
