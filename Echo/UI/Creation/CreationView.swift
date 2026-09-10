// ==========================================
// 文件: CreationView.swift
// i18n: All user-facing strings are hardcoded English. Full String Catalog migration (zh-Hans + en-US) deferred to Phase 3.9.
// 对应规格: docs/01-spec/用户故事与验收标准规格书.md → US-SYN-003 (情感内容生成+保存到备忘录),
//            US-SYN-004 (月度/年度叙事报告), US-SYN-005 (私有 Prompt 草稿)
//            docs/ui/echo-memory-canvas-style.md §3.2 (Focus surfaces — 单列 + grouped metadata),
//            §4 (共享 Token), §7.1 (Focus 共享表达), §10.1.2 (数据加载失败空态),
//            docs/ui/architecture.md §3 (Surface View), §8 (Focus family)
// Task: 4.0b + 4.0i + 4.0j - Balanced Focus surface and persistent report library
// AC coverage: US-SYN-003 AC-1 ✅ (template selection), AC-2 ✅ (stable source routing),
//              AC-3 ✅ (preview/copy/export), AC-4 ✅ (system share handoff),
//              AC-5 ✅ (no fabricated Notes result),
//          US-SYN-004 AC-4 ✅ (分享/导出/打印), AC-5 ✅ (标题含报告周期),
//          US-SYN-005 AC-4 ✅ (Prompt 草稿可编辑确认), AC-6 ✅ (重置为默认)
//          PR #44 review: W-1 ✅ (移除 example.com 外链回退), W-2 ✅ (Toast accessibility .contain)
// 架构约束: AGENTS.md §8.1 (ViewModel 驱动), §17.3 (Focus 禁止 masonry),
//           echo-memory-canvas apple-native 基础; 系统容器 + semantic colors + Dynamic Type
// 生成时间: 2026-08-02 | Updated: 2026-09-07 (4.0j report library)
// ==========================================

import SwiftUI
import UIKit

// MARK: - CreationView

/// AI 创作结果主视图 — 模板选择 + 生成预览 + 复制/导出/保存 + Prompt 草稿编辑。
///
/// ## Surface Family: Focus
/// - 布局: 单列内容流 + grouped metadata（echo-memory-canvas §3.2/§7.1）
/// - 系统容器: NavigationStack (由 MemoryDetailView push) + ScrollView + Form sheet (Prompt 编辑器) + confirmationDialog + Toast
/// - Masonry: **明确禁止**（Focus surface §3.2, §8.1）
///
/// ## 状态驱动
/// - idle: 模板选择 + 生成按钮 + Prompt 编辑入口
/// - generating: ProgressView
/// - generated: 生成内容 + 溯源锚点 + 复制/导出/保存/分享
/// - empty: 无匹配源记忆空态
/// - error: L2 重试横幅
/// - share handoff: local payload presented through a system ShareLink surface
///
/// ## Style
/// - echo-memory-canvas token: .title/.body/.caption, Color.primary, semantic colors, SF Symbols
/// - 禁止 masonry, 禁止 Pinterest 品牌元素
/// - 使用系统 Dynamic Type, semantic colors, 系统容器
struct CreationView: View {
    // MARK: - ViewModel

    @State private var viewModel: CreationViewModel
    @State private var reportPendingDeletion: UUID?
    @State private var isLibraryPresented = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.echoDesignProfile) private var designProfile

    private let returnsToLibrary: Bool

    init(viewModel: CreationViewModel? = nil, returnsToLibrary: Bool = false) {
        self.returnsToLibrary = returnsToLibrary
        _viewModel = State(
            initialValue: viewModel
                ?? CreationViewModel(
                    creativePipeline: AppComposition.shared.creativePipeline,
                    exportCoordinator: LiveAppAdapters.makeCreationExportCoordinator(),
                    narrativeReportActor: AppComposition.shared.narrativeReportActor,
                    creationLibrary: AppComposition.shared.creationLibraryActor
                )
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EchoColorToken.canvasBackground.color)
        }
        .navigationTitle("AI Creation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Prompt 草稿编辑入口 (US-SYN-005 AC-4)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.presentPromptEditor()
                } label: {
                    Label("Personal Prompt", systemImage: "person.text.rectangle")
                }
                .accessibilityIdentifier("creation-edit-prompt")
            }
        }
        .sheet(isPresented: $viewModel.isPromptEditorPresented) {
            PromptEditorSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isLibraryPresented) {
            NavigationStack {
                CreationLibraryView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isLibraryPresented = false }
                        }
                    }
            }
        }
        // 导出格式选择 (US-SYN-003 AC-3)
        .confirmationDialog(
            "Export creation",
            isPresented: $viewModel.isExportPickerPresented,
            titleVisibility: .visible
        ) {
            ForEach(CreationViewModel.ExportFormat.allCases, id: \.self) { format in
                Button(format.displayName) {
                    viewModel.export(format: format)
                }
                .accessibilityIdentifier("creation-export-\(format.rawValue)")
            }

            Button("Cancel", role: .cancel) {
                viewModel.isExportPickerPresented = false
            }
        } message: {
            Text("Choose a format for this creation.")
        }
        .confirmationDialog(
            EchoStrings.tr("Delete narrative report?"),
            isPresented: Binding(
                get: { reportPendingDeletion != nil },
                set: { if !$0 { reportPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(EchoStrings.tr("Delete report"), role: .destructive) {
                guard let reportID = reportPendingDeletion else { return }
                reportPendingDeletion = nil
                viewModel.deleteReport(reportID)
            }
            Button(EchoStrings.tr("Cancel"), role: .cancel) {
                reportPendingDeletion = nil
            }
        } message: {
            Text(EchoStrings.tr("This report cannot be regenerated in this version."))
        }
        // 分享/导出/打印 Sheet (US-SYN-003 AC-3, US-SYN-004 AC-4)
        .sheet(
            item: $viewModel.sharePayload,
            onDismiss: {
                viewModel.shareSheetDidDismiss()
            }
        ) { payload in
            SystemShareSheet(payload: payload, reporter: viewModel)
        }
        .navigationDestination(item: $viewModel.navigationMemoryID) { memoryID in
            MemoryDetailView(memoryId: memoryID)
        }
        .onAppear {
            viewModel.loadReportLibrary()
            #if DEBUG
                handleLaunchArguments()
            #endif
        }
        .onDisappear { viewModel.onDisappear() }
        .animation(.easeInOut(duration: 0.25), value: viewModel.viewState)
        .accessibilityIdentifier("creation-surface-\(designProfile.id)")
    }

    // MARK: - Launch Argument Fixture Injection

    #if DEBUG
        /// 处理 XCUITest / Live Sim Review 启动参数注入确定性 fixture。
        ///
        /// Supports `-ui-fixture creation-generated-letter|creation-generated-report|creation-empty`.
        /// 及 `-creation-error`，通过 CreationFixtureLoader 加载确定性数据。
        /// 仅用于自动化；生产构建（#if DEBUG 排除）无此钩子。
        private func handleLaunchArguments() {
            let args = ProcessInfo.processInfo.arguments
            guard let idx = args.firstIndex(of: "-ui-fixture"), idx + 1 < args.count else { return }
            let fixtureID = args[idx + 1]
            if let model = CreationFixtureLoader.load(fixtureID) {
                viewModel.loadPreloaded(model)
            } else if fixtureID == "creation-error" {
                viewModel.simulateError(
                    .l2Recoverable(message: "Generation is currently unavailable. Please try again.")
                )
            }
        }
    #endif

    // MARK: - Content Views

    /// 根据 ViewState 渲染对应内容
    @ViewBuilder
    private var contentView: some View {
        switch viewModel.viewState {
        case .idle:
            idleState

        case .waitingForResources:
            VStack(spacing: EchoSpacingToken.normal.points) {
                Text("Waiting for device resources")
                Text("Generation is paused for device resources. Continue when the device is ready.")
                    .foregroundStyle(.secondary)
                Button("Continue") { viewModel.retry() }
                    .buttonStyle(EchoActionButtonStyle(role: .recovery))
                    .accessibilityIdentifier("creation-continue-resources")
                Button("View Creation Library") {
                    if returnsToLibrary { dismiss() } else { isLibraryPresented = true }
                }
            }
            .padding()

        case .generating:
            generatingState

        case .generated:
            if let creation = viewModel.creation {
                generatedContent(creation)
            } else {
                emptyState
            }

        case .empty:
            emptyState

        case .error(let level):
            errorView(level: level)
        }
    }

    // MARK: - Idle State

    /// 初始态 — 模板选择 + 生成按钮 (US-SYN-003 AC-1)。
    private var idleState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EchoSpacingToken.section.points) {
                reportLibrarySection
                photoPreparationSection

                EchoSectionHeader(
                    title: "Choose a template",
                    subtitle: "Ground the creation in memories already stored on this device."
                )

                // 模板选择
                ForEach(CreationTemplate.allCases, id: \.self) { template in
                    templateRow(template)
                }

                // 生成按钮
                generateButton
            }
            .padding(EchoSpacingToken.grouped.points)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var reportLibrarySection: some View {
        VStack(alignment: .leading, spacing: EchoSpacingToken.grouped.points) {
            EchoSectionHeader(
                title: "Narrative reports",
                subtitle: "Monthly and yearly reports are generated on device after a period ends."
            )

            if let schedule = viewModel.reportSchedule {
                EchoContainer(level: .section) {
                    VStack(spacing: EchoSpacingToken.normal.points) {
                        Toggle(
                            EchoStrings.tr("Monthly reports"),
                            isOn: Binding(
                                get: { schedule.monthlyEnabled },
                                set: { viewModel.setReportSchedule($0, for: .month) }
                            )
                        )
                        .accessibilityIdentifier("creation-report-monthly-toggle")
                        Toggle(
                            EchoStrings.tr("Yearly reports"),
                            isOn: Binding(
                                get: { schedule.yearlyEnabled },
                                set: { viewModel.setReportSchedule($0, for: .year) }
                            )
                        )
                        .accessibilityIdentifier("creation-report-yearly-toggle")
                    }
                }
            }

            Button {
                viewModel.scanNarrativeReportsNow()
            } label: {
                Label(EchoStrings.tr("Check for completed periods"), systemImage: "calendar.badge.clock")
            }
            .buttonStyle(EchoActionButtonStyle(role: .secondary))
            .accessibilityIdentifier("creation-report-scan")

            switch viewModel.reportLibraryState {
            case .loading:
                ProgressView(EchoStrings.tr("Loading narrative reports…"))
                    .accessibilityIdentifier("creation-report-library-loading")

            case .modelBlocked:
                EchoContainer(level: .emphasized) {
                    VStack(alignment: .leading, spacing: EchoSpacingToken.normal.points) {
                        EchoStatusPresentation(
                            role: .warning,
                            systemImage: "exclamationmark.triangle.fill",
                            title: EchoStrings.tr("Reports unavailable"),
                            message: EchoStrings.tr(ErrorSeverity.l3Blocking.userFacingMessageKey)
                        )
                        Button(EchoStrings.tr("Retry model load")) { viewModel.repairReportRuntime() }
                            .buttonStyle(EchoActionButtonStyle(role: .recovery))
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Settings", destination: url)
                        }
                    }
                }

            case .error(let message):
                EchoContainer(level: .emphasized) {
                    VStack(alignment: .leading, spacing: EchoSpacingToken.normal.points) {
                        EchoStatusPresentation(
                            role: .warning,
                            systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                            title: EchoStrings.tr("Reports unavailable"),
                            message: message
                        )
                        Button(EchoStrings.tr("Retry")) {
                            viewModel.loadReportLibrary()
                        }
                        .buttonStyle(EchoActionButtonStyle(role: .recovery))
                        .accessibilityIdentifier("creation-report-library-retry")
                    }
                }

            case .idle, .loaded:
                EmptyView()
            }

            ForEach(viewModel.recoverableReportPeriods) { period in
                EchoContainer(level: .emphasized) {
                    HStack {
                        VStack(alignment: .leading, spacing: EchoSpacingToken.compact.points) {
                            Text(period.periodKey)
                                .font(EchoTypographyToken.body.font)
                            Text(EchoStrings.tr("Generation needs your retry."))
                                .font(EchoTypographyToken.caption.font)
                                .foregroundStyle(EchoColorToken.secondaryText.color)
                        }
                        Spacer()
                        Button(EchoStrings.tr("Retry")) {
                            viewModel.retryReport(period)
                        }
                        .buttonStyle(EchoActionButtonStyle(role: .secondary))
                        .accessibilityIdentifier("creation-report-retry-\(period.periodKey)")
                    }
                }
            }

            ForEach(viewModel.narrativeReports) { report in
                EchoContainer(level: .card) {
                    HStack(spacing: EchoSpacingToken.normal.points) {
                        Button {
                            viewModel.openReport(report.id)
                        } label: {
                            VStack(alignment: .leading, spacing: EchoSpacingToken.compact.points) {
                                Text(report.envelope.title)
                                    .font(EchoTypographyToken.body.font)
                                    .foregroundStyle(EchoColorToken.primaryText.color)
                                Text(report.periodKey)
                                    .font(EchoTypographyToken.caption.font)
                                    .foregroundStyle(EchoColorToken.secondaryText.color)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("creation-report-open-\(report.id.uuidString)")

                        Button(role: .destructive) {
                            reportPendingDeletion = report.id
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(EchoStrings.tr("Delete narrative report"))
                        .accessibilityIdentifier("creation-report-delete-\(report.id.uuidString)")
                    }
                }
            }
        }
        .accessibilityIdentifier("creation-report-library")
    }

    /// 单个模板行 — 选择 + 展示。
    private func templateRow(_ template: CreationTemplate) -> some View {
        let isSelected = viewModel.selectedTemplate == template
        return Button {
            viewModel.selectTemplate(template)
        } label: {
            HStack(spacing: EchoSpacingToken.normal.points) {
                Image(systemName: template.systemImage)
                    .font(EchoTypographyToken.subtitle.font)
                    .foregroundStyle(
                        isSelected
                            ? EchoColorToken.warmAccent.color
                            : EchoColorToken.secondaryText.color
                    )

                Text(LocalizedStringKey(template.displayName))
                    .font(EchoTypographyToken.body.font)
                    .foregroundStyle(EchoColorToken.primaryText.color)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(EchoColorToken.warmAccent.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(EchoSpacingToken.grouped.points)
            .background(
                isSelected
                    ? EchoContainerLevel.emphasized.background
                    : EchoContainerLevel.card.background
            )
            .compositingGroup()
            .clipShape(.rect(cornerRadius: EchoRadiusToken.card.points))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(template.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("creation-template-\(template.rawValue)")
    }

    /// 生成按钮 — 选择模板后启用。
    private var generateButton: some View {
        Button {
            viewModel.generate()
        } label: {
            Label("Generate", systemImage: "sparkles")
                .font(.callout)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(EchoActionButtonStyle(role: .primary))
        .disabled(!viewModel.canGenerate)
        .accessibilityIdentifier("creation-generate")
    }

    // MARK: - Generating State

    /// 生成中 — 系统 ProgressView (echo-memory-canvas §10.2)。
    private var generatingState: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .tint(EchoColorToken.warmAccent.color)
                .controlSize(.large)

            Text("Generating…")
                .font(EchoTypographyToken.metadata.font)
                .foregroundStyle(EchoColorToken.secondaryText.color)

            if viewModel.libraryRequestID != nil {
                Text("You can browse Echo while this creation continues.")
                    .font(.footnote)
                if returnsToLibrary {
                    Button("View Creation Library") { dismiss() }
                        .accessibilityIdentifier("creation-library-return")
                } else {
                    Button("View Creation Library") { isLibraryPresented = true }
                        .accessibilityIdentifier("creation-library-open-from-creation")
                }
            }
            Spacer().frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Generated Content

    /// 生成内容 — 单列内容流 + 溯源锚点 + 操作按钮 (US-SYN-003/004)。
    private func generatedContent(_ creation: CreationModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EchoSpacingToken.section.points) {
                // Keep the selected form visible after generation; reports retain their period title.
                Text(creation.title ?? EchoStrings.tr(creation.selectedTemplate.displayName))
                    .font(EchoTypographyToken.title.font)
                    .foregroundStyle(EchoColorToken.primaryText.color)
                    .accessibilityAddTraits(.isHeader)

                // 来源计数 metadata
                EchoMetadataGroup {
                    Label(
                        String(
                            format: EchoStrings.tr("%lld source memories"),
                            creation.sourceMemoryCount
                        ),
                        systemImage: "link"
                    )
                    if let coverage = creation.reportCoverage {
                        Text(coverage.coverageStart..<coverage.coverageEnd, format: .interval.day().month().year())
                        if coverage.partialBaseline {
                            Text(EchoStrings.tr("This report covers part of the period."))
                        }
                        if coverage.truncatedSourceCount > 0 {
                            Text(
                                String(
                                    format: EchoStrings.tr("%lld source memories omitted by generation limits"),
                                    coverage.truncatedSourceCount
                                )
                            )
                        }
                        if !coverage.omittedPartitions.isEmpty {
                            Text(EchoStrings.tr("Some source categories are not included."))
                        }
                        if let omitted = creation.omittedParagraphCount, omitted > 0 {
                            Text(String(format: EchoStrings.tr("%lld intermediate paragraphs omitted"), omitted))
                        }
                    }
                }

                // 生成内容 + 溯源锚点
                EchoContainer(level: .section) {
                    VStack(
                        alignment: .leading,
                        spacing: creation.selectedTemplate == .poem
                            ? EchoSpacingToken.compact.points : EchoSpacingToken.grouped.points
                    ) {
                        ForEach(creation.paragraphs) { paragraph in
                            VStack(alignment: .leading, spacing: EchoSpacingToken.compact.points) {
                                Text(paragraph.text)
                                    .font(EchoTypographyToken.body.font)
                                    .foregroundStyle(EchoColorToken.primaryText.color)
                                    .textSelection(.enabled)

                                if creation.selectedTemplate != .poem {
                                    ForEach(paragraph.citations, id: \.memoryId) { citation in
                                        citationAnchor(citation)
                                    }
                                }

                                if paragraph.groundingStatus != .cited {
                                    Label(
                                        EchoStrings.tr("No source for part or all of this paragraph"),
                                        systemImage: "exclamationmark.triangle"
                                    )
                                    .font(EchoTypographyToken.caption.font)
                                    .foregroundStyle(EchoColorToken.secondaryText.color)
                                    .accessibilityIdentifier("creation-citation-no-source")
                                }
                            }
                        }
                    }
                }

                if creation.selectedTemplate == .poem {
                    let citations = creation.distinctSourceCitations
                    EchoMetadataGroup {
                        ForEach(Array(citations.enumerated()), id: \.element.memoryId) { index, citation in
                            citationAnchor(
                                citation,
                                title: citations.count == 1
                                    ? EchoStrings.tr("Source memory")
                                    : String(format: EchoStrings.tr("Source memory %lld"), index + 1)
                            )
                        }
                    }
                }

                // 操作按钮 (US-SYN-003 AC-3/AC-4, US-SYN-004 AC-4)
                actionButtons
            }
            .padding(EchoSpacingToken.grouped.points)
        }
        .scrollContentBackground(.hidden)
    }

    /// Human-readable source navigation; opaque identities stay in the route and accessibility identifier.
    private func citationAnchor(_ citation: CreationCitation, title: String? = nil) -> some View {
        Button {
            viewModel.openCitation(citation)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: citation.availability == .available ? "link" : "link.badge.plus")
                    .font(EchoTypographyToken.caption.font)
                Text(title ?? EchoStrings.tr("Source memory"))
                    .font(EchoTypographyToken.caption.font)
            }
            .foregroundStyle(
                citation.availability == .available
                    ? EchoColorToken.warmAccent.color
                    : EchoColorToken.secondaryText.color
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("creation-citation-anchor-\(citation.memoryId.uuidString.prefix(8))")
        .accessibilityLabel(Text(title ?? EchoStrings.tr("Open source memory citation")))
        .accessibilityValue(
            Text(
                citation.availability == .available
                    ? EchoStrings.tr("Source available")
                    : EchoStrings.tr("Source currently unavailable")
            )
        )
    }

    /// 操作按钮行 — 复制 / 导出 / 保存 / 分享。
    private var actionButtons: some View {
        VStack(spacing: EchoSpacingToken.normal.points) {
            // 复制 (AC-3)
            Button {
                viewModel.copyToClipboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.callout)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EchoActionButtonStyle(role: .secondary))
            .accessibilityIdentifier("creation-copy")

            // 导出 (AC-3)
            Button {
                viewModel.presentExportPicker()
            } label: {
                Label("Export PDF / Markdown", systemImage: "square.and.arrow.up")
                    .font(.callout)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EchoActionButtonStyle(role: .secondary))
            .accessibilityIdentifier("creation-export")

            // 分享/打印 (US-SYN-004 AC-4)
            Button {
                viewModel.presentShare()
            } label: {
                Label("Share / Print", systemImage: "square.and.arrow.up.on.square")
                    .font(.callout)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EchoActionButtonStyle(role: .secondary))
            .accessibilityIdentifier("creation-share")

            // 保存到备忘录 (AC-4)
            Button {
                viewModel.saveToNotes()
            } label: {
                Label("Save to Notes", systemImage: "square.and.pencil")
                    .font(.callout)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EchoActionButtonStyle(role: .primary))
            .accessibilityIdentifier("creation-save-to-notes")
        }
    }

    // MARK: - Empty State (US-SYN-003 无匹配源记忆)

    /// 空态 — 无匹配源记忆 (echo-memory-canvas §10.1.2 Focus 空态)。
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            photoPreparationSection

            EchoContainer(level: .section) {
                EchoStatusPresentation(
                    role: .informational,
                    systemImage: "tray",
                    title: EchoLocalization.localized(
                        viewModel.requiresSourceText
                            ? "Creation material is not ready" : "No source memories found",
                        locale: locale
                    ),
                    message: EchoLocalization.localized(
                        viewModel.requiresSourceText
                            ? "Prepare photo material or choose another available memory, then try creation again."
                            : "Try a different template or add more memories.",
                        locale: locale
                    )
                )
            }

            Button("Choose a template again") { viewModel.dismissError() }
                .buttonStyle(EchoActionButtonStyle(role: .recovery))

            Button {
                dismiss()
            } label: {
                Label("Back to memories", systemImage: "arrow.backward").font(.callout)
            }
            .buttonStyle(EchoActionButtonStyle(role: .recovery))
            .accessibilityIdentifier("creation-back-to-memories")

            Spacer().frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Error State

    @ViewBuilder private var photoPreparationSection: some View {
        if !viewModel.isFixtureBacked {
            if !viewModel.photoSourceIDs.isEmpty, !viewModel.photoMaterialsReady {
                Text("Wait for photo understanding, or add a description in memory details, before generating.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("creation-photo-material-required")
            }
            ForEach(viewModel.photoSourceIDs, id: \.self) { memoryID in
                PhotoPreparationView(memoryID: memoryID, service: AppComposition.shared.photoUnderstandingActor) { ready in
                    viewModel.updatePhotoReadiness(memoryID: memoryID, ready: ready)
                }
            }
        }
    }

    /// 错误视图 — L2 重试横幅 (docs/ui/architecture.md §2.2)。
    private func errorView(level: CreationViewModel.ErrorLevel) -> some View {
        VStack(spacing: 16) {
            Spacer()

            EchoContainer(level: .section) {
                EchoStatusPresentation(
                    role: .warning,
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Unable to generate",
                    message: EchoStrings.tr(errorMessage(for: level))
                )
            }

            if case .l3Blocking = level {
                Button {
                    viewModel.retryModelLoad()
                } label: {
                    Label("Retry model load", systemImage: "arrow.clockwise")
                }
                .buttonStyle(EchoActionButtonStyle(role: .recovery))
                .accessibilityIdentifier("creation-retry-model")
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: settingsURL) {
                        Label("Open Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(EchoActionButtonStyle(role: .recovery))
                }
            } else {
                Button {
                    viewModel.retry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise").font(EchoTypographyToken.action.font)
                }
                .buttonStyle(EchoActionButtonStyle(role: .recovery))
                .accessibilityIdentifier("creation-retry-button")
            }

            Spacer().frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EchoColorToken.canvasBackground.color)
    }

    private func errorMessage(for level: CreationViewModel.ErrorLevel) -> String {
        switch level {
        case .l2Recoverable(let msg), .l3Blocking(let msg):
            return msg
        }
    }
}

// MARK: - PromptEditorSheet

/// Prompt 草稿编辑器 (US-SYN-005 AC-4) — 可编辑确认 + 重置为默认。
///
/// ## Surface Family: Task
/// - Form 布局（Task/Focus 共享 Form 容器，非 masonry）
/// - 字段: Prompt 草稿多行文本 + 确认/取消 + 重置
struct PromptEditorSheet: View {
    @Bindable var viewModel: CreationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $viewModel.promptDraftText)
                        .frame(minHeight: 160)
                        .accessibilityIdentifier("creation-prompt-editor")
                } header: {
                    Text("Personal Prompt")
                } footer: {
                    Text("Used to personalize AI responses. Confirmed drafts are injected into synthesis requests.")
                }

                Section {
                    Button(role: .destructive) {
                        viewModel.resetPrompt()
                        dismiss()
                    } label: {
                        Label("Reset to default prompt", systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityIdentifier("creation-reset-prompt")
                }
            }
            .navigationTitle("Personal Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        viewModel.cancelPromptEdit()
                    }
                    .accessibilityIdentifier("creation-prompt-cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        viewModel.confirmPrompt()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("creation-confirm-prompt")
                }
            }
        }
    }
}

// MARK: - SystemShareSheet

/// 分享 Sheet — 生成内容分享/导出/打印 (US-SYN-003 AC-3, US-SYN-004 AC-4)。
///
/// ## Surface Family: Focus
/// - 系统分享面板，非 masonry
struct SystemShareSheet: UIViewControllerRepresentable {
    let payload: CreationSharePayload
    let reporter: any CreationSharePresentationReporting

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let item: Any
        if let attachmentURL = payload.attachmentURL {
            item = attachmentURL
        } else {
            item = payload.text
        }
        return ReportingActivityViewController(
            activityItems: [item],
            payloadID: payload.id,
            reporter: reporter
        )
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
    }
}

@MainActor
private final class ReportingActivityViewController: UIActivityViewController {
    private let payloadID: UUID
    private weak var presentationReporter: (any CreationSharePresentationReporting)?
    private var didReportPresentation = false

    deinit {}

    init(
        activityItems: [Any],
        payloadID: UUID,
        reporter: any CreationSharePresentationReporting
    ) {
        self.payloadID = payloadID
        self.presentationReporter = reporter
        super.init(activityItems: activityItems, applicationActivities: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didReportPresentation else { return }
        didReportPresentation = true
        presentationReporter?.shareControllerDidAppear(payloadID: payloadID)
    }
}

// MARK: - Preview

#Preview("Idle") {
    NavigationStack {
        CreationView(viewModel: makeCreationViewModel(state: .idle))
    }
}

#Preview("Generating") {
    NavigationStack {
        CreationView(viewModel: makeCreationViewModel(state: .generating))
    }
}

#Preview("Generated Letter") {
    NavigationStack {
        CreationView(viewModel: makeCreationViewModel(state: .generatedLetter))
    }
}

#Preview("Generated Report") {
    NavigationStack {
        CreationView(viewModel: makeCreationViewModel(state: .generatedReport))
    }
}

#Preview("Empty") {
    NavigationStack {
        CreationView(viewModel: makeCreationViewModel(state: .empty))
    }
}

#Preview("Error") {
    NavigationStack {
        CreationView(viewModel: makeCreationViewModel(state: .error))
    }
}

// MARK: - Preview Helpers

/// 从 fixture 构造确定性创作结果。
@MainActor
private func makeCreationViewModel(state: CreationPreviewState) -> CreationViewModel {
    let vm = CreationViewModel()

    switch state {
    case .idle:
        break

    case .generating:
        vm.selectTemplate(.letter)
        vm.generate()

    case .generatedLetter:
        if let model = CreationFixtureLoader.load("creation-generated-letter") {
            vm.loadPreloaded(model)
        }

    case .generatedReport:
        if let model = CreationFixtureLoader.load("creation-generated-report") {
            vm.loadPreloaded(model)
        }

    case .empty:
        if let model = CreationFixtureLoader.load("creation-empty") {
            vm.loadPreloaded(model)
        }

    case .error:
        vm.simulateError(.l2Recoverable(message: "Generation is currently unavailable. Please try again."))
    }

    return vm
}

/// Preview 状态枚举
private enum CreationPreviewState {
    case idle
    case generating
    case generatedLetter
    case generatedReport
    case empty
    case error
}
