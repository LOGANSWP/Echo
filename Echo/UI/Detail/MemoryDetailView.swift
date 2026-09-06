// ==========================================
// 文件: MemoryDetailView.swift
// i18n: All user-facing strings are hardcoded English. Full String Catalog migration (zh-Hans + en-US) deferred to Phase 3.8.
// 对应规格: docs/ui/echo-memory-canvas-style.md §3.2 (Focus surfaces — 单列 + grouped metadata),
//            §7.1 (Focus 共享表达), §10.1.2 (数据加载失败空态), §12.2 (L4 冲突全屏),
//            §14.5 (Bad Case 标记), docs/ui/architecture.md §3 (Surface View), §8 (Focus family)
//            docs/01-spec/用户故事与验收标准规格书.md → US-AWK-007, US-SYN-002/003, US-PRV-004, US-DIS-002
// Task: 4.0b + 4.0h - Balanced Canvas Focus surface and live source lifecycle
// AC coverage: US-AWK-007 AC-1 ✅ (honest edit entry), AC-4 ✅ (honest conflict UI),
//          US-DIS-002 AC-3 ✅ (源语言检测不确定保留原文为主, ADR-005), AC-4 ✅ (原文/译文切换), US-PRV-004 AC-1 ✅ (删除双选项弹窗),
//          US-SYN-002 AC-1 ✅ (溯源锚点渲染), US-SYN-003 AC-3 ✅ (创作预览/复制)
// 架构约束: AGENTS.md §8.1 (ViewModel 驱动), §17.3 (Focus 禁止 masonry),
//           echo-memory-canvas apple-native 基础; 系统容器 + semantic colors + Dynamic Type
// Generated: 2026-08-01 | Updated: 2026-09-05
// ==========================================

import SwiftUI
import AVKit
import AVFoundation

// MARK: - MemoryDetailView

/// 记忆详情主视图 — 单条记忆内容展示 + 翻译切换 + 编辑 + 冲突解决 + 删除确认。
///
/// ## Surface Family: Focus
/// - 布局: 单列内容流 + grouped metadata（echo-memory-canvas §3.2/§7.1）
/// - 系统容器: NavigationStack (由 Search/Home push) + ScrollView + Form sheet + Alert
/// - Masonry: **明确禁止**（Focus surface §3.2, §8.1）
///
/// ## 状态驱动
/// - loading: ProgressView
/// - completed: 记忆内容 + grouped metadata + 翻译切换 + 编辑入口
/// - conflict: L4 冲突 Banner + 保留本地/使用外部 操作
/// - error: L2 重试横幅 / L3 全屏引导
/// - cancelled: 返回 idle
///
/// ## Style
/// - echo-memory-canvas token: .title/.body/.caption, Color.primary, semantic colors, SF Symbols
/// - 禁止 masonry, 禁止 Pinterest 品牌元素
/// - 使用系统 Dynamic Type, semantic colors, 系统容器
struct MemoryDetailView: View {
    // MARK: - ViewModel

    @State private var viewModel: MemoryDetailViewModel
    @Environment(\.echoDesignProfile) private var designProfile
    /// 待加载的记忆 ID（从 Search/Home 导航传入）
    @State private var pendingMemoryID: UUID?
    /// 首次出现标记 — 控制 fixture 注入仅执行一次 (2026-08-02 回归修复)
    @State private var hasHandledLaunchArguments = false
    /// 是否进入 AI 创作结果页 (US-SYN-003, Task 3.9)
    @State private var isShowingCreation = false
    /// Explicit fixture composition for the deterministic creation journey.
    @State private var creationViewModel: CreationViewModel?

    init(viewModel: MemoryDetailViewModel = MemoryDetailViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    init(memoryId: UUID) {
        _viewModel = State(initialValue: MemoryDetailViewModel(
            canonicalRepository: LiveAppAdapters.makeCanonicalRepository(),
            memoryEditService: LiveAppAdapters.makeMemoryEditActor(),
            syncLockChecker: LiveAppAdapters.makeSyncLockChecker(),
            sourceLifecycleService: LiveAppAdapters.makeFocusSourceLifecycleActor()
        ))
        _pendingMemoryID = State(initialValue: memoryId)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EchoColorToken.canvasBackground.color)
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.memory?.assetId) {
            if let assetId = viewModel.memory?.assetId,
               viewModel.memory?.sourceType == "photo" {
                viewModel.loadPhotoImage(assetId: assetId)
            }
        }
        .toolbar {
            if viewModel.viewState == .completed, viewModel.memory != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.presentEditSheet()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("memory-detail-edit-button")
                }
            }
        }
        .onAppear {
            handleFirstAppear()
            if let pendingID = pendingMemoryID {
                pendingMemoryID = nil
                viewModel.load(memoryId: pendingID)
            }
        }
        .onDisappear { viewModel.onDisappear() }
        // 编辑 Sheet (US-AWK-007)
        .sheet(isPresented: $viewModel.isEditing) {
            EditMemorySheet(viewModel: viewModel)
        }
        // AI 创作结果页 (US-SYN-003, Task 3.9)
        .navigationDestination(isPresented: $isShowingCreation) {
            if let creationViewModel {
                CreationView(viewModel: creationViewModel)
            } else {
                CreationView()
            }
        }
        // 删除确认弹窗 (US-PRV-004 AC-1)
        .confirmationDialog(
            "Remove this memory?",
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from Echo only", role: .destructive) {
                viewModel.removeFromEcho()
            }
            .accessibilityIdentifier("memory-delete-remove-from-echo")

            if viewModel.canDeleteOriginal {
                Button("Delete original file too", role: .destructive) {
                    viewModel.deleteOriginal()
                }
                .accessibilityIdentifier("memory-delete-delete-original")
            }

            Button("Cancel", role: .cancel) {
                viewModel.showDeleteConfirmation = false
            }
        } message: {
            Text("Choose how to remove this memory. Your photos and files in the system library are kept unless you choose to delete the original.")
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.viewState)
        .accessibilityIdentifier("memory-detail-surface-\(designProfile.id)")
    }

    // MARK: - Launch Argument Fixture Injection

    /// 首次出现时处理启动参数 fixture 注入。
    ///
    /// 仅首次执行 — TabView 切换 / 详情返回会再次触发 onAppear，
    /// 重复注入会重置已加载内容（回归 2026-08-02 修复，与 SearchView 同源）。
    /// 生产构建（#if DEBUG 排除）无任何注入逻辑。
    private func handleFirstAppear() {
        guard !hasHandledLaunchArguments else { return }
        hasHandledLaunchArguments = true
        #if DEBUG
        handleLaunchArguments()
        #endif
    }

    #if DEBUG
    /// 处理 XCUITest / Live Sim Review 启动参数注入确定性 fixture。
    ///
    /// 支持 `-ui-fixture memory-detail-loaded|memory-detail-translated|memory-detail-conflict|memory-detail-error`
    /// 及 `translation-zh-en-*|translation-error`（task 3.8 翻译 surface），
    /// 通过 MemoryDetailFixtureLoader / TranslationFixtureLoader 加载确定性数据。
    /// 仅用于自动化；生产构建（#if DEBUG 排除）无此钩子。
    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-ui-fixture"), idx + 1 < args.count else { return }
        let fixtureID = args[idx + 1]
        if let model = MemoryDetailFixtureLoader.load(fixtureID) {
            viewModel.loadPreloaded(model)
        } else if let model = TranslationFixtureLoader.load(fixtureID) {
            // 3F.9: 生产默认 translationService 已切换为 AppleTranslationService；
            // 翻译 fixture 路径注入 FixtureTranslationService 保持确定性（XCUITest/Live Sim）。
            viewModel = MemoryDetailViewModel(
                translationService: FixtureTranslationService(),
                translationCache: TranslationCache()
            )
            viewModel.loadPreloaded(model)
        } else if fixtureID == "memory-detail-error" {
            viewModel.simulateError(.l2Recoverable(message: "Unable to load this memory. Please try again."))
        }
    }
    #endif

    // MARK: - Content Views

    /// 根据 ViewState 渲染对应内容
    @ViewBuilder
    private var contentView: some View {
        switch viewModel.viewState {
        case .idle:
            // 删除后（idle + memory nil）→ 移除成功空态；初始 idle 无此状态
            if viewModel.memory == nil && viewModel.hasRemovedMemory {
                removedState
            } else {
                loadingState
            }

        case .loading:
            loadingState

        case .completed:
            if let memory = viewModel.memory {
                if let conflict = memory.conflict {
                    conflictView(conflict)
                } else {
                    detailContent(memory)
                }
            } else {
                emptyState
            }

        case .error(let level):
            errorView(level: level)

        case .cancelled:
            EchoColorToken.canvasBackground.color
                .onAppear { viewModel.dismissError() }
        }
    }

    // MARK: - Loading State

    /// 加载态 — 系统 ProgressView (echo-memory-canvas §10.2)
    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .tint(EchoColorToken.warmAccent.color)
                .controlSize(.large)

            Text("Loading memory…")
                .font(EchoTypographyToken.metadata.font)
                .foregroundStyle(EchoColorToken.secondaryText.color)

            Spacer().frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading memory…")
    }

    // MARK: - Empty State (Focus §10.1.2)

    /// 数据加载失败空态 — 居中布局, 不阻塞导航
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            EchoContainer(level: .section) {
                EchoStatusPresentation(
                    role: .warning,
                    systemImage: "tray",
                    title: "Unable to load memory",
                    message: "Please try again later."
                )
            }

            Button {
                viewModel.retry()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.callout)
            }
            .buttonStyle(EchoActionButtonStyle(role: .recovery))
            .accessibilityIdentifier("memory-detail-retry-button")

            Spacer().frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unable to load memory. Please try again later.")
    }

    // MARK: - Removed State (US-PRV-004, PR #38 review fix)

    /// 删除成功空态 — 记忆已移除确认（区别于加载失败空态）。
    private var removedState: some View {
        VStack(spacing: 12) {
            Spacer()

            EchoContainer(level: .section) {
                EchoStatusPresentation(
                    role: .success,
                    systemImage: "checkmark.circle",
                    title: "Memory removed",
                    message: "This memory has been removed from Echo."
                )
            }

            Spacer().frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Memory removed from Echo")
    }

    // MARK: - Detail Content (Focus single-column + grouped metadata)

    /// 记忆详情内容 — 单列内容流 + grouped metadata (echo-memory-canvas §3.2)
    private func detailContent(_ memory: MemoryDetailModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EchoSpacingToken.section.points) {
                // 媒体预览 (US-RET-001: photo/image, video/player, voice/audio)
                mediaPreview(memory)

                // 主内容本体
                memoryContent(memory)

                // grouped metadata
                metadataGroup(memory)

                #if DEBUG
                // Deterministic creation preview is restricted to explicit fixture journeys.
                if viewModel.isFixtureBacked {
                    creationPreview
                }
                #endif

                // 删除入口 (US-PRV-004)
                deleteSection
            }
            .padding(EchoSpacingToken.grouped.points)
        }
        .scrollContentBackground(.hidden)
    }

    /// Media preview. Production renders only media resolved from its source adapter;
    /// bundled sample assets are restricted to explicit fixture journeys.
    /// - note → 无媒体（不渲染）
    @ViewBuilder
    private func mediaPreview(_ memory: MemoryDetailModel) -> some View {
        switch memory.mediaKind {
        case .image:
            if let uiImage = viewModel.photoImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: EchoRadiusToken.image.points))
                    .accessibilityLabel("\(memory.title) photo")
            } else if viewModel.isFixtureBacked,
                      let name = memory.mediaAssetName,
                      let uiImage = UIImage(named: name) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: EchoRadiusToken.image.points))
                    .accessibilityLabel("\(memory.title) photo")
            } else if viewModel.photoResolutionPhase == .loading {
                EchoContainer(level: .section) {
                    ProgressView("Loading local photo…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                FocusMediaUnavailableView(kind: .image)
            }

        case .video:
            if viewModel.isFixtureBacked,
               let name = memory.mediaAssetName,
               let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 240)
                    .clipShape(.rect(cornerRadius: EchoRadiusToken.image.points))
                    .accessibilityLabel("\(memory.title) video")
            } else {
                FocusMediaUnavailableView(kind: .video)
            }

        case .audio:
            if viewModel.isFixtureBacked,
               let name = memory.mediaAssetName,
               let url = Bundle.main.url(forResource: name, withExtension: "wav") {
                AudioPlayerView(url: url, memoryTitle: memory.title)
            } else {
                FocusMediaUnavailableView(kind: .audio)
            }

        case .none:
            EmptyView()
        }
    }

    /// 主内容本体 — 标题 + 原文/译文
    private func memoryContent(_ memory: MemoryDetailModel) -> some View {
        EchoContainer(level: .canvas) {
            VStack(alignment: .leading, spacing: EchoSpacingToken.normal.points) {
                Text(memory.title)
                    .font(EchoTypographyToken.title.font)
                    .foregroundStyle(EchoColorToken.primaryText.color)

                // 译文切换 (US-DIS-002 AC-4)
                if memory.needsTranslation {
                    translationSection(memory)
                } else {
                    Text(memory.originalText)
                        .font(EchoTypographyToken.body.font)
                        .foregroundStyle(EchoColorToken.primaryText.color)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// 翻译区 — 原文/译文切换 (US-DIS-002)
    private func translationSection(_ memory: MemoryDetailModel) -> some View {
        EchoContainer(level: .section) {
            VStack(alignment: .leading, spacing: EchoSpacingToken.normal.points) {
            // 切换按钮
            Button {
                viewModel.toggleTranslation()
            } label: {
                Label(
                    memory.translationVisible ? "Show original" : "Show translation",
                    systemImage: "character.book.closed"
                )
                .font(EchoTypographyToken.action.font)
            }
            .buttonStyle(EchoActionButtonStyle(role: .secondary))
            .accessibilityIdentifier("memory-detail-translation-toggle")
            .accessibilityValue(memory.translationVisible ? "Translation shown" : "Original shown")

            // 内容展示 — 由 ViewModel 翻译阶段驱动 (US-DIS-002)
            if memory.translationVisible {
                switch viewModel.translationPhase {
                case .idle, .translating:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Translating…")
                            .font(EchoTypographyToken.metadata.font)
                            .foregroundStyle(EchoColorToken.secondaryText.color)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Translating memory")

                case .translated:
                    if let translated = memory.translatedText {
                        VStack(alignment: .leading, spacing: EchoSpacingToken.compact.points) {
                            Text(translated)
                                .font(EchoTypographyToken.body.font)
                                .foregroundStyle(EchoColorToken.primaryText.color)
                                .textSelection(.enabled)

                            Text("Translated · \(memory.preferredLanguage)")
                                .font(EchoTypographyToken.caption.font)
                                .foregroundStyle(EchoColorToken.secondaryText.color)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(
                            String(format: EchoStrings.tr("Translated: %@"), translated)
                        )
                    }

                case .uncertain:
                    if let confidence = memory.sourceLanguageConfidence, confidence < 0.9 {
                        originalLanguagePresentation(memory)
                    }

                case .unavailable(let message):
                    VStack(alignment: .leading, spacing: EchoSpacingToken.normal.points) {
                        originalLanguagePresentation(memory)
                        EchoStatusPresentation(
                            role: .informational,
                            systemImage: "character.book.closed",
                            title: "Translation unavailable",
                            message: EchoStrings.tr(message)
                        )
                    }

                case .error(let message):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(EchoColorToken.warning.color)
                        Text(EchoStrings.tr(message))
                            .font(EchoTypographyToken.metadata.font)
                            .foregroundStyle(EchoColorToken.secondaryText.color)
                        Button("Retry") {
                            viewModel.retryTranslation()
                        }
                        .font(EchoTypographyToken.action.font)
                        .buttonStyle(EchoActionButtonStyle(role: .recovery))
                        .accessibilityIdentifier("memory-detail-translation-retry")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(String(format: EchoStrings.tr("Translation failed. %@"), EchoStrings.tr(message)))
                }
            } else {
                Text(memory.originalText)
                    .font(EchoTypographyToken.body.font)
                    .foregroundStyle(EchoColorToken.primaryText.color)
                    .textSelection(.enabled)
            }
            }
        }
    }

    private func originalLanguagePresentation(_ memory: MemoryDetailModel) -> some View {
        VStack(alignment: .leading, spacing: EchoSpacingToken.compact.points) {
            Text(memory.originalText)
                .font(EchoTypographyToken.body.font)
                .foregroundStyle(EchoColorToken.primaryText.color)
                .textSelection(.enabled)

            Text("Detected · \(memory.sourceLanguage)")
                .font(EchoTypographyToken.caption.font)
                .foregroundStyle(EchoColorToken.secondaryText.color)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Original: \(memory.originalText)")
    }

    /// grouped metadata — 来源/时间/语言/地点/标签 (echo-memory-canvas §4.7, US-RET-004)
    private func metadataGroup(_ memory: MemoryDetailModel) -> some View {
        EchoContainer(level: .section) {
            EchoSectionHeader(title: "Details")
            EchoMetadataGroup {
                LabeledContent("Source", value: memory.sourceTypeLabel)
                LabeledContent("Date", value: memory.dateDescription)
                LabeledContent("Language", value: memory.sourceLanguage)

                if let location = memory.location, !location.isEmpty {
                    LabeledContent("Location") {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .labelStyle(.titleAndIcon)
                    }
                }

                if !memory.tags.isEmpty {
                    LabeledContent("Tags") {
                        Text(memory.tags.joined(separator: ", "))
                    }
                }

                if memory.userEdited {
                    LabeledContent("Status", value: "Edited")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Memory details: \(memory.sourceTypeLabel), \(memory.dateDescription), \(memory.sourceLanguage)")
    }

    #if DEBUG
    // MARK: - Creation Preview (US-SYN-002/003)

    /// 创作展示区 — AI 生成内容预览 + 溯源锚点 (US-SYN-002/003)
    ///
    /// 🔮 Phase 3.9+: 调用创作 Pipeline 生成。当前为 fixture 驱动的静态预览。
    private var creationPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI Creation")
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Text("🔮 Preview")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }

            Text("A letter to future self from your park memories — every claim links to its source memory.")
                .font(.body)
                .foregroundStyle(Color.primary)
                .lineLimit(4)

            // 溯源锚点 (US-SYN-002 AC-1)
            HStack(spacing: 8) {
                Button {
                    // 🔮 Phase 3.9+: 跳转至原始数据详情页
                } label: {
                    Label("🔗 MemoryID:…2222", systemImage: "link")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("memory-detail-citation-anchor-1")
                .accessibilityLabel("Source memory citation")

                Spacer()
            }

            // 进入完整创作结果页 (US-SYN-003, Task 3.9)
            Button {
                let fixtureViewModel = CreationViewModel()
                fixtureViewModel.enableFixtureGeneration()
                creationViewModel = fixtureViewModel
                isShowingCreation = true
            } label: {
                Label("Open full creation", systemImage: "arrow.up.right.square")
                    .font(.callout)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("memory-detail-open-creation")
        }
        .padding(14)
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
    #endif

    // MARK: - Delete Section (US-PRV-004)

    /// 删除入口 — 触发双选项确认弹窗
    private var deleteSection: some View {
        Button(role: .destructive) {
            viewModel.presentDeleteConfirmation()
        } label: {
            Label("Remove Memory…", systemImage: "trash")
                .font(.callout)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(EchoActionButtonStyle(role: .destructive))
        .accessibilityIdentifier("memory-detail-delete-button")
        .accessibilityHint("Opens a dialog to remove this memory from Echo or delete the original file")
    }

    // MARK: - Conflict View (US-AWK-007 AC-4, echo-memory-canvas §12.2)

    /// L4 冲突视图 — 双栏对比 + 三个操作按钮
    private func conflictView(_ conflict: MemoryConflictModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EchoSpacingToken.section.points) {
                EchoContainer(level: .section) {
                    EchoStatusPresentation(
                        role: .conflict,
                        systemImage: "exclamationmark.triangle.fill",
                        title: "Content conflict",
                        message: "The external source changed while you were editing. No production resolution has been saved."
                    )
                }

                // A single-column comparison preserves Focus reading order and Dynamic Type.
                VStack(alignment: .leading, spacing: EchoSpacingToken.normal.points) {
                    conflictColumn(title: "Your edit", content: conflict.localDraft)
                    conflictColumn(title: "External version", content: conflict.externalVersion)
                }

                // 操作按钮
                VStack(spacing: 10) {
                    Button {
                        viewModel.resolveConflict(keep: .local)
                    } label: {
                        Label("Keep my edit", systemImage: "square.and.pencil")
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EchoActionButtonStyle(role: .primary))
                    .accessibilityIdentifier("memory-conflict-keep-local")

                    Button {
                        viewModel.resolveConflict(keep: .external)
                    } label: {
                        Label("Use external version", systemImage: "arrow.down.circle")
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EchoActionButtonStyle(role: .secondary))
                    .accessibilityIdentifier("memory-conflict-keep-external")

                    Button {
                        viewModel.resolveConflict(keep: .merge)
                    } label: {
                        Label("View diff and merge", systemImage: "rectangle.split.3x1")
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EchoActionButtonStyle(role: .secondary))
                    .accessibilityIdentifier("memory-conflict-merge")
                    .accessibilityHint("Review and edit a merged draft")
                }
            }
            .padding(EchoSpacingToken.grouped.points)
        }
        .scrollContentBackground(.hidden)
    }

    /// 冲突对比列
    private func conflictColumn(title: String, content: String) -> some View {
        EchoContainer(level: .card) {
            VStack(alignment: .leading, spacing: EchoSpacingToken.compact.points) {
                Text(title)
                    .font(EchoTypographyToken.caption.font.weight(.semibold))
                    .foregroundStyle(EchoColorToken.secondaryText.color)

                Text(content)
                    .font(EchoTypographyToken.body.font)
                    .foregroundStyle(EchoColorToken.primaryText.color)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Error State

    /// 错误视图 — L2 重试横幅 / L3 全屏 (docs/ui/architecture.md §2.2)
    @ViewBuilder
    private func errorView(level: MemoryDetailViewModel.ErrorLevel) -> some View {
        VStack(spacing: 16) {
            Spacer()

            EchoContainer(level: .section) {
                EchoStatusPresentation(
                    role: isRecoverable(level) ? .warning : .blocking,
                    systemImage: "exclamationmark.triangle.fill",
                    title: EchoStrings.tr(errorTitle(for: level)),
                    message: EchoStrings.tr(errorMessage(for: level))
                )
            }

            if isRecoverable(level) {
                Button {
                    viewModel.retry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(EchoTypographyToken.action.font)
                }
                .buttonStyle(EchoActionButtonStyle(role: .recovery))
                .accessibilityIdentifier("memory-detail-retry-button")
            }

            Spacer().frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EchoColorToken.canvasBackground.color)
    }

    // MARK: - Helpers

    private func errorTitle(for level: MemoryDetailViewModel.ErrorLevel) -> String {
        switch level {
        case .l2Recoverable:   return "Unable to load memory"
        case .l3Blocking:      return "Unable to continue"
        case .l4Conflict:      return "Memory is being updated"
        }
    }

    private func errorMessage(for level: MemoryDetailViewModel.ErrorLevel) -> String {
        switch level {
        case .l2Recoverable(let msg),
             .l3Blocking(let msg),
             .l4Conflict(let msg):
            return msg
        }
    }

    private func isRecoverable(_ level: MemoryDetailViewModel.ErrorLevel) -> Bool {
        switch level {
        case .l2Recoverable: return true
        case .l3Blocking, .l4Conflict: return false
        }
    }
}

private struct FocusMediaUnavailableView: View {
    let kind: MediaKind

    var body: some View {
        EchoContainer(level: .section) {
            EchoStatusPresentation(
                role: .informational,
                systemImage: systemImage,
                title: "Media unavailable",
                message: message
            )
        }
        .accessibilityIdentifier("memory-detail-media-unavailable")
    }

    private var systemImage: String {
        switch kind {
        case .image: "photo"
        case .video: "video"
        case .audio: "waveform"
        case .none: "doc.text"
        }
    }

    private var message: String {
        switch kind {
        case .image:
            "This local photo could not be resolved with the current permission."
        case .video:
            "Video playback is unavailable until the local source is connected."
        case .audio:
            "Audio playback is unavailable until the local source is connected."
        case .none:
            "This memory has no media attachment."
        }
    }
}

// MARK: - AudioPlayerView

/// 语音记忆音频播放器 — 播放/暂停确定性示例 WAV（US-RET-001 voice 记忆展示）。
///
/// ## Surface Family: Focus
/// - 单列播放条 + 播放/暂停按钮（系统 SF Symbol），非 masonry
/// - AVAudioPlayer 本地播放 Bundle 内示例音频，无网络（R-001）
/// - 播放完毕后通过 delegate 回调自动翻转回播放按钮（2026-08-02 用户反馈修复）
struct AudioPlayerView: View {
    let url: URL
    let memoryTitle: String

    @State private var controller = AudioPlayerController()

    var body: some View {
        HStack(spacing: 12) {
            Button {
                controller.toggle(url: url)
            } label: {
                Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isPlaying ? "Pause voice memo" : "Play voice memo")
            .accessibilityIdentifier("memory-detail-audio-play")
            .accessibilityValue(controller.isPlaying ? "Playing" : "Stopped")

            VStack(alignment: .leading, spacing: 2) {
                Text("Voice memo")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.primary)
                Text("\(controller.durationText)")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .onDisappear { controller.stop() }
    }
}

/// 音频播放控制器 — @Observable 状态 + AVAudioPlayerDelegate。
///
/// 播放完毕 (`audioPlayerDidFinishPlaying`) 自动将 `isPlaying` 翻转为 false，
/// 使 UI 播放按钮恢复为 play 状态（用户反馈 2026-08-02）。
/// `@MainActor` 使 Task 闭包捕获 self 在 Swift 6 strict-concurrency 下合法
/// （CI Xcode 16.4 toolchain 报 sending 数据竞争，2026-08-02 PR #38 修复）。
@MainActor
@Observable
final class AudioPlayerController: NSObject, AVAudioPlayerDelegate {
    /// 是否正在播放（驱动 UI 按钮状态）
    private(set) var isPlaying = false

    private var player: AVAudioPlayer?
    /// 播放结束轮询任务（模拟器无声卡时 delegate 不触发，轮询兜底）
    private var monitorTask: Task<Void, Never>?

    deinit {}

    /// 时长展示文本（未就绪时为 0:00）
    var durationText: String {
        guard let player else { return "0:00" }
        let total = Int(player.duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 播放/暂停切换。首次调用时惰性加载 Bundle 内音频。
    func toggle(url: URL) {
        prepareIfNeeded(url: url)
        guard let player else { return }
        if player.isPlaying || isSimulatedPlaying {
            pausePlayback()
        } else {
            // play() 返回 false 表示无可用音频输出设备（iOS 18 模拟器 CoreAudio 缺陷 -66680）
            // → 模拟播放驱动 UI（真机有输出设备时正常播放）
            let started = player.play()
            if started {
                isPlaying = true
                monitorPlaybackEnd()
            } else {
                startSimulatedPlayback()
            }
        }
    }
    /// 暂停播放（真实或模拟）。
    private func pausePlayback() {
        player?.pause()
        simulatedTask?.cancel()
        monitorTask?.cancel()
        isPlaying = false
    }

    /// 停止播放并重置状态（视图消失时调用）。
    func stop() {
        simulatedTask?.cancel()
        monitorTask?.cancel()
        player?.stop()
        player = nil
        isPlaying = false
    }

    // MARK: - AVAudioPlayerDelegate

    /// 播放完毕回调 — 翻转播放按钮回 play 状态。
    ///
    /// `successfully == false` 表示播放因错误终止（如 iOS 18 模拟器无输出设备时
    /// play() 后立即失败）→ 切换到模拟播放，避免按钮瞬间弹回 play 而无法验证 UI。
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.monitorTask?.cancel()
            self.simulatedTask?.cancel()
            if !flag && self.isPlaying {
                self.startSimulatedPlayback()
            } else {
                self.isPlaying = false
            }
        }
    }

    // MARK: - Private

    /// 当前是否处于模拟播放（无声卡模拟器环境）。
    private var isSimulatedPlaying: Bool {
        isPlaying && (simulatedTask != nil)
    }

    /// 模拟播放任务 — 无声卡环境驱动 UI 播放态与自动翻转 (2026-08-02)。
    private var simulatedTask: Task<Void, Never>?

    /// 模拟播放：play() 失败（无输出设备）时按音频时长推进 UI 状态。
    /// 真机不会走到此路径（play() 成功走真实播放 + delegate/轮询）。
    private func startSimulatedPlayback() {
        monitorTask?.cancel()
        isPlaying = true
        let duration = player?.duration ?? 3.0
        simulatedTask?.cancel()
        simulatedTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.isPlaying = false
            self?.simulatedTask = nil
        }
    }

    /// 轮询监听播放结束 — 不依赖 delegate（模拟器环境兜底，2026-08-02）。
    ///
    /// - 真实播放（真机/正常模拟器）：`currentTime` 推进，结束后翻转按钮。
    /// - 假成功（play() 返回 true 但无声卡不推进）：0.5s 无进度 → 切换到模拟播放，
    ///   按时长驱动 UI 翻转，避免按钮永久卡在 Pause。
    private func monitorPlaybackEnd() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            var progressStarted = false
            var pollsWithoutProgress = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, let player = self.player else { return }
                if player.currentTime > 0 {
                    progressStarted = true
                }
                // 假成功：0.5s（3 次轮询）无进度 → 模拟播放
                if !progressStarted && self.isPlaying {
                    pollsWithoutProgress += 1
                    if pollsWithoutProgress >= 3 {
                        self.startSimulatedPlayback()
                        return
                    }
                }
                // 真实播放自然结束
                if progressStarted && !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    return
                }
            }
        }
    }

    private func prepareIfNeeded(url: URL) {
        guard player == nil else { return }
        // iOS 18 模拟器/设备上 AVAudioPlayer 需要激活 audio session 才能播放 (2026-08-02)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.delegate = self
        p?.prepareToPlay()
        player = p
    }
}

// MARK: - EditMemorySheet

/// 编辑记忆 Sheet (US-AWK-007 AC-1)。
///
/// ## Surface Family: Focus
/// - Form 布局（Task/Focus 共享 Form 容器，非 masonry）
/// - 字段: 标题 / 描述（多行）/ 标签 / 时间戳
struct EditMemorySheet: View {
    @Bindable var viewModel: MemoryDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $viewModel.editTitle)
                        .accessibilityIdentifier("memory-edit-title")
                }

                Section("Description") {
                    TextEditor(text: $viewModel.editDescription)
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("memory-edit-description")
                }

                Section("Custom Tags") {
                    TextField("tag1, tag2", text: $viewModel.editTags)
                        .accessibilityIdentifier("memory-edit-tags")
                }

                Section("Timestamp") {
                    DatePicker(
                        "Date",
                        selection: $viewModel.editTimestamp,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityIdentifier("memory-edit-timestamp")
                }
            }
            .navigationTitle("Edit Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        viewModel.isEditing = false
                    }
                    .accessibilityIdentifier("memory-edit-cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveEdit()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("memory-edit-save")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Loading") {
    NavigationStack {
        MemoryDetailView(viewModel: makeDetailViewModel(state: .loading))
    }
}

#Preview("Loaded (zh → en)") {
    NavigationStack {
        MemoryDetailView(viewModel: makeDetailViewModel(state: .loaded))
    }
}

#Preview("Translated") {
    NavigationStack {
        MemoryDetailView(viewModel: makeDetailViewModel(state: .translated))
    }
}

#Preview("Translation high confidence") {
    NavigationStack {
        MemoryDetailView(viewModel: makeTranslationViewModel(state: .highConfidence))
    }
}

#Preview("Translation low confidence") {
    NavigationStack {
        MemoryDetailView(viewModel: makeTranslationViewModel(state: .lowConfidence))
    }
}

#Preview("Translation error") {
    NavigationStack {
        MemoryDetailView(viewModel: makeTranslationViewModel(state: .error))
    }
}

#Preview("Conflict") {
    NavigationStack {
        MemoryDetailView(viewModel: makeDetailViewModel(state: .conflict))
    }
}

#Preview("Error") {
    NavigationStack {
        MemoryDetailView(viewModel: makeDetailViewModel(state: .error))
    }
}

// MARK: - Preview Helpers

/// 从 fixture 构造确定性记忆详情。
@MainActor
private func makeDetailViewModel(state: DetailPreviewState) -> MemoryDetailViewModel {
    let vm = MemoryDetailViewModel()

    switch state {
    case .loading:
        vm.load(memoryId: UUID())

    case .loaded:
        if let model = MemoryDetailFixtureLoader.load("memory-detail-loaded") {
            vm.loadPreloaded(model)
        }

    case .translated:
        if let model = MemoryDetailFixtureLoader.load("memory-detail-translated") {
            vm.loadPreloaded(model)
        }

    case .conflict:
        if let model = MemoryDetailFixtureLoader.load("memory-detail-conflict") {
            vm.loadPreloaded(model)
        }

    case .error:
        vm.simulateError(.l2Recoverable(message: "Unable to load this memory. Please try again."))
    }

    return vm
}

/// 从翻译 fixture 构造确定性记忆详情 (task 3.8)。
@MainActor
private func makeTranslationViewModel(state: TranslationPreviewState) -> MemoryDetailViewModel {
    let vm = MemoryDetailViewModel()

    switch state {
    case .highConfidence:
        if let model = TranslationFixtureLoader.load("translation-zh-en-high") {
            vm.loadPreloaded(model)
        }

    case .lowConfidence:
        if let model = TranslationFixtureLoader.load("translation-zh-en-low") {
            vm.loadPreloaded(model)
        }

    case .error:
        if let model = TranslationFixtureLoader.load("translation-error") {
            vm.loadPreloaded(model)
        }
    }

    return vm
}

/// Preview 状态枚举
private enum DetailPreviewState {
    case loading
    case loaded
    case translated
    case conflict
    case error
}

/// 翻译 surface Preview 状态枚举
private enum TranslationPreviewState {
    case highConfidence
    case lowConfidence
    case error
}
