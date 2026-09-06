// ==========================================
// 文件: SettingsView.swift
// i18n: User-facing strings resolve through Localizable.xcstrings (zh-Hans + en-US).
// 对应规格: docs/01-spec/用户故事与验收标准规格书.md → US-SRC-004/007/008/009,
//            US-PRV-002/003/005, US-RES-004, US-SET-001/002/003/004, US-FBK-002
//            docs/ui/echo-memory-canvas-style.md §3.3 (Task surfaces), §7.2 (Task surfaces),
//            §10.1.3 (空态), §11 (Toast/Banner)
//            docs/ui/architecture.md §2 (单向数据流), §3 (组件边界)
// Task: 4.0c + 4.0h - Balanced Canvas task surface and cascade cleanup notice
// Runtime status: the main overview and supported destructive actions use live services.
// Placeholder sub-pages and unavailable service boundaries are labeled/fail visibly rather than
// presenting fixture-backed success in production.
//            US-SET-002 AC-1/AC-3 ✅, US-SET-003 AC-1/AC-3 ✅,
//            US-SET-004 AC-1 ✅ / AC-2 🔶 (sub-page deferred to 3.9),
//            US-FBK-002 AC-5 ✅, US-PRV-005 AC-1/AC-2/AC-4 ✅
// 架构约束: AGENTS.md §8.1 (@MainActor + @Observable), echo-memory-canvas apple-native 基础,
//           Task surface family (Form/List, 禁止 masonry), §2.3 (semantic colors),
//           §2.4 (SF Symbols), §2.5 (可访问性)
// Generated: 2026-09-02 | Updated: 2026-09-05
// ==========================================

import SwiftUI

// MARK: - SettingsView

/// Settings 视图 — 设置、管理与数据控制面板
///
/// ## Surface Family: Task
/// - 使用系统 Form container with sections
/// - 遵循 echo-memory-canvas style tokens (semantic colors, SF Symbols, Dynamic Type)
/// - Masonry: 绝对禁止
///
/// ## 数据流 (docs/ui/architecture.md §2.1)
/// - User Action → SettingsViewModel action → Core Actor → State Update → View Re-render
///
/// ## Sections
/// - Data Sources: 授权开关 (US-SRC-004)
/// - Storage & Cache: 存储概览 + 清理缓存 (US-SRC-009, US-SET-003)
/// - Excluded Items: 排除项管理入口 (US-SRC-008)
/// - Feedback: 反馈记录 + 重置 (US-FBK-002)
/// - Audit Log: 审计日志查看 + 导出 (US-PRV-002/003)
/// - Model Status: 模型状态 (US-RES-004)
/// - Migration Guide: 迁移指引 (US-SRC-007, US-SET-004)
/// - Account: 删除数据 + 冷却期 (US-PRV-005)
/// - About: 永久保留策略 (US-SET-002)
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @Environment(\.echoDesignProfile) private var designProfile

    /// 注入或默认构造 ViewModel；State 首次构建后复用同一实例（Nitpick：避免默认参数每次重建 VM）。
    init(viewModel: SettingsViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? SettingsViewModel(
            composition: AppComposition.shared,
            dataOverviewService: LiveAppAdapters.makeDataOverviewService()
        ))
    }

    var body: some View {
        content
            .background(EchoColorToken.groupedBackground.color)
            .environment(\.echoDesignProfile, designProfile)
            .navigationTitle("Settings")
            .task { await viewModel.loadSettings() }
            .alert("Clear Cache", isPresented: $viewModel.showClearCacheConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { Task { await viewModel.confirmClearCache() } }
            } message: { Text("This will clear translation cache, search result cache, and thumbnail cache. Vector indices and original media will not be affected.") }
            .alert("Reset All Feedback", isPresented: $viewModel.showResetFeedbackConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { Task { await viewModel.confirmResetFeedback() } }
            } message: { Text("This will permanently delete all your feedback learning data. Re-ranking weights will return to defaults. This cannot be undone.") }
            .alert("Delete All Echo Data", isPresented: $viewModel.showDeleteDataConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Start Deletion", role: .destructive) { Task { await viewModel.startDeleteData() } }
            } message: { Text("A 24-hour cooling period will begin. During this time, you can cancel. After cooling period ends, all Echo data will be permanently erased. Your original photos and files will not be affected.") }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            loadingView

        case .completed(let sections):
            settingsForm(sections)

        case .error(let level):
            errorView(level)

        case .cancelled:
            cancelledView
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        EchoContainer(level: .card) {
            HStack(spacing: EchoSpacingToken.normal.points) {
                ProgressView()
                    .tint(EchoColorToken.warmAccent.color)
                Text("Loading settings...")
                    .font(EchoTypographyToken.metadata.font)
                    .foregroundStyle(EchoColorToken.secondaryText.color)
            }
        }
        .padding(EchoSpacingToken.section.points)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(EchoColorToken.groupedBackground.color)
    }

    // MARK: - Error State

    private func errorView(_ level: SettingsViewModel.ErrorLevel) -> some View {
        EchoContainer(level: .card) {
            VStack(alignment: .leading, spacing: EchoSpacingToken.grouped.points) {
                EchoStatusPresentation(
                    role: .warning,
                    systemImage: "exclamationmark.triangle.fill",
                    title: EchoStrings.tr("Unable to Load Settings"),
                    message: EchoStrings.tr("Please try again.")
                )
                Button(action: { Task { await viewModel.retry() } }) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(EchoActionButtonStyle(role: .recovery))
            }
        }
        .padding(EchoSpacingToken.section.points)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(EchoColorToken.groupedBackground.color)
        .accessibilityLabel("Settings error")
        .accessibilityHint("Tap Retry to reload settings")
    }

    // MARK: - Cancelled State

    private var cancelledView: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle")
                .font(.largeTitle)
                .foregroundStyle(Color.secondary)
            Text("Settings loading was cancelled")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EchoColorToken.groupedBackground.color)
    }

    // MARK: - Settings Form

    private func settingsForm(_ sections: SettingsSections) -> some View {
        Form {
            languageSection
            lowPowerSection
            dataSourcesSection(sections)
            awakeningSection
            storageSection(sections)
            excludedItemsSection(sections)
            feedbackSection(sections)
            auditLogSection
            modelStatusSection(sections)
            migrationSection
            accountSection
            aboutSection
        }
        .background(EchoColorToken.groupedBackground.color)
    }

    // MARK: - Language Section (US-DIS-001 / US-SET-001: single unified App Language)

    private var languageSection: some View {
        Section {
            Picker(selection: Binding(
                get: { viewModel.languageSelection },
                set: { newValue in
                    Task { await viewModel.setLanguage(newValue) }
                }
            )) {
                Text("Follow System").tag(LanguageCenter.AppLanguageSelection.followSystem)
                Text("Simplified Chinese").tag(LanguageCenter.AppLanguageSelection.zhHans)
                Text("English").tag(LanguageCenter.AppLanguageSelection.enUS)
            } label: {
                Text("App Language")
            }
            .accessibilityIdentifier("settings-app-language")
        } header: {
            Text("App Language")
        } footer: {
            Text("Select the language Echo uses to display and respond.")
        }
    }

    // MARK: - Low Power Section (US-RES-002 AC-3: default-on auto-pause toggle)

    private var lowPowerSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { DegradationBannerViewModel.isAutoPauseOnLowPowerEnabled },
                set: { DegradationBannerViewModel.isAutoPauseOnLowPowerEnabled = $0 }
            )) {
                Text("Pause background tasks during low power")
            }
            .accessibilityIdentifier("settings-low-power-auto-pause")
        } footer: {
            Text("When off, background tasks keep running in Low Power Mode and may use more battery.")
        }
    }

    // MARK: - Data Sources Section (US-SRC-004)

    private func dataSourcesSection(_ sections: SettingsSections) -> some View {
        Section {
            ForEach(sections.dataSources) { source in
                if source.id == "photo" {
                    // 3F.11 fix: 照片行始终可点击 — 未授权=授权+首次导入；已授权=重新导入（重触发）
                    Button {
                        Task { await viewModel.requestPhotoLibraryAccess() }
                    } label: {
                        photoDataSourceRow(source)
                    }
                    .disabled(viewModel.photoImportState == .requesting
                              || viewModel.photoImportState == .importing)
                    .accessibilityHint(source.isAuthorized
                                       ? "Re-syncs your photo library into Echo"
                                       : "Requests photo library access and indexes your photos")
                } else {
                    dataSourceRow(source)
                }
            }

            // 3F.11 fix: 首次全量导入进度指示
            if case .importing = viewModel.photoImportState {
                HStack {
                    ProgressView()
                        .padding(.trailing, 4)
                    Text("Importing photos…")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Importing photos")
            }

            // 3F.11 fix: 照片授权/导入错误态展示（此前静默）
            if case .error(let level) = viewModel.photoImportState {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(photoErrorText(level))
                        .font(.caption)
                }
                .foregroundStyle(Color.red)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Photo import error")
            }

            Toggle(isOn: Binding(
                get: { viewModel.isSyncingEnabled },
                set: { viewModel.toggleSync($0) }
            )) {
                Label {
                    Text("Background Auto Sync")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .accessibilityLabel("Background Auto Sync")
            .accessibilityHint("When enabled, new data will be automatically synced in the background")

            Toggle(isOn: Binding(
                get: { viewModel.isPeriodicScanEnabled },
                set: { viewModel.togglePeriodicScan($0) }
            )) {
                Label {
                    Text("Periodic Scan for Missing Data")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .accessibilityLabel("Periodic Scan")
            .accessibilityHint("When enabled, Echo periodically checks for data not yet imported")
        } header: {
            Text("Data Sources")
        } footer: {
            Text("Photo access is required for Echo to index your memories. Notes and Voice Memos support coming via Share Extension — share content directly to Echo to index it.")
        }
    }

    private func photoErrorText(_ level: SettingsViewModel.ErrorLevel) -> String {
        switch level {
        case .l1Transient:
            return EchoStrings.tr("settings.photo.import.unavailable")

        case .l2Recoverable(let message), .l3Blocking(let message), .l4Conflict(let message):
            return message
        }
    }

    private func photoDataSourceRow(_ source: DataSourceItem) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.displayName)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                    if source.isAuthorized {
                        Text("\(source.itemCount) items indexed — tap to re-sync")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    } else {
                        Text("Not authorized — tap to grant access")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
            } icon: {
                Image(systemName: source.systemImage)
                    .foregroundStyle(Color.accentColor)
            }

            Spacer()

            if viewModel.photoImportState == .requesting
                || viewModel.photoImportState == .importing {
                ProgressView()
            } else if source.isAuthorized {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Authorized")
            } else {
                Image(systemName: "arrow.forward.circle")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func dataSourceRow(_ source: DataSourceItem) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.displayName)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                    Text(source.isAuthorized ? "\(source.itemCount) items indexed" : "Not authorized")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            } icon: {
                Image(systemName: source.systemImage)
                    .foregroundStyle(Color.accentColor)
            }

            Spacer()

            if source.isAuthorized {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Authorized")
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(Color.secondary)
                    .accessibilityLabel("Not authorized")
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Awakening Section (US-AWK-001/002/003 — Task 3.12)

    private var awakeningSection: some View {
        Section {
            NavigationLink {
                // 3F.11 fix: 生产注入 live 系统适配器 — 真实权限状态 + 真实通知授权（ADR-012 决策-2/3）
                AwakeningSettingsView(viewModel: AwakeningSettingsViewModel(
                    locationProvider: AppComposition.shared.productionLocationProvider ?? CoreLocationProvider(),
                    healthStore: AppComposition.shared.productionHealthStore ?? RealHealthStore(),
                    notificationScheduler: AppComposition.shared.productionNotificationScheduler ?? LocalNotificationAdapter(),
                    preferenceStore: AppComposition.shared.awakeningPreferenceStore
                ))
            } label: {
                Label {
                    Text("Awakening")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .accessibilityLabel("Awakening settings")
            .accessibilityHint("Manage notification, location, and health permissions for memory awakening")
        } header: {
            Text("Awakening")
        } footer: {
            Text("Configure how Echo proactively delivers memories based on location, date anniversaries, and mood.")
        }
    }

    // MARK: - Storage Section (US-SRC-009, US-SET-003)

    private func storageSection(_ sections: SettingsSections) -> some View {
        Section {
            HStack {
                Label {
                    Text("Indexed Items")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Text("\(sections.storage.indexCount)")
                    .font(.body)
                    .foregroundStyle(Color.secondary)
            }
            .accessibilityLabel(String(format: EchoStrings.tr("%lld indexed items"), sections.storage.indexCount))

            HStack {
                Label {
                    Text("Vector Store")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: "circle.grid.3x3")
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Text(sections.storage.vectorStoreSize)
                    .font(.body)
                    .foregroundStyle(Color.secondary)
            }

            HStack {
                Label {
                    Text("Cache")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Text(sections.storage.cacheSize)
                    .font(.body)
                    .foregroundStyle(Color.secondary)
            }

            HStack {
                Label {
                    Text("Database")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: "externaldrive")
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Text(sections.storage.databaseSize)
                    .font(.body)
                    .foregroundStyle(Color.secondary)
            }

            Button(action: { viewModel.clearCache() }) {
                Label("Clear Cache", systemImage: "trash")
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Clear Cache")
            .accessibilityHint("Clears translation, search, and thumbnail caches. Vector indices preserved.")
        } header: {
            Text("Storage & Cache")
        }
    }

    // MARK: - Excluded Items Section (US-SRC-008)

    private func excludedItemsSection(_ sections: SettingsSections) -> some View {
        Section {
            NavigationLink {
                excludedItemsPlaceholder
            } label: {
                HStack {
                    Label {
                        Text("Excluded Items")
                            .font(.body)
                            .foregroundStyle(Color.primary)
                    } icon: {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Text("\(sections.excludedCount)")
                        .font(.body)
                        .foregroundStyle(Color.secondary)
                }
            }
            .accessibilityLabel(String(format: EchoStrings.tr("Excluded Items, %lld items"), sections.excludedCount))
        } header: {
            Text("Data Management")
        } footer: {
            Text("Items excluded from Echo indexing. You can restore them here if the original file still exists.")
        }
    }

    private var excludedItemsPlaceholder: some View {
        ExcludedItemsStatusView(viewModel: ExcludedItemsViewModel(
            excludedAssets: AppComposition.shared.excludedAssetsActor
        ))
    }

    // MARK: - Feedback Section (US-FBK-002)

    private func feedbackSection(_ sections: SettingsSections) -> some View {
        Section {
            NavigationLink {
                feedbackPlaceholder
            } label: {
                HStack {
                    Label {
                        Text("Feedback Records")
                            .font(.body)
                            .foregroundStyle(Color.primary)
                    } icon: {
                        Image(systemName: "hand.thumbsup")
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Text("\(sections.feedbackCount)")
                        .font(.body)
                        .foregroundStyle(Color.secondary)
                }
            }
            .accessibilityLabel(String(format: EchoStrings.tr("Feedback Records, %lld entries"), sections.feedbackCount))

            Button(role: .destructive, action: { viewModel.resetAllFeedback() }) {
                Label("Reset All Feedback Learning Data", systemImage: "arrow.counterclockwise")
            }
            .accessibilityLabel("Reset All Feedback")
            .accessibilityHint("Permanently deletes all feedback and resets re-ranking weights")
        } header: {
            Text("Feedback & Learning")
        }
    }

    private var feedbackPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.thumbsup")
                .font(.system(size: 48))
                .foregroundStyle(Color.secondary)
            Text("Feedback Records")
                .font(.headline)
            Text("Detailed feedback management coming in next iteration.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Feedback Records")
    }

    // MARK: - Audit Log Section (US-PRV-002/003)

    private var auditLogSection: some View {
        Section {
            NavigationLink {
                auditLogPlaceholder
            } label: {
                Label {
                    Text("View Audit Log")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .accessibilityLabel("View Audit Log")

            Button(action: { viewModel.exportAuditLog() }) {
                Label("Export Audit Log (JSON)", systemImage: "square.and.arrow.up")
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Export Audit Log")
            .accessibilityHint("Exports the last 30 days of privacy operation records as JSON")
        } header: {
            Text("Privacy & Audit")
        } footer: {
            Text("Audit log records the last 30 days of privacy operations. Contains no user data — only operation types, timestamps, and hash digests.")
        }
    }

    private var auditLogPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.secondary)
            Text("Audit Log")
                .font(.headline)
            Text("Detailed audit log viewer coming in next iteration.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Audit Log")
    }

    // MARK: - Model Status Section (US-RES-004, US-SRC-009)

    private func modelStatusSection(_ sections: SettingsSections) -> some View {
        Section {
            NavigationLink {
                modelStatusPlaceholder
            } label: {
                HStack(spacing: 8) {
                    Label {
                        Text("Model Status")
                            .font(.body)
                            .foregroundStyle(Color.primary)
                    } icon: {
                        Image(systemName: "cpu")
                            .foregroundStyle(Color.accentColor)
                    }

                    Spacer()

                    if sections.modelStatus.isDegraded {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.yellow)
                    }

                    Text(String(format: EchoStrings.tr("%lld/%lld loaded"), sections.modelStatus.loadedCount, sections.modelStatus.totalModels))
                        .font(.caption)
                        .foregroundStyle(sections.modelStatus.isDegraded ? Color.yellow : Color.secondary)
                }
            }
            .accessibilityLabel(String(format: EchoStrings.tr("Model Status, %lld of %lld loaded"), sections.modelStatus.loadedCount, sections.modelStatus.totalModels))
        } header: {
            Text("AI Models")
        } footer: {
            if sections.modelStatus.isDegraded {
                Text("Some models failed to load. Basic keyword search is still available.")
            } else {
                Text("All AI models loaded and ready. Models run entirely on-device with no network required.")
            }
        }
    }

    private var modelStatusPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(Color.secondary)
            Text("Model Status")
                .font(.headline)
            Text("Detailed model status page coming in next iteration.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Model Status")
    }

    // MARK: - Migration Section (US-SRC-007, US-SET-004)

    private var migrationSection: some View {
        Section {
            NavigationLink {
                migrationPlaceholder
            } label: {
                Label {
                    Text("Data Migration Guide")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .accessibilityLabel("Data Migration Guide")
        } header: {
            Text("Device Migration")
        } footer: {
            Text("Transfer an encrypted Echo migration package using AirDrop or an encrypted Finder backup. Original media stays in its system source and is not exported.")
        }
    }

    private var migrationPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 48))
                .foregroundStyle(Color.secondary)
            Text("Data Migration Guide")
                .font(.headline)
            Text("An encrypted Echo migration package can move Echo-owned indices, settings, feedback, and exclusions. Original media stays in its system source and is not exported.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Migration Guide")
    }

    // MARK: - Account Section (US-PRV-005)

    private var accountSection: some View {
        Section {
            Button(role: .destructive, action: { viewModel.showDeleteDataConfirmation = true }) {
                Label("Delete All Echo Data", systemImage: "trash")
            }
            .accessibilityLabel("Delete All Echo Data")
            .accessibilityHint("Starts a 24-hour cooling period before permanent deletion of all Echo data")
        } header: {
            Text("Account & Data")
        } footer: {
            Text("Deleting Echo data will erase all indices, vectors, settings and feedback. Your original photos, videos, and files in system apps will NOT be affected. A 24-hour cooling period applies before data is permanently removed.")
        }
    }

    // MARK: - About Section (US-SET-002)

    private var aboutSection: some View {
        Section {
            HStack {
                Label {
                    Text("Memory Policy")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Text("Permanent")
                    .font(.body)
                    .foregroundStyle(Color.secondary)
            }
            .accessibilityLabel("Memory retention policy: Permanent. All memories are kept forever, only deleted manually.")

            HStack {
                Label {
                    Text("Version")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Text("v4.6")
                    .font(.body)
                    .foregroundStyle(Color.secondary)
            }
        } header: {
            Text("About")
        } footer: {
            Text("Echo · 回响 — Your memories, always within reach. All AI processing runs locally on your device. No data ever leaves your phone.")
        }
    }
}

private struct ExcludedItemsStatusView: View {
    @State private var viewModel: ExcludedItemsViewModel

    init(viewModel: ExcludedItemsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: EchoSpacingToken.section.points) {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView()

            case .completed(let cleanupCount, _):
                if cleanupCount > 0 {
                    EchoContainer(level: .section) {
                        EchoStatusPresentation(
                            role: .informational,
                            systemImage: "checkmark.shield",
                            title: EchoStrings.tr("Excluded items cleaned up"),
                            message: String(
                                format: EchoStrings.tr("%lld excluded item references were removed because their original Photo Library items no longer exist."),
                                cleanupCount
                            )
                        )
                    }
                    .accessibilityIdentifier("excluded-cleanup-notice")
                }
                excludedManagementPlaceholder

            case .error:
                EchoStatusPresentation(
                    role: .warning,
                    systemImage: "exclamationmark.triangle",
                    title: EchoStrings.tr("Unable to Load Excluded Items"),
                    message: EchoStrings.tr("Please try again.")
                )
                Button(EchoStrings.tr("Retry")) {
                    Task { await viewModel.load() }
                }
                .buttonStyle(EchoActionButtonStyle(role: .recovery))

            case .cancelled:
                EmptyView()
            }
        }
        .padding(EchoSpacingToken.section.points)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(EchoColorToken.groupedBackground.color)
        .navigationTitle(EchoStrings.tr("Excluded Items"))
        .task { await viewModel.load() }
        .onChange(of: viewModel.state) { _, state in
            guard case .completed(let count, let wasPresented) = state,
                  count > 0,
                  !wasPresented else { return }
            Task {
                await Task.yield()
                await viewModel.markCleanupNoticePresented(visibleCount: count)
            }
        }
    }

    private var excludedManagementPlaceholder: some View {
        EchoContainer(level: .section) {
            VStack(spacing: EchoSpacingToken.normal.points) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(EchoColorToken.secondaryText.color)
                Text(EchoStrings.tr("Excluded Items"))
                    .font(EchoTypographyToken.title.font)
                Text(EchoStrings.tr("Management interface coming in next iteration."))
                    .font(EchoTypographyToken.metadata.font)
                    .foregroundStyle(EchoColorToken.secondaryText.color)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Preview

#Preview("Loaded") {
    NavigationStack {
        SettingsView()
    }
}

#Preview("Error") {
    NavigationStack {
        let vm = SettingsViewModel()
        SettingsView()
            .task {
                vm.state = .error(.l2Recoverable("Failed to load"))
            }
    }
}
