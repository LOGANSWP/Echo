// File: 4.0m_CreationLanguageTests.swift
// Spec: R-004; AGENTS.md section 6.2; ADR-023
// Task: 4.0m - Short Simplified Chinese generation validation
import Testing
@testable import Echo

@Suite("Creation body language", .serialized)
struct CreationLanguageTests {
    @Test("Short Simplified Chinese remains valid", arguments: [
        "一只狗站在沙地上，背景有山。", "狗站在沙地上。", "山在远处。",
    ])
    func shortChinese(_ text: String) {
        #expect(LanguageAligner.bodyMatches(text, language: "zh-Hans"))
        #expect(!LanguageAligner.bodyMatches(text, language: "en-US"))
    }

    @Test("Uncertain fallback cannot accept other scripts or empty content", arguments: [
        "", "123，。", "🐕🏔️", "這隻狗站在沙地上，遠處有山。",
        "The dog stands on the sand.", "犬が砂の上に立っています。", "山 dog mountain",
    ])
    func rejectedChinese(_ text: String) {
        #expect(!LanguageAligner.bodyMatches(text, language: "zh-Hans"))
    }

    @Test("English remains accepted")
    func english() {
        #expect(LanguageAligner.bodyMatches("A dog is standing on the sand, with mountains in the background.", language: "en-US"))
    }
}
