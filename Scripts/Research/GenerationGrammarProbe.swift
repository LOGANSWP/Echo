// Task 4.0k / ADR-023: actual Swift grammar conformance driver, no model.
import Foundation

struct GrammarProbeInput: Decodable {
    let allowedIDs: [String]
    let prefixes: [Data]
}

@main
enum GrammarProbe {
    static func boundaries(_ grammar: EnvelopeGrammar) throws -> [String] {
        let envelope = Array("{\"schemaVersion\":1,\"paragraphs\":[{\"text\":\"x\",\"sourceMemoryIDs\":[]}]}".utf8)
        var decoder = GrammarDecoder(
            grammar: grammar,
            tokenBytes: [0: [123], 1: [123], 2: [120], 3: envelope],
            eosIDs: [4]
        )
        guard try decoder.select([2, 2, 8, 1, 20]) == 0, !decoder.allows(4), !decoder.allows(5) else {
            throw GrammarError.invalidInput
        }
        try decoder.accept(3)
        guard try decoder.select([8, 8, 8, 8, 1]) == 4, !decoder.allows(0) else { throw GrammarError.invalidInput }
        try decoder.accept(4)
        guard !decoder.allows(4) else { throw GrammarError.invalidInput }
        do { _ = try decoder.select([1]); throw GrammarError.invalidInput } catch GrammarError.noAllowedToken {}
        for scores: [Float] in [[.nan], [.infinity]] {
            do { _ = try decoder.select(scores); throw GrammarError.invalidInput } catch GrammarError.invalidLogits {}
        }
        var budget = try GenerationBudget(inputCount: 3, outputLimit: 2, context: 5, startedAt: 10, seconds: 1)
        for position in 0..<3 { try budget.beforePrediction(position: position, now: 10) }
        try budget.afterPrediction(now: 10)
        try budget.recordOutput(now: 10)
        try budget.beforePrediction(position: 3, now: 10)
        try budget.recordOutput(now: 10)
        guard budget.outputCount == 2, budget.predictionCount == 4 else { throw GrammarError.invalidInput }
        do {
            try budget.beforePrediction(position: 4, now: 10); throw GrammarError.invalidInput
        } catch GenerationBudgetError.exhausted {}
        do { try budget.recordOutput(now: 10); throw GrammarError.invalidInput } catch GenerationBudgetError.exhausted {
        }
        do { try budget.afterPrediction(now: 11); throw GrammarError.invalidInput } catch GenerationBudgetError.deadline {}
        do {
            _ = try GenerationBudget(inputCount: 4, outputLimit: 2, context: 5, startedAt: 10, seconds: 1)
            throw GrammarError.invalidInput
        } catch GenerationBudgetError.invalidInput {}
        var order = try GenerationBudget(inputCount: 3, outputLimit: 2, context: 5, startedAt: 10, seconds: 1)
        do {
            try order.beforePrediction(position: 1, now: 10); throw GrammarError.invalidInput
        } catch GenerationBudgetError.invalidPosition {}
        withUnsafeCurrentTask { $0?.cancel() }
        do { try order.afterPrediction(now: 10); throw GrammarError.invalidInput } catch is CancellationError {}
        return [
            "stable_legal_argmax", "eos_only_after_complete", "no_added_tokens", "no_tokens_after_eos",
            "dead_end_error", "nonfinite_rejected", "context_reservation", "monotonic_positions",
            "no_prediction_after_limit", "no_output_after_limit", "deadline_after_prediction", "task_cancellation",
        ]
    }

    static func main() async throws {
        let data = FileHandle.standardInput.readData(ofLength: 2_097_153)
        guard data.count <= 2_097_152 else { throw GrammarError.invalidInput }
        let input = try JSONDecoder().decode(GrammarProbeInput.self, from: data)
        guard input.prefixes.count <= 10_000 else { throw GrammarError.invalidInput }
        let grammar = try EnvelopeGrammar(allowedIDs: input.allowedIDs)
        let statuses = input.prefixes.map { grammar.status(Array($0)).rawValue }
        let checks = try boundaries(grammar)
        FileHandle.standardOutput.write(try JSONEncoder().encode(["statuses": statuses, "boundaryChecks": checks]))
    }
}
