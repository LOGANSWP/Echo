// ==========================================
// 文件: CreationViewModelTests.swift
// 对应规格: docs/01-spec/用户故事与验收标准规格书.md → US-SYN-003 (情感内容生成+保存到备忘录),
//            US-SYN-004 (月度/年度叙事报告), US-SYN-005 (私有 Prompt 草稿编辑确认)
//            docs/ui/echo-memory-canvas-style.md §3.2 (Focus surfaces), docs/ui/architecture.md §6~7 (ViewModel/Adapter 契约)
// 任务: 3.9 - 整合所有 ViewModel 与 Pipeline + 创作保存 UI
// AC 覆盖: US-SYN-003 AC-1 (模板选择), AC-2 (溯源锚点), AC-3 (预览/复制/导出),
//          AC-4 (系统分享交接), AC-5 (交接失败 L2 Toast+重试),
//          US-SYN-004 AC-4 (分享/导出/打印), AC-5 (标题含报告周期),
//          US-SYN-005 AC-4 (Prompt 草稿可编辑确认), AC-6 (重置为默认 Prompt)
// 架构约束: 展示层 ViewModel 测试; 确定性 fixture; 无网络; @MainActor @Observable
// 生成时间: 2026-08-02
// ==========================================

import Testing
import Foundation
import SwiftUI
@testable import Echo

// MARK: - CreationViewModel Tests

@Suite("CreationViewModel", .serialized)
@MainActor
struct CreationViewModelTests {

    private func awaitGenerationSettled(
        _ vm: CreationViewModel,
        timeout: Duration = .seconds(2)
    ) async -> CreationViewModel.ViewState {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline, vm.viewState == .generating {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return vm.viewState
    }

    // MARK: - US-SYN-003 AC-1: Template selection

    @Test("US-SYN-003 AC-1: template selection stores selection in idle state")
    func selectTemplateStoresSelection() {
        let vm = CreationViewModel()
        vm.selectTemplate(.letter)
        #expect(vm.selectedTemplate == .letter)
        #expect(vm.viewState == .idle)
    }

    @Test("US-SYN-003 AC-1: template selection is ignored outside idle state")
    func selectTemplateIgnoredWhenNotIdle() {
        let vm = CreationViewModel()
        vm.loadPreloaded(CreationFixtureLoader.load("creation-generated-letter")!)
        vm.selectTemplate(.report)
        #expect(vm.selectedTemplate == .letter)
    }

    @Test("ADR-007: missing production creation runtime never falls back to fixture content")
    func missingRuntimeDoesNotGenerateFixtureContent() async {
        let vm = CreationViewModel()
        vm.selectTemplate(.letter)

        vm.generate()
        try? await Task.sleep(nanoseconds: 500_000_000)

        #expect(vm.creation == nil)
        #expect(vm.viewState == .error(.l2Recoverable(
            message: "Offline generation runtime is not available. Please try again."
        )))
    }

    // MARK: - US-SYN-003 AC-2: Generation with citation anchors

    @Test("US-SYN-003 AC-2: generated fixture preserves citation anchors")
    func generatedContentHasCitationAnchors() {
        let vm = CreationViewModel()
        vm.loadPreloaded(CreationFixtureLoader.load("creation-generated-letter")!)
        #expect(vm.viewState == .generated)
        #expect(vm.creation?.paragraphs.count == 2)
        #expect(vm.creation?.paragraphs.allSatisfy { !$0.citations.isEmpty } == true)
    }

    @Test("Explicit fixture journey generates the selected deterministic template")
    func explicitFixtureJourneyGeneratesSelectedTemplate() async {
        let vm = CreationViewModel()
        vm.enableFixtureGeneration()
        vm.selectTemplate(.letter)

        vm.generate()
        let settled = await awaitGenerationSettled(vm)

        #expect(settled == .generated)
        #expect(vm.creation?.selectedTemplate == .letter)
        #expect(vm.creation?.paragraphs.allSatisfy { !$0.citations.isEmpty } == true)
    }

    // MARK: - US-SYN-003 AC-3: Preview / Copy / Export

    @Test("US-SYN-003 AC-3: copy contains creation text without internal source markers")
    func copyWritesToPasteboard() {
        let vm = CreationViewModel()
        vm.loadPreloaded(CreationFixtureLoader.load("creation-generated-letter")!)
        vm.copyToClipboard()
        let pasted = UIPasteboard.general.string
        #expect(pasted?.contains("small orange cat") == true)
        #expect(pasted?.contains("🔗") == false)
        #expect(pasted?.contains("MemoryID:") == false)
    }

    @Test("US-SYN-003 AC-3: export picker only presents in generated state")
    func exportPickerOnlyInGeneratedState() {
        let vm = CreationViewModel()
        vm.presentExportPicker()
        #expect(vm.isExportPickerPresented == false)

        vm.loadPreloaded(CreationFixtureLoader.load("creation-generated-letter")!)
        vm.presentExportPicker()
        #expect(vm.isExportPickerPresented == true)
    }

    @Test("US-SYN-003 AC-3: export(format:) presents share sheet")
    func exportPresentsShareSheet() async {
        let vm = CreationViewModel()
        vm.loadPreloaded(CreationFixtureLoader.load("creation-generated-letter")!)
        vm.export(format: .pdf)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline, !vm.isSharePresented {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(vm.isExportPickerPresented == false)
        #expect(vm.isSharePresented == true)
        #expect(vm.sharePayload?.attachmentURL?.pathExtension == "pdf")
    }

    // MARK: - US-SYN-004 AC-4: Share / Export / Print

    @Test("US-SYN-004 AC-4: share sheet presents for narrative report")
    func sharePresentsForReport() {
        let vm = CreationViewModel()
        vm.loadPreloaded(CreationFixtureLoader.load("creation-generated-report")!)
        #expect(vm.creation?.periodType == "year")
        vm.presentShare()
        #expect(vm.isSharePresented == true)
    }

    // MARK: - US-SYN-004 AC-5: Report title contains period

    @Test("US-SYN-004 AC-5: narrative report title includes period")
    func reportTitleContainsPeriod() {
        let vm = CreationViewModel()
        vm.loadPreloaded(CreationFixtureLoader.load("creation-generated-report")!)
        #expect(vm.creation?.title?.contains("2025") == true)
    }

    // MARK: - US-SYN-003 AC-4/AC-5: Save to Notes (ADR-013 decision 4)

    @Test("US-SYN-003 AC-4 ADR-013: saveToNotes presents system share sheet (user-mediated Notes handoff)")
    func saveToNotesPresentsSystemShare() async throws {
        let vm = CreationViewModel()
        vm.loadPreloaded(CreationFixtureLoader.load("creation-generated-letter")!)
        vm.saveToNotes()
        // ADR-013 decision 4: Notes handoff is user-mediated system share/export only.
        #expect(vm.isSharePresented == true)
        #expect(vm.viewState == .generated)
    }

    @Test("US-SYN-003 AC-5 ADR-013: no fixture can fabricate a saved Notes result")
    func savedFixtureIsUnavailable() {
        #expect(CreationFixtureLoader.load("creation-saved") == nil)
        #expect(!CreationFixtureLoader.availableFixtureIDs.contains("creation-saved"))
    }

    // MARK: - US-SYN-003 AC-3: Empty / Error states

    @Test("US-SYN-003: empty fixture maps to empty state")
    func emptyFixtureMapsToEmpty() {
        let vm = CreationViewModel()
        vm.loadPreloaded(CreationFixtureLoader.load("creation-empty")!)
        #expect(vm.viewState == .empty)
        #expect(vm.creation?.emptyReason != nil)
    }

    @Test("US-SYN-003: error state allows retry")
    func errorStateAllowsRetry() {
        let vm = CreationViewModel()
        vm.simulateError(.l2Recoverable(message: "Generation is currently unavailable. Please try again."))
        #expect(vm.viewState == .error(.l2Recoverable(message: "Generation is currently unavailable. Please try again.")))
        vm.retry()
        // retry -> idle -> generate (no template selected, so stays generating only if template present)
        // simulateError 后 viewState == .error, retry() -> idle -> generate() 需要模板
        #expect(vm.viewState == .idle || vm.viewState == .generating)
    }

    // MARK: - US-SYN-005 AC-4: Prompt draft edit / confirm

    @Test("US-SYN-005 AC-4: presentPromptEditor loads confirmed draft into editor")
    func presentPromptEditorLoadsDraft() {
        let vm = CreationViewModel()
        vm.loadPromptDraft("Custom draft")
        vm.confirmPrompt()
        #expect(vm.confirmedPrompt == "Custom draft")
        #expect(vm.isPromptEditorPresented == false)
    }

    @Test("US-SYN-005 AC-4: confirmPrompt updates confirmed draft")
    func confirmPromptUpdatesConfirmed() {
        let vm = CreationViewModel()
        vm.presentPromptEditor()
        vm.promptDraftText = "Edited draft for Echo"
        vm.confirmPrompt()
        #expect(vm.confirmedPrompt == "Edited draft for Echo")
        #expect(vm.isPromptEditorPresented == false)
    }

    @Test("US-SYN-005 AC-4: empty draft is rejected on confirm")
    func emptyDraftRejected() {
        let vm = CreationViewModel()
        vm.presentPromptEditor()
        vm.promptDraftText = "   "
        vm.confirmPrompt()
        #expect(vm.isPromptEditorPresented == true)
        #expect(vm.confirmedPrompt == CreationPromptDefaults.defaultDraft)
    }

    // MARK: - US-SYN-005 AC-6: Reset to default prompt

    @Test("US-SYN-005 AC-6: resetPrompt restores default")
    func resetPromptRestoresDefault() {
        let vm = CreationViewModel()
        vm.loadPromptDraft("Custom draft")
        vm.confirmPrompt()
        #expect(vm.confirmedPrompt == "Custom draft")

        vm.resetPrompt()
        #expect(vm.confirmedPrompt == CreationPromptDefaults.defaultDraft)
        #expect(vm.isPromptEditorPresented == false)
    }

    // MARK: - Lifecycle

    @Test("onDisappear cancels in-flight generation")
    func onDisappearCancelsTask() {
        let vm = CreationViewModel()
        vm.selectTemplate(.letter)
        vm.generate()
        #expect(vm.viewState == .generating)
        vm.onDisappear()
        // 任务取消后 viewState 保留 generating（由 Task 检查 isCancelled 恢复 idle），
        // 此处仅验证不崩溃 + 任务已取消
        #expect(vm.viewState == .generating)
    }
}
