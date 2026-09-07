// ==========================================
// 文件: CreationExportService.swift
// 对应规格: docs/decisions/ADR-013-creation-export-boundary.md → 决策 4 (Markdown/PDF/系统 share 导出),
//            docs/01-spec/用户故事与验收标准规格书.md → US-SYN-003 AC-3 (导出 PDF/Markdown),
//            US-SYN-004 AC-4 (分享/导出/打印)
// 任务: 3F.9 + 4.0i - Citation-preserving creation export
// AC 覆盖: US-SYN-003 AC-3 ✅ (plain text/Markdown/多页 PDF 保留引用), AC-6 ✅ (exportFormat typed 审计),
//          US-SYN-004 AC-4 ✅ (分享/导出/打印), ADR-013 决策 4 ✅ (系统 share/export, 无 notes:// 深链)
// 架构约束: Core 服务; 纯函数 (输入 CreativeOutput → 输出 Markdown/PDF/分享文本);
//           禁止 notes://echo/... 深链 (ADR-013 决策 4 — Notes 交接仅用系统 share/export 流)
// 重要: 项目 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor，struct 成员需 nonisolated
// 生成时间: 2026-08-11 | Updated: 2026-09-07 (4.0i, ADR-020)
// ==========================================

import Foundation
import CoreText
import UIKit

/// 创作导出服务 — Markdown / PDF / 系统分享文本 (US-SYN-003 AC-3, ADR-013 决策 4)。
///
/// ## 职责 (ADR-013 决策 4)
/// - Markdown: 标题 + 段落 + 溯源锚点（`[🔗 MemoryID:xxx]` / `[⚠️ NoSource]`）
/// - PDF: 经 `UIGraphicsPDFRenderer` 渲染为 PDF Data
/// - Share text: 纯文本（不含锚点标记），供系统 share sheet 使用
/// - **Notes 交接仅用系统 share/export 流，不伪造 `notes://` URL**
enum CreationExportService {

    // MARK: - Markdown (US-SYN-003 AC-3)

    /// 生成 Markdown — 标题 + 段落 + 溯源锚点 (US-SYN-002 AC-1)。
    nonisolated static func markdown(from output: CreativeOutput) -> String {
        var lines: [String] = []
        if let title = output.title {
            lines.append("# \(title)")
            lines.append("")
        }
        for paragraph in output.paragraphs {
            lines.append(contentsOf: citationLines(for: paragraph, prefix: "> "))
            lines.append(paragraph.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - PDF (US-SYN-003 AC-3)

    /// 生成 PDF Data — 经 `UIGraphicsPDFRenderer` 渲染 Markdown 文本。
    static func pdf(from output: CreativeOutput) async throws -> Data {
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 595, height: 842),
            format: UIGraphicsPDFRendererFormat()
        )
        let text = markdown(from: output)
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

    // MARK: - Share Text (US-SYN-003 AC-3, US-SYN-004 AC-4)

    /// Plain-text export preserves source meaning so copy/share never strips provenance.
    nonisolated static func plainText(from output: CreativeOutput) -> String {
        var lines: [String] = []
        if let title = output.title {
            lines.append(title)
            lines.append("")
        }
        for paragraph in output.paragraphs {
            lines.append(contentsOf: citationLines(for: paragraph, prefix: ""))
            lines.append(paragraph.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func shareText(from output: CreativeOutput) -> String {
        plainText(from: output)
    }

    private nonisolated static func citationLines(for paragraph: GroundedParagraph, prefix: String) -> [String] {
        var lines = paragraph.anchors.map {
            let availability = $0.availability == .available
                ? ""
                : " [⚠️ SourceUnavailable:\($0.availability.rawValue)]"
            return "\(prefix)[🔗 MemoryID:\($0.memoryID.uuidString)\(availability)]"
        }
        if paragraph.groundingStatus != .cited {
            lines.append("\(prefix)[⚠️ NoSource]")
        }
        return lines
    }
}
