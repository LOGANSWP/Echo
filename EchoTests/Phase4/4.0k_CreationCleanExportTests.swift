// ==========================================
// File: 4.0k_CreationCleanExportTests.swift
// Spec: US-SYN-003 AC-3; user export feedback (2026-09-08)
// Task: 4.0k - Readable creation exports without internal source identifiers
// AC coverage: copy/share/Markdown and extracted multipage PDF content
// Generated: 2026-09-08
// ==========================================

import Foundation
import PDFKit
import Testing
@testable import Echo

@Suite("4.0k Clean Creation Export", .serialized)
@MainActor
struct CreationCleanExportTests {
    private let sourceID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!

    private func output(long: Bool = false) -> CreativeOutput {
        CreativeOutput(template: .poem, title: "A quiet circle", paragraphs: [
            GroundedParagraph(id: UUID(), text: "Opening verse: a blue circle.",
                              anchors: [SourceAnchor(memoryID: sourceID)], groundingStatus: .cited),
            GroundedParagraph(id: UUID(), text: long
                              ? String(repeating: "The white page holds the circle. ", count: 800)
                              : "白纸上的蓝圆\n静静停留。",
                              anchors: [SourceAnchor(memoryID: sourceID)], groundingStatus: .cited),
            GroundedParagraph(id: UUID(), text: "Final verse: the white page.",
                              anchors: [], groundingStatus: .noSource),
        ], sourceMemoryCount: 1)
    }

    @Test("AC-3: text exports never append internal provenance fields")
    func test_AC3_textExportsHideIdentifiers() {
        let creation = output()
        for text in [CreationExportService.plainText(from: creation),
                     CreationExportService.shareText(from: creation),
                     CreationExportService.markdown(from: creation),
        ] {
            #expect(!text.contains(sourceID.uuidString))
            #expect(!text.contains("MemoryID:"))
            #expect(!text.contains("NoSource"))
            #expect(text.contains("白纸上的蓝圆"))
            #expect(text.contains("静静停留。"))
        }
        #expect(creation.paragraphs.first?.anchors.first?.memoryID == sourceID)
        #expect(CreationExportService.plainText(from: creation) ==
                "A quiet circle\n\nOpening verse: a blue circle.\n白纸上的蓝圆\n静静停留。\nFinal verse: the white page.")
        #expect(CreationExportService.markdown(from: creation) ==
                "# A quiet circle\n\nOpening verse: a blue circle.  \n白纸上的蓝圆  \n静静停留。  \nFinal verse: the white page.")
    }

    @Test("AC-3: multipage PDF contains the full text without internal IDs or Markdown markup")
    func test_AC3_pdfTextIsReadable() async throws {
        let data = try await CreationExportService.pdf(from: output(long: true))
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount > 1)
        let text = try #require(document.string)
        #expect(text.contains("Opening verse: a blue circle."))
        #expect(text.contains("Final verse: the white page."))
        #expect(!text.contains("MemoryID:"))
        #expect(!text.contains(sourceID.uuidString))
        #expect(!text.contains("NoSource"))
        #expect(!text.contains("# A quiet circle"))
    }
}
