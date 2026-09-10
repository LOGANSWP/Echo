// ==========================================
// 文件: HomeView.swift
// i18n: User-facing strings resolve through Localizable.xcstrings (zh-Hans + en-US).
// 对应规格: docs/ui/echo-memory-canvas-style.md §3.1 (Discovery adaptive masonry),
//            §4 (共享 Token), §10.1.1 (无记忆时品牌欢迎页), §10.2.1 (骨架屏),
//            §16.1 (离线模式指示器 US-RES-001 AC-3)
//            docs/ui/architecture.md §3 (Surface View), §8 (Discovery surface family)
//            docs/01-spec/用户故事与验收标准规格书.md → US-AWK-001 AC-4, US-AWK-005, US-RES-001 AC-3
// 任务: 3.1 - HomeView + HomeViewModel + Awakening Cards + Offline Indicator; 4.0a - Discovery 平衡画布
//       4.0d - Interactive awakening card production closure
//          (3.6 降级横幅 host; 3.7 断点续传恢复提示 host)
// AC 覆盖: US-AWK-001 AC-4 ✅ (唤醒卡片 UI), US-AWK-005 AC-1 ✅ (卡片展示),
//          US-RES-001 AC-3 ✅ (离线模式标识), AWK-002 AC-3 ✅ (纪念日卡片),
//          AWK-003 AC-4 ✅ (情绪卡片), AWK-005 AC-1~5 ✅ (4.0d production closure)
//          3.7 host: ResumeProgressPromptView + resume-progress-* fixture 注入
//          (2026-08-02 PR review W-1: ResumeProgressPromptView 改真实布局槽位, 移除零高 frame)
//          4.0a: live recent memories, deterministic masonry gate, truthful zero-memory progress
// 架构约束: AGENTS.md §8.1 (ViewModel 驱动), §17.2 (Discovery adaptive masonry),
//           §10.1 (Views 目录), echo-memory-canvas apple-native 基础
// 生成时间: 2026-07-26; 2026-09-02 (4.0d)
// ==========================================

import SwiftUI

enum AwakeningCardInput: Sendable, Equatable {
    case nextButton
    case recordButton
    case openButton
    case nextAccessibilityAction
    case recordAccessibilityAction
    case openAccessibilityAction
}

enum AwakeningCardInteractionPolicy {
    private static let swipeThreshold = 60.0

    static func action(
        for input: AwakeningCardInput,
        canAdvance: Bool
    ) -> AwakeningCardAction? {
        switch input {
        case .nextButton, .nextAccessibilityAction:
            canAdvance ? .next : nil

        case .recordButton, .recordAccessibilityAction:
            .record

        case .openButton, .openAccessibilityAction:
            .jump
        }
    }

    static func action(
        forHorizontalTranslation translation: Double,
        canAdvance: Bool
    ) -> AwakeningCardAction? {
        if translation <= -swipeThreshold {
            return canAdvance ? .next : nil
        }
        if translation >= swipeThreshold {
            return .record
        }
        return nil
    }
}

// MARK: - HomeView

/// Home 主视图 — 记忆发现与唤醒卡片主页。
///
/// ## Surface Family: Discovery
/// - 布局: 真实数据达到确定性门禁时 adaptive masonry，否则稳定单列
/// - 系统容器: NavigationStack (由 AppRootView 提供)
/// - Masonry 启用条件: 20+ 可展示记忆、区块 6+ 卡片、340pt、非 AX 字号且 VoiceOver 关闭
///
/// ## 状态驱动
/// - idle: 品牌欢迎页或初始状态
/// - loading: 骨架屏 (系统 .redacted)
/// - completed: 唤醒卡片列表 + 今日回忆提示
/// - error: 重试按钮
/// - cancelled: 返回 idle
///
/// ## 离线指示器 (US-RES-001 AC-3)
/// - isOffline = true 时, 顶部显示 wifi.slash 横幅
///
/// ## Style
/// - echo-memory-canvas token: .largeTitle, Color.primary, Color(.systemBackground), SF Symbols
/// - 禁止 Pinterest 品牌元素；Focus/Task surfaces 保持非 masonry
/// - 使用系统 Dynamic Type, semantic colors, 系统容器
struct HomeView: View {
    // MARK: - ViewModel

    @State private var viewModel: HomeViewModel
    private let appViewModel: AppViewModel?
    @State private var selectedMemoryID: UUID?
    @State private var selectedAwakeningRoute: AwakeningFocusRoute?
    @State private var feelingEditor: FeelingEditorContext?
    @State private var discoveryContentWidth: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 后台任务面板 ViewModel — 由工具栏按钮展示 (US-SYS-001 AC-1 顶部状态栏入口)
    /// 3F.11 fix: 注入真实 ProgressActor — 面板读取 SQLite TaskProgress 实时进度（US-SYS-001 AC-2）
    @State private var taskPanelViewModel = BackgroundTaskViewModel(
        progressActor: .shared,
        auditWriter: .shared,
        taskQueue: .shared
    )

    /// 后台任务面板展示开关
    @State private var isTaskPanelPresented = false

    /// 降级横幅 ViewModel — production wiring (3F.10): SystemMonitor low-power/thermal sources
    /// drive real runtime behavior (US-RES-002 AC-1/AC-3/AC-5, US-RES-003 AC-1/AC-3/AC-5); model
    /// retry is manual-only against the composition loader (US-RES-004 AC-3); audits via PrivacyActor.
    /// Live Sim Review fixture 注入 (Task 3.6) 仍经 handleLaunchArguments 覆盖同一 VM。
    @State private var degradationViewModel = DegradationBannerViewModel(
        systemMonitor: SystemMonitor(),
        auditWriter: PrivacyActor.shared,
        modelLoader: AppComposition.shared.modelLoader
    )

    /// 断点续传恢复提示 ViewModel — Live Sim Review fixture 注入 (Task 3.7)
    @State private var resumeProgressViewModel = ResumeProgressViewModel(
        progressActor: .shared,
        recoveryCoordinator: AppComposition.shared.taskRecoveryCoordinator
    )

    /// 首次出现标记 — 控制 fixture 注入仅执行一次
    @State private var hasHandledLaunchArguments = false

    init(
        viewModel: HomeViewModel? = nil,
        appViewModel: AppViewModel? = nil,
        makeDefaultViewModel: @MainActor () -> HomeViewModel = Self.makeProductionViewModel
    ) {
        self.appViewModel = appViewModel
        _viewModel = State(initialValue: viewModel ?? makeDefaultViewModel())
    }

    private static func makeProductionViewModel() -> HomeViewModel {
        let feelingStore = MemoryFeelingActor()
        let musicService = try? AwakeningMusicService(
            library: BundledMusicLibrary.loadFromBundleOrRepository()
        )
        return HomeViewModel(
            cardRepository: AwakeningCardRepositoryActor(),
            discoveryAdapter: HomeDiscoveryAdapter(
                memoryReader: LiveAppAdapters.makeCanonicalRepository(),
                progressReader: ProgressActor.shared,
                policyReader: PrivacyActor.shared,
                sourceResolver: LiveDiscoverySourceResolver()
            ),
            searchCapability: LiveHomeSearchCapability(),
            interactionActor: AwakeningCardInteractionActor(feelingStore: feelingStore),
            feelingStore: feelingStore,
            musicService: musicService
        )
    }

    /// 3F.11 fix: 面板关闭后重建时注入真实 ProgressActor（US-SYS-001 AC-2）
    private func makeTaskPanelViewModel() -> BackgroundTaskViewModel {
        BackgroundTaskViewModel(
            progressActor: .shared,
            auditWriter: .shared,
            taskQueue: .shared
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Degradation banner (Task 3.6 — Live Sim Review fixture)
                DegradationBannerView(viewModel: degradationViewModel)
                    .task { await degradationViewModel.startMonitoring() }

                // Resume progress prompt (Task 3.7 — confirmationDialog host + inline L2 error, real layout slot)
                ResumeProgressPromptView(viewModel: resumeProgressViewModel)

                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))

            // Offline banner (US-RES-001 AC-3)
            if viewModel.isOffline {
                offlineBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .navigationTitle("Echo · 回响")
        .navigationBarTitleDisplayMode(.large)
        .modifier(DisableLargeTitleScroll())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { CreationLibraryView() } label: {
                    Label("Creation Library", systemImage: "books.vertical")
                }
                .accessibilityIdentifier("creation-library-open")
            }
            // 后台任务面板入口 (US-SYS-001 AC-1: 顶部状态栏实时显示活跃任务)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    taskPanelViewModel.openPanel()
                    isTaskPanelPresented = true
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("Background Tasks")
                .accessibilityHint("Show active background task progress")
                .accessibilityIdentifier("background-tasks-open")
            }
        }
        .sheet(isPresented: $isTaskPanelPresented) {
            BackgroundTaskPanelView(viewModel: taskPanelViewModel) {
                taskPanelViewModel = makeTaskPanelViewModel()
            }
        }
        .navigationDestination(item: $selectedMemoryID) { memoryID in
            MemoryDetailView(memoryId: memoryID)
        }
        .navigationDestination(item: $selectedAwakeningRoute) { route in
            switch route {
            case .media(let memoryID, _), .text(let memoryID, _), .voice(let memoryID, _):
                MemoryDetailView(memoryId: memoryID)

            case .unavailable:
                EchoStatusPresentation(
                    role: .warning,
                    systemImage: "exclamationmark.triangle",
                    title: EchoStrings.tr("Memory unavailable"),
                    message: EchoStrings.tr("The original source is no longer available or authorized.")
                )
                .padding()
            }
        }
        .sheet(item: $feelingEditor) { context in
            AwakeningFeelingSheet(
                card: context.card,
                editingFeeling: context.feeling,
                viewModel: viewModel
            )
        }
        .alert(
            EchoStrings.tr("Interaction unavailable"),
            isPresented: Binding(
                get: { viewModel.interactionErrorMessage != nil },
                set: { presented in
                    if !presented { viewModel.dismissInteractionError() }
                }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.dismissInteractionError() }
        } message: {
            Text(EchoStrings.tr(viewModel.interactionErrorMessage ?? ""))
        }
        .onAppear {
            viewModel.onAppear()
            handleFirstAppear()
        }
        .onDisappear { viewModel.onDisappear() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.viewState)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: viewModel.isOffline)
    }

    // MARK: - Launch Argument Fixture Injection

    /// 首次出现时处理启动参数 fixture 注入。
    ///
    /// 支持 `-ui-fixture background-tasks-loaded|empty|error` — XCUITest / Live Sim Review
    /// 确定性导航到后台任务面板。生产构建（#if DEBUG 排除）无任何注入逻辑。
    private func handleFirstAppear() {
        guard !hasHandledLaunchArguments else { return }
        hasHandledLaunchArguments = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-fixture") {
            handleLaunchArguments()
            return
        }
        #endif
        resumeProgressViewModel.checkForPendingProgress()
    }

    #if DEBUG
    /// 处理 XCUITest / Live Sim Review 启动参数注入确定性 fixture。
    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-ui-fixture"), idx + 1 < args.count else { return }
        let fixtureID = args[idx + 1]

        switch fixtureID {
        case "background-tasks-loaded", "background-tasks-empty":
            let items = BackgroundTaskFixtureLoader.load(fixtureID)
            taskPanelViewModel.loadPreloadedTasks(items)
            taskPanelViewModel.openPanel()
            isTaskPanelPresented = true

        case "degradation-low-power", "degradation-thermal", "degradation-model-degraded", "degradation-normal":
            degradationViewModel.loadFixture(fixtureID)

        case "resume-progress-pending":
            resumeProgressViewModel.loadFixture(fixtureID)
            resumeProgressViewModel.checkForPendingProgress(taskType: .fullIndex)

        case "resume-progress-none":
            resumeProgressViewModel.loadFixture(fixtureID)
            resumeProgressViewModel.checkForPendingProgress(taskType: .dataSourceSync)

        case "resume-progress-error":
            resumeProgressViewModel.simulateCheckError()

        default:
            break
        }
    }
    #endif

    // MARK: - Content Views

    /// 根据 ViewState 渲染对应内容
    @ViewBuilder
    private var contentView: some View {
        switch viewModel.viewState {
        case .idle, .loading:
            loadingSkeleton

        case .completed:
            if viewModel.awakeningCards.isEmpty && viewModel.discoveryCards.isEmpty {
                emptyWelcomePage
            } else {
                discoveryFeed
            }

        case .error(let level):
            errorView(level: level)

        case .cancelled:
            Color(.systemBackground)
                .onAppear { viewModel.dismissError() }
        }
    }

    // MARK: - Loading Skeleton

    /// 骨架屏 — 使用系统 .redacted(reason: .placeholder) (echo-memory-canvas §10.2.1)
    private var loadingSkeleton: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Welcome header skeleton
                welcomeHeaderSkeleton

                // Card skeletons
                ForEach(0..<4, id: \.self) { _ in
                    awakeningCardSkeleton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .redacted(reason: .placeholder)
        .disabled(true)
        .accessibilityLabel("Loading awakening cards")
    }

    private var welcomeHeaderSkeleton: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(Color(.systemFill))
                .frame(width: 60, height: 60)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemFill))
                .frame(width: 200, height: 24)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemFill))
                .frame(width: 280, height: 16)
        }
        .padding(.vertical, 24)
    }

    private var awakeningCardSkeleton: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemFill))
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemFill))
                    .frame(width: 160, height: 16)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemFill))
                    .frame(width: 220, height: 12)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Empty State (Brand Welcome Page)

    /// 空态 — 品牌欢迎页 (echo-memory-canvas §10.1.1)
    ///
    /// 当系统尚未摄入任何记忆时展示，而非空白列表。
    private var emptyWelcomePage: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer().frame(height: 40)

                // Echo Logo
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)

                // Title
                Text("Echo · 回响")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.primary)

                // Description
                Text("Your memories, always within reach.\nMemories from special places, past moments, and meaningful days will appear here.")
                    .font(.body)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)

                zeroMemoryGuidance

                Spacer().frame(height: 60)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Echo welcome page. Your memories will appear here.")
    }

    @ViewBuilder
    private var zeroMemoryGuidance: some View {
        switch viewModel.zeroMemoryState {
        case .activeScan(let processed, let total):
            VStack(spacing: EchoSpacingToken.compact.points) {
                ProgressView(value: Double(processed), total: Double(max(total, 1)))
                    .tint(EchoColorToken.warmAccent.color)
                Text(String(
                    format: EchoStrings.tr("Scanning your memories (%lld of %lld)"),
                    processed,
                    total
                ))
                    .font(EchoTypographyToken.metadata.font)
                    .foregroundStyle(EchoColorToken.secondaryText.color)
            }
            .padding(.horizontal, EchoSpacingToken.section.points)

        case .importGuidance:
            EchoStatusPresentation(
                role: .informational,
                systemImage: "square.and.arrow.down",
                title: EchoStrings.tr("No memories yet"),
                message: EchoStrings.tr("Share a note or voice memo to Echo to begin.")
            )
            .padding(.horizontal, EchoSpacingToken.section.points)

        case .authorizationGuidance:
            EchoStatusPresentation(
                role: .informational,
                systemImage: "lock.open",
                title: EchoStrings.tr("Connect a memory source"),
                message: EchoStrings.tr("Review data sources in Settings to start importing memories.")
            )
            .padding(.horizontal, EchoSpacingToken.section.points)
        }
    }

    // MARK: - Awakening Card List

    /// 唤醒卡片列表 — Discovery surface 自适应卡片布局
    private var discoveryFeed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EchoSpacingToken.section.points) {
                if !viewModel.searchSuggestions.isEmpty {
                    EchoSectionHeader(
                        title: "Ask Echo",
                        subtitle: "Explore your memories with an offline search"
                    )
                    askEchoSuggestions
                }

                if !viewModel.awakeningCards.isEmpty {
                    EchoSectionHeader(title: "Awakenings")
                    ForEach(viewModel.awakeningCards) { card in
                        AwakeningCardView(
                            card: card,
                            media: viewModel.presentations(for: card),
                            music: viewModel.musicSuggestion(for: card),
                            feelings: viewModel.feelings(for: card),
                            canAdvance: viewModel.canAdvance(card),
                            onNext: { viewModel.advance(card) },
                            onRecordFeeling: {
                                feelingEditor = FeelingEditorContext(card: card, feeling: nil)
                            },
                            onJump: {
                                guard let route = viewModel.focusRoute(for: card) else { return }
                                selectedAwakeningRoute = route
                                viewModel.recordJump(for: card)
                            },
                            onMatchDeviceMusic: { viewModel.matchDeviceMusic(for: card) }
                        )
                    }
                }

                if !viewModel.discoveryCards.isEmpty {
                    EchoSectionHeader(
                        title: "Recent memories",
                        subtitle: "From your connected sources"
                    )
                    discoveryCards
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, EchoSpacingToken.section.points)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                discoveryContentWidth = max(0, width - 32)
            }
        }
        .refreshable {
            viewModel.refresh()
        }
    }

    private var askEchoSuggestions: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: EchoSpacingToken.normal.points) {
                ForEach(viewModel.searchSuggestions) { suggestion in
                    Button {
                        appViewModel?.openSearch(query: EchoStrings.tr(suggestion.queryKey))
                    } label: {
                        Label(
                            EchoStrings.tr(suggestion.titleKey),
                            systemImage: "sparkle.magnifyingglass"
                        )
                    }
                    .buttonStyle(EchoActionButtonStyle(role: .secondary))
                    .accessibilityHint("Open Search and run this query")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var discoveryCards: some View {
        let environment = DiscoveryLayoutEnvironment(
            contentWidth: discoveryContentWidth,
            usesAccessibilityDynamicType: dynamicTypeSize.isAccessibilitySize,
            voiceOverEnabled: voiceOverEnabled
        )
        if viewModel.discoveryLayoutMode(environment: environment) == .adaptiveMasonry {
            DiscoveryMasonryLayout {
                discoveryCardViews
            }
        } else {
            LazyVStack(spacing: EchoSpacingToken.normal.points) {
                discoveryCardViews
            }
        }
    }

    @ViewBuilder
    private var discoveryCardViews: some View {
        ForEach(viewModel.discoveryCards) { card in
            DiscoveryMemoryCardView(card: card) {
                selectedMemoryID = card.id
            }
        }
    }

    // MARK: - Error State

    /// 错误视图 — L2/L3 自适应
    @ViewBuilder
    private func errorView(level: HomeViewModel.ErrorLevel) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.yellow)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(EchoStrings.tr(errorTitle(for: level)))
                .font(.headline)
                .foregroundStyle(Color.primary)

            Text(EchoStrings.tr(errorMessage(for: level)))
                .font(.body)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if isRecoverable(level) {
                Button {
                    viewModel.refresh()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.callout)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
            }

            Spacer().frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Offline Banner

    /// 离线模式指示器 (US-RES-001 AC-3, echo-memory-canvas §16.1)
    ///
    /// 顶部 Banner, 浅灰背景, wifi.slash + "Offline mode — showing cached memories only"
    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.footnote)
                .foregroundStyle(Color.secondary)

            Text("Offline mode — showing cached memories only")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .padding(.top, 0)
        .accessibilityLabel("Offline mode")
        .accessibilityHint("Only cached memories are available")
    }

    // MARK: - Helpers

    private func errorTitle(for level: HomeViewModel.ErrorLevel) -> String {
        switch level {
        case .l2Recoverable:   return "Something went wrong"
        case .l3Blocking:      return "Unable to continue"
        }
    }

    private func errorMessage(for level: HomeViewModel.ErrorLevel) -> String {
        switch level {
        case .l2Recoverable(let msg),
             .l3Blocking(let msg):
            return msg
        }
    }

    private func isRecoverable(_ level: HomeViewModel.ErrorLevel) -> Bool {
        switch level {
        case .l2Recoverable: return true
        case .l3Blocking:    return false
        }
    }
}

// MARK: - AwakeningCardView

/// 唤醒卡片组件 — 展示单条唤醒记忆卡片。
///
/// ## Surface Family: Discovery
/// - 自适应卡片布局, 遵循 echo-memory-canvas token
/// - 包含: SF Symbol 图标 + 标题 + 副标题 + 相对时间
/// - 点击: 🔮 跳转 Focus surface (Phase 3.3 MemoryDetailView)
///
/// ## Style
/// - 系统 background + shadow 层级
/// - 系统 Dynamic Type: .headline, .subheadline, .caption
/// - SF Symbol: 由 triggerType 决定
struct AwakeningCardView: View {
    let card: AwakeningCardModel
    let media: [DiscoveryCardPresentation]
    let music: MusicSuggestion?
    let feelings: [UserFeeling]
    let canAdvance: Bool
    let onNext: () -> Void
    let onRecordFeeling: () -> Void
    let onJump: () -> Void
    let onMatchDeviceMusic: () -> Void

    var body: some View {
        EchoContainer(level: .emphasized) {
            VStack(alignment: .leading, spacing: EchoSpacingToken.normal.points) {
                HStack(alignment: .top, spacing: 14) {
                    iconView
                    textContent
                    Spacer(minLength: 8)
                    Text(card.localizedRelativeTime)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                mediaPreview
                musicSuggestion

                if let latestFeeling = feelings.last {
                    Label(latestFeeling.text, systemImage: "heart.text.square")
                        .font(EchoTypographyToken.metadata.font)
                        .foregroundStyle(EchoColorToken.secondaryText.color)
                        .lineLimit(2)
                }

                ViewThatFits {
                    HStack(spacing: EchoSpacingToken.compact.points) { actionButtons }
                    VStack(spacing: EchoSpacingToken.compact.points) { actionButtons }
                }
            }
        }
        .contentShape(.rect)
        .simultaneousGesture(
            DragGesture(minimumDistance: 32).onEnded { value in
                if let action = AwakeningCardInteractionPolicy.action(
                    forHorizontalTranslation: Double(value.translation.width),
                    canAdvance: canAdvance
                ) {
                    perform(action)
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(cardAccessibilityLabel)
        .accessibilityHint("Use the actions to open, advance, or record a feeling")
        .accessibilityAction(named: Text("Next memory")) {
            perform(.nextAccessibilityAction)
        }
        .accessibilityAction(named: Text("Record feeling")) {
            perform(.recordAccessibilityAction)
        }
        .accessibilityAction(named: Text("Open memory")) {
            perform(.openAccessibilityAction)
        }
    }

    @ViewBuilder
    private var mediaPreview: some View {
        let thumbnails = Array(media.filter { $0.aspectRatio != nil }.prefix(3))
        if !thumbnails.isEmpty {
            HStack(spacing: EchoSpacingToken.compact.points) {
                ForEach(thumbnails) { item in
                    if let aspectRatio = item.aspectRatio {
                        DiscoveryMediaThumbnail(
                            assetID: item.sourceLocator,
                            aspectRatio: aspectRatio,
                            sourceType: item.sourceType
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var musicSuggestion: some View {
        if let music {
            HStack(spacing: EchoSpacingToken.compact.points) {
                Image(systemName: "music.note")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(music.title).font(.subheadline.weight(.semibold))
                    Text(music.artist).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if music.source == .bundled {
                    Text("Suggestion")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            perform(.openButton)
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }
        .buttonStyle(EchoActionButtonStyle(role: .primary))
        .accessibilityIdentifier("awakening-open")

        Button {
            perform(.nextButton)
        } label: {
            Label("Next", systemImage: "arrow.right")
        }
        .buttonStyle(EchoActionButtonStyle(role: .secondary))
        .disabled(!canAdvance)
        .accessibilityIdentifier("awakening-next")

        Button {
            perform(.recordButton)
        } label: {
            Label("Record feeling", systemImage: "heart.text.square")
        }
        .buttonStyle(EchoActionButtonStyle(role: .secondary))
        .accessibilityIdentifier("awakening-record-feeling")

        Button(action: onMatchDeviceMusic) {
            Label("Match device music", systemImage: "music.note.list")
        }
        .buttonStyle(EchoActionButtonStyle(role: .secondary))
        .accessibilityIdentifier("awakening-device-music")
    }

    private func perform(_ input: AwakeningCardInput) {
        guard let action = AwakeningCardInteractionPolicy.action(
            for: input,
            canAdvance: canAdvance
        ) else { return }
        perform(action)
    }

    private func perform(_ action: AwakeningCardAction) {
        switch action {
        case .next:
            onNext()

        case .record:
            onRecordFeeling()

        case .jump:
            onJump()
        }
    }

    // MARK: - Icon

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.1))
                .frame(width: 44, height: 44)

            Image(systemName: card.symbolName)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Text

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.localizedTitle)
                .font(.headline)
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Text(card.localizedSubtitle)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Accessibility

    private var cardAccessibilityLabel: String {
        "\(card.localizedTitle), \(card.localizedSubtitle), \(card.localizedRelativeTime)"
    }
}

private struct FeelingEditorContext: Identifiable {
    let id = UUID()
    let card: AwakeningCardModel
    let feeling: UserFeeling?
}

private struct AwakeningFeelingSheet: View {
    let card: AwakeningCardModel
    let editingFeeling: UserFeeling?
    let viewModel: HomeViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var selectedFeeling: UserFeeling?

    var body: some View {
        NavigationStack {
            Form {
                Section("This moment") {
                    TextField("How do you feel?", text: $draft, axis: .vertical)
                        .lineLimit(3...8)
                }

                if !viewModel.feelings(for: card).isEmpty {
                    Section("Earlier feelings") {
                        ForEach(viewModel.feelings(for: card)) { feeling in
                            HStack(alignment: .top) {
                                Button(feeling.text) {
                                    selectedFeeling = feeling
                                    draft = feeling.text
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button(role: .destructive) {
                                    if selectedFeeling?.feelingID == feeling.feelingID {
                                        selectedFeeling = nil
                                        draft = ""
                                    }
                                    viewModel.deleteFeeling(feeling)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("Delete feeling")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Record feeling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelFeelingEditing()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let selectedFeeling {
                            viewModel.updateFeeling(selectedFeeling, text: draft)
                        } else {
                            viewModel.recordFeeling(draft, for: card)
                        }
                        dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                selectedFeeling = editingFeeling
                draft = editingFeeling?.text ?? ""
            }
        }
    }
}

// MARK: - Preview

#Preview("Idle / Loading") {
    NavigationStack {
        HomeView()
    }
}

#Preview("Awakening Cards") {
    NavigationStack {
        HomeView(viewModel: makePreviewViewModel(
            cards: [
                ("geofenceOnly", "Shanghai Tower"),
                ("emotionNegative", "Home"),
                ("anniversary", "Paris 2024"),
                ("emotionNeutral", "Office"),
            ]
        ))
    }
}

#Preview("Offline Mode") {
    NavigationStack {
        HomeView(viewModel: makePreviewViewModel(
            cards: [("geofenceOnly", "Central Park")],
            isOffline: true
        ))
    }
}

// MARK: - Preview Helpers

@MainActor
private func makePreviewViewModel(cards: [(String, String)], isOffline: Bool = false) -> HomeViewModel {
    let vm = HomeViewModel()
    for (triggerType, region) in cards {
        vm.appendAwakeningCard(AwakeningCard(
            cardId: UUID(),
            memoryIds: [UUID()],
            triggerType: triggerType,
            regionId: region,
            createdAt: Date().addingTimeInterval(-Double.random(in: 60...86400))
        ))
    }
    vm.loadAwakeningCardsPreloaded()
    if isOffline { vm.setOffline(true) }
    return vm
}

// MARK: - iOS 26 Large Title Workaround

/// iOS 26 (Liquid Glass) 将 Large Title 与内容中第一个最高层 ScrollView 联动，
/// overscroll 时标题被拉下穿过固定 Banner（iOS 18 无此行为，标题固定在导航栏）。
/// 通过包裹一个禁用的横向 ScrollView，让 NavigationStack 将标题关联到不可滚动外层，
/// 使标题在 iOS 26 上保持固定，与 iOS 18 行为一致。
/// 参考: stackoverflow.com/q/79771449 (Large navigation title scrolls with ScrollView)
/// 仅 iOS 26+ 生效；iOS 18 原样返回，不改变现有正确行为。
private struct DisableLargeTitleScroll: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundStyle(.clear)
                        content
                            .frame(width: proxy.size.width)
                    }
                }
                .scrollDisabled(true)
            }
        } else {
            content
        }
    }
}
