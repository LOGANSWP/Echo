// Task 4.0k / ADR-023 sections 1-4 and 6: full native research generation.
// Fixed synthetic requests, local pinned model/tokenizer, fresh MLState per call.
// This CLI is not an approved provider, production composition, or iPhone proof.
import CoreML
import Darwin
import Foundation

struct NativeGenerationCase: Decodable {
    let id: String
    let messages: [ChatMessage]
    let allowedIDs: [String]
}

struct NativeGenerationInput: Decodable {
    let schemaVersion: Int
    let context: Int
    let outputLimit: Int
    let cases: [NativeGenerationCase]
}

struct GenerationConfiguration: Decodable {
    let eos_token_id: [Int]
}

struct NativeGenerationResult: Encodable {
    let kind = "case"
    let id: String
    let inputTokenIDs: [Int]
    let outputTokenIDs: [Int]
    let decodedOutput: String?
    let outputBytes: Data
    let stopReason: String
    let predictionCalls: Int
    let candidateChecks: Int
    let elapsedSeconds: Double
    let maximumPhysicalFootprintBytes: Int64
    let finalMemory: MemorySample
}

struct NativeGenerationHeader: Encodable {
    let kind = "loaded"
    let schemaVersion = 1
    let evidenceKind = "native_swift_coreml_structured_generation"
    let productionApproval = "not_granted"
    let computeUnits = "cpuAndGPU"
    let context = 1024
    let outputLimit = 256
    let callDeadlineSeconds = 60
    let runDeadlineSeconds = 600
    let physicalFootprintLimitBytes = 1_500_000_000
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    let compilationSeconds: Double
    let loadSeconds: Double
    let memory: [MemorySample]
}

enum NativeGenerationError: Error { case invalidInput, modelContract }

@main
enum NativeGenerationProbe {
    static func emit<T: Encodable>(_ record: T) throws {
        var data = try JSONEncoder().encode(record)
        data.append(10)
        FileHandle.standardOutput.write(data)
    }

    static func memory(_ stage: String) throws -> MemorySample {
        let sample = try MemorySample.capture(stage)
        guard sample.kernelPhysicalFootprintPeakBytes < 1_500_000_000 else { throw GenerationMemoryError.limit }
        return sample
    }

    nonisolated static func execute() async throws {
        let args = CommandLine.arguments
        guard args.count == 5 else { throw NativeGenerationError.invalidInput }
        let package = URL(fileURLWithPath: args[1])
        let tokenizerURL = URL(fileURLWithPath: args[2])
        let data = try Data(contentsOf: URL(fileURLWithPath: args[3]))
        guard data.count <= 262_144 else { throw NativeGenerationError.invalidInput }
        let input = try JSONDecoder().decode(NativeGenerationInput.self, from: data)
        guard input.schemaVersion == 1, input.context == 1024, input.outputLimit == 256,
            (1...8).contains(input.cases.count), Set(input.cases.map(\.id)).count == input.cases.count,
            input.cases.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 64 })
        else {
            throw NativeGenerationError.invalidInput
        }
        let cancellationPoint: Int?
        if args[4] == "generate" {
            cancellationPoint = nil
        } else if args[4] == "cancel-after-first-prediction" {
            cancellationPoint = 1
        } else {
            throw NativeGenerationError.invalidInput
        }
        let generationConfig = try JSONDecoder().decode(
            GenerationConfiguration.self,
            from: Data(
                contentsOf: tokenizerURL.deletingLastPathComponent().appendingPathComponent("generation_config.json")
            )
        )
        guard generationConfig.eos_token_id == [151_645, 151_643] else { throw NativeGenerationError.invalidInput }
        let runStart = ProcessInfo.processInfo.systemUptime
        var samples = [try memory("before_tokenizer")]
        let tokenizer = try Tokenizer(url: tokenizerURL)
        samples.append(try memory("after_tokenizer"))
        // Validate every complete prompt and reserve output before compiling/loading.
        let prepared = try input.cases.map { item in
            let tokens = try tokenizer.encodeChat(item.messages)
            _ = try EnvelopeGrammar(allowedIDs: item.allowedIDs)
            _ = try GenerationBudget(
                inputCount: tokens.count,
                outputLimit: input.outputLimit,
                context: input.context,
                startedAt: runStart,
                seconds: 60
            )
            return tokens
        }
        let ordinaryBytes = tokenizer.bytesByToken.filter { $0.key < 151_643 }
        let compileStart = ProcessInfo.processInfo.systemUptime
        let compiled = try await MLModel.compileModel(at: package)
        defer { try? FileManager.default.removeItem(at: compiled) }
        let compilationSeconds = ProcessInfo.processInfo.systemUptime - compileStart
        samples.append(try memory("after_compile"))
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        let loadStart = ProcessInfo.processInfo.systemUptime
        let model = try await MLModel.load(contentsOf: compiled, configuration: config)
        let loadSeconds = ProcessInfo.processInfo.systemUptime - loadStart
        samples.append(try memory("after_load"))
        let states = model.modelDescription.stateDescriptionsByName
        guard states.count == 56,
            states.values.allSatisfy({
                $0.stateConstraint?.bufferShape == [1, 8, 1024, 128] && $0.stateConstraint?.dataType == .float16
            })
        else { throw NativeGenerationError.modelContract }
        try emit(
            NativeGenerationHeader(compilationSeconds: compilationSeconds, loadSeconds: loadSeconds, memory: samples)
        )
        for (item, prompt) in zip(input.cases, prepared) {
            let start = ProcessInfo.processInfo.systemUptime
            var budget = try GenerationBudget(
                inputCount: prompt.count,
                outputLimit: input.outputLimit,
                context: input.context,
                startedAt: start,
                seconds: min(60, runStart + 600 - start)
            )
            var decoder = GrammarDecoder(
                grammar: try EnvelopeGrammar(allowedIDs: item.allowedIDs),
                tokenBytes: ordinaryBytes,
                eosIDs: Set(generationConfig.eos_token_id)
            )
            let state = model.makeState()
            var scores: [Float] = []
            var generated: [Int] = []
            var position = 0
            var measured = try memory(item.id + "_start")
            while generated.count < input.outputLimit && !decoder.ended {
                if position < prompt.count || !generated.isEmpty {
                    let token = position < prompt.count ? prompt[position] : generated[generated.count - 1]
                    try budget.beforePrediction(position: position, now: ProcessInfo.processInfo.systemUptime)
                    let tokenArray = try MLMultiArray(shape: [1, 1], dataType: .int32)
                    let positionArray = try MLMultiArray(shape: [1], dataType: .int32)
                    tokenArray[0] = NSNumber(value: token)
                    positionArray[0] = NSNumber(value: position)
                    let features = try MLDictionaryFeatureProvider(dictionary: [
                        "token_id": tokenArray, "position": positionArray,
                    ])
                    let output = try await model.prediction(from: features, using: state)
                    if cancellationPoint == budget.predictionCount {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                    try budget.afterPrediction(now: ProcessInfo.processInfo.systemUptime)
                    measured = try memory(item.id + "_prediction")
                    guard let logits = output.featureValue(for: "logits")?.multiArrayValue,
                        logits.count == 151_936, logits.dataType == .float32
                    else { throw NativeGenerationError.modelContract }
                    position += 1
                    if position < prompt.count { continue }
                    scores = logits.withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
                }
                let token = try decoder.select(scores, deadline: budget.deadline)
                try budget.recordOutput(now: ProcessInfo.processInfo.systemUptime)
                try decoder.accept(token)
                generated.append(token)
            }
            try emit(
                NativeGenerationResult(
                    id: item.id,
                    inputTokenIDs: prompt,
                    outputTokenIDs: generated,
                    decodedOutput: String(bytes: decoder.output, encoding: .utf8),
                    outputBytes: Data(decoder.output),
                    stopReason: decoder.ended ? "eos" : "max_new_tokens",
                    predictionCalls: budget.predictionCount,
                    candidateChecks: decoder.candidateChecks,
                    elapsedSeconds: ProcessInfo.processInfo.systemUptime - start,
                    maximumPhysicalFootprintBytes: measured.kernelPhysicalFootprintPeakBytes,
                    finalMemory: measured
                )
            )
        }
        try emit(["kind": "completed", "productionApproval": "not_granted"])
    }

    static func main() async {
        do { try await execute() } catch {
            try? emit(["kind": "failure", "reason": String(describing: error), "productionApproval": "not_granted"])
            FileHandle.standardError.write(Data("Native generation research failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
