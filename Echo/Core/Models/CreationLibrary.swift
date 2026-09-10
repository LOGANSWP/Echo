// File: CreationLibrary.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md -> US-SYN-003 AC-8/9/10; ADR-026
// Task: 4.0m - Bounded durable creation values
// Architecture: Sendable values, no source text in request descriptors
// Generated: 2026-09-09
import Foundation

nonisolated struct CreationLibraryRequest: Codable, Sendable, Equatable {
    let id: UUID
    let template: CreativeTemplate
    let sourceIDs: [UUID]
    let language: String
    var version = 1
    var modelIdentity = GenerationRuntimeArtifact.identity

    func validate(forExecution: Bool = false) throws {
        guard version == 1, !sourceIDs.isEmpty, sourceIDs.count <= 24,
            Set(sourceIDs).count == sourceIDs.count,
            ["zh-Hans", "en-US"].contains(language), modelIdentity.utf8.count == 64,
            !forExecution || modelIdentity == GenerationRuntimeArtifact.identity
        else { throw GenerationRuntimeError.invalidRequest }
    }
}

nonisolated enum CreationLibraryState: String, Codable, Sendable {
    case submitting, queued, running, completed, failed, cancelled, interrupted, deferred
}

nonisolated struct CreationLibraryRecord: Identifiable, Sendable, Equatable {
    let request: CreationLibraryRequest
    let state: CreationLibraryState
    let createdAt: Date
    let output: CreativeOutput?
    let errorCode: String?
    let unread: Bool
    var id: UUID { request.id }
}
