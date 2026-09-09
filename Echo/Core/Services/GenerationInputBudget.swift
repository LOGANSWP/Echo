// ==========================================
// File: GenerationInputBudget.swift
// Spec: US-SYN-004; ADR-023 section 2
// Task: 4.0k - PR #79 pre-render input bounds
// AC coverage: bounded reads, aggregate source and escaped JSON byte limits
// Architecture: value-only preflight; tokenizer remains the token authority
// Generated: 2026-09-08
// ==========================================

import Foundation

nonisolated enum GenerationInputBudget {
    static let maximumBytes = 16_384
    static let maximumSources = 24

    /// Count UTF-8/JSON bytes without allocating an escaped String or scanning beyond the limit.
    static func consume(_ text: String, remaining: inout Int, escaped: Bool = false) throws {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            var cost = value < 0x80 ? 1 : (value < 0x800 ? 2 : (value < 0x10000 ? 3 : 4))
            if escaped {
                switch value {
                case 0...31, 60, 0x2028, 0x2029: cost = 6
                case 34, 92: cost = 2
                default: break
                }
            }
            guard remaining >= cost else { throw GenerationRuntimeError.contextLimit }
            remaining -= cost
        }
    }

    static func validate(_ passages: [GenerationPassage]) throws {
        guard passages.count <= maximumSources else { throw GenerationRuntimeError.contextLimit }
        var remaining = maximumBytes - 2
        for passage in passages {
            guard passage.sourceMemoryIDs.count <= maximumSources else { throw GenerationRuntimeError.contextLimit }
            // UUID transport is the upper bound, including quotes, separators and object keys.
            remaining -= 40 + passage.sourceMemoryIDs.count * 39
            guard remaining >= 0 else { throw GenerationRuntimeError.contextLimit }
            try consume(passage.text, remaining: &remaining, escaped: true)
        }
    }
}
