// Task: 4.0k / US-SYN-001 AC-4, ADR-023 section 4.
// Research-only macOS NaturalLanguage measurements; no App or model integration.
// Does not infer factual quality, approve distribution, or rewrite generated text.
import Foundation
import NaturalLanguage

struct Measurement: Encodable {
    let dominantLanguage: String?
    let confidence: Double
    let hasLetters: Bool
    let simplificationChanged: Bool?
}

struct ProbeResult: Encodable {
    let schemaVersion = 1
    let operatingSystem: String
    let measurements: [Measurement]
}

let limit = 1_048_576
let data = FileHandle.standardInput.readData(ofLength: limit + 1)
guard data.count <= limit else { throw NSError(domain: "InputTooLarge", code: 1) }
let samples = try JSONDecoder().decode([String].self, from: data)
guard samples.count <= 256 else { throw NSError(domain: "TooManySamples", code: 1) }
let measurements = samples.map { text in
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    let language = recognizer.dominantLanguage
    let confidence = language.flatMap { recognizer.languageHypotheses(withMaximum: 1)[$0] } ?? 0
    let simplified = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false)
    return Measurement(
        dominantLanguage: language?.rawValue,
        confidence: confidence,
        hasLetters: text.unicodeScalars.contains { CharacterSet.letters.contains($0) },
        simplificationChanged: simplified.map { $0 != text }
    )
}
let result = ProbeResult(
    operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
    measurements: measurements
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(result))
