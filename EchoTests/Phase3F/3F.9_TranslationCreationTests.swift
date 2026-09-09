// ==========================================
// 文件: 3F.9_TranslationCreationTests.swift
// 对应规格: docs/01-spec/用户故事与验收标准规格书.md → US-DIS-002 (按需翻译),
//            US-SYN-001~008 (grounded creation), docs/decisions/ADR-013 (创作/导出边界),
//            docs/03-implementation/双语言实现说明文档.md §6.2 (术语表优先)
// 任务: 3F.9 - Apple Translation 与 grounded creation
// AC 覆盖: US-DIS-002 AC-1/2/3/4/5 (按需翻译 + 七天持久缓存 + availability),
//          US-SYN-002 (溯源锚点), US-SYN-003 AC-2/3 (grounded 生成 + 导出),
//          US-SYN-007 AC-3 (术语表优先), US-SYN-008 (合成失败模板降级),
//          ADR-013 (系统 share 导出, 无 notes:// 深链)
// 架构约束: AGENTS.md §4.2 (Actor 隔离), §5.4 (hash-only 审计), §9.4 (串行执行),
//           R-004/R-005 (语言受限 + 零网络); 展示层翻译禁止注入管线中间阶段
// 重要: TDD — AppleTranslationService / PersistentTranslationCache / TerminologyTable /
//             CreativePipeline / CreationExportService 均为本任务新实现。
// 生成时间: 2026-08-11
// ==========================================

import Testing
import Foundation
import NaturalLanguage
import os
@testable import Echo

// MARK: - TranslationCreationTests (3F.9 聚焦套件)

@Suite("TranslationCreationTests", .serialized)
@MainActor
struct TranslationCreationTests {

    // MARK: - TerminologyTable (US-SYN-007 AC-3)

    @Suite("TerminologyTable", .serialized)
    @MainActor
    struct TerminologyTableTests {

        private static let sampleJSON = """
        {
          "memory": { "zh-Hans": "记忆", "en-US": "Memory" },
          "awakening": { "zh-Hans": "唤醒", "en-US": "Awakening" }
        }
        """

        @Test("US-SYN-007 AC-3: decodes term table from JSON with zh/en entries")
        func decodesFromJSON() throws {
            let table = try TerminologyTable(jsonData: Data(Self.sampleJSON.utf8))
            #expect(table.resolve("memory", to: "en-US") == "Memory")
            #expect(table.resolve("memory", to: "zh-Hans") == "记忆")
        }

        @Test("US-SYN-007 AC-3: unknown term returns nil (fallback to Apple Translation)")
        func unknownTermReturnsNil() throws {
            let table = try TerminologyTable(jsonData: Data(Self.sampleJSON.utf8))
            #expect(table.resolve("nonexistent", to: "en-US") == nil)
        }

        @Test("US-SYN-007 AC-3: unsupported language returns nil")
        func unsupportedLanguageReturnsNil() throws {
            let table = try TerminologyTable(jsonData: Data(Self.sampleJSON.utf8))
            #expect(table.resolve("memory", to: "fr-FR") == nil)
        }

        @Test("empty table resolves nothing")
        func emptyTable() {
            let table = TerminologyTable.empty
            #expect(table.resolve("memory", to: "en-US") == nil)
        }
    }

    // MARK: - AppleTranslationService (US-DIS-002, ADR-013, ADR-005)

    @Suite("AppleTranslationService", .serialized)
    @MainActor
    struct AppleTranslationServiceTests {

        /// Stub availability provider — 确定性注入，不依赖真机语言包。
        private struct StubAvailability: TranslationAvailabilityProviding {
            let status: TranslationAvailabilityStatus
            func status(from source: String, to target: String) async -> TranslationAvailabilityStatus { status }
        }

        /// Stub executor — 确定性译文，验证 delegate 调用与结果传递。
        private struct StubExecutor: TranslationExecuting {
            let output: String
            func translate(_ text: String, from source: String, to target: String) async throws -> String { output }
        }

        private func makeService(
            availability: TranslationAvailabilityStatus = .installed,
            executor: String = "translated",
            terminology: TerminologyTable? = nil
        ) -> AppleTranslationService {
            AppleTranslationService(
                availability: StubAvailability(status: availability),
                executor: StubExecutor(output: executor),
                terminology: terminology ?? .empty
            )
        }

        @Test("US-DIS-002 ADR-013: unsupported language pair throws before translation")
        func unsupportedPairThrows() async {
            let service = makeService(availability: .unsupported)
            await #expect(throws: TranslationError.unsupportedLanguage("en-US")) {
                _ = try await service.translate("你好", from: "zh-Hans", to: "en-US")
            }
        }

        @Test("US-DIS-002 AC-2: supported pair delegates to executor and returns translated text")
        func supportedPairTranslates() async throws {
            let service = makeService(executor: "Hello")
            let result = try await service.translate("你好", from: "zh-Hans", to: "en-US")
            #expect(result.translatedText == "Hello")
        }

        @Test("US-DIS-002 AC-3 ADR-005: never fabricates confidence — NLTagger confidence reflects detection")
        func confidenceNeverFabricated() async throws {
            let service = makeService()
            // 中文文本 → 置信度来自 NLTagger 检测（确定性，不编造），且 ≤ 1.0
            let zh = try await service.translate("你好世界", from: "zh-Hans", to: "en-US")
            #expect(zh.sourceLanguageConfidence >= 0.0)
            #expect(zh.sourceLanguageConfidence <= 1.0)
            // 与独立 NLTagger 检测结果一致（证明置信度源自检测而非编造）
            let recognizer = NLLanguageRecognizer()
            recognizer.processString("你好世界")
            let expected = recognizer.languageHypotheses(withMaximum: 1).first?.value ?? 0
            #expect(abs(zh.sourceLanguageConfidence - expected) < 0.001)

            // 空/极短文本 → 检测不确定 (<0.9)，保留原文由 View 层处理
            let short = try await service.translate("a", from: "zh-Hans", to: "en-US")
            #expect(short.sourceLanguageConfidence < 0.9)
        }

        @Test("US-SYN-007 AC-3: terminology precedence — term hit skips executor")
        func terminologyTakesPrecedence() async throws {
            let table = try TerminologyTable(jsonData: Data(#"{"memory": {"zh-Hans": "记忆", "en-US": "Memory"}}"#.utf8))
            let service = makeService(terminology: table)
            let result = try await service.translate("memory", from: "en-US", to: "zh-Hans")
            #expect(result.translatedText == "记忆")
        }
    }

    // MARK: - PersistentTranslationCache (US-DIS-002 AC-5, ADR-013)

    @Suite("PersistentTranslationCache", .serialized)
    @MainActor
    struct PersistentTranslationCacheTests {

        /// 临时目录 + 确定性时钟 — 每个测试独立，避免共享 SQLite 状态污染 (§9.4)。
        private func makeTempDirectory() throws -> URL {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("ptc-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        private struct MutableClock: Sendable {
            private let lock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000_000))
            init(_ start: Date) { lock.withLock { $0 = start } }
            var now: Date { lock.withLock { $0 } }
            func advance(by interval: TimeInterval) { lock.withLock { $0 = $0.addingTimeInterval(interval) } }
        }

        @Test("US-DIS-002 AC-5: store then lookup within 7d TTL returns entry")
        func lookupWithinTTL() async throws {
            let dir = try makeTempDirectory()
            let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
            let cache = PersistentTranslationCache(directory: dir) { clock.now }

            await cache.store(
                sourceText: "你好",
                sourceLanguage: "zh-Hans",
                targetLanguage: "en-US",
                translatedText: "Hello",
                sourceLanguageConfidence: 0.95
            )
            clock.advance(by: 3 * 24 * 3600)

            let entry = await cache.lookup(key: "zh-Hans|en-US|你好")
            #expect(entry != nil)
            #expect(entry?.translatedText == "Hello")
        }

        @Test("US-DIS-002 AC-5: lookup after TTL (7d) returns nil")
        func lookupAfterTTLReturnsNil() async throws {
            let dir = try makeTempDirectory()
            let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
            let cache = PersistentTranslationCache(directory: dir) { clock.now }

            await cache.store(
                sourceText: "你好",
                sourceLanguage: "zh-Hans",
                targetLanguage: "en-US",
                translatedText: "Hello",
                sourceLanguageConfidence: 0.95
            )
            clock.advance(by: 7 * 24 * 3600 + 1)
            #expect(await cache.lookup(key: "zh-Hans|en-US|你好") == nil)
        }

        @Test("US-DIS-002 AC-5 ADR-013: cache survives relaunch (new instance, same directory)")
        func survivesRelaunch() async throws {
            let dir = try makeTempDirectory()
            let cacheA = PersistentTranslationCache(directory: dir)
            await cacheA.store(
                sourceText: "你好",
                sourceLanguage: "zh-Hans",
                targetLanguage: "en-US",
                translatedText: "Hello",
                sourceLanguageConfidence: 0.95
            )

            // 模拟重启：同目录新实例
            let cacheB = PersistentTranslationCache(directory: dir)
            let entry = await cacheB.lookup(key: "zh-Hans|en-US|你好")
            #expect(entry?.translatedText == "Hello")
        }

        @Test("US-DIS-002 AC-5: persisted file exists on disk after store")
        func filePersistedOnDisk() async throws {
            let dir = try makeTempDirectory()
            let cache = PersistentTranslationCache(directory: dir)
            await cache.store(
                sourceText: "你好",
                sourceLanguage: "zh-Hans",
                targetLanguage: "en-US",
                translatedText: "Hello",
                sourceLanguageConfidence: 0.95
            )
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            #expect(files.contains { $0.lastPathComponent.hasSuffix(".json") } == true)
        }
    }

    // MARK: - CreativePipeline (US-SYN-002/003, ADR-009/013)

    @Suite("CreativePipeline", .serialized)
    @MainActor
    struct CreativePipelineTests {

        /// Stub LLMProvider — 确定性 grounded 生成输出。
        private struct StubLLMProvider: LLMProvider {
            let output: String
            func generate(prompt: String, preferredLanguage: String) async throws -> String { output }
        }

        /// Test setup authorizes the real source types consumed by creation.
        /// 与 SearchPipelineTests init() 同模式（§9.4 串行执行共享单例）。
        init() async throws {
            try await DatabaseManager.shared.open()
            try await DatabaseManager.shared.execute(sql: "DELETE FROM AuditLog")
            try await PrivacyActor.shared.updatePolicy(UserPolicy(
                preferredLanguage: "en-US",
                authorizedSourceTypes: ["photo", "note", "voice", "text"],
                policyVersion: 1
            ))
        }

        private func makePipeline(output: String) async throws -> CreativePipeline {
            let provider = StubLLMProvider(output: output)
            return CreativePipeline(
                llmProvider: provider,
                aligner: LanguageAligner(llmProvider: provider, preferredLanguage: "en-US")
            )
        }

        private func sampleSources() -> [CreativeSource] {
            [
                CreativeSource(
                    memoryID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    assetID: "note-zh-1",
                    sourceType: "note",
                    text: "昨晚在公园遇到一只橘猫。",
                    timestamp: 1_723_420_800
                ),
                CreativeSource(
                    memoryID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    assetID: "note-zh-2",
                    sourceType: "note",
                    text: "今天在公园散步。",
                    timestamp: 1_723_680_000
                ),
            ]
        }

        @Test("US-SYN-003 AC-2: grounded generation attaches source anchors to output")
        func groundedOutputHasAnchors() async throws {
            let pipeline = try await makePipeline(output: #"{"schemaVersion":1,"paragraphs":[{"text":"You loved walking in the park with a small cat.","sourceMemoryIDs":["22222222-2222-2222-2222-222222222222"]},{"text":"You also enjoyed quiet mornings.","sourceMemoryIDs":["33333333-3333-3333-3333-333333333333"]}]}"#)
            let output = try await pipeline.generate(
                template: .letter,
                sources: sampleSources(),
                traceID: "test-trace"
            )
            #expect(output.paragraphs.count == 2)
            #expect(output.paragraphs.allSatisfy { !$0.anchors.isEmpty } == true)
            #expect(output.sourceMemoryCount == 2)
            #expect(output.paragraphs[0].anchors.first?.memoryID == UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        }

        @Test("US-SYN-003: empty sources produce empty output with reason")
        func emptySourcesProduceEmpty() async throws {
            let pipeline = try await makePipeline(output: "anything")
            let output = try await pipeline.generate(template: .letter, sources: [], traceID: "test-trace")
            #expect(output.emptyReason != nil)
            #expect(output.paragraphs.isEmpty)
        }

        @Test("US-PRV-001 AC-7: generation checks real sources instead of a search pseudo-source")
        func generationChecksRealSourceAuthorization() async throws {
            try await PrivacyActor.shared.updatePolicy(UserPolicy(
                preferredLanguage: "en-US",
                authorizedSourceTypes: ["photo"],
                policyVersion: 1
            ))
            let pipeline = try await makePipeline(output: "anything")

            await #expect(throws: CreativeError.self) {
                _ = try await pipeline.generate(
                    template: .letter,
                    sources: sampleSources(),
                    traceID: "test-real-source-policy"
                )
            }
        }

        @Test("US-SYN-008: runtime unavailable (no LLM provider) fails closed with L2/L3 error")
        func noProviderFailsClosed() async {
            let pipeline = CreativePipeline(llmProvider: nil, aligner: LanguageAligner(llmProvider: nil, preferredLanguage: "en-US"))
            await #expect(throws: CreativeError.runtimeUnavailable) {
                _ = try await pipeline.generate(template: .letter, sources: [], traceID: "test-trace")
            }
        }
    }

    // MARK: - CreationExportService (US-SYN-003 AC-3, ADR-013)

    @Suite("CreationExportService", .serialized)
    @MainActor
    struct CreationExportServiceTests {

        private func sampleOutput() -> CreativeOutput {
            CreativeOutput(
                template: .letter,
                title: "A letter to your future self",
                periodType: nil,
                paragraphs: [
                    GroundedParagraph(
                        id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
                        text: "You loved walking in the park.",
                        anchors: [
                            SourceAnchor(memoryID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!),
                        ],
                        groundingStatus: .cited
                    ),
                    GroundedParagraph(
                        id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
                        text: "You enjoyed quiet mornings.",
                        anchors: [],
                        groundingStatus: .noSource
                    ),
                ],
                sourceMemoryCount: 2,
                emptyReason: nil
            )
        }

        @Test("US-SYN-003 AC-3: markdown includes title and body without internal source markers")
        func markdownContainsCleanText() {
            let md = CreationExportService.markdown(from: sampleOutput())
            #expect(md.contains("A letter to your future self"))
            #expect(!md.contains("MemoryID:22222222"))
            #expect(md.contains("You loved walking in the park."))
            #expect(md.contains("NoSource") == false)
            #expect(md.contains("You enjoyed quiet mornings."))
        }

        @Test("US-SYN-003 AC-3: share text contains body without source markers")
        func shareTextPlain() {
            let share = CreationExportService.shareText(from: sampleOutput())
            #expect(share.contains("You loved walking in the park."))
            #expect(share.contains("[🔗") == false)
        }

        @Test("US-SYN-003 AC-3 ADR-013: PDF data is non-empty")
        func pdfDataNonEmpty() async throws {
            let data = try await CreationExportService.pdf(from: sampleOutput())
            #expect(!data.isEmpty)
        }
    }

    // MARK: - MemoryDetailViewModel Integration (US-DIS-002 AC-3 availability, ADR-005)

    @Suite("MemoryDetailViewModel Availability", .serialized)
    @MainActor
    struct MemoryDetailAvailabilityTests {

        @Test("US-DIS-002 ADR-013: unavailable service surfaces L2 error phase (keeps original)")
        func unavailableServiceShowsL2Error() async throws {
            let service = AppleTranslationService(
                availability: StubUnavailableAvailability(),
                executor: StubFailingExecutor(),
                terminology: .empty
            )
            let cache = PersistentTranslationCache(directory: FileManager.default.temporaryDirectory)
            let vm = MemoryDetailViewModel(translationService: service, translationCache: cache)
            let model = MemoryDetailModel(
                id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                assetId: "note-zh-x",
                sourceType: "note",
                title: "测试",
                originalText: "这是一条需要翻译但语言对不受支持的记忆。",
                sourceLanguage: "zh-Hans",
                preferredLanguage: "en-US",
                timestamp: Date(timeIntervalSince1970: 1_723_000_000)
            )
            vm.loadPreloaded(model)
            vm.toggleTranslation()
            try? await Task.sleep(nanoseconds: 300_000_000)
            #expect(vm.memory?.translationVisible == true)
            #expect(vm.translationPhase != .translated)
        }
    }
}

// MARK: - Test Helpers

/// 恒定 unavailable 的 availability provider（集成测试）。
private struct StubUnavailableAvailability: TranslationAvailabilityProviding {
    func status(from source: String, to target: String) async -> TranslationAvailabilityStatus { .unsupported }
}

/// 恒抛 L2 错误的 executor（集成测试）。
private struct StubFailingExecutor: TranslationExecuting {
    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        throw TranslationError.serviceUnavailable
    }
}
