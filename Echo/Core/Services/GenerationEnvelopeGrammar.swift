// ==========================================
// File: GenerationEnvelopeGrammar.swift
// Spec: US-SYN-001/002/004; ADR-023 sections 1-4
// Task: 4.0k - Approved offline generation runtime
// AC coverage: bounded inference, UUID/alias prefix isolation and US-SYN-003 poem line structure
// Architecture: AGENTS.md sections 4.2, 6.2; request-owned value types
// Generated: 2026-09-08
// ==========================================

import Foundation

nonisolated enum GenerationGrammarError: Error {
    case invalidInput, invalidPrefix, incomplete, noAllowedToken, invalidLogits
}
nonisolated enum GenerationPrefixStatus: String { case invalid, prefix, complete }

nonisolated struct GenerationEnvelopeGrammar {
    let identities: [[UInt8]]
    let requiresPoem: Bool

    init(allowedIDs: [String], requiresPoem: Bool = false) throws {
        let ids = Array(Set(allowedIDs)).sorted()
        guard (1...24).contains(ids.count),
            ids.allSatisfy({
                UUID(uuidString: $0)?.uuidString.lowercased() == $0.lowercased() && $0.utf8.count == 36
            })
        else { throw GenerationGrammarError.invalidInput }
        identities = ids.map { Array(("\"" + $0 + "\"").utf8) }
        self.requiresPoem = requiresPoem
    }

    init(allowedAliases: [String], requiresPoem: Bool = false) throws {
        let names = Array(Set(allowedAliases)).sorted()
        guard (1...24).contains(names.count), names.allSatisfy({ name in
            guard name.first == "S", let number = Int(name.dropFirst()) else { return false }
            return (1...24).contains(number) && name == "S\(number)"
        }) else { throw GenerationGrammarError.invalidInput }
        identities = names.map { Array(("\"" + $0 + "\"").utf8) }
        self.requiresPoem = requiresPoem
    }

    func status(_ data: [UInt8]) -> GenerationPrefixStatus {
        guard data.count <= 65_536 else { return .invalid }
        let utf8 = Self.utf8Status(data)
        guard utf8 != .invalid else { return .invalid }
        var parser = Parser(data: data, identities: identities, requiresPoem: requiresPoem)
        do {
            try parser.document()
            return utf8 == .prefix ? .prefix : .complete
        } catch GenerationGrammarError.incomplete { return .prefix } catch { return .invalid }
    }

    private static func utf8Status(_ bytes: [UInt8]) -> GenerationPrefixStatus {
        var index = 0
        while index < bytes.count {
            let head = bytes[index]
            if head < 128 {
                index += 1
                continue
            }
            let length: Int
            var minimum: UInt8 = 128
            var maximum: UInt8 = 191
            switch head {
            case 194...223: length = 2

            case 224:
                length = 3
                minimum = 160

            case 225...236, 238...239: length = 3

            case 237:
                length = 3
                maximum = 159

            case 240:
                length = 4
                minimum = 144

            case 241...243: length = 4

            case 244:
                length = 4
                maximum = 143

            default: return .invalid
            }
            for offset in 1..<length {
                guard index + offset < bytes.count else { return .prefix }
                let value = bytes[index + offset]
                guard (offset == 1 ? minimum...maximum : 128...191).contains(value) else { return .invalid }
            }
            index += length
        }
        return .complete
    }

    nonisolated private struct Parser {
        let data: [UInt8]
        let identities: [[UInt8]]
        let requiresPoem: Bool
        var position = 0

        mutating func whitespace() {
            while position < data.count && [9, 10, 13, 32].contains(data[position]) { position += 1 }
        }

        func peek() throws -> UInt8 {
            guard position < data.count else { throw GenerationGrammarError.incomplete }
            return data[position]
        }

        mutating func literal(_ value: String) throws {
            for byte in value.utf8 {
                guard try peek() == byte else { throw GenerationGrammarError.invalidPrefix }
                position += 1
            }
        }

        mutating func token(_ value: String) throws {
            whitespace()
            try literal(value)
        }

        mutating func document() throws {
            try token("{")
            try token("\"schemaVersion\"")
            try token(":")
            try token("1")
            try token(",")
            try token("\"paragraphs\"")
            try token(":")
            try token("[")
            try paragraph()
            whitespace()
            if requiresPoem {
                for _ in 1..<CreativeGenerationLimits.targetPoemLineCount {
                    try token(",")
                    try paragraph()
                }
            } else if try peek() == 44 {
                position += 1
                try paragraph()
            }
            try token("]")
            try token("}")
            whitespace()
            guard position == data.count else { throw GenerationGrammarError.invalidPrefix }
        }

        mutating func paragraph() throws {
            try token("{")
            try token("\"text\"")
            try token(":")
            whitespace()
            try text()
            try token(",")
            try token("\"sourceMemoryIDs\"")
            try token(":")
            try references()
            try token("}")
        }

        mutating func hexUnit(lowSurrogate: Bool = false) throws -> Int {
            var value = 0
            for offset in 0..<4 {
                let byte = try peek()
                let digit: Int
                switch byte {
                case 48...57: digit = Int(byte - 48)
                case 65...70: digit = Int(byte - 55)
                case 97...102: digit = Int(byte - 87)
                default: throw GenerationGrammarError.invalidPrefix
                }
                value = value * 16 + digit
                position += 1
                let scale = 1 << ((3 - offset) * 4)
                let possible = (value * scale)...((value + 1) * scale - 1)
                if lowSurrogate {
                    guard possible.overlaps(0xDC00...0xDFFF) else { throw GenerationGrammarError.invalidPrefix }
                } else {
                    guard possible.lowerBound < 0xDC00 || possible.upperBound > 0xDFFF else {
                        throw GenerationGrammarError.invalidPrefix
                    }
                }
            }
            return value
        }

        mutating func text() throws {
            let start = position
            try literal("\"")
            var count = 0
            while true {
                let byte = try peek()
                if byte == 34 {
                    guard count > 0 else { throw GenerationGrammarError.invalidPrefix }
                    position += 1
                    if requiresPoem {
                        // Validate the model's JSON escapes; never manufacture line breaks after decoding.
                        let value = try JSONDecoder().decode(String.self, from: Data(data[start..<position]))
                        let lines = value.split(whereSeparator: \.isNewline)
                            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        guard lines.count == 1 else {
                            throw GenerationGrammarError.invalidPrefix
                        }
                    }
                    return
                }
                guard byte >= 32 else { throw GenerationGrammarError.invalidPrefix }
                position += 1
                if byte == 92 {
                    let escaped = try peek()
                    position += 1
                    if escaped == 117 {
                        let unit = try hexUnit()
                        if (0xD800...0xDBFF).contains(unit) {
                            try literal("\\u")
                            _ = try hexUnit(lowSurrogate: true)
                        } else if (0xDC00...0xDFFF).contains(unit) {
                            throw GenerationGrammarError.invalidPrefix
                        }
                    } else if ![34, 92, 47, 98, 102, 110, 114, 116].contains(escaped) {
                        throw GenerationGrammarError.invalidPrefix
                    }
                }
                count += 1
            }
        }

        mutating func reference() throws {
            whitespace()
            let remaining = data.count - position
            for identity in identities {
                let length = min(remaining, identity.count)
                let slice = data[position..<(position + length)]
                guard identity.prefix(length).elementsEqual(slice) else { continue }
                guard remaining >= identity.count else { throw GenerationGrammarError.incomplete }
                position += identity.count
                return
            }
            throw GenerationGrammarError.invalidPrefix
        }

        mutating func references() throws {
            try token("[")
            whitespace()
            if try peek() == 93 {
                position += 1
                return
            }
            for index in 0..<4 {
                try reference()
                whitespace()
                if try peek() == 93 {
                    position += 1
                    return
                }
                guard index < 3 else { throw GenerationGrammarError.invalidPrefix }
                try literal(",")
            }
        }
    }
}

nonisolated struct GenerationGrammarDecoder {
    let grammar: GenerationEnvelopeGrammar
    let tokenBytes: [Int: [UInt8]]
    let eosIDs: Set<Int>
    private(set) var output: [UInt8] = []
    private(set) var ended = false
    private(set) var candidateChecks = 0

    func allows(_ id: Int) -> Bool {
        guard !ended else { return false }
        let complete = grammar.status(output) == .complete
        if eosIDs.contains(id) { return complete }
        guard !complete, let fragment = tokenBytes[id], !fragment.isEmpty else { return false }
        return grammar.status(output + fragment) != .invalid
    }

    mutating func select(_ scores: [Float], deadline: Double? = nil) throws -> Int {
        try Task.checkCancellation()
        guard scores.allSatisfy({ !$0.isNaN && $0 != .infinity }) else { throw GenerationGrammarError.invalidLogits }
        let ranked = scores.indices.sorted {
            scores[$0] == scores[$1] ? $0 < $1 : scores[$0] > scores[$1]
        }
        for id in ranked where scores[id].isFinite {
            candidateChecks += 1
            if candidateChecks % 256 == 1 {
                try Task.checkCancellation()
                if let deadline, ProcessInfo.processInfo.systemUptime >= deadline {
                    throw GenerationBudgetError.deadline
                }
            }
            if allows(id) { return id }
        }
        throw GenerationGrammarError.noAllowedToken
    }

    mutating func accept(_ id: Int) throws {
        guard allows(id) else { throw GenerationGrammarError.invalidPrefix }
        if eosIDs.contains(id) { ended = true } else if let bytes = tokenBytes[id] { output += bytes }
    }
}
