// ==========================================
// File: BundledPhotoUnderstandingActor.swift
// Spec: US-ING-004 AC-6/8; ADR-025 and approved 4.0l packet
// Task: 4.0l - Local pixel description runtime
// AC coverage: bounded image-to-caption, actual language, no fixture fallback
// Architecture: R-005/R-006, request-owned Core ML state
// Generated: 2026-09-09
// ==========================================

import CoreML
import Foundation

nonisolated enum PhotoRuntimeContractFailure: String, Error, Sendable {
    case stateShape, visionTensor, decoderTensor, nonFiniteScores, generatedProtocolToken, imageIndex

    var severity: ErrorSeverity { self == .generatedProtocolToken ? .l2Recoverable : .l3Blocking }
}

nonisolated public struct PhotoCaptionOutput: Sendable {
    public let text: String
    public let language: String
    public let outputTokenCount: Int
}

nonisolated public protocol PhotoCaptionGenerating: Sendable {
    func describe(imageData: Data, traceID: String) async throws -> PhotoCaptionOutput
}

public actor BundledPhotoUnderstandingActor: PhotoCaptionGenerating {
    private let privacyActor: PrivacyActor
    private let resourceRoot: URL?
    private let manifestActor: ModelManifestActor?
    private var tokenizer: PhotoTokenizer?
    private var ownsRequest = false

    public init(
        privacyActor: PrivacyActor,
        resourceRoot: URL? = Bundle.main.url(
            forResource: "PhotoUnderstanding",
            withExtension: "bundle"
        ),
        manifestActor: ModelManifestActor? = nil
    ) {
        self.privacyActor = privacyActor
        self.resourceRoot = resourceRoot
        self.manifestActor = manifestActor
    }

    public func describe(imageData: Data, traceID: String) async throws -> PhotoCaptionOutput {
        let checkpoint = await privacyActor.validate(operation: .ingest, traceID: traceID, sourceTypes: ["photo"])
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard !ownsRequest else { throw GenerationRuntimeError.busy }
        ownsRequest = true
        defer { ownsRequest = false }
        let lease = try await GenerativeModelSessionActor.shared.acquire()
        do {
            let result = try await perform(
                imageData: imageData,
                traceID: traceID,
                policyVersion: checkpoint.policyVersion
            )
            // perform has returned: its models, feature arrays and KV state are out of scope.
            await GenerativeModelSessionActor.shared.release(lease)
            return result
        } catch {
            await GenerativeModelSessionActor.shared.release(lease)
            if (error as? GenerationRuntimeError)?.severity == .l3Blocking
                || (error as? PhotoRuntimeContractFailure)?.severity == .l3Blocking {
                try? await privacyActor.writeAuditLog(
                    eventType: .modelLoadFailed,
                    traceID: traceID,
                    policyVersion: checkpoint.policyVersion,
                    success: false,
                    sourceType: "photo-understanding",
                    content: String(describing: error)
                )
            }
            throw error
        }
    }

    public func validateAvailability(traceID: String) async throws {
        let checkpoint = await privacyActor.validate(operation: .ingest, traceID: traceID, sourceTypes: ["photo"])
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard let resourceRoot else { throw GenerationRuntimeError.invalidArtifact }
        try GenerationArtifactVerifier.verify(root: resourceRoot, files: ApprovedPhotoUnderstandingArtifact.files)
    }

    private func perform(imageData: Data, traceID: String, policyVersion: Int) async throws -> PhotoCaptionOutput {
        let started = ProcessInfo.processInfo.systemUptime
        guard let resourceRoot else { throw GenerationRuntimeError.invalidArtifact }
        if tokenizer == nil {
            try GenerationArtifactVerifier.verify(root: resourceRoot, files: ApprovedPhotoUnderstandingArtifact.files)
            tokenizer = try PhotoTokenizer(url: resourceRoot.appendingPathComponent("SmolVLMTokenizer/tokenizer.json"))
        }
        guard let tokenizer else { throw GenerationRuntimeError.invalidArtifact }
        try await manifestActor?.register(
            ModelManifest(
                modelId: "smolvlm-256m-photo-context1024-cpu-v2",
                revision: "7e3e67edbbed1bf9888184d9df282b700a323964",
                artifactHash: ApprovedPhotoUnderstandingArtifact.identity,
                licenseId: "apache-2.0",
                runtime: .coreML,
                tokenizer: "smolvlm-byte-bpe-pinned-v1",
                promptTemplate: ApprovedPhotoUnderstandingArtifact.processingVersion,
                pooling: .none,
                normalization: .none,
                dimension: 576,
                quantization: "vision-fp16-decoder-fp32-kv-fp16"
            )
        )
        let prepared = try PhotoImagePreprocessor.prepare(imageData)
        let prompt = try tokenizer.encodePrompt(ApprovedPhotoUnderstandingArtifact.prompt)
        try checkBudget(started: started)
        let config = MLModelConfiguration()
        #if targetEnvironment(simulator)
            // The simulator GPU backend rejects this stateful graph with Espresso -14.
            config.computeUnits = .cpuOnly
        #else
            config.computeUnits = .cpuAndGPU
        #endif
        let vision = try loadModel(resourceRoot.appendingPathComponent("SmolVision512.mlmodelc"), configuration: config)
        let decoder = try loadModel(
            resourceRoot.appendingPathComponent("SmolDecoder1024.mlmodelc"),
            configuration: config
        )
        let states = decoder.modelDescription.stateDescriptionsByName
        guard states.count == 60,
            states.values.allSatisfy({
                $0.stateConstraint?.bufferShape == [1, 3, 1024, 64] && $0.stateConstraint?.dataType == .float16
            })
        else { throw PhotoRuntimeContractFailure.stateShape }
        let embeddings = try visualEmbeddings(prepared, model: vision)
        try checkBudget(started: started)
        let state = decoder.makeState()
        var tokens = prompt
        var generated: [Int] = []
        var position = 0
        var imageIndex = 0
        var ended = false
        while position < tokens.count && generated.count < 128 {
            try checkBudget(started: started)
            guard position < 1024 else { throw GenerationRuntimeError.contextLimit }
            let currentToken = tokens[position]
            let scores = try predict(
                runtime: (decoder, state),
                token: (currentToken, position),
                embeddings: embeddings,
                imageIndex: imageIndex,
                needsLogits: position >= prompt.count - 1
            )
            if currentToken == 49190 { imageIndex += 1 }
            if position >= prompt.count - 1 {
                var top = 0
                var best = -Float.infinity
                for (index, score) in scores.enumerated() {
                    guard score.isFinite else { throw PhotoRuntimeContractFailure.nonFiniteScores }
                    if score > best {
                        top = index
                        best = score
                    }
                }
                generated.append(top)
                if top == 49279 {
                    ended = true
                    break
                }
                // All added/framing tokens fail closed; never feed image tokens back into the decoder.
                guard (17..<49152).contains(top) else { throw PhotoRuntimeContractFailure.generatedProtocolToken }
                tokens.append(top)
            }
            position += 1
            if position.isMultiple(of: 16) {
                let checkpoint = await privacyActor.validate(
                    operation: .ingest,
                    traceID: traceID,
                    sourceTypes: ["photo"]
                )
                guard checkpoint.isAllowed, checkpoint.policyVersion == policyVersion else {
                    throw GenerationRuntimeError.privacyDenied
                }
            }
        }
        guard ended, imageIndex == 64 else { throw GenerationRuntimeError.outputLimit }
        let text = try tokenizer.decode(Array(generated.dropLast())).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 4096 else { throw GenerationRuntimeError.outputLimit }
        guard LanguageAligner.detectLanguage(text) == "en-US" else { throw GenerationRuntimeError.languageFallback }
        let final = await privacyActor.validate(operation: .ingest, traceID: traceID, sourceTypes: ["photo"])
        guard final.isAllowed, final.policyVersion == policyVersion else { throw GenerationRuntimeError.privacyDenied }
        try checkBudget(started: started)
        return PhotoCaptionOutput(text: text, language: "en-US", outputTokenCount: generated.count)
    }

    private func visualEmbeddings(_ prepared: PreparedPhoto, model: MLModel) throws -> [Float] {
        try autoreleasepool {
            let pixels = try MLMultiArray(shape: [1, 3, 512, 512], dataType: .float32)
            for index in prepared.pixels.indices { pixels[index] = NSNumber(value: prepared.pixels[index]) }
            let positions = try MLMultiArray(shape: [1, 1024], dataType: .int32)
            let mask = try MLMultiArray(shape: [1, 1, 1, 1024], dataType: .float32)
            for index in 0..<1024 {
                positions[index] = NSNumber(value: prepared.positionIDs[index])
                mask[index] = NSNumber(value: prepared.attentionMask[index])
            }
            let output = try model.prediction(
                from: MLDictionaryFeatureProvider(dictionary: [
                    "pixels": pixels, "position_ids": positions, "attention_mask": mask,
                ])
            )
            guard let value = output.featureValue(for: "image_embeddings")?.multiArrayValue,
                value.shape == [1, 64, 576], value.dataType == .float32
            else { throw PhotoRuntimeContractFailure.visionTensor }
            return PhotoTensorValues.logicalFloats(value)
        }
    }

    private func loadModel(_ url: URL, configuration: MLModelConfiguration) throws -> MLModel {
        do { return try MLModel(contentsOf: url, configuration: configuration) } catch {
            throw GenerationRuntimeError.modelContract
        }
    }

    private func predict(
        runtime: (model: MLModel, state: MLState),
        token input: (id: Int, position: Int),
        embeddings: [Float],
        imageIndex: Int,
        needsLogits: Bool
    ) throws -> [Float] {
        try autoreleasepool {
            let token = try MLMultiArray(shape: [1, 1], dataType: .int32)
            let offset = try MLMultiArray(shape: [1], dataType: .int32)
            let image = try MLMultiArray(shape: [1, 1, 576], dataType: .float32)
            token[0] = NSNumber(value: input.id)
            offset[0] = NSNumber(value: input.position)
            guard input.id != 49190 || (0..<64).contains(imageIndex) else {
                throw PhotoRuntimeContractFailure.imageIndex
            }
            for column in 0..<576 {
                image[column] = input.id == 49190 ? NSNumber(value: embeddings[imageIndex * 576 + column]) : 0
            }
            let output = try runtime.model.prediction(
                from: MLDictionaryFeatureProvider(dictionary: [
                    "token_id": token, "position": offset, "image_embedding": image,
                ]),
                using: runtime.state
            )
            guard let logits = output.featureValue(for: "logits")?.multiArrayValue,
                logits.count == 49280, logits.dataType == .float32
            else { throw PhotoRuntimeContractFailure.decoderTensor }
            return needsLogits ? PhotoTensorValues.logicalFloats(logits) : []
        }
    }

    private func checkBudget(started: Double) throws {
        try GenerationResourcePolicy.check()
        guard ProcessInfo.processInfo.systemUptime - started <= 60 else { throw GenerationRuntimeError.deadline }
        guard try GenerationMemorySample.capture("photo").physicalFootprintBytes < 1_500_000_000 else {
            throw GenerationRuntimeError.memoryLimit
        }
    }
}
