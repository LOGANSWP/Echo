// ==========================================
// File: GenerationReferenceMap.swift
// Spec: US-SYN-002 AC-1/2/3; ADR-023 requestAliasV1
// Task: 4.0k - Lossless request-owned source transport
// AC coverage: explicit alias lookup, unchanged text, bounded decoding and no source fallback
// Architecture: AGENTS.md section 4.2; immutable Sendable values, no persistence
// Generated: 2026-09-08
// ==========================================

import Foundation

nonisolated public enum GenerationReferenceEncoding: Sendable {
    case memoryUUID, requestAliasV1
}

nonisolated struct GenerationReferenceMap: Sendable {
    let aliases: [String]
    private let byAlias: [String: UUID]
    private let byMemoryID: [UUID: String]

    init(memoryIDs: [UUID]) {
        let ids = Array(Set(memoryIDs)).sorted { $0.uuidString < $1.uuidString }
        let names = ids.indices.map { "S\($0 + 1)" }
        aliases = names
        byAlias = Dictionary(uniqueKeysWithValues: zip(names, ids))
        byMemoryID = Dictionary(uniqueKeysWithValues: zip(ids, names))
    }

    func alias(for memoryID: UUID) throws -> String {
        guard let value = byMemoryID[memoryID] else { throw GenerationRuntimeError.invalidRequest }
        return value
    }

    /// This is a transport decode, not a repair: only explicit known references are restored.
    func resolveEnvelope(_ raw: String) throws -> String {
        let input = Data(raw.utf8)
        guard input.count <= CreativeGenerationLimits.maximumPayloadBytes else {
            throw GenerationRuntimeError.invalidRequest
        }
        do {
            var envelope = try JSONDecoder().decode(Envelope.self, from: input)
            guard envelope.schemaVersion == 1, !envelope.paragraphs.isEmpty,
                envelope.paragraphs.count <= CreativeGenerationLimits.maximumParagraphs
            else { throw GenerationRuntimeError.invalidRequest }
            for index in envelope.paragraphs.indices {
                let paragraph = envelope.paragraphs[index]
                guard !paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    paragraph.text.count <= CreativeGenerationLimits.maximumParagraphCharacters,
                    paragraph.sourceMemoryIDs.count <= CreativeGenerationLimits.maximumReferencesPerParagraph
                else { throw GenerationRuntimeError.invalidRequest }
                envelope.paragraphs[index].sourceMemoryIDs = try paragraph.sourceMemoryIDs.map { reference in
                    guard let id = byAlias[reference] else { throw GenerationRuntimeError.invalidRequest }
                    return id.uuidString
                }
            }
            let encoded = try JSONEncoder().encode(envelope)
            guard encoded.count <= CreativeGenerationLimits.maximumPayloadBytes,
                let result = String(data: encoded, encoding: .utf8)
            else { throw GenerationRuntimeError.invalidRequest }
            return result
        } catch {
            throw GenerationRuntimeError.invalidRequest
        }
    }

    nonisolated private struct Envelope: Codable {
        let schemaVersion: Int
        var paragraphs: [Paragraph]
    }

    nonisolated private struct Paragraph: Codable {
        let text: String
        var sourceMemoryIDs: [String]
    }
}
