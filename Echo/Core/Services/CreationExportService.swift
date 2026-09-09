// ==========================================
// File: CreationExportService.swift
// Spec: US-SYN-003 AC-3/4; ADR-024 clean creation export
// Task: 4.0k - Title/body-only copy, Markdown, PDF and system share
// AC coverage: no appended source IDs; verse continuity; complete multipage PDF
// Boundary: callers authorize the full source-bearing output before formatting.
// Internal provenance and original paragraph text remain unchanged.
// Updated: 2026-09-08
// ==========================================

import Foundation
import CoreText
import UIKit

/// Formats authorized creation text for user-mediated copy, export and sharing.
enum CreationExportService {
    /// Markdown keeps headings and explicit poetic line breaks without source metadata.
    nonisolated static func markdown(from output: CreativeOutput) -> String {
        let separator = output.template == .poem ? "  \n" : "\n\n"
        let body = output.paragraphs.map { paragraph in
            output.template == .poem
                ? paragraph.text.replacingOccurrences(of: "\n", with: "  \n")
                : paragraph.text
        }.joined(separator: separator)
        guard let title = output.title, !title.isEmpty else { return body }
        return "# \(title)\n\n\(body)"
    }

    /// PDF renders readable text, never raw Markdown control characters.
    static func pdf(from output: CreativeOutput) async throws -> Data {
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 595, height: 842),
            format: UIGraphicsPDFRendererFormat()
        )
        let text = plainText(from: output)
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: UIFont.systemFont(ofSize: 12)]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let contentBounds = CGRect(x: 40, y: 40, width: 515, height: 762)
        var location = 0
        let data = renderer.pdfData { context in
            repeat {
                context.beginPage()
                let graphics = context.cgContext
                graphics.saveGState()
                graphics.translateBy(x: 0, y: pageBounds.height)
                graphics.scaleBy(x: 1, y: -1)
                let path = CGPath(rect: contentBounds, transform: nil)
                let range = CFRange(location: location, length: attributed.length - location)
                let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
                CTFrameDraw(frame, graphics)
                let visible = CTFrameGetVisibleStringRange(frame)
                location += visible.length
                graphics.restoreGState()
                if visible.length == 0 { break }
            } while location < attributed.length
        }
        return data
    }

    /// Provenance stays in the domain model and is not appended to external text.
    nonisolated static func plainText(from output: CreativeOutput) -> String {
        let separator = output.template == .poem ? "\n" : "\n\n"
        let body = output.paragraphs.map(\.text).joined(separator: separator)
        guard let title = output.title, !title.isEmpty else { return body }
        return "\(title)\n\n\(body)"
    }

    nonisolated static func shareText(from output: CreativeOutput) -> String {
        plainText(from: output)
    }
}
