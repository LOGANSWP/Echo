// ==========================================
// 文件: CreativePipeline.swift
// 对应规格: docs/decisions/ADR-009-offline-model-runtime.md → 决策 4 (grounded creation),
//            docs/decisions/ADR-013-creation-export-boundary.md → 决策 3 (grounded 生成 + source anchors),
//            docs/01-spec/用户故事与验收标准规格书.md → US-SYN-002 (溯源锚点), US-SYN-003 (grounded 生成),
//            US-SYN-007 (术语表注入), US-SYN-008 (合成失败模板降级)
// 任务: 3F.9 + 4.0a + 4.0i - Grounded creation and verifiable citations
// AC 覆盖: US-SYN-002 AC-1/3 ✅ (多锚点/NoSource/partialNoSource), AC-5 ✅ (.synthesis 审计),
//          US-SYN-003 AC-2 ✅ (版本化 JSON + exact allow-list), AC-6 ✅ (.creativeGeneration typed 审计),
//          US-SYN-007 AC-1 ✅ (Prompt 注入术语表子集), US-SYN-008 AC-1/5 ✅ (失败模板降级 + .synthesisFallback 审计),
//          US-PRV-001 AC-7 ✅ (按真实 sourceType 授权，不使用 search 伪来源),
//          R-004 ✅ (LanguageAligner 语言对齐)
// 架构约束: AGENTS.md §4.1 (Pipeline 契约: 审计强制 / 错误分级 / 纯函数), R-006 (PrivacyCheckpoint 入口),
//           §4.2 (仅持有不可变引用); actor 声明合法 (v5.12)
// 生成时间: 2026-08-11 | Updated: 2026-09-07 (4.0i, ADR-020)
// ==========================================

import Foundation

// MARK: - Grounded Creation Types

/// 创作模板类型 (US-SYN-003 AC-1: 信件/报告/诗歌/时间线)。
public enum CreativeTemplate: String, Sendable, Equatable {
    case letter
    case report
    case poem
    case timeline
}

/// grounded 创作源记忆 — 检索结果输入 (US-SYN-003 AC-2 严格引用检索结果)。
public nonisolated struct CreativeSource: Sendable, Equatable {
    /// 源记忆 ID
    public nonisolated let memoryID: UUID
    /// 数据源引用 (PHAsset.localIdentifier / note 定位符)
    public nonisolated let assetID: String
    /// 数据源类型 ("photo" / "note" / "voice" / "video_frame" 等)
    public nonisolated let sourceType: String
    /// 源文本 (nil = 图片/视频帧无文本)
    public nonisolated let text: String?
    /// 记忆时间戳
    public nonisolated let timestamp: TimeInterval

    public nonisolated init(
        memoryID: UUID,
        assetID: String,
        sourceType: String,
        text: String?,
        timestamp: TimeInterval
    ) {
        self.memoryID = memoryID
        self.assetID = assetID
        self.sourceType = sourceType
        self.text = text
        self.timestamp = timestamp
    }
}

/// 溯源锚点 — `[🔗 MemoryID:xxx]` (US-SYN-002 AC-1)。
public nonisolated struct SourceAnchor: Sendable, Equatable {
    /// 源记忆 ID
    public nonisolated let memoryID: UUID
    /// Canonical source type is carried internally for current-policy revalidation.
    public nonisolated let sourceType: String?
    /// Refreshed at the copy/export/navigation boundary; never inferred from model output.
    public nonisolated let availability: CitationSourceAvailability

    public nonisolated init(
        memoryID: UUID,
        sourceType: String? = nil,
        availability: CitationSourceAvailability = .available
    ) {
        self.memoryID = memoryID
        self.sourceType = sourceType
        self.availability = availability
    }

}

public nonisolated enum CitationSourceAvailability: String, Sendable, Codable, Equatable {
    case available
    case offlineUnavailable
    case missing
    case unsupported
}

/// Provenance state for one generated paragraph. This proves source identity, not factual accuracy.
public nonisolated enum GroundingStatus: String, Sendable, Codable, Equatable {
    case cited
    case noSource
    case partialNoSource
}

/// grounded 生成段落 — AI 生成文本 + 溯源锚点 (US-SYN-002/003 AC-2)。
public nonisolated struct GroundedParagraph: Sendable, Equatable, Identifiable {
    /// 段落唯一标识（确定性）
    public nonisolated let id: UUID
    /// 段落文本
    public nonisolated let text: String
    /// All validated source anchors in model-declared order, deduplicated within the paragraph.
    public nonisolated let anchors: [SourceAnchor]
    /// Whether every, none, or only part of the model-declared references passed the allow-list.
    public nonisolated let groundingStatus: GroundingStatus

    public nonisolated init(
        id: UUID,
        text: String,
        anchors: [SourceAnchor],
        groundingStatus: GroundingStatus
    ) {
        self.id = id
        self.text = text
        self.anchors = anchors
        self.groundingStatus = groundingStatus
    }

}

/// grounded 创作输出 — 含 source anchors (ADR-013 决策 3)。
public nonisolated struct CreativeOutput: Sendable, Equatable {
    /// 选中的创作模板
    public nonisolated let template: CreativeTemplate
    /// 结果标题（叙事报告含周期, US-SYN-004 AC-5）
    public nonisolated let title: String?
    /// 报告周期（US-SYN-004: 月/年）
    public nonisolated let periodType: String?
    /// 生成段落（含溯源锚点）
    public nonisolated let paragraphs: [GroundedParagraph]
    /// 引用的源记忆数
    public nonisolated let sourceMemoryCount: Int
    /// Canonical source types actually submitted to the model, retained for action-time policy checks.
    public nonisolated let sourceTypes: [String]
    /// 空态原因（无匹配源记忆时非 nil → empty state）
    public nonisolated let emptyReason: String?
    /// 合成是否走了失败降级模板 (US-SYN-008)
    public nonisolated let didFallback: Bool
    /// Count of validated anchor occurrences; duplicate IDs within one paragraph count once.
    public nonisolated var citationCount: Int {
        paragraphs.reduce(0) { $0 + $1.anchors.count }
    }
    /// Paragraphs carrying either noSource or partialNoSource.
    public nonisolated var noSourceCount: Int {
        paragraphs.count { $0.groundingStatus != .cited }
    }

    public nonisolated init(
        template: CreativeTemplate,
        title: String? = nil,
        periodType: String? = nil,
        paragraphs: [GroundedParagraph],
        sourceMemoryCount: Int,
        sourceTypes: [String] = [],
        emptyReason: String? = nil,
        didFallback: Bool = false
    ) {
        self.template = template
        self.title = title
        self.periodType = periodType
        self.paragraphs = paragraphs
        self.sourceMemoryCount = sourceMemoryCount
        self.sourceTypes = Array(Set(sourceTypes)).sorted()
        self.emptyReason = emptyReason
        self.didFallback = didFallback
    }
}

// MARK: - Creative Error

/// 创作管线错误 — 映射统一错误矩阵 (AGENTS.md §4.4)。
public enum CreativeError: Error, LocalizedError, Sendable, Equatable {
    /// 离线 LLM 运行时不可用 (L2 可恢复 — ViewModel 映射 .l2Recoverable, US-SYN-008 重试按钮)
    case runtimeUnavailable
    /// 隐私校验拒绝 (R-006)
    case privacyDenied(sourceTypes: [String])
    /// 语言对齐失败超出重试上限 (R-004, L2)
    case alignmentFailed
    /// 无匹配源记忆 (空态, 非错误 — 业务空结果)
    case noSources
    /// The model output did not satisfy ADR-020's bounded, versioned envelope contract (L2).
    case invalidStructuredOutput(CreativeProtocolFailure)

    public nonisolated var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            return "Offline LLM runtime is not available."
        case .privacyDenied(let sourceTypes):
            return "Privacy validation denied for sources: \(sourceTypes.joined(separator: ", "))"
        case .alignmentFailed:
            return "Language alignment failed after the maximum retry count."
        case .noSources:
            return "No source memories matched this template."
        case .invalidStructuredOutput(let failure):
            return "The generated response did not satisfy the grounded-output contract: \(failure.rawValue)."
        }
    }
}

public nonisolated enum CreativeProtocolFailure: String, Sendable, Equatable {
    case oversizedPayload
    case malformedEnvelope
    case unsupportedSchemaVersion
    case tooManyParagraphs
    case emptyParagraph
    case paragraphTooLong
    case tooManyReferences
}

/// Named limits make the local generation boundary deterministic and reviewable.
public nonisolated enum CreativeGenerationLimits {
    public nonisolated static let maximumPayloadBytes = 262_144
    public nonisolated static let maximumParagraphs = 64
    public nonisolated static let maximumParagraphCharacters = 8_000
    public nonisolated static let maximumReferencesPerParagraph = 16
}

private nonisolated struct CreativeGenerationEnvelope: Decodable {
    let schemaVersion: Int
    let paragraphs: [CreativeGenerationParagraph]
}

private nonisolated struct CreativeGenerationParagraph: Decodable {
    let text: String
    let sourceMemoryIDs: [UUID]
}

// MARK: - Creative Pipeline

/// 创作管线 — grounded 生成（ADR-009 决策 4 / ADR-013 决策 3）。
///
/// ## Pipeline 契约 (AGENTS.md §4.1)
/// - 审计强制: `generate()` 入口调用 PrivacyActor.validate() (R-006)
/// - 错误分级: 全部 throws 映射 CreativeError (L1~L4)
/// - 无状态: 仅持有不可变引用（LLM provider + aligner + privacy actor）
///
/// ## 数据流
/// ```
/// generate() → PrivacyCheckpoint → 校验源记忆
///   → 构建 grounded prompt（源文本 + 术语表子集 + R-004 语言指令）
///   → LanguageAligner.align (R-004 重试≤1)
///   → 解析段落 + 附加溯源锚点
///   → .synthesis / .creativeGeneration 审计
///   → 返回 CreativeOutput
/// ```
public actor CreativePipeline {

    /// 离线 LLM 推理来源 (ADR-009 决策 4) — nil 表示运行时未落地
    private let llmProvider: (any LLMProvider)?
    /// 语言对齐器 (R-004)
    private let aligner: LanguageAligner
    /// 隐私校验 Actor
    private let privacyActor: PrivacyActor
    /// 领域术语表 (US-SYN-007 AC-1: Prompt 注入术语表子集)
    private let terminology: TerminologyTable

    public init(
        llmProvider: (any LLMProvider)?,
        aligner: LanguageAligner,
        privacyActor: PrivacyActor = .shared,
        terminology: TerminologyTable = .empty
    ) {
        self.llmProvider = llmProvider
        self.aligner = aligner
        self.privacyActor = privacyActor
        self.terminology = terminology
    }

    // MARK: - Public API

    /// 生成 grounded 内容 — 每段附溯源锚点 (US-SYN-002/003)。
    ///
    /// - Parameters:
    ///   - template: 创作模板 (信件/报告/诗歌/时间线)
    ///   - sources: 检索结果源记忆（严格引用, US-SYN-003 AC-2）
    ///   - traceID: 追踪 ID（审计）
    /// - Returns: 含 source anchors 的创作输出
    /// - Throws: `CreativeError` (L1~L4)
    public func generate(
        template: CreativeTemplate,
        sources: [CreativeSource],
        traceID: String
    ) async throws -> CreativeOutput {
        // R-006: PrivacyCheckpoint 入口强制
        let checkpoint = await privacyActor.validate(
            operation: .search,
            traceID: traceID,
            sourceTypes: Array(Set(sources.map { SearchPipeline.normalizeSourceType($0.sourceType) })).sorted()
        )
        guard checkpoint.isAllowed else {
            throw CreativeError.privacyDenied(sourceTypes: checkpoint.sourceTypes)
        }

        // 无 LLM 运行时 → L2 fail-closed (ADR-009 决策 4: 未获批运行时无生成; US-SYN-008 L2 重试)
        guard llmProvider != nil else {
            try? await privacyActor.writeAuditLog(
                eventType: .synthesisFallback,
                traceID: traceID,
                policyVersion: checkpoint.policyVersion,
                success: false,
                sourceType: "creation",
                affectedCount: 0,
                outcome: "runtime-unavailable"
            )
            throw CreativeError.runtimeUnavailable
        }

        // 无匹配源记忆 → 空态 (US-SYN-003 空态)
        guard !sources.isEmpty else {
            let output = CreativeOutput(
                template: template,
                paragraphs: [],
                sourceMemoryCount: 0,
                sourceTypes: [],
                emptyReason: "No source memories matched this template",
                didFallback: false
            )
            try? await privacyActor.writeAuditLog(
                eventType: .synthesis,
                traceID: traceID,
                policyVersion: checkpoint.policyVersion,
                success: true,
                sourceType: "creation",
                affectedCount: 0,
                citationCount: 0,
                noSourceCount: 0
            )
            return output
        }

        // Exact allow-list and unique submitted sources define the only legal citation identities.
        var submittedIDs: Set<UUID> = []
        let submittedSources = sources.filter { submittedIDs.insert($0.memoryID).inserted }
        let submittedSourceTypes = Dictionary(
            uniqueKeysWithValues: submittedSources.map {
                ($0.memoryID, SearchPipeline.normalizeSourceType($0.sourceType))
            }
        )
        let groundedPrompt = buildGroundedPrompt(template: template, sources: submittedSources)

        do {
            let generated = try await aligner.align(prompt: groundedPrompt, traceID: traceID)
            let paragraphs = try parseParagraphs(
                from: generated,
                allowedMemoryIDs: submittedIDs,
                sourceTypes: submittedSourceTypes
            )
            let output = CreativeOutput(
                template: template,
                paragraphs: paragraphs,
                sourceMemoryCount: submittedSources.count,
                sourceTypes: Array(Set(submittedSourceTypes.values)).sorted(),
                didFallback: false
            )

            try? await privacyActor.writeAuditLog(
                eventType: .synthesis,
                traceID: traceID,
                policyVersion: checkpoint.policyVersion,
                success: true,
                sourceType: "creation",
                affectedCount: submittedSources.count,
                citationCount: output.citationCount,
                noSourceCount: output.noSourceCount
            )
            try? await privacyActor.writeAuditLog(
                eventType: .creativeGeneration,
                traceID: traceID,
                policyVersion: checkpoint.policyVersion,
                success: true,
                sourceType: "creation",
                affectedCount: submittedSources.count,
                templateType: template.rawValue,
                sourceMemoryCount: submittedSources.count,
                citationCount: output.citationCount,
                noSourceCount: output.noSourceCount
            )
            return output
        } catch let error as CreativeError {
            // Invalid/unknown/oversized structured output must never be displayed or fabricated.
            try? await privacyActor.writeAuditLog(
                eventType: .synthesisFallback,
                traceID: traceID,
                policyVersion: checkpoint.policyVersion,
                success: false,
                sourceType: "creation",
                affectedCount: submittedSources.count,
                outcome: error.errorDescription
            )
            throw error
        } catch {
            // 对齐失败 → 失败降级模板 (US-SYN-008) — 模板内容固定，不含 LLM 生成成分
            try? await privacyActor.writeAuditLog(
                eventType: .synthesisFallback,
                traceID: traceID,
                policyVersion: checkpoint.policyVersion,
                success: false,
                sourceType: "creation",
                affectedCount: submittedSources.count,
                outcome: "generation-or-language-alignment-failed"
            )
            let fallbackOutput = CreativeOutput(
                template: template,
                paragraphs: [
                    GroundedParagraph(
                        id: UUID(),
                        text: alignerFallbackText(),
                        anchors: [],
                        groundingStatus: .noSource
                    ),
                ],
                sourceMemoryCount: submittedSources.count,
                sourceTypes: Array(Set(submittedSourceTypes.values)).sorted(),
                didFallback: true
            )
            return fallbackOutput
        }
    }

    // MARK: - Private Helpers

    /// 构建 grounded prompt — 源文本摘要 + 术语表子集 (US-SYN-007 AC-1)。
    private func buildGroundedPrompt(template: CreativeTemplate, sources: [CreativeSource]) -> String {
        var lines: [String] = ["Generate a \(template.rawValue) grounded strictly in the source memories below."]
        lines.append("Each statement MUST reference its source memory. Do not invent facts.")

        if !terminology.isEmpty {
            let termLines = terminology.entries.keys.sorted().map { key in
                let entry = terminology.entries[key] ?? [:]
                let zh = entry["zh-Hans"] ?? ""
                let en = entry["en-US"] ?? ""
                return "\(key): \(zh) / \(en)"
            }
            lines.append("Use these product terms verbatim:")
            lines.append(contentsOf: termLines)
        }

        for source in sources {
            let text = source.text ?? "[no text — \(source.sourceType)]"
            lines.append("MemoryID \(source.memoryID.uuidString): \(text)")
        }

        lines.append("Return JSON only using this exact shape:")
        lines.append(#"{"schemaVersion":1,"paragraphs":[{"text":"...","sourceMemoryIDs":["opaque-memory-uuid"]}]}"#)
        lines.append("Use only MemoryIDs listed above. Use an empty sourceMemoryIDs array when no source supports a paragraph.")
        return lines.joined(separator: "\n")
    }

    private func parseParagraphs(
        from generated: String,
        allowedMemoryIDs: Set<UUID>,
        sourceTypes: [UUID: String]
    ) throws -> [GroundedParagraph] {
        let data = Data(generated.utf8)
        guard data.count <= CreativeGenerationLimits.maximumPayloadBytes else {
            throw CreativeError.invalidStructuredOutput(.oversizedPayload)
        }
        let envelope: CreativeGenerationEnvelope
        do {
            envelope = try JSONDecoder().decode(CreativeGenerationEnvelope.self, from: data)
        } catch {
            throw CreativeError.invalidStructuredOutput(.malformedEnvelope)
        }
        guard envelope.schemaVersion == 1 else {
            throw CreativeError.invalidStructuredOutput(.unsupportedSchemaVersion)
        }
        guard envelope.paragraphs.count <= CreativeGenerationLimits.maximumParagraphs else {
            throw CreativeError.invalidStructuredOutput(.tooManyParagraphs)
        }

        return try envelope.paragraphs.enumerated().map { index, paragraph in
            let text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw CreativeError.invalidStructuredOutput(.emptyParagraph)
            }
            guard text.count <= CreativeGenerationLimits.maximumParagraphCharacters else {
                throw CreativeError.invalidStructuredOutput(.paragraphTooLong)
            }
            guard paragraph.sourceMemoryIDs.count <= CreativeGenerationLimits.maximumReferencesPerParagraph else {
                throw CreativeError.invalidStructuredOutput(.tooManyReferences)
            }

            var seen: Set<UUID> = []
            let declaredIDs = paragraph.sourceMemoryIDs.filter { seen.insert($0).inserted }
            let validIDs = declaredIDs.filter(allowedMemoryIDs.contains)
            let status: GroundingStatus
            if declaredIDs.isEmpty || validIDs.isEmpty {
                status = .noSource
            } else if validIDs.count == declaredIDs.count {
                status = .cited
            } else {
                status = .partialNoSource
            }
            return GroundedParagraph(
                id: Self.stableParagraphID(index: index, text: text),
                text: text,
                anchors: validIDs.map {
                    SourceAnchor(memoryID: $0, sourceType: sourceTypes[$0])
                },
                groundingStatus: status
            )
        }
    }

    private nonisolated static func stableParagraphID(index: Int, text: String) -> UUID {
        let bytes = Array(AuditContentHasher.sha256Hex("\(index):\(text)").utf8.prefix(32))
        let string = String(decoding: bytes, as: UTF8.self)
        let formatted = "\(string.prefix(8))-\(string.dropFirst(8).prefix(4))-\(string.dropFirst(12).prefix(4))-\(string.dropFirst(16).prefix(4))-\(string.dropFirst(20).prefix(12))"
        return UUID(uuidString: formatted) ?? UUID()
    }

    /// 对齐失败降级模板文本 (US-SYN-008 AC-3: 模板内容固定，不含 LLM 生成成分)。
    private func alignerFallbackText() -> String {
        "Unable to generate this creation right now. Please try again later."
    }

}
