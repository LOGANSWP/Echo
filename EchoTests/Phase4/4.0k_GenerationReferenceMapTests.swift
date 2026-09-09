// ==========================================
// File: 4.0k_GenerationReferenceMapTests.swift
// Spec: US-SYN-002 AC-1/2/3; ADR-023 requestAliasV1
// Task: 4.0k - Lossless request-owned source transport
// AC coverage: explicit mapping, unknown reference rejection, NoSource and prefix isolation
// Architecture: Sendable values; no positional source assignment
// Generated: 2026-09-08
// ==========================================

import Foundation
import Testing

@testable import Echo

@Suite("4.0k Generation Reference Map", .serialized)
@MainActor
struct GenerationReferenceMapTests {
    let first = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let second = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!

    @Test("AC-1/2: aliases are restored by name, never by paragraph position")
    func test_AC2_explicitMappingPreservesTextAndOrder() throws {
        let map = GenerationReferenceMap(memoryIDs: [second, first, second])
        #expect(try map.alias(for: first) == "S1")
        #expect(try map.alias(for: second) == "S2")
        let body = "  A line\nA second line 👩🏽‍💻 e\u{301}  "
        let raw = try envelope([
            ["text": body, "sourceMemoryIDs": ["S2", "S1", "S2"]],
            ["text": "Another line", "sourceMemoryIDs": ["S1"]],
        ])
        let restored = try JSONSerialization.jsonObject(with: Data(map.resolveEnvelope(raw).utf8)) as? [String: Any]
        let paragraphs = try #require(restored?["paragraphs"] as? [[String: Any]])
        #expect(paragraphs[0]["text"] as? String == body)
        let restoredBody = try #require(paragraphs[0]["text"] as? String)
        #expect(Array(restoredBody.utf8) == Array(body.utf8))
        #expect(paragraphs[0]["sourceMemoryIDs"] as? [String]
                == [second.uuidString, first.uuidString, second.uuidString])
        #expect(paragraphs[1]["sourceMemoryIDs"] as? [String] == [first.uuidString])
    }

    @Test("AC-1/3: empty references remain NoSource and unknown aliases cannot get a fallback")
    func test_AC1_failClosedAndNoSource() throws {
        let map = GenerationReferenceMap(memoryIDs: [first])
        let raw = try envelope([["text": "A line without a source", "sourceMemoryIDs": [String]()]])
        let parsed = try CreativePipeline.parseParagraphs(
            from: map.resolveEnvelope(raw), allowedMemoryIDs: [first], sourceTypes: [first: "note"])
        #expect(parsed.first?.groundingStatus == .noSource)
        for references in [["S2"], ["S1", "S2"], [first.uuidString], ["S01"]] {
            let invalid = try envelope([["text": "A line", "sourceMemoryIDs": references]])
            #expect(throws: GenerationRuntimeError.invalidRequest) { try map.resolveEnvelope(invalid) }
        }
        #expect(throws: GenerationRuntimeError.invalidRequest) { try map.alias(for: second) }
        #expect(throws: GenerationRuntimeError.invalidRequest) { try map.resolveEnvelope("{}") }
        let oversized = try envelope([
            [
                "text": String(repeating: "x", count: CreativeGenerationLimits.maximumParagraphCharacters + 1),
                "sourceMemoryIDs": ["S1"],
            ],
        ])
        #expect(throws: GenerationRuntimeError.invalidRequest) { try map.resolveEnvelope(oversized) }
    }

    @Test("AC-1: short reference prefixes distinguish S1 from S10 and reject UUID substitution")
    func test_AC1_aliasGrammarPrefixes() throws {
        let grammar = try GenerationEnvelopeGrammar(allowedAliases: ["S1", "S10"])
        let raw = "{\"schemaVersion\":1,\"paragraphs\":[{\"text\":\"中文\",\"sourceMemoryIDs\":[\"S10\"]}]}"
        let bytes = Array(raw.utf8)
        for length in 0..<bytes.count {
            #expect(grammar.status(Array(bytes.prefix(length))) == .prefix)
        }
        #expect(grammar.status(bytes) == .complete)
        #expect(grammar.status(Array(raw.replacingOccurrences(of: "S10", with: "S1").utf8)) == .complete)
        for value in ["S2", "S01", first.uuidString] {
            #expect(grammar.status(Array(raw.replacingOccurrences(of: "S10", with: value).utf8)) == .invalid)
        }
    }

    @Test("AC-1/2: the prompt encodes only reference fields and retry retains its mapping")
    func test_AC2_requestAndRetryKeepSameReferences() throws {
        let body = "The printed identifier is \(first.uuidString)."
        let request = try GenerationPrompt.request(
            template: .poem,
            passages: [.init(text: body, sourceMemoryIDs: [second]), .init(text: "A second source", sourceMemoryIDs: [first])],
            sourceTypes: ["note"],
            context: .init(language: "zh-Hans", traceID: "reference-encoding", deadline: 60,
                           terminology: TerminologyTable(entries: [:])))
        #expect(request.referenceEncoding == .requestAliasV1)
        #expect(request.languageRetry().referenceEncoding == .requestAliasV1)
        #expect(request.languageRetry().allowedMemoryIDs == request.allowedMemoryIDs)
        #expect(request.user.contains(body))
        let json = try #require(request.user.components(separatedBy: "BEGIN_UNTRUSTED_SOURCES_JSON\n").last)
        let payload = try #require(json.components(separatedBy: "\nEND_UNTRUSTED_SOURCES_JSON").first)
        let sources = try #require(try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [[String: Any]])
        #expect(sources[0]["sourceMemoryIDs"] as? [String] == ["S2"])
        #expect(sources[1]["sourceMemoryIDs"] as? [String] == ["S1"])
    }

    private func envelope(_ paragraphs: [[String: Any]]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "paragraphs": paragraphs])
        return try #require(String(data: data, encoding: .utf8))
    }
}
