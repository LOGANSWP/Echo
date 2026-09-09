// ==========================================
// File: GenerationTokenizer.swift
// Spec: US-SYN-001/002/004; ADR-023 sections 1-4
// Task: 4.0k - Approved offline generation runtime
// AC coverage: pinned tokenizer, bounded inference and provenance grammar
// Architecture: AGENTS.md sections 4.2, 6.2; request-owned value types
// Generated: 2026-09-08
// ==========================================

import Foundation

nonisolated enum GenerationTokenizerError: Error {
    case unsupportedConfiguration, invalidVocabulary, inputBudget, encodingFailure
}

nonisolated struct GenerationTokenPair: Hashable {
    let left: Int
    let right: Int
}

nonisolated struct GenerationTokenMerge {
    let rank: Int
    let token: Int
}

nonisolated struct GenerationTokenizer {
    let vocabulary: [String: Int]
    let bytesByToken: [Int: [UInt8]]
    let byteTokens: [Int]
    let merges: [GenerationTokenPair: GenerationTokenMerge]
    let regex: NSRegularExpression
    let framingTokens: [String: Int]

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count <= 32 * 1_048_576,
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let model = json["model"] as? [String: Any], model["type"] as? String == "BPE",
            model["dropout"] is NSNull, model["unk_token"] is NSNull,
            (model["continuing_subword_prefix"] as? String)?.isEmpty == true,
            (model["end_of_word_suffix"] as? String)?.isEmpty == true,
            model["fuse_unk"] as? Bool == false, model["byte_fallback"] as? Bool == false,
            model["ignore_merges"] as? Bool == false,
            let normalizer = json["normalizer"] as? [String: Any], normalizer["type"] as? String == "NFC",
            let pre = json["pre_tokenizer"] as? [String: Any], pre["type"] as? String == "Sequence",
            let steps = pre["pretokenizers"] as? [[String: Any]], steps.count == 2,
            steps[0]["type"] as? String == "Split", steps[0]["behavior"] as? String == "Isolated",
            steps[0]["invert"] as? Bool == false,
            let pattern = (steps[0]["pattern"] as? [String: String])?["Regex"],
            steps[1]["type"] as? String == "ByteLevel",
            steps[1]["add_prefix_space"] as? Bool == false, steps[1]["use_regex"] as? Bool == false,
            let vocab = model["vocab"] as? [String: Int], vocab.count == 151_643,
            let rawMerges = model["merges"] as? [[String]], rawMerges.count == 151_387
        else {
            throw GenerationTokenizerError.unsupportedConfiguration
        }
        // Exact Qwen3 pinned splitter. Other dialects require separate conformance.
        let supportedPattern =
            #"(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"#
        guard pattern == supportedPattern else { throw GenerationTokenizerError.unsupportedConfiguration }
        regex = try NSRegularExpression(pattern: pattern)
        vocabulary = vocab
        var alphabet: [UInt8: Unicode.Scalar] = [:]
        var inverse: [Unicode.Scalar: UInt8] = [:]
        var extra = 256
        for byte in 0...255 {
            let literal = (33...126).contains(byte) || (161...172).contains(byte) || (174...255).contains(byte)
            guard let scalar = Unicode.Scalar(literal ? byte : extra) else {
                throw GenerationTokenizerError.invalidVocabulary
            }
            if !literal { extra += 1 }
            alphabet[UInt8(byte)] = scalar
            inverse[scalar] = UInt8(byte)
        }
        byteTokens = try (0...255).map { byte in
            guard let scalar = alphabet[UInt8(byte)], let token = vocab[String(scalar)] else {
                throw GenerationTokenizerError.invalidVocabulary
            }
            return token
        }
        var decoded: [Int: [UInt8]] = [:]
        for (text, token) in vocab {
            guard decoded[token] == nil else { throw GenerationTokenizerError.invalidVocabulary }
            decoded[token] = try text.unicodeScalars.map { scalar in
                guard let byte = inverse[scalar] else { throw GenerationTokenizerError.invalidVocabulary }
                return byte
            }
        }
        guard let added = json["added_tokens"] as? [[String: Any]], added.count == 26 else {
            throw GenerationTokenizerError.unsupportedConfiguration
        }
        var special: [String: Int] = [:]
        for item in added {
            guard let content = item["content"] as? String, let token = item["id"] as? Int,
                item["normalized"] as? Bool == false, decoded[token] == nil,
                special[content] == nil
            else { throw GenerationTokenizerError.invalidVocabulary }
            special[content] = token
            decoded[token] = Array(content.utf8)
        }
        let required = [
            "<|im_start|>": 151_644, "<|im_end|>": 151_645,
            "<think>": 151_667, "</think>": 151_668,
        ]
        guard required.allSatisfy({ special[$0.key] == $0.value }) else {
            throw GenerationTokenizerError.unsupportedConfiguration
        }
        framingTokens = required
        bytesByToken = decoded
        var table: [GenerationTokenPair: GenerationTokenMerge] = [:]
        for (rank, parts) in rawMerges.enumerated() {
            guard parts.count == 2, let left = vocab[parts[0]], let right = vocab[parts[1]],
                let token = vocab[parts[0] + parts[1]], table[GenerationTokenPair(left: left, right: right)] == nil
            else {
                throw GenerationTokenizerError.invalidVocabulary
            }
            table[GenerationTokenPair(left: left, right: right)] = GenerationTokenMerge(rank: rank, token: token)
        }
        merges = table
    }

    func encode(_ text: String) throws -> [Int] {
        guard text.utf8.count <= 16_384 else { throw GenerationTokenizerError.inputBudget }
        // GenerationTokenizer normalization never mutates the original memory/source value.
        let normalized = text.precomposedStringWithCanonicalMapping as NSString
        let matches = regex.matches(in: normalized as String, range: NSRange(location: 0, length: normalized.length))
        var result: [Int] = []
        var covered = 0
        for match in matches {
            guard match.range.location == covered else { throw GenerationTokenizerError.encodingFailure }
            covered += match.range.length
            var tokens = normalized.substring(with: match.range).utf8.map { byteTokens[Int($0)] }
            while tokens.count > 1 {
                var chosen: (index: Int, merge: GenerationTokenMerge)?
                for index in 0..<(tokens.count - 1) {
                    if let merge = merges[GenerationTokenPair(left: tokens[index], right: tokens[index + 1])],
                        merge.rank < (chosen?.merge.rank ?? Int.max) {
                        chosen = (index, merge)
                    }
                }
                guard let chosen else { break }
                tokens.replaceSubrange(chosen.index...chosen.index + 1, with: [chosen.merge.token])
            }
            result.append(contentsOf: tokens)
        }
        guard covered == normalized.length else { throw GenerationTokenizerError.encodingFailure }
        return result
    }

    func decode(_ tokens: [Int]) throws -> String {
        let bytes = try tokens.flatMap { token -> [UInt8] in
            guard let value = bytesByToken[token] else { throw GenerationTokenizerError.encodingFailure }
            return value
        }
        guard let text = String(bytes: bytes, encoding: .utf8) else { throw GenerationTokenizerError.encodingFailure }
        return text
    }

    func encodeChat(_ messages: [GenerationChatMessage]) throws -> [Int] {
        guard messages.map(\.role) == ["system", "user"] else {
            throw GenerationTokenizerError.unsupportedConfiguration
        }
        guard let start = framingTokens["<|im_start|>"], let end = framingTokens["<|im_end|>"],
            let think = framingTokens["<think>"], let endThink = framingTokens["</think>"]
        else {
            throw GenerationTokenizerError.unsupportedConfiguration
        }
        var tokens: [Int] = []
        for message in messages {
            tokens.append(start)
            tokens += try encode(message.role + "\n" + message.content)
            tokens.append(end)
            tokens += try encode("\n")
        }
        tokens.append(start)
        tokens += try encode("assistant\n")
        tokens.append(think)
        tokens += try encode("\n\n")
        tokens.append(endThink)
        tokens += try encode("\n\n")
        return tokens
    }
}

nonisolated struct GenerationChatMessage: Decodable {
    let role: String
    let content: String
}
