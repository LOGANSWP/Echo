// ==========================================
// File: GenerationBudget.swift
// Spec: US-SYN-001/002/004; ADR-023 sections 1-4
// Task: 4.0k - Approved offline generation runtime
// AC coverage: pinned tokenizer, bounded inference and provenance grammar
// Architecture: AGENTS.md sections 4.2, 6.2; request-owned value types
// Generated: 2026-09-08
// ==========================================

import Foundation

nonisolated enum GenerationBudgetError: Error { case invalidInput, invalidPosition, exhausted, deadline }

nonisolated struct GenerationBudget {
    let inputCount: Int
    let outputLimit: Int
    let deadline: Double
    private(set) var predictionCount = 0
    private(set) var outputCount = 0
    private var processedTokenCount = 0

    init(
        inputCount: Int,
        outputLimit: Int,
        context: Int,
        startedAt: Double,
        seconds: Double,
        executionScope: GenerationExecutionScope = .standard
    ) throws {
        guard (1...1024).contains(context), (1...context).contains(inputCount),
            (1...256).contains(outputLimit), outputLimit <= context - inputCount,
            startedAt.isFinite, seconds.isFinite, seconds > 0, seconds <= executionScope.callSeconds
        else {
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

    mutating func beforePrediction(position: Int, count: Int = 1, now: Double) throws {
        try afterPrediction(now: now)
        guard outputCount < outputLimit, processedTokenCount < inputCount + outputLimit - 1 else {
            throw GenerationBudgetError.exhausted
        }
        guard (1...16).contains(count), position == processedTokenCount,
            (position < inputCount && count <= inputCount - position)
                || (count == 1 && position == inputCount + outputCount - 1)
        else {
            throw GenerationBudgetError.invalidPosition
        }
        predictionCount += 1
        processedTokenCount += count
    }

    mutating func recordOutput(now: Double) throws {
        try afterPrediction(now: now)
        guard outputCount < outputLimit else { throw GenerationBudgetError.exhausted }
        guard processedTokenCount == inputCount + outputCount else { throw GenerationBudgetError.invalidPosition }
        outputCount += 1
    }
}
