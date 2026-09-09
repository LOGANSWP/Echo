// Task 4.0k / ADR-023 sections 2-4: bounded research grammar-v1 byte parser.
// Matches the existing one/two-paragraph experiment. Never repairs JSON, supplies
// text, assigns references, or treats valid source identities as factual proof.
import Foundation

enum GrammarError: Error { case invalidInput, invalidPrefix, incomplete, noAllowedToken, invalidLogits }
enum PrefixStatus: String { case invalid, prefix, complete }

struct EnvelopeGrammar {
    let identities: [[UInt8]]

    init(allowedIDs: [String]) throws {
        let ids = Array(Set(allowedIDs)).sorted()
        guard (1...4).contains(ids.count),
            ids.allSatisfy({
                UUID(uuidString: $0)?.uuidString.lowercased() == $0.lowercased() && $0.utf8.count == 36
            })
        else { throw GrammarError.invalidInput }
        identities = ids.map { Array(("\"" + $0 + "\"").utf8) }
    }

    func status(_ data: [UInt8]) -> PrefixStatus {
        guard data.count <= 262_144 else { return .invalid }
        let utf8 = Self.utf8Status(data)
        guard utf8 != .invalid else { return .invalid }
        var parser = Parser(data: data, identities: identities)
        do {
            try parser.document()
            return utf8 == .prefix ? .prefix : .complete
        } catch GrammarError.incomplete { return .prefix } catch { return .invalid }
    }

    private static func utf8Status(_ bytes: [UInt8]) -> PrefixStatus {
        var index = 0
        while index < bytes.count {
            let head = bytes[index]
            if head < 128 { index += 1; continue }
            let length: Int
            var minimum: UInt8 = 128
            var maximum: UInt8 = 191
            switch head {
            case 194...223: length = 2
            case 224: length = 3; minimum = 160
            case 225...236, 238...239: length = 3
            case 237: length = 3; maximum = 159
            case 240: length = 4; minimum = 144
            case 241...243: length = 4
            case 244: length = 4; maximum = 143
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

    private struct Parser {
        let data: [UInt8]
        let identities: [[UInt8]]
        var position = 0

        mutating func whitespace() {
            while position < data.count && [9, 10, 13, 32].contains(data[position]) { position += 1 }
        }

        func peek() throws -> UInt8 {
            guard position < data.count else { throw GrammarError.incomplete }
            return data[position]
        }

        mutating func literal(_ value: String) throws {
            for byte in value.utf8 {
                guard try peek() == byte else { throw GrammarError.invalidPrefix }
                position += 1
            }
        }

        mutating func token(_ value: String) throws {
            whitespace()
            try literal(value)
        }

        mutating func document() throws {
            try token("{"); try token("\"schemaVersion\""); try token(":"); try token("1")
            try token(","); try token("\"paragraphs\""); try token(":"); try token("[")
            try paragraph()
            whitespace()
            if try peek() == 44 { position += 1; try paragraph() }
            try token("]"); try token("}"); whitespace()
            guard position == data.count else { throw GrammarError.invalidPrefix }
        }

        mutating func paragraph() throws {
            try token("{"); try token("\"text\""); try token(":"); whitespace(); try text()
            try token(","); try token("\"sourceMemoryIDs\""); try token(":"); try references(); try token("}")
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
                default: throw GrammarError.invalidPrefix
                }
                value = value * 16 + digit; position += 1
                let scale = 1 << ((3 - offset) * 4)
                let possible = (value * scale)...((value + 1) * scale - 1)
                if lowSurrogate {
                    guard possible.overlaps(0xDC00...0xDFFF) else { throw GrammarError.invalidPrefix }
                } else {
                    guard possible.lowerBound < 0xDC00 || possible.upperBound > 0xDFFF else {
                        throw GrammarError.invalidPrefix
                    }
                }
            }
            return value
        }

        mutating func text() throws {
            try literal("\"")
            var count = 0
            while true {
                let byte = try peek()
                if byte == 34 {
                    guard count > 0 else { throw GrammarError.invalidPrefix }
                    position += 1; return
                }
                guard byte >= 32 else { throw GrammarError.invalidPrefix }
                position += 1
                if byte == 92 {
                    let escaped = try peek(); position += 1
                    if escaped == 117 {
                        let unit = try hexUnit()
                        if (0xD800...0xDBFF).contains(unit) {
                            try literal("\\u")
                            _ = try hexUnit(lowSurrogate: true)
                        } else if (0xDC00...0xDFFF).contains(unit) {
                            throw GrammarError.invalidPrefix
                        }
                    } else if ![34, 92, 47, 98, 102, 110, 114, 116].contains(escaped) {
                        throw GrammarError.invalidPrefix
                    }
                }
                count += 1
            }
        }

        mutating func reference() throws {
            whitespace()
            let remaining = data.count - position
            let length = min(remaining, 38)
            let slice = data[position..<(position + length)]
            guard identities.contains(where: { $0.prefix(length).elementsEqual(slice) }) else {
                throw GrammarError.invalidPrefix
            }
            guard remaining >= 38 else { throw GrammarError.incomplete }
            position += 38
        }

        mutating func references() throws {
            try token("["); whitespace()
            if try peek() == 93 { position += 1; return }
            for index in 0..<4 {
                try reference(); whitespace()
                if try peek() == 93 { position += 1; return }
                guard index < 3 else { throw GrammarError.invalidPrefix }
                try literal(",")
            }
        }
    }
}

struct GrammarDecoder {
    let grammar: EnvelopeGrammar
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
        guard scores.allSatisfy({ !$0.isNaN && $0 != .infinity }) else { throw GrammarError.invalidLogits }
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
        throw GrammarError.noAllowedToken
    }

    mutating func accept(_ id: Int) throws {
        guard allows(id) else { throw GrammarError.invalidPrefix }
        if eosIDs.contains(id) {
            ended = true
        } else {
            guard let bytes = tokenBytes[id] else { throw GrammarError.invalidPrefix }
            output += bytes
        }
    }
}
