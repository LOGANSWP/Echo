// ==========================================
// File: GenerationRequest.swift
// Spec: US-SYN-001/002/003/004; ADR-023 sections 1-5
// Task: 4.0k - Typed bounded generation
// AC coverage: source identity, language, deadline, finish reason and retry-preserved form/reference encoding
// Architecture: AGENTS.md sections 4.2, 6.2
// Generated: 2026-09-08
// ==========================================

import Foundation

nonisolated public enum GenerationRuntimeError: Error, Sendable, Equatable {
    case invalidArtifact, modelContract, busy, invalidRequest, contextLimit
    case outputLimit, deadline, memoryLimit, privacyDenied, languageFallback, restartRequired

    public var severity: ErrorSeverity {
        switch self {
        case .invalidArtifact, .modelContract: .l3Blocking
        default: .l2Recoverable
        }
    }
}

nonisolated public enum GenerationOutputForm: Sendable {
    case prose, poem
}

nonisolated public struct GenerationRequest: Sendable {
    public let outputForm: GenerationOutputForm
    public let referenceEncoding: GenerationReferenceEncoding
    public let system: String
    public let user: String
    public let allowedMemoryIDs: [UUID]
    public let sourceTypes: [String]
    public let preferredLanguage: String
    public let traceID: String
    public let executionDeadline: Double

    public init(
        system: String,
        user: String,
        allowedMemoryIDs: [UUID],
        sourceTypes: [String],
        preferredLanguage: String,
        traceID: String,
        executionDeadline: Double,
        outputForm: GenerationOutputForm = .prose,
        referenceEncoding: GenerationReferenceEncoding = .memoryUUID
    ) {
        self.system = system
        self.user = user
        self.allowedMemoryIDs = Array(Set(allowedMemoryIDs)).sorted { $0.uuidString < $1.uuidString }
        self.sourceTypes = Array(Set(sourceTypes)).sorted()
        self.preferredLanguage = preferredLanguage
        self.traceID = traceID
        self.executionDeadline = executionDeadline
        self.outputForm = outputForm
        self.referenceEncoding = referenceEncoding
    }

    public func languageRetry() -> Self {
        Self(
            system: system + (preferredLanguage == "zh-Hans"
                ? " 请检查每段正文，必须全部使用简体中文，不要直接复制英文来源。"
                : " Respond entirely in \(preferredLanguage); check the language of every paragraph."),
            user: user,
            allowedMemoryIDs: allowedMemoryIDs,
            sourceTypes: sourceTypes,
            preferredLanguage: preferredLanguage,
            traceID: traceID,
            executionDeadline: executionDeadline,
            outputForm: outputForm,
            referenceEncoding: referenceEncoding
        )
    }
}

nonisolated public struct GenerationResult: Sendable {
    public enum FinishReason: String, Sendable { case endOfSequence }
    public var finishReason: FinishReason { .endOfSequence }
    public let envelope: String
    public let inputTokenCount: Int
    public let outputTokenCount: Int
    public let predictionCount: Int
    public let elapsedSeconds: Double
    public let artifactIdentity: String
}

/// The production contract cannot discard trace, provenance or termination evidence.
nonisolated public protocol StructuredLLMProvider: LLMProvider {
    func validateAvailability(traceID: String) async throws
    func retryAvailability(traceID: String) async throws
    func tokenCount(request: GenerationRequest) async throws -> Int
    func generate(request: GenerationRequest) async throws -> GenerationResult
}

nonisolated extension StructuredLLMProvider {
    public func retryAvailability(traceID: String) async throws {
        try await validateAvailability(traceID: traceID)
    }
}
