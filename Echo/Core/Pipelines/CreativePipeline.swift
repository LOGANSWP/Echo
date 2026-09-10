// ==========================================
// 文件: CreativePipeline.swift
// 对应规格: docs/decisions/ADR-009-offline-model-runtime.md → 决策 4 (grounded creation),
//            docs/decisions/ADR-013-creation-export-boundary.md → 决策 3 (grounded 生成 + source anchors),
//            docs/01-spec/用户故事与验收标准规格书.md → US-SYN-002 (溯源锚点), US-SYN-003 (grounded 生成),
//            US-SYN-007 (术语表注入), US-SYN-008 (合成失败模板降级)
// 任务: 3F.9 + 4.0a + 4.0i - Grounded creation and verifiable citations
// AC coverage: 4.0k source-read and pre-render aggregate limits (PR #79);
// AC 覆盖: US-SYN-002 AC-1/3 ✅ (多锚点/NoSource/partialNoSource), AC-5 ✅ (.synthesis 审计),
//          US-SYN-003 AC-2 ✅ (版本化 JSON + exact allow-list), AC-6 ✅ (.creativeGeneration typed 审计),
//          US-SYN-007 AC-1 ✅ (Prompt 注入术语表子集), US-SYN-008 AC-1/5 ✅ (失败模板降级 + .synthesisFallback 审计),
//          US-PRV-001 AC-7 ✅ (按真实 sourceType 授权，不使用 search 伪来源),
//          R-004 ✅ (LanguageAligner 语言对齐)
// 架构约束: AGENTS.md §4.1 (Pipeline 契约: 审计强制 / 错误分级 / 纯函数), R-006 (PrivacyCheckpoint 入口),
//           §4.2 (仅持有不可变引用); actor 声明合法 (v5.12)
// 生成时间: 2026-08-11 | Updated: 2026-09-07 (4.0i, ADR-020)
// Task 4.0k (2026-09-08): canonical source snapshots, structured language alignment and real prompt budgets.
// Traceability: US-SYN-001/004 and ADR-023; device/quality qualification remains pending.
// US-SYN-003 AC-1: reject prose as a poem before publishing success; preserve model-authored verse.
// ==========================================

import Foundation

// MARK: - Grounded Creation Types

/// 创作模板类型 (US-SYN-003 AC-1: 信件/报告/诗歌/时间线)。
public enum CreativeTemplate: String, Sendable, Equatable, Codable {
    case letter
    case report
    case poem
    case timeline
}

/// grounded 创作源记忆 — 检索结果输入 (US-SYN-003 AC-2 严格引用检索结果)。
nonisolated public struct CreativeSource: Sendable, Equatable {
    /// 源记忆 ID
    nonisolated public let memoryID: UUID
    /// 数据源引用 (PHAsset.localIdentifier / note 定位符)
    nonisolated public let assetID: String
    /// 数据源类型 ("photo" / "note" / "voice" / "video_frame" 等)
    nonisolated public let sourceType: String
    /// 源文本 (nil = 图片/视频帧无文本)
    nonisolated public let text: String?
    /// 记忆时间戳
    nonisolated public let timestamp: TimeInterval
    nonisolated public let revision: TimeInterval?
    /// Current caption or nonblank user description, resolved by storage.
    nonisolated public let photoCreationReady: Bool

    nonisolated public init(
        memoryID: UUID,
        assetID: String,
        sourceType: String,
        text: String?,
        timestamp: TimeInterval,
        revision: TimeInterval? = nil,
        photoCreationReady: Bool = false
    ) {
        self.memoryID = memoryID
        self.assetID = assetID
        self.sourceType = sourceType
        self.text = text
        self.timestamp = timestamp
        self.revision = revision
        self.photoCreationReady = photoCreationReady
    }
}

/// 溯源锚点 — `[🔗 MemoryID:xxx]` (US-SYN-002 AC-1)。
nonisolated public struct SourceAnchor: Sendable, Equatable, Codable {
    /// 源记忆 ID
    nonisolated public let memoryID: UUID
    /// Canonical source type is carried internally for current-policy revalidation.
    nonisolated public let sourceType: String?
    /// Refreshed at the copy/export/navigation boundary; never inferred from model output.
    nonisolated public let availability: CitationSourceAvailability

    nonisolated public init(
        memoryID: UUID,
        sourceType: String? = nil,
        availability: CitationSourceAvailability = .available
    ) {
        self.memoryID = memoryID
        self.sourceType = sourceType
        self.availability = availability
    }
}

nonisolated public enum CitationSourceAvailability: String, Sendable, Codable, Equatable {
    case available
    case offlineUnavailable
    case missing
    case unsupported
}

/// Provenance state for one generated paragraph. This proves source identity, not factual accuracy.
nonisolated public enum GroundingStatus: String, Sendable, Codable, Equatable {
    case cited
    case noSource
    case partialNoSource
}

/// grounded 生成段落 — AI 生成文本 + 溯源锚点 (US-SYN-002/003 AC-2)。
nonisolated public struct GroundedParagraph: Sendable, Equatable, Identifiable, Codable {
    /// 段落唯一标识（确定性）
    nonisolated public let id: UUID
    /// 段落文本
    nonisolated public let text: String
    /// All validated source anchors in model-declared order, deduplicated within the paragraph.
    nonisolated public let anchors: [SourceAnchor]
    /// Whether every, none, or only part of the model-declared references passed the allow-list.
    nonisolated public let groundingStatus: GroundingStatus

    nonisolated public init(
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
nonisolated public struct CreativeOutput: Sendable, Equatable, Codable {
    /// 选中的创作模板
    nonisolated public let template: CreativeTemplate
    /// 结果标题（叙事报告含周期, US-SYN-004 AC-5）
    nonisolated public let title: String?
    /// 报告周期（US-SYN-004: 月/年）
    nonisolated public let periodType: String?
    /// 生成段落（含溯源锚点）
    nonisolated public let paragraphs: [GroundedParagraph]
    /// 引用的源记忆数
    nonisolated public let sourceMemoryCount: Int
    /// Canonical source types actually submitted to the model, retained for action-time policy checks.
    nonisolated public let sourceTypes: [String]
    /// 空态原因（无匹配源记忆时非 nil → empty state）
    nonisolated public let emptyReason: String?
    /// 合成是否走了失败降级模板 (US-SYN-008)
    nonisolated public let didFallback: Bool
    /// Count of validated anchor occurrences; duplicate IDs within one paragraph count once.
    nonisolated public var citationCount: Int {
        paragraphs.reduce(0) { $0 + $1.anchors.count }
    }
    /// Paragraphs carrying either noSource or partialNoSource.
    nonisolated public var noSourceCount: Int {
        paragraphs.count { $0.groundingStatus != .cited }
    }

    nonisolated public init(
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

    nonisolated public var errorDescription: String? {
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

nonisolated public enum CreativeProtocolFailure: String, Sendable, Equatable {
    case oversizedPayload
    case malformedEnvelope
    case unsupportedSchemaVersion
    case tooManyParagraphs
    case emptyParagraph
    case paragraphTooLong
    case tooManyReferences
    case templateMismatch
}

/// Named limits make the local generation boundary deterministic and reviewable.
nonisolated public enum CreativeGenerationLimits {
    nonisolated public static let maximumPayloadBytes = 262_144
    nonisolated public static let maximumParagraphs = 64
    nonisolated public static let maximumParagraphCharacters = 8_000
    nonisolated public static let maximumReferencesPerParagraph = 16
    nonisolated public static let poemLineRange = 3...6
    nonisolated public static let targetPoemLineCount = 4
}

nonisolated private struct CreativeGenerationEnvelope: Decodable {
    let schemaVersion: Int
    let paragraphs: [CreativeGenerationParagraph]
}

nonisolated private struct CreativeGenerationParagraph: Decodable {
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
    private let canonicalRepository: CanonicalMemoryRepositoryActor?

    public init(
        llmProvider: (any LLMProvider)?,
        aligner: LanguageAligner,
        privacyActor: PrivacyActor = .shared,
        terminology: TerminologyTable = .empty,
        canonicalRepository: CanonicalMemoryRepositoryActor? = nil
    ) {
        self.llmProvider = llmProvider
        self.aligner = aligner
        self.privacyActor = privacyActor
        self.terminology = terminology
        self.canonicalRepository = canonicalRepository
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
        guard Set(sources.map(\.memoryID)).count <= GenerationInputBudget.maximumSources else {
            throw GenerationRuntimeError.contextLimit
        }
        var submittedIDs: Set<UUID> = []
        let uniqueSources = sources.filter { submittedIDs.insert($0.memoryID).inserted }
        var currentSources = uniqueSources
        if let canonicalRepository {
            currentSources = []
            var remaining = GenerationInputBudget.maximumBytes
            for source in uniqueSources {
                guard let current = try await canonicalRepository.loadCreationSource(
                    memoryID: source.memoryID, maximumTextBytes: remaining
                ) else {
                    throw GenerationRuntimeError.privacyDenied
                }
                guard current.sourceType != "photo" || current.photoCreationReady else {
                    throw CreativeError.noSources
                }
                try GenerationInputBudget.consume(current.text ?? "", remaining: &remaining)
                currentSources.append(current)
            }
        }
        let submittedSources = currentSources
        try GenerationInputBudget.validate(submittedSources.map {
            GenerationPassage(text: $0.text ?? "", sourceMemoryIDs: [$0.memoryID])
        })
        guard submittedSources.allSatisfy({ !($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw CreativeError.noSources
        }
        let submittedSourceTypes = Dictionary(
            uniqueKeysWithValues: submittedSources.map {
                ($0.memoryID, SearchPipeline.normalizeSourceType($0.sourceType))
            }
        )
        do {
            let aligned = try await generatePassages(
                template: template,
                passages: submittedSources.map {
                    GenerationPassage(text: $0.text ?? "", sourceMemoryIDs: [$0.memoryID])
                },
                sourceTypes: submittedSourceTypes,
                traceID: traceID,
                deadline: ProcessInfo.processInfo.systemUptime + GenerationExecutionScope.manualCreation.requestSeconds,
                sourceSnapshots: submittedSources,
                useEffectiveSourceText: true,
                executionScope: .manualCreation
            )
            let paragraphs = aligned.paragraphs
            if template == .poem {
                let lines = paragraphs.flatMap { $0.text.split(whereSeparator: \.isNewline) }
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                guard CreativeGenerationLimits.poemLineRange.contains(lines.count) else {
                    throw CreativeError.invalidStructuredOutput(.templateMismatch)
                }
            }
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
        } catch is CancellationError {
            throw CancellationError()
        } catch NarrativeReportError.resourceDeferred {
            throw NarrativeReportError.resourceDeferred
        } catch let error as GenerationRuntimeError {
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

    /// 4.0k: absence and configured artifact failure remain distinct before a report claim.
    public func validateAvailability(traceID: String) async throws {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard let llmProvider else { throw CreativeError.runtimeUnavailable }
        if let provider = llmProvider as? any StructuredLLMProvider {
            try await provider.validateAvailability(traceID: traceID)
        }
    }

    public func retryRuntime(traceID: String) async throws {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard let provider = llmProvider as? any StructuredLLMProvider else { throw CreativeError.runtimeUnavailable }
        try await provider.retryAvailability(traceID: traceID)
    }

    public func configurationIdentity(traceID: String) async throws -> String {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(terminology.entries)
        return AuditContentHasher.sha256Hex(data.base64EncodedString())
    }

    public func passagesFit(
        template: CreativeTemplate,
        passages: [GenerationPassage],
        sourceTypes: [UUID: String],
        traceID: String,
        deadline: Double,
        isReduction: Bool = false
    ) async throws -> Bool {
        let checkpoint = await privacyActor.validate(
            operation: .search,
            traceID: traceID,
            sourceTypes: Array(Set(sourceTypes.values)).sorted()
        )
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard let provider = llmProvider as? any StructuredLLMProvider else { return true }
        let policy = await privacyActor.getPolicy()
        let request = try GenerationPrompt.request(
            template: template,
            passages: passages,
            sourceTypes: Array(Set(sourceTypes.values)).sorted(),
            context: .init(
                language: policy.preferredLanguage,
                traceID: traceID,
                deadline: deadline,
                terminology: terminology
            ),
            isReduction: isReduction
        )
        do {
            _ = try await provider.tokenCount(request: request)
            _ = try await provider.tokenCount(request: request.languageRetry())
            return true
        } catch GenerationRuntimeError.contextLimit {
            return false
        } catch GenerationTokenizerError.inputBudget {
            return false
        }
    }

    public func generatePassages(
        template: CreativeTemplate,
        passages: [GenerationPassage],
        sourceTypes: [UUID: String],
        traceID: String,
        deadline: Double,
        isReduction: Bool = false,
        sourceSnapshots: [CreativeSource] = [],
        excerptScalarLimit: Int? = nil,
        useEffectiveSourceText: Bool = false,
        executionScope: GenerationExecutionScope = .standard
    ) async throws -> AlignedGeneration {
        let checkpoint = await privacyActor.validate(
            operation: .search,
            traceID: traceID,
            sourceTypes: Array(Set(sourceTypes.values)).sorted()
        )
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        let actualIDs = Set(passages.flatMap(\.sourceMemoryIDs))
        guard !passages.isEmpty, !actualIDs.isEmpty, actualIDs == Set(sourceTypes.keys),
            passages.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw GenerationRuntimeError.invalidRequest
        }
        let policy = await privacyActor.getPolicy()
        let sourceValidation: GenerationSourceValidation?
        if let canonicalRepository {
            guard Set(sourceSnapshots.map(\.memoryID)) == actualIDs else {
                throw GenerationRuntimeError.invalidRequest
            }
            sourceValidation = GenerationSourceValidation(
                repository: canonicalRepository,
                sources: sourceSnapshots,
                excerptScalarLimit: excerptScalarLimit,
                useEffectiveSourceText: useEffectiveSourceText
            )
        } else {
            sourceValidation = nil
        }
        let request = try GenerationPrompt.request(
            template: template,
            passages: passages,
            sourceTypes: Array(Set(sourceTypes.values)).sorted(),
            context: .init(
                language: policy.preferredLanguage,
                traceID: traceID,
                deadline: deadline,
                terminology: terminology,
                executionScope: executionScope
            ),
            isReduction: isReduction
        )
        let aligned: AlignedGeneration
        do {
            aligned = try await aligner.alignEnvelope(request: request, sourceValidation: sourceValidation)
        } catch GenerationRuntimeError.languageFallback {
            try await privacyActor.writeAuditLog(
                eventType: .generationLanguageChecked,
                traceID: traceID,
                policyVersion: checkpoint.policyVersion,
                success: false,
                uiLanguage: policy.preferredLanguage,
                languageRetryCount: 1
            )
            throw GenerationRuntimeError.languageFallback
        }
        let final = await privacyActor.validate(operation: .search, traceID: traceID, sourceTypes: request.sourceTypes)
        guard final.isAllowed, final.policyVersion == checkpoint.policyVersion else {
            throw GenerationRuntimeError.privacyDenied
        }
        try await privacyActor.writeAuditLog(
            eventType: .generationLanguageChecked,
            traceID: traceID,
            policyVersion: final.policyVersion,
            outputLanguage: policy.preferredLanguage,
            uiLanguage: policy.preferredLanguage,
            languageRetryCount: aligned.languageRetryCount
        )
        return AlignedGeneration(
            paragraphs: aligned.paragraphs.map { paragraph in
                GroundedParagraph(
                    id: paragraph.id,
                    text: paragraph.text,
                    anchors: paragraph.anchors.map {
                        SourceAnchor(memoryID: $0.memoryID, sourceType: sourceTypes[$0.memoryID])
                    },
                    groundingStatus: paragraph.groundingStatus
                )
            },
            languageRetryCount: aligned.languageRetryCount,
            modelCallCount: aligned.modelCallCount
        )
    }

    nonisolated static func parseParagraphs(
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

    nonisolated private static func stableParagraphID(index: Int, text: String) -> UUID {
        let string = String(AuditContentHasher.sha256Hex("\(index):\(text)").prefix(32))
        let formatted =
            "\(string.prefix(8))-\(string.dropFirst(8).prefix(4))-\(string.dropFirst(12).prefix(4))-\(string.dropFirst(16).prefix(4))-\(string.dropFirst(20).prefix(12))"
        return UUID(uuidString: formatted) ?? UUID()
    }

    /// 对齐失败降级模板文本 (US-SYN-008 AC-3: 模板内容固定，不含 LLM 生成成分)。
    private func alignerFallbackText() -> String {
        "Unable to generate this creation right now. Please try again later."
    }
}
