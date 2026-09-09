// ==========================================
// 文件: LanguageAligner.swift
// 对应规格: docs/decisions/ADR-009-offline-model-runtime.md → 决策 4 (LanguageAligner, R-004)
//            AGENTS.md §1.3 (§6.2 语言检测契约: 置信度 ≥0.9, 重试 ≤1)
// 任务: 3F.3 - E5、SigLIP2、Whisper 与离线生成决策落地
// AC 覆盖: AI 输出语言仅限 zh-Hans/en-US (R-004)、响应匹配 UserPolicy.preferredLanguage、
//          重试上限 1 次、降级模板跟随 preferredLanguage
// 架构约束: AGENTS.md §4.2 (Actor 隔离), R-004/R-005
// 重要: 项目 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor，所有 struct stored/computed 需 nonisolated
// 生成时间: 2026-08-06
// Task 4.0k (2026-09-08): schema-first body validation and at most one source-revalidated language retry.
// Traceability: US-SYN-001/004 and ADR-023; device/quality qualification remains pending.
// ==========================================

import Foundation
import NaturalLanguage

// MARK: - Language Alignment

/// 语言对齐器（ADR-009 决策 4）— 保证 AI 输出语言匹配 `UserPolicy.preferredLanguage`。
///
/// ## 契约（AGENTS.md §6.2）
/// - 仅输出 `zh-Hans` / `en-US`
/// - 使用 NLTagger 检测输出语言，置信度阈值 ≥ 0.9
/// - 重试上限：严格 1 次
/// - 重试仍不匹配 → 降级模板（跟随 preferredLanguage）
///
/// ## 设计
/// - `LLMProvider` 抽象推理来源（离线捆绑 LLM 运行时，随 3F.9 落地）
/// - 无 LLM 提供方时 `align` 直接判定无输出（不伪造生成）
public actor LanguageAligner {
    // MARK: - Constants

    /// NLTagger 置信度阈值（AGENTS.md §6.2）
    nonisolated private static let confidenceThreshold = 0.9
    /// 最大重试次数（严格 1 次）
    nonisolated private static let maxRetries = 1

    /// zh-Hans 语言码
    nonisolated public static let zhHans = "zh-Hans"
    /// en-US 语言码
    nonisolated public static let enUS = "en-US"

    // MARK: - Dependencies

    private let llmProvider: (any LLMProvider)?
    private let preferredLanguage: String

    // MARK: - Initialization

    /// 创建语言对齐器。
    ///
    /// - Parameters:
    ///   - llmProvider: 离线 LLM 推理来源（nil 表示运行时尚未落地）
    ///   - preferredLanguage: `UserPolicy.preferredLanguage`（zh-Hans/en-US）
    public init(
        llmProvider: (any LLMProvider)?,
        preferredLanguage: String = LanguageAligner.enUS
    ) {
        self.llmProvider = llmProvider
        self.preferredLanguage = preferredLanguage
    }

    // MARK: - Public API

    /// 生成并校准为 preferredLanguage 的文本。
    ///
    /// - Parameters:
    ///   - prompt: 生成提示（含 R-004 语言指令）
    ///   - traceID: 追踪 ID（审计）
    /// - Returns: 对齐后的输出文本
    /// - Throws: `LanguageAlignerError` 若无 LLM 提供方、超出重试上限或检测失败
    public func align(prompt: String, traceID: String = UUID().uuidString) async throws -> String {
        guard let provider = llmProvider else {
            throw LanguageAlignerError.runtimeUnavailable
        }

        var lastDetected = ""
        for attempt in 0...Self.maxRetries {
            let output = try await provider.generate(
                prompt: Self.injectedPrompt(base: prompt, preferredLanguage: preferredLanguage),
                preferredLanguage: preferredLanguage
            )
            lastDetected = Self.detectLanguage(output)
            if Self.isSupported(lastDetected) && lastDetected == preferredLanguage {
                return output
            }
            if attempt < Self.maxRetries {
                // R-004: 语言不符 → 重试（注入更严格指令），最多 1 次
                continue
            }
        }
        // 重试仍不匹配 → 降级模板
        return Self.fallbackTemplate(preferredLanguage: preferredLanguage)
    }

    // MARK: - Language Detection

    /// US-SYN-001 AC-4/5 (4.0k): schema first, body-only screening, no repair loop.
    public func alignEnvelope(
        request: GenerationRequest,
        sourceValidation: GenerationSourceValidation? = nil
    ) async throws -> AlignedGeneration {
        guard let provider = llmProvider else { throw LanguageAlignerError.runtimeUnavailable }
        guard Self.isSupported(request.preferredLanguage) else { throw GenerationRuntimeError.invalidRequest }
        for attempt in 0...Self.maxRetries {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < request.executionDeadline else {
                throw GenerationRuntimeError.deadline
            }
            let current = attempt == 0 ? request : request.languageRetry()
            try await sourceValidation?.validate()
            let raw: String
            if let structured = provider as? any StructuredLLMProvider {
                raw = try await structured.generate(request: current).envelope
            } else {
                raw = try await provider.generate(
                    prompt: current.system + "\n" + current.user,
                    preferredLanguage: current.preferredLanguage
                )
            }
            try await sourceValidation?.validate()
            guard raw.utf8.count <= 65_536 else { throw CreativeError.invalidStructuredOutput(.oversizedPayload) }
            let paragraphs = try CreativePipeline.parseParagraphs(
                from: raw,
                allowedMemoryIDs: Set(request.allowedMemoryIDs),
                sourceTypes: [:]
            )
            guard !paragraphs.isEmpty else { throw CreativeError.invalidStructuredOutput(.emptyParagraph) }
            if paragraphs.allSatisfy({ Self.bodyMatches($0.text, language: request.preferredLanguage) }) {
                return AlignedGeneration(
                    paragraphs: paragraphs,
                    languageRetryCount: attempt,
                    modelCallCount: attempt + 1
                )
            }
        }
        throw GenerationRuntimeError.languageFallback
    }

    nonisolated static func bodyMatches(_ text: String, language: String) -> Bool {
        // Remove only protocol-shaped UUID metadata. Names/quotes remain in the sample.
        let sample = text.replacingOccurrences(
            of: #"(?i)(?<![\w-])[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}(?![\w-])"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard sample.unicodeScalars.contains(where: CharacterSet.letters.contains),
            detectLanguage(sample) == language
        else { return false }
        if language == zhHans {
            guard let simplified = sample.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false),
                simplified == sample
            else { return false }
        }
        return true
    }

    /// 检测文本语言，返回 zh-Hans / en-US / uncertain。
    ///
    /// 使用 `NLLanguageRecognizer`，置信度 ≥ 0.9 才认定；否则 `.uncertain`。
    /// 繁体/方言映射为 zh-Hans（AGENTS.md §1.3）。
    nonisolated static func detectLanguage(_ text: String) -> String {
        guard !text.isEmpty else { return "uncertain" }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage,
            let confidence = recognizer.languageHypotheses(withMaximum: 1)[language],
            confidence >= confidenceThreshold
        else {
            return "uncertain"
        }
        let raw = language.rawValue.lowercased()
        if raw.hasPrefix("zh") { return zhHans }
        if raw.hasPrefix("en") { return enUS }
        return "uncertain"
    }

    /// 是否支持该语言（仅 zh-Hans/en-US）。
    nonisolated static func isSupported(_ language: String) -> Bool {
        language == zhHans || language == enUS
    }

    // MARK: - Prompt / Fallback

    /// 注入 R-004 语言指令。
    nonisolated static func injectedPrompt(base: String, preferredLanguage: String) -> String {
        "You MUST respond in \(preferredLanguage).\n\(base)"
    }

    /// 降级模板（跟随 preferredLanguage）— String Catalog backed (DEF-52-001, 3F.10):
    /// AGENTS.md §6.4 requires degradation prompts to resolve from the catalog.
    nonisolated static func fallbackTemplate(preferredLanguage: String) -> String {
        EchoLocalization.localized(
            "Unable to generate a response in your language. Please try again later.",
            locale: Locale(identifier: preferredLanguage)
        )
    }
}

// MARK: - LLM Provider

/// 离线 LLM 推理来源（ADR-009 决策 4，3F.9 落地捆绑运行时）。
nonisolated public protocol LLMProvider: Sendable {
    /// 生成文本。
    ///
    /// - Parameters:
    ///   - prompt: 含 R-004 语言指令的提示
    ///   - preferredLanguage: 目标语言
    /// - Returns: 生成的原始输出（未校准语言）
    func generate(prompt: String, preferredLanguage: String) async throws -> String
}

// MARK: - Error

/// 语言对齐器错误。
public enum LanguageAlignerError: Error, LocalizedError, Sendable {
    /// 无 LLM 提供方（离线运行时未落地）
    case runtimeUnavailable

    nonisolated public var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            return "Offline LLM runtime not available"
        }
    }
}
