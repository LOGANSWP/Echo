// ==========================================
// 文件: SearchView.swift
// i18n: User-facing strings resolve through Localizable.xcstrings (zh-Hans + en-US).
// 对应规格: docs/ui/echo-memory-canvas-style.md §3.1 (Discovery surfaces), §6 (adaptive masonry / single-column fallback),
//            §10.2 (加载态), §14 (筛选与搜索 UI 模式), §14.3 (低置信度横幅), §14.4 (反馈按钮),
//            §14.5 (Bad Case 标记)
//            docs/ui/architecture.md §3 (Surface View), §8 (Discovery surface family)
//            docs/01-spec/用户故事与验收标准规格书.md → US-RET-001, US-RET-006, US-FBK-001, US-FBK-003
// 任务: 3.2 - SearchView + SearchViewModel + Feedback + Low-confidence banner; 4.0a - Discovery 平衡画布
// AC 覆盖: US-RET-001 AC-3 ✅ (结果列表展示), US-RET-006 AC-2/AC-4 ✅ (低置信度横幅),
//          US-FBK-001 AC-1 ✅ (👍/👎 按钮), US-FBK-003 AC-1 ✅ (Bad Case contextMenu)
//          4.0a: stable relevance order, exact presentationKind gate, real source metadata and Focus route
// 架构约束: AGENTS.md §8.1 (ViewModel 驱动), §17.2 (Discovery adaptive masonry),
//           echo-memory-canvas apple-native 基础; 系统 .searchable + ScrollView
// 生成时间: 2026-08-01; 2026-09-01 (4.0a)
// ==========================================

import SwiftUI

// MARK: - SearchView

/// 检索主视图 — 记忆搜索 + 结果展示 + 反馈交互。
///
/// ## Surface Family: Discovery
/// - 布局: scanEligible 严格多数且通过数量/宽度/AX 门禁时 adaptive masonry，否则稳定单列
/// - 系统容器: NavigationStack (由 AppRootView 提供) + .searchable
/// - Masonry 启用条件: 6+ 可展示结果、scanEligible 严格多数、340pt、非 AX 字号且 VoiceOver 关闭
///
/// ## 状态驱动
/// - idle: 提示文本 + 搜索框
/// - loading: ProgressView / 骨架屏
/// - completed: 结果列表 / 空态
/// - error: L2 重试横幅
/// - cancelled: 返回 idle
///
/// ## 反馈交互 (echo-memory-canvas §14.4/§14.5)
/// - 每张结果卡片右下角 👍/👎 迷你按钮
/// - 长按卡片 → contextMenu "Mark as problem" (Bad Case, US-FBK-003)
/// - 低置信度横幅 (US-RET-006): 结果含低置信度时顶部显示
///
/// ## Style
/// - echo-memory-canvas token: .headline/.body/.caption, Color.primary, semantic colors, SF Symbols
/// - 禁止 Pinterest 品牌元素；continuousReading 多数和平票回退单列
/// - 使用系统 Dynamic Type, semantic colors, 系统容器
struct SearchView: View {
    // MARK: - ViewModel

    @State private var viewModel: SearchViewModel
    private let appViewModel: AppViewModel?
    @State private var discoveryContentWidth: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 搜索框绑定文本
    @State private var searchText: String = ""

    /// 当前选中的记忆 ID — 触发导航到 MemoryDetailView (Focus surface)
    @State private var selectedMemoryID: UUID?

    /// 预加载的记忆详情 ViewModel — Live Sim Review fixture 直接导航
    @State private var detailViewModel: MemoryDetailViewModel?

    /// 预加载的创作结果 ViewModel — Live Sim Review fixture 直接导航 (US-SYN-003, Task 3.9)
    @State private var creationViewModel: CreationViewModel?

    /// 是否展示创作结果页 (US-SYN-003, Task 3.9)
    @State private var isShowingCreation = false

    /// 首次出现标记 — 控制 fixture 注入仅执行一次 (2026-08-02 回归修复)
    @State private var hasHandledLaunchArguments = false

    init(
        viewModel: SearchViewModel = SearchViewModel(composition: AppComposition.shared),
        appViewModel: AppViewModel? = nil
    ) {
        self.appViewModel = appViewModel
        _viewModel = State(initialValue: viewModel)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))

            // Low-confidence banner (US-RET-006) — 顶部叠加
            if viewModel.viewState == .completed && viewModel.hasLowConfidence {
                lowConfidenceBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .searchable(text: $searchText, prompt: "Search your memories")
        .autocorrectionDisabled(true)
        .onSubmit(of: .search) {
            viewModel.submitQuery(searchText)
        }
        .navigationDestination(item: $selectedMemoryID) { memoryID in
            if let detailViewModel {
                MemoryDetailView(viewModel: detailViewModel)
            } else {
                MemoryDetailView(memoryId: memoryID)
            }
        }
        // AI 创作结果页 (US-SYN-003, Task 3.9)
        .navigationDestination(isPresented: $isShowingCreation) {
            if let creationViewModel {
                CreationView(viewModel: creationViewModel)
            } else {
                CreationView()
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .onDisappear { viewModel.onDisappear() }
        .onAppear {
            handleFirstAppear()
            submitPendingHomeQuery()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.viewState)
    }

    // MARK: - Launch Argument Fixture Injection

    /// 首次出现时处理启动参数 fixture 注入。
    ///
    /// 仅首次执行 — TabView 切换 / 详情返回会再次触发 onAppear，
    /// 重复注入会重置用户已浏览的搜索状态（回归 2026-08-02 修复）。
    /// 生产构建（#if DEBUG 排除）无任何注入逻辑。
    private func handleFirstAppear() {
        guard !hasHandledLaunchArguments else { return }
        hasHandledLaunchArguments = true
        #if DEBUG
            handleLaunchArguments()
        #endif
    }

    private func submitPendingHomeQuery() {
        guard let query = appViewModel?.consumePendingSearchQuery() else { return }
        searchText = query
        viewModel.submitQuery(query)
    }

    #if DEBUG
        /// 处理 XCUITest / Live Sim Review 启动参数注入确定性 fixture。
        ///
        /// 支持 `-ui-fixture search-loaded|search-empty|search-lowconfidence`，
        /// 通过 SearchFixtureLoader 加载确定性数据到 loaded 状态。
        /// 仅用于自动化；生产构建（#if DEBUG 排除）无此钩子。
        private func handleLaunchArguments() {
            let args = ProcessInfo.processInfo.arguments
            guard let idx = args.firstIndex(of: "-ui-fixture"), idx + 1 < args.count else { return }
            let fixtureID = args[idx + 1]

            // 支持 `-ui-fixture memory-detail-*` 直接导航到记忆详情 (Live Sim Review)
            if fixtureID.hasPrefix("memory-detail-") {
                if let model = MemoryDetailFixtureLoader.load(fixtureID) {
                    let vm = MemoryDetailViewModel()
                    vm.loadPreloaded(model)
                    detailViewModel = vm
                    selectedMemoryID = model.id
                }
                return
            }

            // 支持 `-ui-fixture translation-*` 导航到翻译 surface (Task 3.8)
            if fixtureID.hasPrefix("translation-") {
                if let model = TranslationFixtureLoader.load(fixtureID) {
                    let vm = MemoryDetailViewModel()
                    vm.loadPreloaded(model)
                    detailViewModel = vm
                    selectedMemoryID = model.id
                }
                return
            }

            // 支持 `-ui-fixture creation-*` 导航到创作结果 surface (Task 3.9)
            if fixtureID.hasPrefix("creation-") {
                if let model = CreationFixtureLoader.load(fixtureID) {
                    let vm = CreationViewModel()
                    vm.loadPreloaded(model)
                    creationViewModel = vm
                    isShowingCreation = true
                }
                return
            }

            let items = SearchFixtureLoader.load(fixtureID)
            viewModel.loadPreloadedResults(items)
        }
    #endif

    // MARK: - Navigation

    /// 点击结果卡片 → 记忆详情（US-RET-001 结果展示 / 3.3 详情页）。
    ///
    /// Explicit fixture journeys may resolve a deterministic detail fixture. Production
    /// results always navigate through the live canonical repository.
    private func openDetail(for result: SearchResultModel) {
        if viewModel.isFixtureBacked,
            let model = MemoryDetailFixtureLoader.load(memoryID: result.id) {
            let vm = MemoryDetailViewModel()
            vm.loadPreloaded(model)
            detailViewModel = vm
        } else {
            detailViewModel = nil
        }
        selectedMemoryID = result.id
    }

    // MARK: - Content Views

    /// 根据 ViewState 渲染对应内容
    @ViewBuilder
    private var contentView: some View {
        switch viewModel.viewState {
        case .idle:
            idlePrompt

        case .loading:
            loadingState

        case .completed:
            if viewModel.results.isEmpty {
                emptyState
            } else {
                resultList
            }

        case .error(let level):
            errorView(level: level)

        case .cancelled:
            Color(.systemBackground)
                .onAppear { viewModel.dismissError() }
        }
    }

    // MARK: - Idle State

    /// 初始提示态 — 鼓励用户开始搜索
    private var idlePrompt: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(Color.secondary)
                .accessibilityHidden(true)

            Text("Search your memories")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.primary)

            Text("Photos, videos, notes and voice — all offline on your device.")
                .font(.body)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search your memories")
    }

    // MARK: - Loading State

    /// 加载态 — 系统 ProgressView (echo-memory-canvas §10.2)
    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .tint(Color.accentColor)
                .controlSize(.large)

            Text("Searching…")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)

            Spacer().frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Searching memories")
    }

    // MARK: - Empty State

    /// 空态 — 无匹配结果 (echo-memory-canvas §10.1.3 Task 标准空态风格适配 Discovery)
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(Color.secondary)
                .accessibilityHidden(true)

            Text("No memories found")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.primary)

            Text("Try a different search term.")
                .font(.body)
                .foregroundStyle(Color.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No memories found for your search")
    }

    // MARK: - Result List

    /// Result canvas — adaptive masonry only when the deterministic policy allows it.
    private var resultList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EchoSpacingToken.grouped.points) {
                HStack {
                    Text("Results")
                        .font(EchoTypographyToken.subtitle.font)
                        .foregroundStyle(EchoColorToken.primaryText.color)

                    Spacer()

                    Text("\(viewModel.results.count)")
                        .font(EchoTypographyToken.metadata.font)
                        .foregroundStyle(EchoColorToken.secondaryText.color)
                }
                .accessibilityAddTraits(.isHeader)

                resultCards
            }
            .padding(.horizontal, EchoSpacingToken.grouped.points)
            .padding(.vertical, EchoSpacingToken.compact.points)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                discoveryContentWidth = max(0, width - 32)
            }
        }
        .accessibilityIdentifier("search-results-list")
    }

    @ViewBuilder
    private var resultCards: some View {
        let environment = DiscoveryLayoutEnvironment(
            contentWidth: discoveryContentWidth,
            usesAccessibilityDynamicType: dynamicTypeSize.isAccessibilitySize,
            voiceOverEnabled: voiceOverEnabled
        )
        if viewModel.discoveryLayoutMode(environment: environment) == .adaptiveMasonry {
            DiscoveryMasonryLayout {
                resultCardViews
            }
        } else {
            LazyVStack(spacing: EchoSpacingToken.normal.points) {
                resultCardViews
            }
        }
    }

    @ViewBuilder
    private var resultCardViews: some View {
        ForEach(viewModel.results) { result in
            SearchResultRow(
                result: result,
                feedbackState: viewModel.feedbackStates[result.id] ?? .none,
                onLike: { viewModel.recordLike(result) },
                onDislike: { viewModel.recordDislike(result) },
                onMarkBadCase: { viewModel.markBadCase(result) },
                onOpen: { openDetail(for: result) },
                onCreate: viewModel.isFixtureBacked
                    ? nil
                    : {
                        let composition = AppComposition.shared
                        let model = CreationViewModel(
                            creativePipeline: composition.creativePipeline,
                            exportCoordinator: composition.creationExportCoordinator,
                            narrativeReportActor: composition.narrativeReportActor,
                            creationLibrary: composition.creationLibraryActor
                        )
                        model.loadSourceMemories([
                            CreativeSource(
                                memoryID: result.id,
                                assetID: "",
                                sourceType: result.sourceType,
                                text: result.originalText,
                                timestamp: result.timestamp
                            ),
                        ])
                        creationViewModel = model
                        isShowingCreation = true
                    }
            )
        }
    }

    // MARK: - Low-Confidence Banner

    /// 跨语言低置信度横幅 (US-RET-006, echo-memory-canvas §14.3)
    private var lowConfidenceBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(Color.secondary)

            Text("Some results have lower relevance. Try refining your keywords or phrasing.")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .accessibilityLabel("Low confidence search results")
        .accessibilityHint("Some results may have lower relevance")
    }

    // MARK: - Error State

    /// 错误视图 — L2 重试横幅 (docs/ui/architecture.md §2.2 错误传播)
    @ViewBuilder
    private func errorView(level: SearchViewModel.ErrorLevel) -> some View {
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
                    viewModel.retry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.callout)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search-retry-button")
            }

            Spacer().frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Helpers

    private func errorTitle(for level: SearchViewModel.ErrorLevel) -> String {
        switch level {
        case .l2Recoverable: return "Search failed"
        case .l3Blocking: return "Unable to continue"
        }
    }

    private func errorMessage(for level: SearchViewModel.ErrorLevel) -> String {
        switch level {
        case .l2Recoverable(let msg),
            .l3Blocking(let msg):
            return msg
        }
    }

    private func isRecoverable(_ level: SearchViewModel.ErrorLevel) -> Bool {
        switch level {
        case .l2Recoverable: return true
        case .l3Blocking: return false
        }
    }
}

// MARK: - SearchResultRow

/// 单条搜索结果卡片组件。
///
/// ## Surface Family: Discovery
/// - 自适应单列卡片, 遵循 echo-memory-canvas token
/// - 包含: 类型标签 + 摘要 + 时间 + 相似度 + 👍/👎 反馈按钮
/// - 长按: contextMenu "Mark as problem" (Bad Case, US-FBK-003)
/// - 点击: 🔮 跳转 Focus surface (Phase 3.3 MemoryDetailView)
///
/// ## Style
/// - 系统 background + shadow 层级
/// - 系统 Dynamic Type: .headline, .subheadline, .caption
/// - SF Symbols: hand.thumbsup.fill / hand.thumbsdown.fill / flag.fill
struct SearchResultRow: View {
    let result: SearchResultModel
    let feedbackState: SearchViewModel.FeedbackState
    let onLike: () -> Void
    let onDislike: () -> Void
    let onMarkBadCase: () -> Void
    let onOpen: () -> Void
    var onCreate: (() -> Void)?

    var body: some View {
        EchoContainer(level: .card) {
            VStack(alignment: .leading, spacing: EchoSpacingToken.normal.points) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: EchoSpacingToken.normal.points) {
                        if let aspectRatio = result.aspectRatio {
                            DiscoveryMediaThumbnail(
                                assetID: result.assetId,
                                aspectRatio: aspectRatio,
                                sourceType: result.sourceType
                            )
                        }

                        Text(result.summary)
                            .font(EchoTypographyToken.body.font)
                            .foregroundStyle(EchoColorToken.primaryText.color)
                            .lineLimit(result.presentationKind == .scanEligible ? 3 : nil)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        EchoMetadataGroup {
                            Text(result.sourceTypeLabel)
                            Text(result.dateDescription)
                            if let locationLabel = result.locationLabel {
                                Label(locationLabel, systemImage: "location")
                            }
                            Label("\(result.similarityPercent) match", systemImage: "bolt.fill")
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(result.accessibilityLabel)
                .accessibilityHint("Open memory details")

                HStack(spacing: EchoSpacingToken.normal.points) {
                    Spacer()
                    feedbackButton(
                        selected: feedbackState == .liked,
                        systemImage: "hand.thumbsup",
                        selectedSystemImage: "hand.thumbsup.fill",
                        label: "Like this result",
                        identifier: "result-like-\(result.id.uuidString)",
                        action: onLike
                    )
                    feedbackButton(
                        selected: feedbackState == .disliked,
                        systemImage: "hand.thumbsdown",
                        selectedSystemImage: "hand.thumbsdown.fill",
                        label: "Dislike this result",
                        identifier: "result-dislike-\(result.id.uuidString)",
                        action: onDislike
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .contextMenu {
            if let onCreate {
                Button(action: onCreate) {
                    Label("AI Creation", systemImage: "sparkles")
                }
                .accessibilityIdentifier("result-create-\(result.id.uuidString)")
            }
            Button {
                onMarkBadCase()
            } label: {
                Label("Mark as problem", systemImage: "flag.fill")
            }
            .accessibilityIdentifier("result-badcase-\(result.id.uuidString)")
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func feedbackButton(
        selected: Bool,
        systemImage: String,
        selectedSystemImage: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: selected ? selectedSystemImage : systemImage)
                .foregroundStyle(
                    selected ? EchoColorToken.warmAccent.color : EchoColorToken.secondaryText.color
                )
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Preview

#Preview("Idle") {
    NavigationStack {
        SearchView()
    }
}

#Preview("Loading") {
    NavigationStack {
        SearchView(
            viewModel: makeSearchViewModel(
                state: .loading
            )
        )
    }
}

#Preview("Loaded Results") {
    NavigationStack {
        SearchView(
            viewModel: makeSearchViewModel(
                state: .loaded
            )
        )
    }
}

#Preview("Empty Results") {
    NavigationStack {
        SearchView(
            viewModel: makeSearchViewModel(
                state: .empty
            )
        )
    }
}

#Preview("Low Confidence") {
    NavigationStack {
        SearchView(
            viewModel: makeSearchViewModel(
                state: .lowConfidence
            )
        )
    }
}

#Preview("Error") {
    NavigationStack {
        SearchView(
            viewModel: makeSearchViewModel(
                state: .error
            )
        )
    }
}

// MARK: - Preview Helpers

/// 从 fixture 构造确定性搜索结果。
@MainActor
private func makeSearchViewModel(state: SearchState) -> SearchViewModel {
    let vm = SearchViewModel()

    switch state {
    case .loading:
        vm.submitQuery("preview")

    case .loaded:
        vm.loadPreloadedResults([
            makeResultItem(
                ResultFixtureConfig(
                    id: fixtureID("11111111-1111-1111-1111-111111111111"),
                    assetId: "photo-zh-1",
                    sourceType: "photo",
                    timestamp: 1723507200,
                    originalText: nil,
                    cosineSimilarity: 0.91
                )
            ),
            makeResultItem(
                ResultFixtureConfig(
                    id: fixtureID("22222222-2222-2222-2222-222222222222"),
                    assetId: "note-zh-2",
                    sourceType: "note",
                    timestamp: 1723420800,
                    originalText: "昨晚在公园遇到一只橘猫，很亲人",
                    cosineSimilarity: 0.87
                )
            ),
        ])

    case .empty:
        vm.loadPreloadedResults([])

    case .lowConfidence:
        vm.loadPreloadedResults([
            makeResultItem(
                ResultFixtureConfig(
                    id: fixtureID("33333333-3333-3333-3333-333333333333"),
                    assetId: "photo-en-1",
                    sourceType: "photo",
                    timestamp: 1723680000,
                    originalText: nil,
                    cosineSimilarity: 0.82,
                    lowConfidence: true
                )
            ),
        ])

    case .error:
        vm.simulateError(.l2Recoverable(message: "Search failed. Please try again."))
    }

    return vm
}

private func fixtureID(_ string: String) -> UUID {
    UUID(uuidString: string) ?? UUID()
}

/// 构造确定性 SearchResultItem (Preview fixture)
private struct ResultFixtureConfig {
    var id: UUID
    var assetId: String
    var sourceType: String
    var timestamp: TimeInterval
    var originalText: String?
    var cosineSimilarity: Float
    var lowConfidence: Bool = false
}

private func makeResultItem(_ config: ResultFixtureConfig) -> SearchResultItem {
    SearchResultItem(
        id: config.id,
        assetId: config.assetId,
        sourceType: config.sourceType,
        timestamp: config.timestamp,
        originalText: config.originalText,
        sourceLanguage: config.originalText == nil ? nil : "zh-Hans",
        crossLanguageMatch: false,
        cosineSimilarity: config.cosineSimilarity,
        alignmentScore: config.lowConfidence ? 0.55 : nil,
        feedbackAdjustment: nil,
        lowConfidence: config.lowConfidence,
        fallbackReason: config.lowConfidence ? "cross_language_low_alignment" : nil,
        unappliedFilters: []
    )
}

/// Preview 状态枚举
private enum SearchState {
    case loading
    case loaded
    case empty
    case lowConfidence
    case error
}
