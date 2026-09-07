// ==========================================
// 文件: CreationViewModel.swift
// i18n: All user-facing strings are hardcoded English. Full String Catalog migration (zh-Hans + en-US) deferred to Phase 3.9.
// 对应规格: docs/01-spec/用户故事与验收标准规格书.md → US-SYN-003 (情感内容生成+保存到备忘录),
//            US-SYN-004 (月度/年度叙事报告), US-SYN-005 (私有 Prompt 草稿编辑确认)
//            docs/ui/echo-memory-canvas-style.md §3.2 (Focus surfaces — 单列 + grouped metadata),
//            docs/ui/architecture.md §6 (ViewModel 契约), §7 (适配器契约)
// 任务: 3.9 + 4.0i + 4.0j - Grounded creation, report library, and truthful share audit
// AC coverage: US-SYN-003 AC-1 ✅ (template selection), AC-2 ✅ (grounded citations),
//              AC-3 ✅ (preview/copy/export), AC-4 ✅ (system share handoff),
//              AC-5 ✅ (visible L2 recovery when payload preparation fails),
//          US-SYN-004 AC-4 ✅ (分享/导出/打印), AC-5 ✅ (保存逻辑与 SYN-003 一致, 标题含报告周期),
//          US-SYN-005 AC-4 ✅ (Prompt 草稿可编辑确认), AC-6 ✅ (重置为默认 Prompt)
//              Task 4.0b ✅ (native Focus presentation), Task 4.0i ✅ (multi-anchor/current-policy handoff)
// 架构约束: AGENTS.md §8.1 (@MainActor + @Observable + state enum: idle/loading/completed/error/cancelled),
//           §8.2 (状态流转), docs/ui/architecture.md §6~7 (适配器契约),
//           §2.5 (Adapter 不保存第二份领域真相 — 仅转换展示字段)
// 生成时间: 2026-08-02 | Updated: 2026-09-07 (4.0j report library)
// ==========================================

import Foundation
import SwiftUI

struct CreationSharePayload: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text
        case markdown
        case pdf
        case notesHandoff
    }

    let id: UUID
    let kind: Kind
    let text: String
    let previewTitle: String
    let attachmentURL: URL?
    let exportFormat: CreationExportFormat
    let traceID: String
    let periodType: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        text: String,
        previewTitle: String,
        attachmentURL: URL? = nil,
        exportFormat: CreationExportFormat,
        traceID: String,
        periodType: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.previewTitle = previewTitle
        self.attachmentURL = attachmentURL
        self.exportFormat = exportFormat
        self.traceID = traceID
        self.periodType = periodType
    }
}

private extension CreationSharePayload.Kind {
    var exportFormat: CreationExportFormat {
        switch self {
        case .markdown: .markdown
        case .pdf: .pdf
        case .text, .notesHandoff: .plainText
        }
    }
}

@MainActor
protocol CreationSharePresentationReporting: AnyObject {
    func shareControllerDidAppear(payloadID: UUID)
}

// MARK: - CreationViewModel

/// AI 创作结果页 ViewModel — 模板选择 + 生成预览 + 复制/导出 + 保存到备忘录 + Prompt 草稿编辑。
///
/// ## Surface Family: Focus
/// - 布局: 单列内容流 + grouped metadata（echo-memory-canvas §3.2）
/// - 样式: echo-memory-canvas + apple-native 基础
/// - Masonry: 禁止（Focus surface）
///
/// ## 职责 (docs/ui/architecture.md §7.1)
/// - 状态映射: fixture/Core 创作输出 → UI State
/// - 错误映射: L1~L4 → error state
/// - Intent 转发: 生成/复制/导出/保存/分享/Prompt 编辑 → Core await 调用（🔮 Phase 3.9）
/// - 生命周期: Task 管理，View 消失时 cancel
///
/// ## 状态流转 (AGENTS.md §8.2)
/// ```
/// idle → generating → generated
///                     → empty
///                     → error(L2)
/// generated → share handoff (system-owned) → generated
///                                → error(L2, preparation/presentation)
/// ```
@MainActor
@Observable
final class CreationViewModel: CreationSharePresentationReporting {
    // MARK: - State Enum

    /// ViewModel 统一状态枚举 (AGENTS.md §8.1)
    enum ViewState: Equatable, Sendable {
        /// 初始状态 — 未选择模板
        case idle
        /// 生成中 — ProgressView
        case generating
        /// 生成完成 — 展示内容 + 操作按钮
        case generated
        /// 空态 — 无匹配源记忆
        case empty
        /// 错误状态 — L2 重试
        case error(ErrorLevel)
    }

    /// 错误等级 — 对应 AGENTS.md §4.4 L1~L4
    enum ErrorLevel: Equatable, Sendable {
        /// L2 可恢复: Toast + 重试按钮
        case l2Recoverable(message: String)
    }

    enum ReportLibraryState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case error(message: String)
    }

    /// 导出格式 (US-SYN-003 AC-3)
    enum ExportFormat: String, CaseIterable, Sendable {
        case pdf
        case markdown

        var displayName: String {
            switch self {
            case .pdf:       return "PDF"
            case .markdown:  return "Markdown"
            }
        }
    }

    // MARK: - Published State

    /// 统一视图状态
    private(set) var viewState: ViewState = .idle
    /// 当前创作结果
    private(set) var creation: CreationModel?
    /// 已选模板
    private(set) var selectedTemplate: CreationTemplate?
    private(set) var reportLibraryState: ReportLibraryState = .idle
    private(set) var reportSchedule: NarrativeReportSchedule?
    private(set) var narrativeReports: [PersistedNarrativeReport] = []
    private(set) var recoverableReportPeriods: [NarrativeReportPeriod] = []

    // MARK: - Prompt Editor State (US-SYN-005 AC-4)

    /// Prompt 编辑器 Sheet 是否呈现
    var isPromptEditorPresented: Bool = false
    /// Prompt 草稿编辑文本
    var promptDraftText: String = CreationPromptDefaults.defaultDraft
    /// 当前生效的 Prompt 草稿（确认后更新）
    private(set) var confirmedPrompt: String = CreationPromptDefaults.defaultDraft
    /// True only after an explicit Preview/test/XCUITest fixture injection.
    private(set) var isFixtureBacked = false

    // MARK: - Export / Share State (US-SYN-003 AC-3, US-SYN-004 AC-4)

    /// 导出格式确认弹窗是否呈现
    var isExportPickerPresented: Bool = false
    /// Set only after current-policy/source resolution succeeds.
    var navigationMemoryID: UUID?
    /// Prepared local payload for the user-mediated system share handoff.
    var sharePayload: CreationSharePayload? {
        didSet {
            guard let previousURL = oldValue?.attachmentURL,
                  previousURL != sharePayload?.attachmentURL else { return }
            try? FileManager.default.removeItem(at: previousURL)
        }
    }

    /// Compatibility binding used by existing integration tests and dismissal paths.
    var isSharePresented: Bool {
        get { sharePayload != nil }
        set {
            if !newValue {
                activeSharePayload = nil
                presentedPayloadIDs.removeAll()
                sharePayload = nil
            }
        }
    }

    // MARK: - Dependencies

    /// 当前活跃的生成 Task
    private var generateTask: Task<Void, Never>?
    /// Currently active PDF generation task.
    private var exportTask: Task<Void, Never>?
    private var activeSharePayload: CreationSharePayload?
    private var presentedPayloadIDs: Set<UUID> = []
    /// UI 切片模式模拟创作源 — fixture 注入
    private var stubCreation: CreationModel?
    /// Production creation pipeline. A missing runtime must fail closed and never load fixture output.
    private let creativePipeline: CreativePipeline?
    /// Production action boundary. Fixtures may bypass it but cannot serve as production evidence.
    private let exportCoordinator: CreationExportCoordinator?
    private let narrativeReportActor: NarrativeReportActor?
    /// 创作源记忆（grounded 输入，经检索结果映射）— 3F.9 生产路径
    private var sourceMemories: [CreativeSource] = []

    init(
        creativePipeline: CreativePipeline? = nil,
        exportCoordinator: CreationExportCoordinator? = nil,
        narrativeReportActor: NarrativeReportActor? = nil
    ) {
        self.creativePipeline = creativePipeline
        self.exportCoordinator = exportCoordinator
        self.narrativeReportActor = narrativeReportActor
    }

    // MARK: - Actions

    func loadReportLibrary() {
        reportLibraryState = .loading
        guard let narrativeReportActor else {
            reportLibraryState = .idle
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                async let schedule = narrativeReportActor.loadSchedule()
                async let reports = narrativeReportActor.listReports()
                async let recoverable = narrativeReportActor.listRecoverablePeriods()
                self.reportSchedule = try await schedule
                self.narrativeReports = try await reports
                self.recoverableReportPeriods = try await recoverable
                self.reportLibraryState = .loaded
            } catch {
                self.reportLibraryState = .error(
                    message: EchoStrings.tr("Unable to load narrative reports. Please try again.")
                )
            }
        }
    }

    func setReportSchedule(_ enabled: Bool, for periodType: NarrativeReportPeriodType) {
        reportLibraryState = .loading
        guard let narrativeReportActor else {
            reportLibraryState = .error(
                message: EchoStrings.tr("Narrative report scheduling is unavailable.")
            )
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await narrativeReportActor.setEnabled(enabled, for: periodType)
                self.reportSchedule = try await narrativeReportActor.loadSchedule()
                self.reportLibraryState = .loaded
            } catch {
                self.reportLibraryState = .error(
                    message: EchoStrings.tr("Unable to update narrative report scheduling.")
                )
            }
        }
    }

    func openReport(_ reportID: UUID) {
        reportLibraryState = .loading
        guard let narrativeReportActor else {
            reportLibraryState = .error(
                message: EchoStrings.tr("Narrative report is unavailable.")
            )
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let report = try await narrativeReportActor.loadReport(reportID: reportID) else {
                    throw NarrativeReportError.periodUnavailable
                }
                self.creation = Self.creationModel(from: report)
                self.selectedTemplate = .report
                self.isFixtureBacked = false
                self.reportLibraryState = .loaded
                self.viewState = .generated
            } catch {
                self.reportLibraryState = .error(
                    message: EchoStrings.tr("Unable to open this narrative report.")
                )
            }
        }
    }

    func deleteReport(_ reportID: UUID) {
        reportLibraryState = .loading
        guard let narrativeReportActor else {
            reportLibraryState = .error(
                message: EchoStrings.tr("Unable to delete this narrative report.")
            )
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await narrativeReportActor.deleteReport(reportID: reportID)
                self.narrativeReports = try await narrativeReportActor.listReports()
                self.recoverableReportPeriods = try await narrativeReportActor.listRecoverablePeriods()
                self.reportLibraryState = .loaded
            } catch {
                self.reportLibraryState = .error(
                    message: EchoStrings.tr("Unable to delete this narrative report.")
                )
            }
        }
    }

    func retryReport(_ period: NarrativeReportPeriod) {
        reportLibraryState = .loading
        guard let narrativeReportActor else {
            reportLibraryState = .error(
                message: EchoStrings.tr("Unable to retry this narrative report.")
            )
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await narrativeReportActor.retryReport(
                    periodType: period.periodType,
                    periodKey: period.periodKey
                )
                self.recoverableReportPeriods = try await narrativeReportActor.listRecoverablePeriods()
                self.reportLibraryState = .loaded
            } catch {
                self.reportLibraryState = .error(
                    message: EchoStrings.tr("Unable to retry this narrative report.")
                )
            }
        }
    }

    func scanNarrativeReportsNow() {
        reportLibraryState = .loading
        guard let narrativeReportActor else {
            reportLibraryState = .error(
                message: EchoStrings.tr("Narrative report scheduling is unavailable.")
            )
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await narrativeReportActor.establishEligibilityIfNeeded()
                let result = try await narrativeReportActor.scanAndEnqueue(
                    calendarContext: .init(
                        timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
                    ),
                    trigger: .userInitiated
                )
                guard result != .generationUnavailable else {
                    self.reportLibraryState = .error(
                        message: EchoStrings.tr(
                            "Offline generation runtime is not available. Please try again."
                        )
                    )
                    return
                }
                self.recoverableReportPeriods = try await narrativeReportActor
                    .listRecoverablePeriods()
                self.narrativeReports = try await narrativeReportActor.listReports()
                self.reportLibraryState = .loaded
            } catch {
                self.reportLibraryState = .error(
                    message: EchoStrings.tr("Unable to start narrative report generation.")
                )
            }
        }
    }

    private static func creationModel(from report: PersistedNarrativeReport) -> CreationModel {
        let sourcesByID = Dictionary(uniqueKeysWithValues: report.sources.map {
            ($0.memoryID, $0)
        })
        return CreationModel(
            selectedTemplate: .report,
            title: report.envelope.title,
            periodType: report.periodType.rawValue,
            paragraphs: report.envelope.paragraphs.map { paragraph in
                CreationParagraph(
                    id: paragraph.id,
                    text: paragraph.text,
                    citations: paragraph.sourceMemoryIDs.map { memoryID in
                        let source = sourcesByID[memoryID]
                        return CreationCitation(
                            memoryId: memoryID,
                            sourceType: source?.sourceType,
                            availability: source?.availability ?? .missing
                        )
                    },
                    groundingStatus: paragraph.groundingStatus
                )
            },
            sourceMemoryCount: report.sources.count,
            sourceTypes: report.sourceTypes,
            emptyReason: nil
        )
    }

    /// 选择创作模板 (US-SYN-003 AC-1)。
    func selectTemplate(_ template: CreationTemplate) {
        guard viewState == .idle else { return }
        selectedTemplate = template
    }

    /// 生成内容 — 设置 state = .generating，完成后进入 generated/empty/error。
    ///
    /// Production uses grounded generation through CreativePipeline. Fixture output is
    /// available only after explicit Preview/test injection.
    func generate() {
        guard viewState == .idle, selectedTemplate != nil else { return }

        generateTask?.cancel()

        // Set loading synchronously (AGENTS.md §8.1: first line of action)
        viewState = .generating

        generateTask = Task { [weak self] in
            guard let self else { return }

            // 生产路径: grounded generation (ADR-013 决策 3)
            if let pipeline = self.creativePipeline, let template = self.selectedTemplate {
                self.isFixtureBacked = false
                await self.generateViaPipeline(pipeline, template: template)
                return
            }

            guard !Task.isCancelled else {
                self.viewState = .idle
                return
            }

            // Explicit Preview/test injection may regenerate deterministic output.
            if self.isFixtureBacked, let template = self.selectedTemplate {
                guard let model = self.stubCreation ?? CreationFixtureLoader.load(for: template) else {
                    self.creation = nil
                    self.viewState = .error(.l2Recoverable(
                        message: "Generation is currently unavailable. Please try again."
                    ))
                    return
                }
                self.creation = model
                self.viewState = model.emptyReason != nil ? .empty : .generated
            } else {
                self.creation = nil
                self.viewState = .error(.l2Recoverable(
                    message: "Offline generation runtime is not available. Please try again."
                ))
            }
        }
    }

    /// 经生产管线 grounded 生成 — 源记忆经检索结果映射（无源 → 空态）。
    private func generateViaPipeline(_ pipeline: CreativePipeline, template: CreationTemplate) async {
        do {
            let coreTemplate: CreativeTemplate
            switch template {
            case .letter:   coreTemplate = .letter
            case .report:   coreTemplate = .report
            case .poem:     coreTemplate = .poem
            case .timeline: coreTemplate = .timeline
            }

            let output = try await pipeline.generate(
                template: coreTemplate,
                sources: sourceMemories,
                traceID: UUID().uuidString
            )

            guard !Task.isCancelled else {
                viewState = .idle
                return
            }

            guard !output.didFallback else {
                viewState = .error(.l2Recoverable(
                    message: "Generation is currently unavailable. Please try again."
                ))
                return
            }

            guard !output.paragraphs.isEmpty else {
                creation = nil
                viewState = .empty
                return
            }

            creation = mapToCreationModel(output)
            viewState = .generated
        } catch CreativeError.noSources {
            creation = nil
            viewState = .empty
        } catch CreativeError.runtimeUnavailable {
            viewState = .error(.l2Recoverable(
                message: "Offline generation runtime is not available. Please try again."
            ))
        } catch {
            viewState = .error(.l2Recoverable(
                message: "Generation is currently unavailable. Please try again."
            ))
        }
    }

    /// 映射 grounded 输出为 UI 展示模型（适配器职责，docs/ui/architecture.md §7）。
    private func mapToCreationModel(_ output: CreativeOutput) -> CreationModel {
        let uiTemplate: CreationTemplate
        switch output.template {
        case .letter:   uiTemplate = .letter
        case .report:   uiTemplate = .report
        case .poem:     uiTemplate = .poem
        case .timeline: uiTemplate = .timeline
        }

        let paragraphs = output.paragraphs.map { paragraph in
            CreationParagraph(
                id: paragraph.id,
                text: paragraph.text,
                citations: paragraph.anchors.map {
                    CreationCitation(
                        memoryId: $0.memoryID,
                        sourceType: $0.sourceType,
                        availability: $0.availability
                    )
                },
                groundingStatus: paragraph.groundingStatus
            )
        }

        return CreationModel(
            selectedTemplate: uiTemplate,
            title: output.title,
            periodType: output.periodType,
            paragraphs: paragraphs,
            sourceMemoryCount: output.sourceMemoryCount,
            sourceTypes: output.sourceTypes,
            emptyReason: output.emptyReason
        )
    }

    /// 重新生成 (generated → generating)。
    func regenerate() {
        guard viewState == .generated else { return }
        viewState = .idle
        generate()
    }

    /// Copies citation-preserving plain text after current-policy revalidation.
    func copyToClipboard() {
        guard let creation else { return }
        let output = Self.creativeOutput(from: creation)
        if isFixtureBacked {
            completeCopy(output)
            return
        }
        exportTask?.cancel()
        exportTask = Task { [weak self] in
            guard let self, let coordinator = self.exportCoordinator else {
                self?.showHandoffError()
                return
            }
            do {
                let authorized = try await coordinator.authorize(
                    output: output,
                    traceID: UUID().uuidString
                )
                self.completeCopy(authorized)
            } catch {
                self.showHandoffError()
            }
        }
    }

    /// 呈现导出格式选择 (US-SYN-003 AC-3)。
    func presentExportPicker() {
        guard viewState == .generated else { return }
        isExportPickerPresented = true
    }

    /// 确认导出格式 — 呈现系统分享 Sheet (PDF/Markdown 导出入口, US-SYN-003 AC-3)。
    ///
    /// 3F.9 (ADR-013 决策 4): 经 `CreationExportService` 生成导出内容后呈现系统 share sheet。
    func export(format: ExportFormat) {
        isExportPickerPresented = false
        prepareSharePayload(kind: format == .pdf ? .pdf : .markdown)
    }

    /// 呈现分享/打印 Sheet (US-SYN-004 AC-4)。
    func presentShare() {
        guard viewState == .generated else { return }
        prepareSharePayload(kind: .text)
    }

    /// 保存到备忘录 (US-SYN-003 AC-4)。
    ///
    /// ADR-013 决策 4 (3F.9): Notes 交接**仅用系统 share/export 流（用户中介）**，
    /// 禁止 `notes://` 深链与私有 NoteStore 直写。直接呈现系统分享面板，由用户选择保存到备忘录。
    func saveToNotes() {
        guard viewState == .generated else { return }
        prepareSharePayload(kind: .notesHandoff)
    }

    private func prepareSharePayload(kind: CreationSharePayload.Kind) {
        guard viewState == .generated, let creation else {
            showHandoffError()
            return
        }
        let output = Self.creativeOutput(from: creation)
        let payloadID = UUID()
        let traceID = UUID().uuidString
        if isFixtureBacked, kind != .pdf {
            finishTextPayload(
                output: output,
                creation: creation,
                kind: kind,
                payloadID: payloadID,
                traceID: traceID
            )
            return
        }
        exportTask?.cancel()
        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let authorized: CreativeOutput
                if self.isFixtureBacked {
                    authorized = output
                } else if let coordinator = self.exportCoordinator {
                    authorized = try await coordinator.authorize(output: output, traceID: traceID)
                } else {
                    throw CreationExportError.privacyDenied
                }
                try Task.checkCancellation()
                if kind == .pdf {
                    try await self.finishPDFPayload(
                        output: authorized,
                        creation: creation,
                        payloadID: payloadID,
                        traceID: traceID
                    )
                } else {
                    self.finishTextPayload(
                        output: authorized,
                        creation: creation,
                        kind: kind,
                        payloadID: payloadID,
                        traceID: traceID
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await self.recordFailedPresentation(
                    payloadID: payloadID,
                    kind: kind,
                    periodType: creation.periodType,
                    traceID: traceID
                )
                self.showHandoffError()
            }
        }
    }

    private func finishTextPayload(
        output: CreativeOutput,
        creation: CreationModel,
        kind: CreationSharePayload.Kind,
        payloadID: UUID,
        traceID: String
    ) {
        let text = kind == .markdown
            ? CreationExportService.markdown(from: output)
            : CreationExportService.plainText(from: output)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showHandoffError()
            return
        }
        publishPayload(CreationSharePayload(
            id: payloadID,
            kind: kind,
            text: text,
            previewTitle: creation.title ?? "Echo Creation",
            exportFormat: kind.exportFormat,
            traceID: traceID,
            periodType: creation.periodType
        ))
    }

    private func finishPDFPayload(
        output: CreativeOutput,
        creation: CreationModel,
        payloadID: UUID,
        traceID: String
    ) async throws {
        let data = try await CreationExportService.pdf(from: output)
        try Task.checkCancellation()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Echo-Creation-\(payloadID.uuidString)")
            .appendingPathExtension("pdf")
        try data.write(to: fileURL, options: .atomic)
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: fileURL)
            throw CancellationError()
        }
        publishPayload(CreationSharePayload(
            id: payloadID,
            kind: .pdf,
            text: "",
            previewTitle: creation.title ?? "Echo Creation",
            attachmentURL: fileURL,
            exportFormat: .pdf,
            traceID: traceID,
            periodType: creation.periodType
        ))
    }

    private func publishPayload(_ payload: CreationSharePayload) {
        activeSharePayload = payload
        sharePayload = payload
    }

    private func completeCopy(_ output: CreativeOutput) {
        UIPasteboard.general.string = CreationExportService.plainText(from: output)
        UIAccessibility.post(
            notification: .announcement,
            argument: EchoStrings.tr("Creation copied to clipboard")
        )
    }

    private func showHandoffError() {
        activeSharePayload = nil
        presentedPayloadIDs.removeAll()
        sharePayload = nil
        viewState = .error(.l2Recoverable(
            message: EchoStrings.tr("Unable to prepare this creation for sharing. Please try again.")
        ))
    }

    private func showCitationError(_ error: CreationExportError) {
        let message = error == .privacyDenied
            ? EchoStrings.tr("The current privacy policy no longer permits opening this source.")
            : EchoStrings.tr("This source memory is currently unavailable.")
        viewState = .error(.l2Recoverable(message: message))
    }

    func openCitation(_ citation: CreationCitation) {
        let anchor = SourceAnchor(
            memoryID: citation.memoryId,
            sourceType: citation.sourceType,
            availability: citation.availability
        )
        if isFixtureBacked {
            navigationMemoryID = citation.memoryId
            return
        }
        Task { [weak self] in
            guard let self, let coordinator = self.exportCoordinator else {
                self?.showCitationError(.sourceUnavailable)
                return
            }
            do {
                self.navigationMemoryID = try await coordinator.authorizeNavigation(
                    anchor: anchor,
                    traceID: UUID().uuidString
                )
            } catch let error as CreationExportError {
                self.showCitationError(error)
            } catch {
                self.showCitationError(.sourceUnavailable)
            }
        }
    }

    func shareControllerDidAppear(payloadID: UUID) {
        guard let payload = activeSharePayload,
              payload.id == payloadID,
              presentedPayloadIDs.insert(payloadID).inserted,
              let coordinator = exportCoordinator else { return }
        Task { [weak self] in
            do {
                try await coordinator.recordSharePresentation(
                    payloadID: payload.id,
                    format: payload.exportFormat,
                    periodType: payload.periodType,
                    traceID: payload.traceID,
                    presented: true
                )
            } catch {
                // The true presentation already happened; never rewrite it as false.
                self?.viewState = .error(.l2Recoverable(
                    message: EchoStrings.tr("The share was presented, but its audit record is pending retry.")
                ))
            }
        }
    }

    func shareSheetDidDismiss() {
        guard let payload = activeSharePayload else { return }
        activeSharePayload = nil
        sharePayload = nil
        let wasPresented = presentedPayloadIDs.remove(payload.id) != nil
        guard !wasPresented else { return }
        Task { [weak self] in
            await self?.recordFailedPresentation(
                payloadID: payload.id,
                kind: payload.kind,
                periodType: payload.periodType,
                traceID: payload.traceID
            )
            self?.viewState = .error(.l2Recoverable(
                message: EchoStrings.tr("Unable to present the system share sheet. Please try again.")
            ))
        }
    }

    private func recordFailedPresentation(
        payloadID: UUID,
        kind: CreationSharePayload.Kind,
        periodType: String?,
        traceID: String
    ) async {
        try? await exportCoordinator?.recordSharePresentation(
            payloadID: payloadID,
            format: kind.exportFormat,
            periodType: periodType,
            traceID: traceID,
            presented: false
        )
    }

    private static func creativeOutput(from creation: CreationModel) -> CreativeOutput {
        let template = CreativeTemplate(rawValue: creation.selectedTemplate.rawValue) ?? .letter
        return CreativeOutput(
            template: template,
            title: creation.title,
            periodType: creation.periodType,
            paragraphs: creation.paragraphs.map { paragraph in
                GroundedParagraph(
                    id: paragraph.id,
                    text: paragraph.text,
                    anchors: paragraph.citations.map {
                        SourceAnchor(
                            memoryID: $0.memoryId,
                            sourceType: $0.sourceType,
                            availability: $0.availability
                        )
                    },
                    groundingStatus: paragraph.groundingStatus
                )
            },
            sourceMemoryCount: creation.sourceMemoryCount,
            sourceTypes: creation.sourceTypes,
            emptyReason: creation.emptyReason
        )
    }

    /// 重试 (L2 恢复路径) — error → generating; empty → generating。
    func retry() {
        guard case .error = viewState else { return }
        viewState = .idle
        generate()
    }

    // MARK: - Prompt Editor Actions (US-SYN-005)

    /// 呈现 Prompt 编辑器 (AC-4)。
    func presentPromptEditor() {
        promptDraftText = confirmedPrompt
        isPromptEditorPresented = true
    }

    /// 确认编辑后的 Prompt 草稿 (AC-4/AC-5)。
    ///
    /// 非空校验后更新生效草稿；后续合成请求注入（🔮 Phase 3.9）。
    func confirmPrompt() {
        let trimmed = promptDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        confirmedPrompt = trimmed
        isPromptEditorPresented = false
    }

    /// 重置为默认 Prompt (AC-6)。
    func resetPrompt() {
        confirmedPrompt = CreationPromptDefaults.defaultDraft
        promptDraftText = confirmedPrompt
        isPromptEditorPresented = false
    }

    /// 取消 Prompt 编辑，不保存。
    func cancelPromptEdit() {
        isPromptEditorPresented = false
    }

    // MARK: - Fixture Injection

    /// Enables deterministic generation only for an explicit Preview/test journey.
    /// Production composition never calls this method and therefore remains fail-closed.
    func enableFixtureGeneration() {
        isFixtureBacked = true
        stubCreation = nil
        creation = nil
        viewState = .idle
    }

    /// 预加载确定性创作结果（Preview / 测试 / XCUITest fixture 注入）。
    func loadPreloaded(_ model: CreationModel) {
        isFixtureBacked = true
        stubCreation = model
        creation = model
        selectedTemplate = model.selectedTemplate
        if model.emptyReason != nil {
            viewState = .empty
        } else {
            viewState = .generated
        }
    }

    /// 注入 Prompt 草稿态 (Preview / 测试)。
    func loadPromptDraft(_ draft: String) {
        promptDraftText = draft
        confirmedPrompt = draft
    }

    /// 仅 Preview/调试使用 — 直接构造错误状态，不触发任何副作用。
    /// 生产路径的错误由 generate() 的 catch 自然产生，不调用此方法。
    func simulateError(_ level: ErrorLevel) {
        viewState = .error(level)
    }

    /// 注入 grounded 创作源记忆（US-SYN-003 AC-2: 严格引用检索结果）。
    ///
    /// 生产路径从检索结果映射 `CreativeSource` 后调用；UI 切片/测试可注入确定性源。
    func loadSourceMemories(_ sources: [CreativeSource]) {
        sourceMemories = sources
    }

    /// 消除错误状态，返回 idle。
    func dismissError() {
        viewState = .idle
    }

    // MARK: - Lifecycle

    deinit {}

    /// 视图消失时调用 — 取消进行中的任务。
    func onDisappear() {
        generateTask?.cancel()
        generateTask = nil
        exportTask?.cancel()
        exportTask = nil
        activeSharePayload = nil
        presentedPayloadIDs.removeAll()
        sharePayload = nil
    }
}
