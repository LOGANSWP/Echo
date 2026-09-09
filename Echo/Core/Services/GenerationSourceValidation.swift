// ==========================================
// File: GenerationSourceValidation.swift
// Spec: US-SYN-004; ADR-023 section 3
// Task: 4.0k - Revalidate actual inputs around every model call
// AC coverage: edits, deletion and authorization invalidate generated prose
// Architecture: AGENTS.md sections 4.2/7.1; immutable actor references and values
// Generated: 2026-09-08
// ==========================================

import Foundation

nonisolated public struct GenerationSourceValidation: Sendable {
    let repository: CanonicalMemoryRepositoryActor
    let sources: [CreativeSource]
    let excerptScalarLimit: Int?
    var useEffectiveSourceText = false

    func validate() async throws {
        for source in sources {
            try Task.checkCancellation()
            if useEffectiveSourceText {
                guard let current = try await repository.loadCreationSource(memoryID: source.memoryID),
                      current.revision == source.revision, current.text == source.text,
                      SearchPipeline.normalizeSourceType(current.sourceType)
                        == SearchPipeline.normalizeSourceType(source.sourceType) else {
                    throw GenerationRuntimeError.privacyDenied
                }
                continue
            }
            guard let memory = try await repository.loadMemory(memoryId: source.memoryID),
                memory.updatedAt.timeIntervalSince1970 == source.revision,
                SearchPipeline.normalizeSourceType(memory.sourceType)
                    == SearchPipeline.normalizeSourceType(source.sourceType)
            else { throw GenerationRuntimeError.privacyDenied }
            let text = memory.canonicalText ?? ""
            let compared: String
            if let excerptScalarLimit {
                compared = String(String.UnicodeScalarView(text.unicodeScalars.prefix(excerptScalarLimit)))
            } else {
                compared = text
            }
            guard compared == source.text ?? "" else { throw GenerationRuntimeError.privacyDenied }
        }
    }
}
