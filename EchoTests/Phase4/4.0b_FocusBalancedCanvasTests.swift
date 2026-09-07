// ==========================================
// File: 4.0b_FocusBalancedCanvasTests.swift
// Specification: docs/05-planning/开发计划安排文档.md → Task 4.0b
// Task: 4.0b - Focus Balanced Canvas for Detail, Creation and Translation
// AC coverage: AC-1 (Focus contracts), AC-2 (shared visual identity),
//              AC-3 (truthful media and mutations), AC-4 (grounded creation/share),
//              AC-5 (cache-first translation and accessibility semantics)
// Architecture: AGENTS.md §17.2 (Focus is single-column and never masonry)
// Generated: 2026-09-01
// ==========================================

import Foundation
import Testing
@testable import Echo

@Suite("FocusBalancedCanvasTests", .serialized)
@MainActor
struct FocusBalancedCanvasTests {
    @Test("AC-1: all Focus surface contracts use one profile, one column and no masonry")
    func test_AC1_focusContractsAreSingleColumn() throws {
        for path in [
            "UIAutomation/Contracts/instances/memory-detail-surface.json",
            "UIAutomation/Contracts/instances/creation-surface.json",
            "UIAutomation/Contracts/instances/translation-surface.json",
        ] {
            let contract = try loadJSON(path)
            #expect(contract["designProfileId"] as? String == "echo-memory-canvas")
            #expect(contract["surfaceFamily"] as? String == "focus")
            #expect(contract["layoutMode"] as? String == "single_column")
            #expect(contract["masonryEnabled"] as? Bool == false)
        }
    }

    @Test("AC-2: Detail, Creation and Translation consume shared Balanced Canvas components")
    func test_AC2_focusViewsUseSharedVisualIdentity() throws {
        let detail = try loadSource("Echo/UI/Detail/MemoryDetailView.swift")
        let creation = try loadSource("Echo/UI/Creation/CreationView.swift")

        for source in [detail, creation] {
            #expect(source.contains("@Environment(\\.echoDesignProfile)"))
            #expect(source.contains("EchoContainer"))
            #expect(source.contains("EchoMetadataGroup"))
            #expect(source.contains("EchoActionButtonStyle"))
            #expect(source.contains("EchoColorToken.canvasBackground.color"))
            #expect(!source.contains("LazyVGrid"))
            #expect(!source.contains("DiscoveryMasonry"))
        }
    }

    @Test("AC-3: unresolved production media has an honest shared fallback")
    func test_AC3_detailHasTruthfulMediaFallback() throws {
        let source = try loadSource("Echo/UI/Detail/MemoryDetailView.swift")

        #expect(source.contains("FocusMediaUnavailableView"))
        #expect(source.contains("Media unavailable"))
        #expect(source.contains("EchoStatusPresentation"))
        #expect(source.contains("viewModel.isFixtureBacked"))
    }

    @Test("AC-3: unsupported production mutations remain visible failures")
    func test_AC3_productionMutationBoundariesFailHonestly() throws {
        let source = try loadSource("Echo/UI/Detail/MemoryDetailViewModel.swift")

        #expect(source.contains("Editing is unavailable because the production memory update boundary is not connected."))
        #expect(source.contains("Conflict resolution is unavailable because the production update boundary is not connected."))
        #expect(source.contains("FocusSourceLifecycleServicing"))
        #expect(source.contains("sourceDeletionCapability"))
        #expect(!source.contains("Original-file deletion is unavailable because the source deletion boundary is not connected."))
        #expect(!source.contains("guard !isFixtureBacked else { return }"))
    }

    @Test("AC-4: citations revalidate before stable MemoryID routing and NoSource is non-interactive")
    func test_AC4_creationCitationRouting() throws {
        let source = try loadSource("Echo/UI/Creation/CreationView.swift")

        #expect(source.contains("viewModel.openCitation(citation)"))
        #expect(source.contains("navigationDestination(item: $viewModel.navigationMemoryID)"))
        #expect(source.contains("MemoryDetailView(memoryId: memoryID)"))
        #expect(source.contains("creation-citation-no-source"))
        #expect(source.contains("No source for part or all of this paragraph"))
    }

    @Test("AC-4: Notes handoff never exposes a fabricated saved state or link")
    func test_AC4_notesHandoffHasNoFabricatedSuccess() throws {
        let view = try loadSource("Echo/UI/Creation/CreationView.swift")
        let viewModel = try loadSource("Echo/UI/Creation/CreationViewModel.swift")
        let fixtures = try loadSource("Echo/UI/Creation/CreationFixtureLoader.swift")

        #expect(view.contains(".sheet(item:"))
        #expect(view.contains("SystemShareSheet(payload: payload, reporter: viewModel)"))
        #expect(view.contains("super.init(activityItems: activityItems"))
        #expect(!view.contains("ShareLink("))
        #expect(viewModel.contains("CreationSharePayload"))
        #expect(!view.contains("savedToast"))
        #expect(!viewModel.contains("case saved"))
        #expect(!viewModel.contains("noteLink"))
        #expect(!viewModel.contains("Saved to Notes"))
        #expect(!fixtures.contains("creation-saved"))
        #expect(CreationFixtureLoader.load("creation-saved") == nil)
    }

    @Test("AC-4: cancelling the share handoff returns to generated without an L2 error")
    func test_AC4_shareCancellationIsNotFailure() throws {
        let viewModel = CreationViewModel()
        let model = try #require(CreationFixtureLoader.load("creation-generated-letter"))
        viewModel.loadPreloaded(model)

        viewModel.saveToNotes()
        #expect(viewModel.isSharePresented)
        #expect(viewModel.viewState == .generated)

        viewModel.isSharePresented = false
        #expect(viewModel.viewState == .generated)
    }

    @Test("AC-4: an empty local export fails visibly instead of opening a blank share surface")
    func test_AC4_sharePreparationFailureIsRecoverable() {
        let viewModel = CreationViewModel()
        viewModel.loadPreloaded(CreationModel(
            selectedTemplate: .letter,
            title: nil,
            periodType: nil,
            paragraphs: [],
            sourceMemoryCount: 0,
            emptyReason: nil
        ))

        viewModel.saveToNotes()

        #expect(!viewModel.isSharePresented)
        #expect(viewModel.viewState == .error(.l2Recoverable(
            message: "Unable to prepare this creation for sharing. Please try again."
        )))
    }

    @Test("AC-4: Markdown export distinguishes unavailable provenance from a source anchor")
    func test_AC4_markdownExportPreservesNoSourceTruth() throws {
        let viewModel = CreationViewModel()
        let memoryID = UUID()
        viewModel.loadPreloaded(CreationModel(
            selectedTemplate: .letter,
            title: "Grounded draft",
            periodType: nil,
            paragraphs: [
                CreationParagraph(
                    id: UUID(),
                    text: "A paragraph without resolvable provenance.",
                    citations: [],
                    groundingStatus: .noSource
                ),
            ],
            sourceMemoryCount: 0,
            emptyReason: nil
        ))

        viewModel.export(format: .markdown)

        let payload = try #require(viewModel.sharePayload)
        #expect(payload.kind == .markdown)
        #expect(payload.text.contains("NoSource"))
        #expect(!payload.text.contains(memoryID.uuidString))
        #expect(payload.attachmentURL == nil)
    }

    @Test("AC-4: PDF export prepares a real local PDF attachment")
    func test_AC4_pdfExportCreatesAttachment() async throws {
        let viewModel = CreationViewModel()
        let model = try #require(CreationFixtureLoader.load("creation-generated-letter"))
        viewModel.loadPreloaded(model)

        viewModel.export(format: .pdf)
        let payload = try await awaitSharePayload(viewModel)
        let attachmentURL = try #require(payload.attachmentURL)
        let data = try Data(contentsOf: attachmentURL)

        #expect(payload.kind == .pdf)
        #expect(attachmentURL.pathExtension == "pdf")
        #expect(data.starts(with: Data("%PDF".utf8)))
    }

    @Test("AC-4: production generation fails closed while explicit fixture generation is labeled")
    func test_AC4_generationTruthfulness() async {
        let production = CreationViewModel()
        production.selectTemplate(.letter)
        production.generate()
        _ = await awaitCreationSettled(production)
        #expect(production.creation == nil)
        #expect(production.viewState == .error(.l2Recoverable(
            message: "Offline generation runtime is not available. Please try again."
        )))

        let fixture = CreationViewModel()
        fixture.enableFixtureGeneration()
        fixture.selectTemplate(.letter)
        fixture.generate()
        _ = await awaitCreationSettled(fixture)
        #expect(fixture.isFixtureBacked)
        #expect(fixture.viewState == .generated)
    }

    @Test("AC-5: Translation keeps the exact uncertainty boundary and shared reading hierarchy")
    func test_AC5_translationPresentationContract() throws {
        let view = try loadSource("Echo/UI/Detail/MemoryDetailView.swift")
        let viewModel = try loadSource("Echo/UI/Detail/MemoryDetailViewModel.swift")
        let cache = try loadSource("Echo/UI/Translation/TranslationCache.swift")

        #expect(view.contains("confidence < 0.9"))
        #expect(view.contains("EchoContainer"))
        #expect(view.contains("EchoMetadataGroup"))
        #expect(view.contains("accessibilityElement(children: .contain)"))
        #expect(!viewModel.contains("<0.7"))
        #expect(cache.contains("7 * 24 * 3600"))
    }

    @Test("AC-5: a cache hit is rendered without invoking an uncertain fallback")
    func test_AC5_translationCacheHit() async throws {
        let cache = TranslationCache()
        let model = try #require(TranslationFixtureLoader.load("translation-zh-en-high"))
        await cache.store(
            sourceText: model.originalText,
            sourceLanguage: model.sourceLanguage,
            targetLanguage: model.preferredLanguage,
            translatedText: "Cached local translation",
            sourceLanguageConfidence: 0.95
        )
        let viewModel = MemoryDetailViewModel(
            translationService: FixtureTranslationService(),
            translationCache: cache
        )
        viewModel.loadPreloaded(model)

        viewModel.toggleTranslation()
        _ = await awaitTranslationSettled(viewModel)

        #expect(viewModel.translationPhase == .translated)
        #expect(viewModel.memory?.translatedText == "Cached local translation")
        #expect(await cache.count == 1)
    }

    @Test("AC-5: uncertain source detection exposes and caches no translated text")
    func test_AC5_uncertainTranslationKeepsOnlyOriginal() async throws {
        let cache = TranslationCache()
        let model = try #require(TranslationFixtureLoader.load("translation-zh-en-low"))
        let viewModel = MemoryDetailViewModel(
            translationService: FixtureTranslationService(),
            translationCache: cache
        )
        viewModel.loadPreloaded(model)

        viewModel.toggleTranslation()
        _ = await awaitTranslationSettled(viewModel)

        #expect(viewModel.translationPhase == .uncertain)
        #expect(viewModel.memory?.translatedText == nil)
        #expect(viewModel.memory?.sourceLanguageConfidence == 0.55)
        #expect(await cache.isEmpty)
    }

    @Test("AC-5: unsupported language pair retains original in an explicit unavailable state")
    func test_AC5_unsupportedTranslationIsUnavailable() async throws {
        let model = try #require(TranslationFixtureLoader.load("translation-unavailable"))
        let viewModel = MemoryDetailViewModel(
            translationService: FixtureTranslationService(),
            translationCache: TranslationCache()
        )
        viewModel.loadPreloaded(model)

        viewModel.toggleTranslation()
        _ = await awaitTranslationSettled(viewModel)

        if case .unavailable = viewModel.translationPhase {
            #expect(viewModel.memory?.translatedText == nil)
            #expect(viewModel.memory?.originalText == model.originalText)
        } else {
            Issue.record("Expected an explicit unavailable translation state")
        }
    }

    @Test("AC-5: Focus acceptance policy prohibits fixture evidence and saved-note claims")
    func test_AC5_focusTruthfulnessPolicy() throws {
        let policy = try loadJSON("UIAutomation/Policies/acceptance-policy.json")
        let gates = try #require(policy["verification_gates"] as? [String: Any])
        let focus = try #require(gates["focus_truthfulness"] as? [String: Any])
        let description = try #require(focus["description"] as? String)

        #expect(focus["required"] as? Bool == true)
        #expect(description.contains("single-column"))
        #expect(description.contains("<0.9"))
        #expect(description.contains("saved-note Toasts"))
    }

    private func loadJSON(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func awaitCreationSettled(
        _ viewModel: CreationViewModel
    ) async -> CreationViewModel.ViewState {
        for _ in 0..<200 where viewModel.viewState == .generating {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return viewModel.viewState
    }

    private func awaitSharePayload(
        _ viewModel: CreationViewModel,
        timeout: Duration = .seconds(2)
    ) async throws -> CreationSharePayload {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let payload = viewModel.sharePayload {
                return payload
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw SharePayloadTimeout()
    }

    private func awaitTranslationSettled(
        _ viewModel: MemoryDetailViewModel
    ) async -> MemoryDetailViewModel.TranslationPhase {
        for _ in 0..<200 where viewModel.translationPhase == .translating {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return viewModel.translationPhase
    }

    private func loadSource(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            root.deleteLastPathComponent()
        }
        return root
    }
}

private struct SharePayloadTimeout: Error {}
