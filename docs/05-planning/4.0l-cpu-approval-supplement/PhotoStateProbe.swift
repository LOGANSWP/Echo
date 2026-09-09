// Task 4.0l / ADR-025: native image-to-caption functional research outside the App.
// Native TIFF decoding, orientation, pixels and tokenizer; no personal media or Python inference.
import CoreML
import CryptoKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin
import Foundation

struct PhotoCase: Encodable {
    let id: Int
    let normalizedPixelSHA256: String
    let width: Int
    let height: Int
    let inputIDs: [Int]
    let inputTokens: Int
    let generatedIDs: [Int]
    let text: String
    let eos: Bool
    let predictionCalls: Int
    let seconds: Double
    let firstTokenTop1: Int
}

struct PhotoReport: Encodable {
    let scope = "Mac native Swift/Core ML image decode/preprocess/tokenizer/caption; no App/device qualification"
    let productionApproval = "pending"
    let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    let compileSeconds: Double
    let loadSeconds: Double
    let cases: [PhotoCase]
    let memory: [MemorySample]
}

enum PhotoProbeError: Error { case input, modelContract, invalidLogits, budget, pixelMismatch }

@main
enum PhotoFunctionalProbe {
    nonisolated static func execute() async throws {
        guard CommandLine.arguments.count == 5 ||
              (CommandLine.arguments.count == 6 && CommandLine.arguments[5] == "--compiled") else { throw PhotoProbeError.input }
        let suppliedCompiled = CommandLine.arguments.count == 6
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        let tokenizerURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let outputPath = URL(fileURLWithPath: CommandLine.arguments[3])
        let cancel = CommandLine.arguments[4] == "cancel-after-vision"
        guard cancel || CommandLine.arguments[4] == "generate",
              !FileManager.default.fileExists(atPath: outputPath.path) else { throw PhotoProbeError.input }
        let tokenizer = try PhotoTokenizer(url: tokenizerURL)
        let promptIDs = try tokenizer.encodePrompt("Describe this image in one short sentence.")
        var memory = [try MemorySample.capture("before_compile")]
        let start = ProcessInfo.processInfo.systemUptime
        let visionURL: URL
        if suppliedCompiled { visionURL = base.appendingPathComponent("SmolVision512.mlmodelc") }
        else { visionURL = try await MLModel.compileModel(at: base.appendingPathComponent("SmolVision512.mlpackage")) }
        defer { if !suppliedCompiled { try? FileManager.default.removeItem(at: visionURL) } }
        let decoderURL: URL
        if suppliedCompiled { decoderURL = base.appendingPathComponent("SmolDecoder1024.mlmodelc") }
        else { decoderURL = try await MLModel.compileModel(at: base.appendingPathComponent("SmolDecoder1024.mlpackage")) }
        defer { if !suppliedCompiled { try? FileManager.default.removeItem(at: decoderURL) } }
        let compileSeconds = ProcessInfo.processInfo.systemUptime - start
        let config = MLModelConfiguration()
        config.computeUnits = ProcessInfo.processInfo.environment["ECHO_PHOTO_DECODER_GPU"] == "1" ? .cpuAndGPU : .cpuOnly
        let visionConfig = MLModelConfiguration()
        visionConfig.computeUnits = ProcessInfo.processInfo.environment["ECHO_PHOTO_VISION_GPU"] == "1" ? .cpuAndGPU : .cpuOnly
        let loadStart = ProcessInfo.processInfo.systemUptime
        let vision = try await MLModel.load(contentsOf: visionURL, configuration: visionConfig)
        let decoder = try await MLModel.load(contentsOf: decoderURL, configuration: config)
        let loadSeconds = ProcessInfo.processInfo.systemUptime - loadStart
        guard decoder.modelDescription.stateDescriptionsByName.count == 60 else { throw PhotoProbeError.modelContract }
        memory.append(try MemorySample.capture("after_load"))
        var results: [PhotoCase] = []
        for (caseID, size) in [(512, 512), (512, 256), (256, 512)].enumerated() {
            let caseStart = ProcessInfo.processInfo.systemUptime
            let prepared = try PhotoImagePreprocessor.prepare(makeImage(width: size.0, height: size.1))
            let pixels = try MLMultiArray(shape: [1, 3, 512, 512], dataType: .float32)
            for index in prepared.pixels.indices { pixels[index] = NSNumber(value: prepared.pixels[index]) }
            let pixelHash = prepared.pixels.withUnsafeBytes { SHA256.hash(data: Data($0)).map { String(format: "%02x", $0) }.joined() }
            let positions = try MLMultiArray(shape: [1, 1024], dataType: .int32)
            let mask = try MLMultiArray(shape: [1, 1, 1, 1024], dataType: .float32)
            for index in 0..<1024 {
                positions[index] = NSNumber(value: prepared.positionIDs[index])
                mask[index] = NSNumber(value: prepared.attentionMask[index])
            }
            try checkBudget(since: caseStart)
            let visual = try await vision.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "pixels": pixels, "position_ids": positions, "attention_mask": mask,
            ]))
            if cancel {
                withUnsafeCurrentTask { $0?.cancel() }
                FileHandle.standardError.write(Data("Cancelled after one actual vision prediction; no decoder call or caption.\n".utf8))
                try Task.checkCancellation()
            }
            guard let embeddings = visual.featureValue(for: "image_embeddings")?.multiArrayValue,
                  embeddings.shape == [1, 64, 576], embeddings.dataType == .float32
            else { throw PhotoProbeError.modelContract }
            let state = decoder.makeState()
            let token = try MLMultiArray(shape: [1, 1], dataType: .int32)
            let position = try MLMultiArray(shape: [1], dataType: .int32)
            let image = try MLMultiArray(shape: [1, 1, 576], dataType: .float32)
            var imageIndex = 0
            var ids = promptIDs
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
                if caseID == 0 && pos < 3 {
                    var sample: [Double] = []
                    state.withMultiArray(for: "key_cache_0") { cache in
                        sample = (0..<8).map { cache[$0].doubleValue }
                    }
                    let diagnostic = try JSONSerialization.data(withJSONObject: ["position": pos, "key0": sample], options: [.sortedKeys])
                    FileHandle.standardError.write(diagnostic + Data([10]))
                }
                calls += 1
                try checkBudget(since: caseStart)
                guard let logits = output.featureValue(for: "logits")?.multiArrayValue,
                      logits.count == 49280, logits.dataType == .float32 else { throw PhotoProbeError.modelContract }
                if pos >= promptIDs.count - 1 {
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
            results.append(PhotoCase(id: caseID, normalizedPixelSHA256: pixelHash, width: prepared.width, height: prepared.height, inputIDs: promptIDs, inputTokens: promptIDs.count,
                generatedIDs: generated, text: try tokenizer.decode(generated.filter { $0 != 49279 }), eos: eos,
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

    nonisolated static func makeImage(width: Int, height: Int) throws -> Data {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let radius = min(width, height) / 4
        for y in 0..<height {
            for x in 0..<width {
                if (x-width/2)*(x-width/2) + (y-height/2)*(y-height/2) <= radius*radius {
                    rgba[(y*width+x)*4+1] = 0
                    rgba[(y*width+x)*4+2] = 0
                }
            }
        }
        guard let color = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width*4, space: color, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw PhotoProbeError.input }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil)
        else { throw PhotoProbeError.input }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PhotoProbeError.input }
        return data as Data
    }

    static func main() async {
        do { try await execute() }
        catch {
            FileHandle.standardError.write(Data("Photo native research failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
