// Task 4.0k / ADR-023 section 2: fail before an out-of-budget prediction.
// Research value type. The caller owns it for one request, across sequential awaits.
import Foundation

enum GenerationBudgetError: Error { case invalidInput, invalidPosition, exhausted, deadline }

struct GenerationBudget {
    let inputCount: Int
    let outputLimit: Int
    let deadline: Double
    private(set) var predictionCount = 0
    private(set) var outputCount = 0

    init(inputCount: Int, outputLimit: Int, context: Int, startedAt: Double, seconds: Double) throws {
        guard (1...1024).contains(context), (1...context).contains(inputCount),
              (1...256).contains(outputLimit), outputLimit <= context - inputCount,
              startedAt.isFinite, seconds.isFinite, seconds > 0, seconds <= 600 else {
            throw GenerationBudgetError.invalidInput
        }
        self.inputCount = inputCount
        self.outputLimit = outputLimit
        deadline = startedAt + seconds
    }

    func afterPrediction(now: Double) throws {
        try Task.checkCancellation()
        guard now.isFinite, now < deadline else { throw GenerationBudgetError.deadline }
    }

    mutating func beforePrediction(position: Int, now: Double) throws {
        try afterPrediction(now: now)
        guard outputCount < outputLimit, predictionCount < inputCount + outputLimit - 1 else {
            throw GenerationBudgetError.exhausted
        }
        guard position == predictionCount,
              predictionCount < inputCount || predictionCount == inputCount + outputCount - 1 else {
            throw GenerationBudgetError.invalidPosition
        }
        predictionCount += 1
    }

    mutating func recordOutput(now: Double) throws {
        try afterPrediction(now: now)
        guard outputCount < outputLimit else { throw GenerationBudgetError.exhausted }
        guard predictionCount == inputCount + outputCount else { throw GenerationBudgetError.invalidPosition }
        outputCount += 1
    }
}
