// ==========================================
// File: 4.0k_CreationCitationPresentationTests.swift
// Spec: US-SYN-002 AC-2/3/4; US-SYN-003
// Task: 4.0k - Group poem source links without changing provenance
// AC coverage: stable distinct links, unavailable sources, original per-line attribution
// Generated: 2026-09-08
// ==========================================

import Foundation
import Testing

@testable import Echo

@Suite("4.0k Creation Citation Presentation")
@MainActor
struct CreationCitationPresentationTests {
    @Test("AC-2/3: group repeated sources while preserving every line and warning")
    func test_AC2_groupPoemSources() {
        let first = CreationCitation(memoryId: UUID(), sourceType: "photo")
        let second = CreationCitation(memoryId: UUID(), sourceType: "note", availability: .offlineUnavailable)
        let paragraphs = [
            CreationParagraph(id: UUID(), text: "First verse", citations: [first], groundingStatus: .cited),
            CreationParagraph(id: UUID(), text: "Second verse", citations: [first, second], groundingStatus: .partialNoSource),
            CreationParagraph(id: UUID(), text: "Third verse", citations: [], groundingStatus: .noSource),
            CreationParagraph(id: UUID(), text: "Fourth verse", citations: [second, first], groundingStatus: .cited),
        ]
        let model = CreationModel(selectedTemplate: .poem, title: nil, periodType: nil,
                                  paragraphs: paragraphs, sourceMemoryCount: 2, emptyReason: nil)
        #expect(model.distinctSourceCitations == [first, second])
        #expect(model.paragraphs == paragraphs)
        #expect(model.distinctSourceCitations[1].availability == .offlineUnavailable)
    }
}
