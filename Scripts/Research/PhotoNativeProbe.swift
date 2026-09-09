// Task 4.0l / ADR-025: native image-to-caption functional research outside the App.
// Fixed synthetic pixels and pretokenized prompts; no personal media or Python inference.
import CoreML
import CryptoKit
import Darwin
import Foundation

struct PhotoInput: Decodable {
    let promptIDs: [Int]
    let vocabulary: [String]
    let expectedPixels: [String]
}

struct PhotoCase: Encodable {
    let id: Int
    let pixelSHA256: String
    let inputTokens: Int
    let generatedIDs: [Int]
    let text: String
    let eos: Bool
    let predictionCalls: Int
    let seconds: Double
    let firstTokenTop1: Int
}

struct PhotoReport: Encodable {
    let scope = "Mac native Swift/Core ML synthetic-square image-to-caption; pretokenized input, no App/device qualification"
    let productionApproval = "pending"
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    let compileSeconds: Double
    let loadSeconds: Double
    let cases: [PhotoCase]
    let memory: [MemorySample]
}

enum PhotoProbeError: Error { case input, modelContract, invalidLogits, budget, pixelMismatch }

@main
enum PhotoNativeProbe {
    nonisolated static func execute() async throws {
        guard CommandLine.arguments.count == 4 else { throw PhotoProbeError.input }
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        let inputPath = URL(fileURLWithPath: CommandLine.arguments[2])
        let outputPath = URL(fileURLWithPath: CommandLine.arguments[3])
        guard !FileManager.default.fileExists(atPath: outputPath.path) else { throw PhotoProbeError.input }
        let data = try Data(contentsOf: inputPath)
        guard data.count <= 4_000_000 else { throw PhotoProbeError.input }
        let input = try JSONDecoder().decode(PhotoInput.self, from: data)
        guard (65...768).contains(input.promptIDs.count), input.promptIDs.filter({ $0 == 49190 }).count == 64,
              input.promptIDs.allSatisfy({ (0..<49280).contains($0) }), input.vocabulary.count == 49280,
              input.expectedPixels.count == 2 else { throw PhotoProbeError.input }
        var memory = [try MemorySample.capture("before_compile")]
        let start = ProcessInfo.processInfo.systemUptime
        let visionURL = try await MLModel.compileModel(at: base.appendingPathComponent("SmolVision512.mlpackage"))
        defer { try? FileManager.default.removeItem(at: visionURL) }
        let decoderURL = try await MLModel.compileModel(at: base.appendingPathComponent("SmolDecoder1024.mlpackage"))
        defer { try? FileManager.default.removeItem(at: decoderURL) }
        let compileSeconds = ProcessInfo.processInfo.systemUptime - start
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        let loadStart = ProcessInfo.processInfo.systemUptime
        let vision = try await MLModel.load(contentsOf: visionURL, configuration: config)
        let decoder = try await MLModel.load(contentsOf: decoderURL, configuration: config)
        let loadSeconds = ProcessInfo.processInfo.systemUptime - loadStart
        guard decoder.modelDescription.stateDescriptionsByName.count == 60 else { throw PhotoProbeError.modelContract }
        memory.append(try MemorySample.capture("after_load"))
        var results: [PhotoCase] = []
        for caseID in 0..<2 {
            let caseStart = ProcessInfo.processInfo.systemUptime
            let pixels = try MLMultiArray(shape: [1, 3, 512, 512], dataType: .float32)
            var rgb = [UInt8]()
            rgb.reserveCapacity(512 * 512 * 3)
            for y in 0..<512 {
                for x in 0..<512 {
                    let inside = (x - 256) * (x - 256) + (y - 256) * (y - 256) <= 112 * 112
                    for channel in 0..<3 {
                        let bright = !inside || channel == (caseID == 0 ? 0 : 2)
                        rgb.append(bright ? 255 : 0)
                        pixels[channel * 512 * 512 + y * 512 + x] = NSNumber(value: bright ? Float(1) : Float(-1))
                    }
                }
            }
            let pixelHash = SHA256.hash(data: Data(rgb)).map { String(format: "%02x", $0) }.joined()
            guard pixelHash == input.expectedPixels[caseID] else { throw PhotoProbeError.pixelMismatch }
            let positions = try MLMultiArray(shape: [1, 1024], dataType: .int32)
            let mask = try MLMultiArray(shape: [1, 1, 1, 1024], dataType: .float32)
            for index in 0..<1024 { positions[index] = NSNumber(value: index); mask[index] = 0 }
            try checkBudget(since: caseStart)
            let visual = try await vision.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "pixels": pixels, "position_ids": positions, "attention_mask": mask,
            ]))
            guard let embeddings = visual.featureValue(for: "image_embeddings")?.multiArrayValue,
                  embeddings.shape == [1, 64, 576], embeddings.dataType == .float32
            else { throw PhotoProbeError.modelContract }
            let state = decoder.makeState()
            let token = try MLMultiArray(shape: [1, 1], dataType: .int32)
            let position = try MLMultiArray(shape: [1], dataType: .int32)
            let image = try MLMultiArray(shape: [1, 1, 576], dataType: .float32)
            var imageIndex = 0
            var ids = input.promptIDs
            var generated: [Int] = []
            var calls = 1
            var eos = false
            var first = -1
            var pos = 0
            while pos < ids.count && generated.count < 128 {
                try checkBudget(since: caseStart)
                guard pos < 1024 else { throw PhotoProbeError.budget }
                token[0] = NSNumber(value: ids[pos]); position[0] = NSNumber(value: pos)
                for column in 0..<576 {
                    image[column] = ids[pos] == 49190 ? embeddings[imageIndex * 576 + column] : 0
                }
                if ids[pos] == 49190 { imageIndex += 1 }
                let output = try await decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                    "token_id": token, "position": position, "image_embedding": image,
                ]), using: state)
                calls += 1
                try checkBudget(since: caseStart)
                guard let logits = output.featureValue(for: "logits")?.multiArrayValue,
                      logits.count == 49280, logits.dataType == .float32 else { throw PhotoProbeError.modelContract }
                if pos >= input.promptIDs.count - 1 {
                    var top1 = 0
                    var best = -Double.infinity
                    for index in 0..<logits.count {
                        let value = logits[index].doubleValue
                        guard value.isFinite else { throw PhotoProbeError.invalidLogits }
                        if value > best { best = value; top1 = index }
                    }
                    if first == -1 { first = top1 }
                    generated.append(top1)
                    if top1 == 49279 { eos = true; break }
                    // Generated image protocol tokens must never index outside the 64 input patches.
                    guard top1 != 49190 else { throw PhotoProbeError.modelContract }
                    ids.append(top1)
                }
                pos += 1
            }
            memory.append(try MemorySample.capture("case_\(caseID)_completed"))
            results.append(PhotoCase(id: caseID, pixelSHA256: pixelHash, inputTokens: input.promptIDs.count,
                generatedIDs: generated, text: try decode(generated, vocabulary: input.vocabulary), eos: eos,
                predictionCalls: calls, seconds: ProcessInfo.processInfo.systemUptime - caseStart,
                firstTokenTop1: first))
        }
        let report = PhotoReport(compileSeconds: compileSeconds, loadSeconds: loadSeconds, cases: results, memory: memory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: outputPath, options: .withoutOverwriting)
    }

    nonisolated static func checkBudget(since start: Double) throws {
        try Task.checkCancellation()
        guard ProcessInfo.processInfo.systemUptime - start <= 60 else { throw PhotoProbeError.budget }
        guard try MemorySample.capture("budget").residentBytes <= 8_000_000_000 else { throw PhotoProbeError.budget }
    }

    nonisolated static func decode(_ ids: [Int], vocabulary: [String]) throws -> String {
        // The pinned tokenizer has no normalizer and uses the standard ByteLevel alphabet.
        var bytes = Array(33...126) + Array(161...172) + Array(174...255)
        var scalars = bytes
        var extra = 0
        for byte in 0...255 where !bytes.contains(byte) {
            bytes.append(byte); scalars.append(256 + extra); extra += 1
        }
        let reverse = Dictionary(uniqueKeysWithValues: zip(scalars, bytes))
        var result: [UInt8] = []
        for id in ids where id != 49279 {
            for scalar in vocabulary[id].unicodeScalars {
                guard let byte = reverse[Int(scalar.value)] else { throw PhotoProbeError.invalidLogits }
                result.append(UInt8(byte))
            }
        }
        guard let decoded = String(bytes: result, encoding: .utf8) else { throw PhotoProbeError.invalidLogits }
        return decoded
    }

    static func main() async {
        do { try await execute() }
        catch {
            FileHandle.standardError.write(Data("Photo native research failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
