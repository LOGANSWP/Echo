// ==========================================
// File: 4.0l_PhotoUnderstandingCreationTests.swift
// Spec: US-ING-004 AC-7/8; US-SYN-003 AC-7; ADR-025
// Task: 4.0l - Independent photo-derived creation sources
// AC coverage: separate persistence, bounded reads, correction precedence and deletion
// Architecture: isolated SQLite, original MemoryID, no model-quality claims
// Generated: 2026-09-09
// ==========================================

import Foundation
import Testing

@testable import Echo

private actor GateLLMProbe: LLMProvider {
    private(set) var calls = 0
    func generate(prompt: String, preferredLanguage: String) async throws -> String {
        calls += 1
        return ""
    }
}

@Suite("4.0l Photo Understanding Creation", .serialized)
struct PhotoUnderstandingCreationTests {
    enum SourceScenario: CaseIterable {
        case automatic, correction, titleOnly, stale, previousArtifact, pending, budget, assetChanged, metadataOnly, correctionOnly, whitespaceCorrection
    }

    @Test(
        "AC-7: creation consumes bounded current derived text with correction precedence",
        arguments: SourceScenario.allCases
    )
    func test_AC7_creationSource(_ scenario: SourceScenario) async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("photo-source-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path.path + suffix) }
        }
        let db = DatabaseManager(databaseURL: path)
        try await db.open()
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
        if [.correction, .titleOnly, .metadataOnly, .correctionOnly, .whitespaceCorrection].contains(scenario) {
            try await db.executeWrite(
                sql: "INSERT INTO MemoryUserEdit VALUES (?, 'My title', ?, '[\"garden\"]', 2)",
                bindings: [.text(id.uuidString), .text([.correction, .correctionOnly].contains(scenario) ? "A blue square" : (scenario == .whitespaceCorrection ? " \n\t " : ""))]
            )
        }
        for kind in ([.metadataOnly, .correctionOnly, .whitespaceCorrection].contains(scenario) ? ["ocr"] : ["caption", "ocr"]) {
            try await db.executeWrite(
                sql: """
                    INSERT INTO PhotoDerivedContent
                    (memoryId, kind, sourceVersion, modelVersion, processingVersion, language, state, body, updatedAt)
                    VALUES (?, ?, ?, ?,
                        'echo-photo-imageio-v1/echo-photo-caption-v1', 'en-US', ?, ?, 3)
                    """,
                bindings: [
                    .text(id.uuidString), .text(kind),
                    .text(scenario == .stale ? "old-source" : "source-v1"),
                    .text(
                        scenario == .previousArtifact
                            ? "625d3457c9e632b29bd2fe2e40467ba116079f935a4b303ebb3f7dee577117a7"
                            : ApprovedPhotoUnderstandingArtifact.identity
                    ),
                    .text(scenario == .pending ? "pending" : "ready"),
                    .text(kind == "caption" ? "A red circle" : "OPEN"),
                ]
            )
        }
        let repo = CanonicalMemoryRepositoryActor(
            db: db,
            privacyActor: PrivacyActor(db: db),
            photoPixelSource: scenario == .assetChanged ? ChangedPhotoSource() : nil
        )
        if scenario == .budget {
            await #expect(throws: GenerationRuntimeError.contextLimit) {
                _ = try await repo.loadCreationSource(memoryID: id, maximumTextBytes: 5)
            }
        } else {
            let source = try #require(await repo.loadCreationSource(memoryID: id, maximumTextBytes: 100))
            #expect(source.memoryID == id)
            #expect(source.photoCreationReady == [.automatic, .correction, .titleOnly, .correctionOnly].contains(scenario))
            if !source.photoCreationReady {
                let privacy = PrivacyActor(db: db)
                try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["photo"]))
                let provider = GateLLMProbe()
                let pipeline = CreativePipeline(
                    llmProvider: provider,
                    aligner: LanguageAligner(llmProvider: provider, preferredLanguage: "en-US"),
                    privacyActor: privacy,
                    canonicalRepository: repo
                )
                // A forged ready UI snapshot must not bypass the current persisted material gate.
                let snapshot = CreativeSource(
                    memoryID: id, assetID: "", sourceType: "photo",
                    text: "Old caption", timestamp: 1, photoCreationReady: true
                )
                await #expect(throws: CreativeError.noSources) {
                    _ = try await pipeline.generate(template: .letter, sources: [snapshot], traceID: "gate-recheck")
                }
                #expect(await provider.calls == 0)
            }
            switch scenario {
            case .automatic:
                #expect(source.text == "A red circle\nOPEN")
                try await GenerationSourceValidation(
                    repository: repo,
                    sources: [source],
                    excerptScalarLimit: 512
                ).validate()

            case .titleOnly: #expect(source.text == "My title\ngarden\nA red circle\nOPEN")

            case .correction:
                #expect(source.text == "My title\nA blue square\ngarden\nOPEN")
                #expect(source.text?.contains("red circle") == false)

            case .stale, .previousArtifact, .pending, .assetChanged: #expect(source.text?.isEmpty == true)
            case .metadataOnly, .whitespaceCorrection: #expect(source.text?.contains("OPEN") == true)
            case .correctionOnly: #expect(source.text?.contains("A blue square") == true)
            case .budget: break
            }
        }
        await db.close()
    }

    @Test("AC-7: derived bodies survive migration without changing source or user text")
    func test_AC7_independentStorage() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("photo-derived-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path.path + suffix) }
        }
        let database = DatabaseManager(databaseURL: path)
        try await database.open()
        let id = UUID().uuidString
        try await database.executeWrite(
            sql:
                "INSERT INTO Memory (memoryId, sourceLocator, canonicalText, sourceType, createdAt, updatedAt) VALUES (?, 'photo:test', 'Original text', 'photo', 1, 1)",
            bindings: [.text(id)]
        )
        try await database.executeWrite(
            sql: "INSERT INTO MemoryUserEdit VALUES (?, 'My title', 'My correction', '[]', 2)",
            bindings: [.text(id)]
        )
        for kind in ["caption", "ocr"] {
            try await database.executeWrite(
                sql: """
                    INSERT INTO PhotoDerivedContent
                    (memoryId, kind, sourceVersion, modelVersion, processingVersion, language, state, body, updatedAt)
                    VALUES (?, ?, 'source-v1', 'approved-v1', 'processing-v1', 'en-US', 'ready', ?, 3)
                    """,
                bindings: [.text(id), .text(kind), .text("Independent \(kind)")]
            )
        }
        await database.close()
        try await database.open()
        let original = try #require(
            await database.executeQuery(
                sql:
                    "SELECT m.canonicalText, e.description FROM Memory m JOIN MemoryUserEdit e USING(memoryId) WHERE memoryId = ?",
                bindings: [.text(id)]
            ).first
        )
        #expect(original["canonicalText"]?.stringValue == "Original text")
        #expect(original["description"]?.stringValue == "My correction")
        #expect(
            try await database.executeQuery(
                sql: "SELECT * FROM PhotoDerivedContent WHERE memoryId = ?",
                bindings: [.text(id)]
            ).count == 2
        )
        try await database.executeWrite(sql: "DELETE FROM Memory WHERE memoryId = ?", bindings: [.text(id)])
        #expect(try await database.executeQuery(sql: "SELECT * FROM PhotoDerivedContent", bindings: []).isEmpty)
        await database.close()
    }
}

nonisolated private struct ChangedPhotoSource: PhotoPixelSourceReading {
    func currentRevision(assetID: String) async throws -> String { "changed-system-resource" }
    func read(assetID: String, expectedRevision: String) async throws -> Data {
        throw GenerationRuntimeError.invalidRequest
    }
}
