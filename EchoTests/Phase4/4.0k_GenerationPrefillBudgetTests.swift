// Task: 4.0k; ADR-023. Batched prefill preserves token, time and autoregressive limits.
import Testing

@testable import Echo

@Suite("4.0k Prefill Budget", .serialized)
struct GenerationPrefillBudgetTests {
    @Test("AC-1: chunks consume every input position and count actual model calls")
    func test_AC1_chunksPreserveAccounting() throws {
        var budget = try GenerationBudget(inputCount: 17, outputLimit: 8, context: 64, startedAt: 0, seconds: 60)
        try budget.beforePrediction(position: 0, count: 16, now: 1)
        #expect(budget.predictionCount == 1)
        #expect(throws: GenerationBudgetError.self) { try budget.recordOutput(now: 2) }
        #expect(throws: GenerationBudgetError.self) { try budget.beforePrediction(position: 1, count: 1, now: 2) }
        try budget.beforePrediction(position: 16, count: 1, now: 2)
        try budget.recordOutput(now: 3)
        #expect(budget.predictionCount == 2)
        #expect(throws: GenerationBudgetError.self) { try budget.beforePrediction(position: 17, count: 2, now: 3) }
        try budget.beforePrediction(position: 17, count: 1, now: 3)
        try budget.recordOutput(now: 4)
        #expect(budget.predictionCount == 3)
        #expect(budget.outputCount == 2)
        #expect(throws: GenerationBudgetError.self) { try budget.beforePrediction(position: 18, count: 1, now: 60) }
    }

    @Test("AC-1: invalid chunks cannot cross the prefill boundary or alter accounting")
    func test_AC1_invalidChunkIsAtomic() throws {
        var budget = try GenerationBudget(inputCount: 3, outputLimit: 2, context: 16, startedAt: 0, seconds: 60)
        for count in [0, -1, 4, 17] {
            #expect(throws: GenerationBudgetError.self) { try budget.beforePrediction(position: 0, count: count, now: 1) }
            #expect(budget.predictionCount == 0)
        }
        try budget.beforePrediction(position: 0, count: 3, now: 1)
        try budget.recordOutput(now: 2)
        try budget.beforePrediction(position: 3, count: 1, now: 3)
        try budget.recordOutput(now: 4)
        #expect(throws: GenerationBudgetError.self) { try budget.beforePrediction(position: 4, count: 1, now: 5) }
    }
}
