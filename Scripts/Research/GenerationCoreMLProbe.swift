// Task: 4.0k / ADR-023 sections 1-2 and 6.
// Native Swift/Core ML short-prefix research probe, outside the App Bundle.
// Fixed synthetic reference tokens; no Python runtime in the model process.
import CoreML
import Darwin
import Foundation

struct ReferenceSample: Decodable {
    let position: Int
    let expectedTop1: Int
    let indices: [Int]
    let logits: [Double]
}

struct PrefixCase: Decodable {
    let id: String
    let tokens: [Int]
    let samples: [ReferenceSample]
}

struct ProbeInput: Decodable {
    let schemaVersion: Int
    let context: Int
    let cases: [PrefixCase]
}

struct Comparison: Encodable {
    let position: Int
    let expectedTop1: Int
    let actualTop1: Int
    let sampleMaxAbsoluteError: Double
    let comparedLogitCount: Int
}

struct PrefixResult: Encodable {
    let id: String
    let predictionCalls: Int
    let elapsedSeconds: Double
    let comparisons: [Comparison]
}

struct NativeReport: Encodable {
    let schemaVersion = 1
    let evidenceKind = "native_swift_coreml_short_prefix"
    let productionApproval = "not_granted"
    let computeUnits = "cpuAndGPU"
    let operatingSystem: String
    let compilationSeconds: Double
    let loadSeconds: Double
    let stateCount: Int
    let inputFormat: String
    let maximumResidentSetBytes: Int
    let maximumResidentSetScope = "whole Mac probe process including compile/load; not App or iPhone footprint"
    let memory: [MemorySample]
    let cases: [PrefixResult]
}

struct MemorySample: Encodable {
    let stage: String
    let residentBytes: UInt64
    let residentPeakBytes: UInt64
    let physicalFootprintBytes: UInt64
    let kernelPhysicalFootprintPeakBytes: Int64

    static func capture(_ stage: String) throws -> Self {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { buffer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), buffer, &count)
            }
        }
        guard let peakOffset = MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_phys_footprint_peak),
            result == KERN_SUCCESS,
            Int(count) * MemoryLayout<integer_t>.size >= peakOffset + MemoryLayout<Int64>.size,
            info.ledger_phys_footprint_peak >= 0
        else { throw NativeProbeError.resourceMeasurement }
        return Self(
            stage: stage,
            residentBytes: info.resident_size,
            residentPeakBytes: info.resident_size_peak,
            physicalFootprintBytes: info.phys_footprint,
            kernelPhysicalFootprintPeakBytes: info.ledger_phys_footprint_peak
        )
    }
}

enum NativeProbeError: Error { case invalidInput, modelContract, invalidLogits, resourceMeasurement }

@main
enum NativeProbe {
    nonisolated static func execute() async throws {
        guard
            CommandLine.arguments.count == 3
                || (CommandLine.arguments.count == 4 && CommandLine.arguments[3] == "--compiled")
        else { throw NativeProbeError.invalidInput }
        let suppliedCompiled = CommandLine.arguments.count == 4
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let inputURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let data = try Data(contentsOf: inputURL)
        guard data.count <= 1_048_576 else { throw NativeProbeError.invalidInput }
        let input = try JSONDecoder().decode(ProbeInput.self, from: data)
        guard input.schemaVersion == 1, input.context == 1024, (1...4).contains(input.cases.count) else {
            throw NativeProbeError.invalidInput
        }
        for item in input.cases {
            guard (1...64).contains(item.tokens.count), item.tokens.allSatisfy({ (0..<151_936).contains($0) }),
                (1...8).contains(item.samples.count), Set(item.samples.map(\.position)).count == item.samples.count,
                item.samples.allSatisfy({ sample in
                    item.tokens.indices.contains(sample.position) && (0..<151_936).contains(sample.expectedTop1)
                        && (1...64).contains(sample.indices.count) && sample.indices.count == sample.logits.count
                        && sample.indices.allSatisfy({ (0..<151_936).contains($0) })
                        && sample.logits.allSatisfy(\.isFinite)
                })
            else { throw NativeProbeError.invalidInput }
        }
        var memory = [try MemorySample.capture("before_compile")]
        let compileStart = ProcessInfo.processInfo.systemUptime
        guard !suppliedCompiled || source.pathExtension == "mlmodelc" else { throw NativeProbeError.invalidInput }
        let compiled = suppliedCompiled ? source : try await MLModel.compileModel(at: source)
        // Delete only temporary compiler output owned by this exact call.
        defer { if !suppliedCompiled { try? FileManager.default.removeItem(at: compiled) } }
        let compilationSeconds = ProcessInfo.processInfo.systemUptime - compileStart
        memory.append(try MemorySample.capture("after_compile"))
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        let loadStart = ProcessInfo.processInfo.systemUptime
        let model = try await MLModel.load(contentsOf: compiled, configuration: config)
        let loadSeconds = ProcessInfo.processInfo.systemUptime - loadStart
        memory.append(try MemorySample.capture("after_load"))
        let states = model.modelDescription.stateDescriptionsByName
        guard states.count == 56,
            states.values.allSatisfy({
                $0.stateConstraint?.bufferShape == [1, 8, 1024, 128]
                    && $0.stateConstraint?.dataType == .float16
            })
        else { throw NativeProbeError.modelContract }
        var results: [PrefixResult] = []
        for item in input.cases {
            let caseStart = ProcessInfo.processInfo.systemUptime
            let state = model.makeState()
            var comparisons: [Comparison] = []
            for (position, token) in item.tokens.enumerated() {
                try Task.checkCancellation()
                let tokenArray = try MLMultiArray(shape: [1, 1], dataType: .int32)
                let positionArray = try MLMultiArray(shape: [1], dataType: .int32)
                tokenArray[0] = NSNumber(value: token)
                positionArray[0] = NSNumber(value: position)
                let features = try MLDictionaryFeatureProvider(dictionary: [
                    "token_id": tokenArray, "position": positionArray,
                ])
                // Sequential across every suspension; this CLI has a single owner.
                let output = try await model.prediction(from: features, using: state)
                memory.append(try MemorySample.capture("\(item.id)_position_\(position)"))
                guard let logits = output.featureValue(for: "logits")?.multiArrayValue,
                    logits.count == 151_936, logits.dataType == .float32
                else {
                    throw NativeProbeError.modelContract
                }
                if let sample = item.samples.first(where: { $0.position == position }) {
                    var top1 = 0
                    var best = -Double.infinity
                    for index in 0..<logits.count {
                        let value = logits[index].doubleValue
                        guard value.isFinite else { throw NativeProbeError.invalidLogits }
                        if value > best { best = value; top1 = index }
                    }
                    let errors = zip(sample.indices, sample.logits).map { index, reference in
                        abs(logits[index].doubleValue - reference)
                    }
                    comparisons.append(
                        Comparison(
                            position: position,
                            expectedTop1: sample.expectedTop1,
                            actualTop1: top1,
                            sampleMaxAbsoluteError: errors.max() ?? 0,
                            comparedLogitCount: sample.indices.count
                        )
                    )
                }
            }
            results.append(
                PrefixResult(
                    id: item.id,
                    predictionCalls: item.tokens.count,
                    elapsedSeconds: ProcessInfo.processInfo.systemUptime - caseStart,
                    comparisons: comparisons
                )
            )
        }
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw NativeProbeError.resourceMeasurement }
        let report = NativeReport(
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            compilationSeconds: compilationSeconds,
            loadSeconds: loadSeconds,
            stateCount: states.count,
            inputFormat: suppliedCompiled ? "mlmodelc" : "mlpackage",
            maximumResidentSetBytes: Int(usage.ru_maxrss),
            memory: memory,
            cases: results
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(report))
    }

    static func main() async {
        do { try await execute() } catch {
            FileHandle.standardError.write(Data("Native Core ML probe failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
