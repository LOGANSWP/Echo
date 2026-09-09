// ==========================================
// File: NarrativeGenerationIdentity.swift
// Spec: US-SYN-004; ADR-023 section 5
// Task: 4.0k - Content-free recovery identity
// AC coverage: model/tokenizer/template/input/language/budget changes require Restart
// Architecture: AGENTS.md section 4.5; no source text or KV persistence
// Generated: 2026-09-08
// ==========================================

import Foundation

nonisolated enum NarrativeGenerationIdentity {
    static func digest(
        sources: [CreativeSource],
        language: String,
        policyVersion: Int,
        batches: [[CreativeSource]] = [],
        configuration: String = "default"
    ) throws -> String {
        let rows: [[String: String]] = sources.map { source in
            [
                "id": source.memoryID.uuidString, "type": source.sourceType,
                "textDigest": AuditContentHasher.sha256Hex(source.text ?? ""),
                "timestamp": String(source.timestamp), "revision": source.revision.map { String($0) } ?? "none",
            ]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(rows)
        let partitionData = try encoder.encode(batches.map { $0.map { $0.memoryID.uuidString } })
        guard let input = String(data: encoded, encoding: .utf8) else { throw GenerationRuntimeError.invalidRequest }
        let prefix =
            GenerationRuntimeArtifact.identity + ":" + GenerationRuntimeArtifact.computeBackend
            + ":" + GenerationPrompt.version + ":hierarchy-v2:1024/256/4/24/3/32/600:"
        return AuditContentHasher.sha256Hex(
            prefix + language + ":" + String(policyVersion) + ":" + input
                + ":" + partitionData.base64EncodedString() + ":" + configuration
        )
    }
}
