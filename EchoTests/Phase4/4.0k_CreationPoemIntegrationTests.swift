// ==========================================
// File: 4.0k_CreationPoemIntegrationTests.swift
// Spec: US-SYN-003 AC-1/2; ADR-023
// Task: 4.0k - Real model poetic form regression
// AC coverage: bilingual poem form, language and citations with the bundled model
// Evidence: synthetic runtime integration; normal App ingestion verified separately
// Generated: 2026-09-08
// ==========================================

import Foundation
import Testing

@testable import Echo

@Suite("4.0k Real Poem Generation", .serialized)
@MainActor
struct CreationPoemIntegrationTests {
    @Test("AC-1/2: bundled model writes verse from a synthetic photo description", arguments: ["en-US", "zh-Hans"])
    func test_AC1_realPoem(language: String) async throws {
        try await verifyPoem(
            language: language, subject: "circle",
            sourceText: "Blue circle test\nA blue circle is centered on a white background. This is a synthetic test image.")
    }

    @Test("AC-1/2: Chinese poems keep independent subjects without importing demonstration content",
          arguments: ["rain", "river"])
    func test_AC1_otherSubjects(subject: String) async throws {
        let sourceText = subject == "rain"
            ? "Raindrops run down the window. The room is quiet."
            : "At sunset, golden light reflects on the river. Two white birds rest on a branch."
        try await verifyPoem(language: "zh-Hans", subject: subject, sourceText: sourceText)
    }

    private func verifyPoem(language: String, subject: String, sourceText: String) async throws {
        let database = DatabaseManager(databaseURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("real-poem-\(UUID().uuidString).sqlite"))
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: language, authorizedSourceTypes: ["photo"]))
        let runtime = BundledGenerationActor(resourceRoot: Bundle.main.url(
            forResource: GenerationRuntimeArtifact.resourceName, withExtension: "bundle"), privacyActor: privacy)
        let id = UUID(uuidString: "AA8FF0CC-2736-573D-A190-FC7FFB943844")!
        let request = try GenerationPrompt.request(
            template: .poem,
            passages: [
                GenerationPassage(
                    text: sourceText,
                    sourceMemoryIDs: [id]),
            ],
            sourceTypes: ["photo"],
            context: .init(language: language, traceID: "synthetic-poem",
                           deadline: ProcessInfo.processInfo.systemUptime + 60, terminology: TerminologyTable(entries: [:])))
        let result = try await runtime.generate(request: request)
        let paragraphs = try CreativePipeline.parseParagraphs(
            from: result.envelope,
            allowedMemoryIDs: [id], sourceTypes: [id: "photo"])
        #expect(paragraphs.count == 4)
        let body = paragraphs.map(\.text).joined(separator: "\n")
        #expect(CreativeGenerationLimits.poemLineRange.contains(body.split(whereSeparator: \.isNewline).count),
                "Synthetic poem envelope: \(result.envelope)")
        #expect(LanguageAligner.bodyMatches(body, language: language))
        #expect(paragraphs.allSatisfy { $0.anchors.map(\.memoryID) == [id] })
        if language == "zh-Hans" {
            // A regression for this visual subject, not an automatic literary-quality score.
            // The test metadata must not replace the image's subject in the poem.
            #expect(!body.contains("测试") && !body.contains("合成"), "Synthetic poem: \(body)")
            #expect(Set(paragraphs.map(\.text)).count == paragraphs.count)
            #expect(!body.contains("叶尖") && !body.contains("绿意"), "Demonstration leaked into poem: \(body)")
            if subject == "rain" {
                #expect(!body.contains("雨停"), "The source does not record the rain stopping: \(body)")
                // These freeze observed unsupported assertions, not a general word blacklist.
                // A metaphor mentioning night or sound still requires contextual human review.
                #expect(!body.contains("静谧的夜晚"), "The source does not record a time of day: \(body)")
            }
            if subject == "river" {
                #expect(!body.contains("河面的光，与鸟鸣相映"),
                        "The source records resting birds, not birdsong: \(body)")
            }
        }
        let evidence = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-poem-\(language)-\(subject).json")
        try Data(result.envelope.utf8).write(to: evidence, options: .atomic)
        let metrics = try JSONSerialization.data(withJSONObject: [
            "subject": subject, "language": language, "promptVersion": GenerationPrompt.version,
            "inputTokens": result.inputTokenCount, "outputTokens": result.outputTokenCount,
            "predictions": result.predictionCount, "elapsedSeconds": result.elapsedSeconds,
            "artifactIdentity": result.artifactIdentity,
            "referenceEncoding": String(describing: request.referenceEncoding),
        ])
        try metrics.write(to: evidence.deletingPathExtension().appendingPathExtension("metrics.json"), options: .atomic)
    }
}
