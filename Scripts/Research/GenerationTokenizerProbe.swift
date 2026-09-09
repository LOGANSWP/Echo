// Task 4.0k: standalone driver for the shared research tokenizer.
import Foundation
import Darwin

struct TokenResult: Encodable {
    let tokenIDs: [Int]
    let roundTrip: String
}

struct TokenReport: Encodable {
    let schemaVersion = 1
    let encoding: String
    let results: [TokenResult]
}

func run() throws {
    let args = CommandLine.arguments
    guard args.count == 2 || (args.count == 3 && args[2] == "--chat") else {
        throw ProbeError.unsupportedConfiguration
    }
    let tokenizer = try Tokenizer(url: URL(fileURLWithPath: args[1]))
    let input = FileHandle.standardInput.readData(ofLength: 1_048_577)
    guard input.count <= 1_048_576 else { throw ProbeError.inputBudget }
    let encoded: [[Int]]
    if args.count == 3 {
        let samples = try JSONDecoder().decode([[ChatMessage]].self, from: input)
        guard samples.count <= 256 else { throw ProbeError.inputBudget }
        encoded = try samples.map { try tokenizer.encodeChat($0) }
    } else {
        let samples = try JSONDecoder().decode([String].self, from: input)
        guard samples.count <= 256 else { throw ProbeError.inputBudget }
        encoded = try samples.map { try tokenizer.encode($0) }
    }
    let results = try encoded.map { tokens in
        TokenResult(tokenIDs: tokens, roundTrip: try tokenizer.decode(tokens))
    }
    let report = TokenReport(
        encoding: args.count == 3 ? "qwen3_system_user_no_thinking" : "ordinary_text_NFC",
        results: results
    )
    FileHandle.standardOutput.write(try JSONEncoder().encode(report))
}

@main
enum TokenizerProbe {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("Tokenizer probe rejected input or configuration.\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
