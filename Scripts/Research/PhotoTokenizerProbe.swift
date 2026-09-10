// Task 4.0l: independent official-tokenizer conformance driver.
import Foundation
import Darwin

struct PhotoTokenSample: Decodable { let text: String; let prompt: Bool; let expected: [Int] }

@main
enum PhotoTokenizerProbe {
    static func main() {
        do {
            guard CommandLine.arguments.count == 2 else { throw PhotoTokenError.configuration }
            let tokenizer = try PhotoTokenizer(url: URL(fileURLWithPath: CommandLine.arguments[1]))
            let data = FileHandle.standardInput.readData(ofLength: 1_048_577)
            guard data.count <= 1_048_576 else { throw PhotoTokenError.inputBudget }
            let samples = try JSONDecoder().decode([PhotoTokenSample].self, from: data)
            guard samples.count <= 256 else { throw PhotoTokenError.inputBudget }
            for (index, sample) in samples.enumerated() {
                let result = sample.prompt ? try tokenizer.encodePrompt(sample.text) : try tokenizer.encode(sample.text)
                guard result == sample.expected else {
                    FileHandle.standardError.write(Data("Mismatch at case \(index): \(result) != \(sample.expected)\n".utf8))
                    throw PhotoTokenError.encoding
                }
                if !sample.prompt {
                    guard try tokenizer.decode(result) == sample.text else { throw PhotoTokenError.encoding }
                }
            }
            var rejections = 0
            for input in [String(repeating: "a", count: 16_385), String(repeating: "照片", count: 3000)] {
                do { _ = try tokenizer.encode(input) } catch PhotoTokenError.inputBudget { rejections += 1 }
            }
            for input in ["", String(repeating: "照片", count: 700)] {
                do { _ = try tokenizer.encodePrompt(input) } catch PhotoTokenError.inputBudget { rejections += 1 }
            }
            guard rejections == 4 else { throw PhotoTokenError.inputBudget }
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: ["conformancePassed": samples.count, "budgetRejections": rejections]))
        } catch {
            FileHandle.standardError.write(Data("Photo tokenizer rejected: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
