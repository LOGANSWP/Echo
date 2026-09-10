// ==========================================
// File: BundledGenerationActor.swift
// Spec: US-SYN-001/002/004; ADR-009/023
// Task: 4.0k - Approved Core ML generation runtime
// AC coverage: file integrity, request isolation, bounded tokens, explicit reference decoding and poem form
// Architecture: AGENTS.md sections 4.2, 7.1, R-005/R-007
// Task 4.0l: release request models before handing the shared visual/text lease to another actor.
// Generated: 2026-09-08
// ==========================================

import CoreML
import Foundation
import OSLog

public actor BundledGenerationActor: StructuredLLMProvider {
    private let resourceRoot: URL?
    private let privacyActor: PrivacyActor
    private let manifestActor: ModelManifestActor?
    private var manifestRegistered = false
    private var tokenizer: GenerationTokenizer?
    private var ownsRequest = false
    private var artifactFailure = false
    private var modelFailure = false
    private var modelValidated = false

    public init(resourceRoot: URL?, privacyActor: PrivacyActor, manifestActor: ModelManifestActor? = nil) {
        self.resourceRoot = resourceRoot
        self.privacyActor = privacyActor
        self.manifestActor = manifestActor
    }

    public func validateAvailability(traceID: String) async throws {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        let lease = try await GenerativeModelSessionActor.shared.acquire()
        do {
            try await validateAvailabilityUnderLease(traceID: traceID)
            await GenerativeModelSessionActor.shared.release(lease)
        } catch {
            await GenerativeModelSessionActor.shared.release(lease)
            throw error
        }
    }

    private func validateAvailabilityUnderLease(traceID: String) async throws {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard !ownsRequest else { throw GenerationRuntimeError.busy }
        ownsRequest = true
        defer { ownsRequest = false }
        do {
            try prepareTokenizer()
            try await registerVerifiedIdentity()
            guard !modelFailure else { throw GenerationRuntimeError.modelContract }
            if !modelValidated {
                let started = ProcessInfo.processInfo.systemUptime
                try autoreleasepool { _ = try loadModel() }
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime - started < 60 else { throw GenerationRuntimeError.deadline }
                try checkMemory()
                modelValidated = true
            }
        } catch {
            await recordModelFailure(error, traceID: traceID, policyVersion: checkpoint.policyVersion)
            throw error
        }
    }

    /// Only an explicit repair action clears cached failure; fixed approval and bytes are rechecked.
    public func retryAvailability(traceID: String) async throws {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard !ownsRequest else { throw GenerationRuntimeError.busy }
        artifactFailure = false
        modelFailure = false
        modelValidated = false
        manifestRegistered = false
        tokenizer = nil
        try await validateAvailability(traceID: traceID)
        try await privacyActor.writeAuditLog(
            eventType: .modelLoadRetrySuccess,
            traceID: traceID,
            policyVersion: checkpoint.policyVersion,
            sourceType: GenerationRuntimeArtifact.modelName
        )
    }

    public func tokenCount(request: GenerationRequest) async throws -> Int {
        let checkpoint = await privacyActor.validate(
            operation: .search,
            traceID: request.traceID,
            sourceTypes: request.sourceTypes
        )
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        try prepareTokenizer()
        return try tokens(for: request).count
    }

    /// Legacy string-only requests cannot enter the production provider without provenance.
    public func generate(prompt: String, preferredLanguage: String) async throws -> String {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: UUID().uuidString)
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        throw GenerationRuntimeError.invalidRequest
    }

    public func generate(request: GenerationRequest) async throws -> GenerationResult {
        let checkpoint = await privacyActor.validate(
            operation: .search,
            traceID: request.traceID,
            sourceTypes: request.sourceTypes
        )
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        let lease = try await GenerativeModelSessionActor.shared.acquire()
        do {
            let result = try await generateUnderLease(request: request)
            await GenerativeModelSessionActor.shared.release(lease)
            return result
        } catch {
            await GenerativeModelSessionActor.shared.release(lease)
            throw error
        }
    }

    private func generateUnderLease(request: GenerationRequest) async throws -> GenerationResult {
        let checkpoint = await privacyActor.validate(
            operation: .search,
            traceID: request.traceID,
            sourceTypes: request.sourceTypes
        )
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard !ownsRequest else { throw GenerationRuntimeError.busy }
        ownsRequest = true
        defer { ownsRequest = false }
        do {
            let policy = await privacyActor.getPolicy()
            guard policy.preferredLanguage == request.preferredLanguage,
                policy.policyVersion == checkpoint.policyVersion
            else { throw GenerationRuntimeError.privacyDenied }
            try prepareTokenizer()
            try await registerVerifiedIdentity()
            let prompt = try tokens(for: request)
            let start = ProcessInfo.processInfo.systemUptime
            var loadSeconds = 0.0
            var prefillSeconds = 0.0
            var decodeSeconds = 0.0
            var selectionSeconds = 0.0
            var generatedTokens = 0
            defer {
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                Logger(subsystem: "com.echo.Echo", category: "GenerationTiming").notice(
                    "Generation timing: elapsed=\(elapsed, privacy: .public) load=\(loadSeconds, privacy: .public) prefill=\(prefillSeconds, privacy: .public) decode=\(decodeSeconds, privacy: .public) selection=\(selectionSeconds, privacy: .public) tokens=\(generatedTokens, privacy: .public)"
                )
            }
            guard resourceRoot != nil, let tokenizer,
                request.executionDeadline.isFinite, request.executionDeadline > start
            else {
                throw GenerationRuntimeError.deadline
            }
            var budget = try GenerationBudget(
                inputCount: prompt.count,
                outputLimit: 256,
                context: 1024,
                startedAt: start,
                seconds: min(request.executionScope.callSeconds, request.executionDeadline - start),
                executionScope: request.executionScope
            )
            let referenceMap = GenerationReferenceMap(memoryIDs: request.allowedMemoryIDs)
            let grammar = request.referenceEncoding == .requestAliasV1
                ? try GenerationEnvelopeGrammar(
                    allowedAliases: referenceMap.aliases, requiresPoem: request.outputForm == .poem)
                : try GenerationEnvelopeGrammar(
                    allowedIDs: request.allowedMemoryIDs.map { $0.uuidString.lowercased() },
                    requiresPoem: request.outputForm == .poem
                )
            var decoder = GenerationGrammarDecoder(
                grammar: grammar,
                tokenBytes: tokenizer.bytesByToken.filter { $0.key < 151_643 },
                eosIDs: [151_645, 151_643]
            )
            try checkMemory()
            // All non-Sendable Core ML objects stay on this actor. Synchronous prediction
            // has an SDK-supported state overload; no unsafe conformance or actor escape.
            let loadStarted = ProcessInfo.processInfo.systemUptime
            let model = try loadModel()
            loadSeconds = ProcessInfo.processInfo.systemUptime - loadStarted
            try budget.afterPrediction(now: ProcessInfo.processInfo.systemUptime)
            let state = model.makeState()
            var lastToken: Int?
            var position = 0
            while budget.outputCount < 256 && !decoder.ended {
                try GenerationResourcePolicy.check()
                let count = position < prompt.count
                    ? min(GenerationRuntimeArtifact.prefillBatchSize, prompt.count - position) : 1
                try budget.beforePrediction(position: position, count: count, now: ProcessInfo.processInfo.systemUptime)
                let inputTokens: [Int]
                if position < prompt.count {
                    inputTokens = Array(prompt[position..<position + count])
                } else if let lastToken {
                    inputTokens = [lastToken]
                } else {
                    throw GenerationRuntimeError.invalidRequest
                }
                let predictionStarted = ProcessInfo.processInfo.systemUptime
                let isPrefill = position < prompt.count
                let scores = try predict(
                    model: model,
                    state: state,
                    tokens: inputTokens,
                    position: position,
                    needsLogits: position + count >= prompt.count
                )
                let predictionSeconds = ProcessInfo.processInfo.systemUptime - predictionStarted
                if isPrefill { prefillSeconds += predictionSeconds } else { decodeSeconds += predictionSeconds }
                try budget.afterPrediction(now: ProcessInfo.processInfo.systemUptime)
                try GenerationResourcePolicy.check()
                try checkMemory()
                position += count
                if position >= prompt.count {
                    let selectionStarted = ProcessInfo.processInfo.systemUptime
                    let next: Int
                    do {
                        defer { selectionSeconds += ProcessInfo.processInfo.systemUptime - selectionStarted }
                        next = try decoder.select(scores, deadline: budget.deadline)
                    }
                    generatedTokens += 1
                    try budget.recordOutput(now: ProcessInfo.processInfo.systemUptime)
                    try decoder.accept(next)
                    lastToken = next
                }
                // Ownership survives reentrancy; policy and cancellation are checked again.
                if position.isMultiple(of: 16) {
                    let current = await privacyActor.validate(
                        operation: .search,
                        traceID: request.traceID,
                        sourceTypes: request.sourceTypes
                    )
                    guard current.isAllowed, current.policyVersion == checkpoint.policyVersion else {
                        throw GenerationRuntimeError.privacyDenied
                    }
                }
            }
            guard decoder.ended, let envelope = String(bytes: decoder.output, encoding: .utf8) else {
                throw GenerationRuntimeError.outputLimit
            }
            let canonicalEnvelope = request.referenceEncoding == .requestAliasV1
                ? try referenceMap.resolveEnvelope(envelope) : envelope
            let final = await privacyActor.validate(
                operation: .search,
                traceID: request.traceID,
                sourceTypes: request.sourceTypes
            )
            guard final.isAllowed, final.policyVersion == checkpoint.policyVersion else {
                throw GenerationRuntimeError.privacyDenied
            }
            try budget.afterPrediction(now: ProcessInfo.processInfo.systemUptime)
            return GenerationResult(
                envelope: canonicalEnvelope,
                inputTokenCount: prompt.count,
                outputTokenCount: budget.outputCount,
                predictionCount: budget.predictionCount,
                elapsedSeconds: ProcessInfo.processInfo.systemUptime - start,
                artifactIdentity: GenerationRuntimeArtifact.identity
            )
        } catch let error as GenerationBudgetError {
            switch error {
            case .deadline: throw GenerationRuntimeError.deadline
            case .exhausted: throw GenerationRuntimeError.outputLimit
            case .invalidInput: throw GenerationRuntimeError.contextLimit
            case .invalidPosition: throw GenerationRuntimeError.modelContract
            }
        } catch GenerationTokenizerError.inputBudget {
            throw GenerationRuntimeError.contextLimit
        } catch is GenerationGrammarError {
            throw GenerationRuntimeError.invalidRequest
        } catch let error as GenerationRuntimeError {
            await recordModelFailure(error, traceID: request.traceID, policyVersion: checkpoint.policyVersion)
            throw error
        }
    }

    private func registerVerifiedIdentity() async throws {
        guard tokenizer != nil else { throw GenerationRuntimeError.invalidArtifact }
        guard !manifestRegistered, let manifestActor else { return }
        try await manifestActor.register(GenerationRuntimeArtifact.manifest)
        manifestRegistered = true
    }

    private func recordModelFailure(_ error: Error, traceID: String, policyVersion: Int) async {
        guard let failure = error as? GenerationRuntimeError, failure.severity == .l3Blocking else { return }
        try? await privacyActor.writeAuditLog(
            eventType: .modelLoadFailed,
            traceID: traceID,
            policyVersion: policyVersion,
            success: false,
            sourceType: GenerationRuntimeArtifact.modelName,
            content: String(describing: failure)
        )
    }

    private func prepareTokenizer() throws {
        try Task.checkCancellation()
        guard !artifactFailure, let resourceRoot else { throw GenerationRuntimeError.invalidArtifact }
        guard tokenizer == nil else { return }
        do {
            try GenerationArtifactVerifier.verify(root: resourceRoot, files: GenerationRuntimeArtifact.files)
            tokenizer = try GenerationTokenizer(
                url: resourceRoot.appendingPathComponent("Qwen3Tokenizer/tokenizer.json")
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            artifactFailure = true
            throw GenerationRuntimeError.invalidArtifact
        }
    }

    private func loadModel() throws -> MLModel {
        try Task.checkCancellation()
        guard !modelFailure, let resourceRoot else { throw GenerationRuntimeError.modelContract }
        let configuration = MLModelConfiguration()
        #if DEBUG && targetEnvironment(simulator)
            configuration.computeUnits = .cpuOnly
            configuration.optimizationHints.specializationStrategy = .fastPrediction
            configuration.optimizationHints.reshapeFrequency = .infrequent
        #else
            configuration.computeUnits = .cpuAndGPU
        #endif
        do {
            let model = try MLModel(
                contentsOf: resourceRoot.appendingPathComponent(
                    GenerationRuntimeArtifact.modelName + ".mlmodelc"
                ),
                configuration: configuration
            )
            let descriptions = model.modelDescription.stateDescriptionsByName
            let inputs = model.modelDescription.inputDescriptionsByName
            let width = GenerationRuntimeArtifact.prefillBatchSize
            guard descriptions.count == 56,
                inputs["token_id"]?.multiArrayConstraint?.shape == [1, NSNumber(value: width)],
                inputs["position"]?.multiArrayConstraint?.shape == [NSNumber(value: width)],
                width == 1 || inputs["valid_count"]?.multiArrayConstraint?.shape == [1],
                descriptions.values.allSatisfy({
                    $0.stateConstraint?.bufferShape == [1, 8, 1024, 128] && $0.stateConstraint?.dataType == .float16
                })
            else { throw GenerationRuntimeError.modelContract }
            return model
        } catch {
            modelFailure = true
            throw GenerationRuntimeError.modelContract
        }
    }

    private func tokens(for request: GenerationRequest) throws -> [Int] {
        guard let tokenizer, ["en-US", "zh-Hans"].contains(request.preferredLanguage),
            (1...24).contains(request.allowedMemoryIDs.count), !request.sourceTypes.isEmpty,
            !request.traceID.isEmpty
        else { throw GenerationRuntimeError.invalidRequest }
        let tokens = try tokenizer.encodeChat([
            GenerationChatMessage(role: "system", content: request.system),
            GenerationChatMessage(role: "user", content: request.user),
        ])
        guard tokens.count <= 768 else { throw GenerationRuntimeError.contextLimit }
        return tokens
    }

    private func predict(
        model: MLModel, state: MLState, tokens: [Int], position: Int, needsLogits: Bool
    ) throws -> [Float] {
        let width = GenerationRuntimeArtifact.prefillBatchSize
        guard !tokens.isEmpty, tokens.count <= width else { throw GenerationRuntimeError.invalidRequest }
        let tokenArray = try MLMultiArray(shape: [1, NSNumber(value: width)], dataType: .int32)
        let positionArray = try MLMultiArray(shape: [NSNumber(value: width)], dataType: .int32)
        for index in 0..<width {
            let sourceIndex = min(index, tokens.count - 1)
            tokenArray[index] = NSNumber(value: tokens[sourceIndex])
            positionArray[index] = NSNumber(value: position + sourceIndex)
        }
        var features: [String: MLMultiArray] = ["token_id": tokenArray, "position": positionArray]
        if width > 1 {
            let validCount = try MLMultiArray(shape: [1], dataType: .int32)
            validCount[0] = NSNumber(value: tokens.count)
            features["valid_count"] = validCount
        }
        let input = try MLDictionaryFeatureProvider(dictionary: features)
        let output: any MLFeatureProvider
        do {
            output = try model.prediction(from: input, using: state)
        } catch {
            modelFailure = true
            throw GenerationRuntimeError.modelContract
        }
        guard let logits = output.featureValue(for: "logits")?.multiArrayValue,
            logits.count == 151_936, logits.dataType == .float32
        else { throw GenerationRuntimeError.modelContract }
        return needsLogits ? logits.withUnsafeBufferPointer(ofType: Float.self) { Array($0) } : []
    }

    private func checkMemory() throws {
        let sample: GenerationMemorySample
        do {
            sample = try GenerationMemorySample.capture("generation")
        } catch {
            throw GenerationRuntimeError.memoryLimit
        }
        guard sample.physicalFootprintBytes < 1_500_000_000 else { throw GenerationRuntimeError.memoryLimit }
    }
}
