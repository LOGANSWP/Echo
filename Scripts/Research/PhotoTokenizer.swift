// Task 4.0l / ADR-025: pinned SmolVLM ByteLevel BPE, outside the App.
// Local tokenizer.json is authoritative; ordinary text cannot create protocol tokens.
import Foundation

enum PhotoTokenError: Error {
    case configuration, vocabulary, inputBudget, encoding
}

struct PhotoTokenPair: Hashable {
    let left: Int
    let right: Int
}

struct PhotoTokenMerge {
    let rank: Int
    let token: Int
}

struct PhotoTokenizer {
    let vocabulary: [String: Int]
    let bytesByToken: [Int: [UInt8]]
    let byteTokens: [Int?]
    let merges: [PhotoTokenPair: PhotoTokenMerge]
    let regex: NSRegularExpression
    let digits: NSRegularExpression
    let framingTokens: [String: Int]

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count <= 32 * 1_048_576,
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let model = json["model"] as? [String: Any], model["type"] as? String == "BPE",
            model["dropout"] is NSNull, model["unk_token"] is NSNull,
            model["continuing_subword_prefix"] is NSNull, model["end_of_word_suffix"] is NSNull,
            model["fuse_unk"] as? Bool == false, model["byte_fallback"] as? Bool == false,
            model["ignore_merges"] as? Bool == false, json["normalizer"] is NSNull,
            let pre = json["pre_tokenizer"] as? [String: Any], pre["type"] as? String == "Sequence",
            let steps = pre["pretokenizers"] as? [[String: Any]], steps.count == 2,
            steps[0]["type"] as? String == "Digits", steps[0]["individual_digits"] as? Bool == true,
            steps[1]["type"] as? String == "ByteLevel", steps[1]["add_prefix_space"] as? Bool == false,
            steps[1]["use_regex"] as? Bool == true,
            let vocab = model["vocab"] as? [String: Int], vocab.count == 49152,
            let rawMerges = model["merges"] as? [[String]], rawMerges.count == 48900
        else { throw PhotoTokenError.configuration }
        // Hugging Face ByteLevel GPT-2 splitter after individual Unicode numeric splits.
        regex = try NSRegularExpression(pattern:
            #"'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+"#)
        digits = try NSRegularExpression(pattern: #"\p{N}|[^\p{N}]+"#)
        vocabulary = vocab
        var alphabet: [UInt8: Unicode.Scalar] = [:]
        var inverse: [Unicode.Scalar: UInt8] = [:]
        var extra = 256
        for byte in 0...255 {
            let literal = (33...126).contains(byte) || (161...172).contains(byte) || (174...255).contains(byte)
            guard let scalar = Unicode.Scalar(literal ? byte : extra) else { throw PhotoTokenError.vocabulary }
            if !literal { extra += 1 }
            alphabet[UInt8(byte)] = scalar
            inverse[scalar] = UInt8(byte)
        }
        byteTokens = (0...255).map { byte in
            alphabet[UInt8(byte)].flatMap { vocab[String($0)] }
        }
        var decoded: [Int: [UInt8]] = [:]
        for (text, token) in vocab {
            guard decoded[token] == nil else { throw PhotoTokenError.vocabulary }
            decoded[token] = try text.unicodeScalars.map { scalar in
                guard let byte = inverse[scalar] else { throw PhotoTokenError.vocabulary }
                return byte
            }
        }
        guard let added = json["added_tokens"] as? [[String: Any]], added.count == 145 else {
            throw PhotoTokenError.configuration
        }
        var special: [String: Int] = [:]
        for item in added {
            guard let content = item["content"] as? String, let token = item["id"] as? Int,
                item["normalized"] as? Bool == false, item["special"] as? Bool == true,
                special[content] == nil, decoded[token] == nil || vocab[content] == token
            else { throw PhotoTokenError.vocabulary }
            special[content] = token
            decoded[token] = Array(content.utf8)
        }
        let required = ["<|im_start|>": 1, "<end_of_utterance>": 49279,
                        "<fake_token_around_image>": 49189, "<global-img>": 49152, "<image>": 49190]
        guard required.allSatisfy({ special[$0.key] == $0.value }) else { throw PhotoTokenError.configuration }
        framingTokens = required
        bytesByToken = decoded
        var table: [PhotoTokenPair: PhotoTokenMerge] = [:]
        for (rank, parts) in rawMerges.enumerated() {
            guard parts.count == 2, let left = vocab[parts[0]], let right = vocab[parts[1]],
                let token = vocab[parts[0] + parts[1]], table[PhotoTokenPair(left: left, right: right)] == nil
            else {
                throw PhotoTokenError.vocabulary
            }
            table[PhotoTokenPair(left: left, right: right)] = PhotoTokenMerge(rank: rank, token: token)
        }
        merges = table
    }

    func encode(_ text: String) throws -> [Int] {
        guard text.utf8.count <= 16_384 else { throw PhotoTokenError.inputBudget }
        // No NFC normalization: preserve the pinned tokenizer's byte identity.
        let original = text as NSString
        var result: [Int] = []
        var covered = 0
        for group in digits.matches(in: text, range: NSRange(location: 0, length: original.length)) {
            guard group.range.location == covered else { throw PhotoTokenError.encoding }
            covered += group.range.length
            let part = original.substring(with: group.range) as NSString
            var localCovered = 0
            for match in regex.matches(in: part as String, range: NSRange(location: 0, length: part.length)) {
                guard match.range.location == localCovered else { throw PhotoTokenError.encoding }
                localCovered += match.range.length
                // This pinned vocabulary omits some byte symbols; never silently drop them.
                var tokens = try part.substring(with: match.range).utf8.map { byte in
                    guard let token = byteTokens[Int(byte)] else { throw PhotoTokenError.encoding }
                    return token
                }
                while tokens.count > 1 {
                    var chosen: (index: Int, merge: PhotoTokenMerge)?
                    for index in 0..<(tokens.count - 1) {
                        if let merge = merges[PhotoTokenPair(left: tokens[index], right: tokens[index + 1])],
                            chosen.map({ merge.rank < $0.merge.rank }) ?? true {
                            chosen = (index, merge)
                        }
                    }
                    guard let chosen else { break }
                    tokens.replaceSubrange(chosen.index...chosen.index + 1, with: [chosen.merge.token])
                }
                result.append(contentsOf: tokens)
            }
            guard localCovered == part.length else { throw PhotoTokenError.encoding }
        }
        guard covered == original.length else { throw PhotoTokenError.encoding }
        return result
    }

    func decode(_ tokens: [Int]) throws -> String {
        let bytes = try tokens.flatMap { token -> [UInt8] in
            guard let value = bytesByToken[token] else { throw PhotoTokenError.encoding }
            return value
        }
        guard let text = String(bytes: bytes, encoding: .utf8) else { throw PhotoTokenError.encoding }
        return text
    }

    func encodePrompt(_ text: String) throws -> [Int] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 4096 else { throw PhotoTokenError.inputBudget }
        var result = [1] + (try encode("User:")) + [49189, 49152]
        result += Array(repeating: 49190, count: 64)
        result += [49189] + (try encode(text)) + [49279]
        result += try encode("\nAssistant:")
        guard result.count <= 768 else { throw PhotoTokenError.inputBudget }
        return result
    }
}
