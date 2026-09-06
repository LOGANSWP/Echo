// ==========================================
// 文件: MemoryDetailViewModel.swift
// i18n: All user-facing strings are hardcoded English. Full String Catalog migration (zh-Hans + en-US) deferred to Phase 3.8.
// 对应规格: docs/01-spec/用户故事与验收标准规格书.md → US-AWK-007 (手动编辑记忆),
//            US-SYN-002 (溯源锚点), US-SYN-003 (创作预览), US-PRV-004 (删除确认), US-DIS-002 (按需翻译)
//            docs/ui/echo-memory-canvas-style.md §3.2 (Focus surfaces — 单列 + grouped metadata),
//            docs/ui/architecture.md §6 (ViewModel 契约), §7 (适配器契约)
// Task: 3.3 + 4.0e + 4.0h - MemoryDetail UI, edit/conflict, and source lifecycle
// AC coverage: US-AWK-007 editing/re-index/conflict actions use the live MemoryEditActor boundary;
//          US-DIS-002 AC-1 ✅ (展开详情触发), AC-2 ✅ (cache-first + TranslationService fallback),
//          AC-3 ✅ (源语言检测不确定 <0.9 保留原文为主, ADR-005), AC-4 ✅ (原文/译文切换), AC-5 ✅ (缓存写入 TTL=7d),
//          US-PRV-004 remove-from-Echo uses CanonicalMemoryRepositoryActor in production;
//          US-PRV-004 original-source deletion is exposed only for live-deletable PhotoKit assets,
//          US-SYN-002 AC-1 ✅ (溯源锚点展示), US-SYN-003 AC-3 ✅ (创作预览/复制)
// 架构约束: AGENTS.md §8.1 (@MainActor + @Observable + state enum: idle/loading/completed/error/cancelled),
//           §8.2 (状态流转), §4.2 (仅持有不可变引用), docs/ui/architecture.md §6~7 (适配器契约),
//           §2.5 (Adapter 不保存第二份领域真相 — 仅转换展示字段)
// Generated: 2026-08-01 | Updated: 2026-09-05 (4.0h source lifecycle)
// PR#65 third review fix: production loads clear stale fixture/content state and retry the
//                        exact requested memory through an injectable repository boundary.
// ==========================================

import SwiftUI
import Foundation
import Photos

protocol MemoryDetailRepository: Sendable {
    func loadMemory(memoryId: UUID) async throws -> Memory?
    func deleteMemory(
        memoryId: UUID,
        sourceLocator: String?,
        sourceType: String?,
        writeExcluded: Bool,
        traceID: String
    ) async throws -> Bool
}

extension CanonicalMemoryRepositoryActor: MemoryDetailRepository {}

protocol MemoryEditServicing: Sendable {
    func loadSnapshot(memoryID: UUID, traceID: String) async throws -> MemoryEditSnapshot?
    func beginEditing(memoryID: UUID, traceID: String) async throws
    func save(_ request: MemoryEditRequest, traceID: String) async throws -> MemoryEditResult
    func resolveConflict(memoryID: UUID, resolution: MemoryConflictResolution, traceID: String) async throws
}

extension MemoryEditActor: MemoryEditServicing {}

protocol FocusSourceLifecycleServicing: Sendable {
    func resolveSource(memoryID: UUID, traceID: String) async throws -> FocusSourceResolution
    func deletePhotoLibraryOriginal(
        memoryID: UUID,
        traceID: String
    ) async throws -> FocusSourceDeletionResult
}

extension FocusSourceLifecycleActor: FocusSourceLifecycleServicing {}

protocol MemorySyncLockChecking: Sendable {
    func isMemoryLockedForSync(memoryId: String) async -> Bool
}

extension SyncPipeline: MemorySyncLockChecking {}

// MARK: - Memory Detail UI Model

/// 媒体预览类型 — 详情页按记忆 sourceType 渲染媒体内容（US-RET-001 媒体记忆展示）。
enum MediaKind: Equatable, Sendable {
    /// 无媒体 — 纯文本记忆（note）
    case none
    /// 图片预览（photo）
    case image
    /// 视频播放（video_frame / video_audio）
    case video
    /// 音频播放（voice）
    case audio
}

enum MediaResolutionPhase: Equatable, Sendable {
    case idle
    case loading
    case resolved
    case unavailable
}

/// UI 层记忆详情展示模型 — 从 Core ``Memory`` / ``MemoryEntry`` 映射的薄适配器。
///
/// 适配器职责 (docs/ui/architecture.md §7.1):
/// - 状态映射: Core 值类型 → UI State
/// - 不保存第二份领域真相 — 仅按需转换展示字段
struct MemoryDetailModel: Identifiable, Sendable, Equatable {
    /// 记忆唯一标识 (映射自 Memory.memoryId / MemoryEntry.id)
    let id: UUID
    /// 数据源引用
    let assetId: String
    /// 数据源类型 ("photo" / "note" / "voice" / "video_frame" 等)
    let sourceType: String
    /// 记忆标题（用户可编辑，US-AWK-007）
    var title: String
    /// 正文内容（备忘录/语音转写文本）
    var originalText: String
    /// User-authored description, kept separate from source text.
    var userDescription: String
    /// 源语言
    let sourceLanguage: String
    /// 首选语言 (UserPolicy.preferredLanguage)
    let preferredLanguage: String
    /// 记忆时间戳（用户可覆盖时间戳，US-AWK-007 AC-1）
    var timestamp: Date
    /// 自定义标签列表 (US-AWK-007)
    var tags: [String]
    /// 用户已编辑标记 (US-AWK-007 AC-2 → userEdited=true)
    var userEdited: Bool
    /// Original-source content availability; independent from presentation and deletion.
    var contentAvailability: FocusContentAvailability
    /// Focus presentation selected by the live source resolver.
    var sourcePresentation: FocusSourcePresentation
    /// Original-source deletion capability selected by current policy + PhotoKit state.
    var sourceDeletionCapability: FocusSourceDeletionCapability

    // MARK: - Translation (US-DIS-002)

    /// 翻译可见性 — 原文/译文切换
    var translationVisible: Bool
    /// 译文文本（未请求时为 nil）
    var translatedText: String?
    /// 源语言检测置信度 (NLTagger) — < 0.9 (.uncertain) 时保留原文 + 语言标签 (US-DIS-002 AC-3, ADR-005)
    var sourceLanguageConfidence: Double?

    // MARK: - Conflict (US-AWK-007 AC-4)

    /// 冲突信息 — 外部数据源变更而用户编辑未保存
    var conflict: MemoryConflictModel?

    // MARK: - Media Preview (US-RET-001 媒体记忆展示)

    /// Bundle 内示例媒体资源名（photo/video/voice 记忆详情媒体预览）。
    /// UI 切片阶段确定性媒体样本；生产路径由 Core 提供媒体引用（Phase 3.9）。
    var mediaAssetName: String?

    // MARK: - Location (US-RET-004 多维元数据)

    /// 地点描述（geohash/地名，检索元数据）。无地点时为 nil。
    var location: String?

    // MARK: - Init

    init(
        id: UUID,
        assetId: String,
        sourceType: String,
        title: String,
        originalText: String,
        userDescription: String? = nil,
        sourceLanguage: String,
        preferredLanguage: String,
        timestamp: Date,
        tags: [String] = [],
        userEdited: Bool = false,
        contentAvailability: FocusContentAvailability = .available,
        sourcePresentation: FocusSourcePresentation? = nil,
        sourceDeletionCapability: FocusSourceDeletionCapability? = nil,
        translationVisible: Bool = false,
        translatedText: String? = nil,
        sourceLanguageConfidence: Double? = nil,
        conflict: MemoryConflictModel? = nil,
        mediaAssetName: String? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.assetId = assetId
        self.sourceType = sourceType
        self.title = title
        self.originalText = originalText
        self.userDescription = userDescription ?? originalText
        self.sourceLanguage = sourceLanguage
        self.preferredLanguage = preferredLanguage
        self.timestamp = timestamp
        self.tags = tags
        self.userEdited = userEdited
        self.contentAvailability = contentAvailability
        self.sourcePresentation = sourcePresentation ?? Self.defaultPresentation(for: sourceType)
        self.sourceDeletionCapability = sourceDeletionCapability
            ?? Self.defaultDeletionCapability(for: sourceType)
        self.translationVisible = translationVisible
        self.translatedText = translatedText
        self.sourceLanguageConfidence = sourceLanguageConfidence
        self.conflict = conflict
        self.mediaAssetName = mediaAssetName
        self.location = location
    }

    // MARK: - Presentation Helpers

    /// 是否展示翻译切换按钮 — 源语言 ≠ 首选语言时 (US-DIS-002)
    var needsTranslation: Bool {
        sourceLanguage != preferredLanguage
    }

    /// 媒体预览类型 — 从 sourceType 派生，不保存第二份领域真相 (docs/ui/architecture.md §7.1)
    var mediaKind: MediaKind {
        switch sourcePresentation {
        case .photo: return .image
        case .video: return .video
        case .canonicalText, .transcriptText: return .none
        case .unavailable:
            switch sourceType {
            case "voice": return .audio
            default: return .none
            }
        }
    }

    private static func defaultPresentation(for sourceType: String) -> FocusSourcePresentation {
        switch sourceType {
        case "photo": .photo
        case "video", "video_frame", "video_audio": .video
        case "note", "thirdParty": .canonicalText
        default: .unavailable
        }
    }

    private static func defaultDeletionCapability(
        for sourceType: String
    ) -> FocusSourceDeletionCapability {
        sourceType == "photo" || sourceType == "video" ? .photoLibraryDeletable : .unavailable
    }

    /// 数据源类型展示标签
    var sourceTypeLabel: String {
        switch sourceType {
        case "photo":       return "Photo"
        case "video_frame": return "Video"
        case "video_audio": return "Video audio"
        case "note":        return "Note"
        case "voice":       return "Voice"
        default:            return sourceType
        }
    }

    /// 时间描述（绝对日期）
    var dateDescription: String {
        timestamp.formatted(date: .abbreviated, time: .omitted)
    }

    /// VoiceOver 标签 (echo-memory-canvas §17.3)
    var accessibilityLabel: String {
        "\(sourceTypeLabel), \(title), \(dateDescription)"
    }
}

// MARK: - Memory Conflict Model

/// 记忆编辑冲突模型 (US-AWK-007 AC-4)。
///
/// 外部数据源变更而用户编辑未保存时标记 conflict，提供差异化对比。
struct MemoryConflictModel: Sendable, Equatable {
    /// 用户本地编辑草稿
    let localDraft: String
    /// 外部新版本内容
    let externalVersion: String
}

// MARK: - MemoryDetailViewModel

/// 记忆详情视图 ViewModel — 内容展示 + 翻译切换 + 编辑 + 冲突解决 + 删除确认。
///
/// ## Surface Family: Focus
/// - 布局: 单列内容流 + grouped metadata（echo-memory-canvas §3.2）
/// - 样式: echo-memory-canvas + apple-native 基础
/// - Masonry: 禁止（Focus surface）
///
/// ## 职责 (docs/ui/architecture.md §7.1)
/// - 状态映射: Memory/MemoryEntry → MemoryDetailModel
/// - 错误映射: L1~L4 → error state
/// - Intent forwarding: translation and remove-from-Echo use live boundaries; unsupported
///   edit/conflict/original-source mutations fail visibly instead of reporting fake success.
/// - 生命周期: Task 管理，View 消失时 cancel
///
/// ## 状态流转 (AGENTS.md §8.2)
/// ```
/// idle → loading → completed
///                → error(L2/L3)
///                → cancelled
/// ```
@MainActor
@Observable
final class MemoryDetailViewModel {
    // MARK: - State Enum

    /// ViewModel 统一状态枚举 (AGENTS.md §8.1)
    enum ViewState: Equatable, Sendable {
        /// 初始状态 — 尚未加载
        case idle
        /// 加载中 — ProgressView
        case loading
        /// 加载完成 — 展示内容
        case completed
        /// 错误状态 — 按 L2/L3 区分 UI 表现
        case error(ErrorLevel)
        /// 已取消 — 用户离开页面
        case cancelled
    }

    /// 错误等级 — 对应 AGENTS.md §4.4 L1~L4
    enum ErrorLevel: Equatable, Sendable {
        /// L2 可恢复: Toast + 重试按钮
        case l2Recoverable(message: String)
        /// L3 阻断: 全屏引导页
        case l3Blocking(message: String)
        /// L4 数据冲突: 后台同步正在更新同一条记忆
        case l4Conflict(message: String)
    }

    /// 冲突解决选择 (US-AWK-007 AC-4)
    enum ConflictResolution: Equatable, Sendable {
        /// 保留用户编辑 → userLocked=true，后续同步跳过
        case local
        /// 使用外部新版本
        case external
        case merge
    }

    // MARK: - Published State

    /// 统一视图状态
    private(set) var viewState: ViewState = .idle
    /// 当前展示的记忆详情
    private(set) var memory: MemoryDetailModel?
    /// 编辑 Sheet 是否呈现 (US-AWK-007)
    var isEditing: Bool = false
    /// 删除确认弹窗是否呈现 (US-PRV-004)
    var showDeleteConfirmation: Bool = false
    /// 记忆已被移除标记 — 删除后显示移除成功空态 (US-PRV-004, PR #38 review fix)
    private(set) var hasRemovedMemory = false
    /// True only after an explicit Preview/test/XCUITest fixture injection.
    private(set) var isFixtureBacked = false

    // MARK: - Edit Form State (US-AWK-007 AC-1)

    /// 编辑标题
    var editTitle: String = ""
    /// 编辑描述（富文本 → 当前为多行文本）
    var editDescription: String = ""
    /// 编辑标签列表
    var editTags: String = ""
    /// 编辑覆盖时间戳
    var editTimestamp = Date()

    // MARK: - Dependencies

    /// 当前活跃的加载 Task
    private var loadTask: Task<Void, Never>?

    /// The production identifier retained for an explicit user retry.
    private var requestedMemoryID: UUID?

    /// UI 切片模式模拟记忆源 — fixture 注入
    private var stubMemory: MemoryDetailModel?

    /// 展示层翻译服务 — 按需翻译 (US-DIS-002 AC-2)
    private let translationService: any TranslationService

    /// 展示层翻译缓存 — TTL=7d (US-DIS-002 AC-5) — 生产持久缓存 / 测试内存缓存
    private let translationCache: any TranslationCaching

    /// 当前活跃的翻译 Task — 视图消失时取消
    private var translationTask: Task<Void, Never>?
    /// WP7: 详情页媒体预览——PHAsset 图片本体（照片记忆展示生产接线）
    private(set) var photoImage: UIImage?
    /// Presentation-only resolution state; never substitutes a second source of truth.
    private(set) var photoResolutionPhase: MediaResolutionPhase = .idle
    /// WP7: canonical 仓库——生产 load 接线（route ENABLED 后详情真实加载）
    private let canonicalRepository: (any MemoryDetailRepository)?
    private let memoryEditService: (any MemoryEditServicing)?
    private let syncLockChecker: (any MemorySyncLockChecking)?
    private let sourceLifecycleService: (any FocusSourceLifecycleServicing)?
    private var isResolvingMerge = false

    // MARK: - Translation State (US-DIS-002)

    /// 翻译流程状态 — 驱动翻译区 UI (translating / translated / error)
    enum TranslationPhase: Equatable, Sendable {
        /// 未请求翻译
        case idle
        /// 翻译中
        case translating
        /// A trustworthy translation is ready for presentation.
        case translated
        /// Source-language detection is uncertain; no translated text is exposed or cached.
        case uncertain
        /// The requested language pair is unavailable; original text remains primary.
        case unavailable(String)
        /// L2 可恢复错误
        case error(String)
    }

    /// 当前翻译阶段 — 用于翻译区 UI 渲染
    private(set) var translationPhase: TranslationPhase = .idle

    // MARK: - Initialization

    init(
        translationService: any TranslationService = AppleTranslationService(),
        translationCache: any TranslationCaching = MemoryDetailViewModel.defaultPersistentCache(),
        canonicalRepository: (any MemoryDetailRepository)? = nil,
        memoryEditService: (any MemoryEditServicing)? = nil,
        syncLockChecker: (any MemorySyncLockChecking)? = nil,
        sourceLifecycleService: (any FocusSourceLifecycleServicing)? = nil
    ) {
        self.translationService = translationService
        self.translationCache = translationCache
        self.canonicalRepository = canonicalRepository
        self.memoryEditService = memoryEditService
        self.syncLockChecker = syncLockChecker
        self.sourceLifecycleService = sourceLifecycleService
    }

    deinit {}

    /// 生产默认持久缓存目录 — Application Support 下 EchoTranslationCache。
    /// 展示层翻译缓存独立于 Core 存储，仅缓存译文（不重复持久化源文本）。
    static func defaultPersistentCache() -> PersistentTranslationCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("EchoTranslationCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PersistentTranslationCache(directory: dir)
    }

    // MARK: - Actions

    /// 加载指定记忆详情。
    ///
    /// 设置 state = .loading，加载完成后设置 .completed 或 .error。
    /// Production loads by memoryId from CanonicalMemoryRepositoryActor. Explicit fixtures use
    /// loadPreloaded only in Debug previews/tests.
    static func makeDetailModel(from memory: Memory) -> MemoryDetailModel {
        let preferredLanguage = LanguageCenter.shared.resolvedLanguage
        let sourceLanguage = GenerationRoutedChannelAdapter.detectLanguage(from: memory.canonicalText)
            ?? preferredLanguage
        return MemoryDetailModel(
            id: memory.memoryId,
            assetId: memory.sourceLocator,
            sourceType: memory.sourceType,
            title: memory.canonicalText ?? Self.sourceTitle(memory.sourceType),
            originalText: memory.canonicalText ?? "",
            sourceLanguage: sourceLanguage,
            preferredLanguage: preferredLanguage,
            timestamp: memory.createdAt,
            tags: [],
            userEdited: memory.userEdited
        )
    }

    static func makeDetailModel(from snapshot: MemoryEditSnapshot) -> MemoryDetailModel {
        var model = makeDetailModel(from: snapshot.memory)
        if let edit = snapshot.edit {
            if !edit.title.isEmpty { model.title = edit.title }
            model.userDescription = edit.description
            model.tags = edit.tags
        }
        if let conflict = snapshot.conflict {
            model.conflict = MemoryConflictModel(
                localDraft: snapshot.edit?.description ?? snapshot.memory.canonicalText ?? "",
                externalVersion: conflict.externalVersionSummary
            )
        }
        return model
    }

    private static func sourceTitle(_ sourceType: String) -> String {
        switch sourceType {
        case "photo": "Photo"
        case "video", "video_frame", "video_audio": "Video"
        case "voice": "Voice Memo"
        case "note": "Note"
        default: "Memory"
        }
    }

    func load(memoryId: UUID) {
        guard viewState != .loading else { return }

        loadTask?.cancel()
        requestedMemoryID = memoryId
        memory = nil
        stubMemory = nil

        // Set loading synchronously (AGENTS.md §8.1: first line of action)
        viewState = .loading
        isFixtureBacked = false

        loadTask = Task { [weak self] in
            guard let self else { return }

            guard !Task.isCancelled else {
                self.viewState = .cancelled
                return
            }

            if let editService = memoryEditService {
                do {
                    guard let snapshot = try await editService.loadSnapshot(
                        memoryID: memoryId,
                        traceID: UUID().uuidString
                    ) else {
                        self.viewState = .error(.l2Recoverable(message: "This memory is no longer available."))
                        return
                    }
                    guard !Task.isCancelled else { self.viewState = .cancelled; return }
                    self.memory = await self.resolvingSourceFacets(
                        for: Self.makeDetailModel(from: snapshot)
                    )
                    self.viewState = .completed
                } catch is CancellationError {
                    self.viewState = .cancelled
                } catch {
                    guard !Task.isCancelled else {
                        self.viewState = .cancelled
                        return
                    }
                    self.viewState = .error(.l2Recoverable(message: "Unable to load this memory. Please try again."))
                }
                return
            }

            // WP7: 生产 load——canonical 仓库真实加载（route ENABLED 后详情接线）
            if let repo = canonicalRepository {
                do {
                    guard let memory = try await repo.loadMemory(memoryId: memoryId) else {
                        guard !Task.isCancelled else {
                            self.viewState = .cancelled
                            return
                        }
                        self.viewState = .error(.l2Recoverable(
                            message: "This memory is no longer available."
                        ))
                        return
                    }
                    guard !Task.isCancelled else {
                        self.viewState = .cancelled
                        return
                    }
                    self.memory = await self.resolvingSourceFacets(
                        for: Self.makeDetailModel(from: memory)
                    )
                    self.viewState = .completed
                } catch is CancellationError {
                    self.viewState = .cancelled
                } catch {
                    guard !Task.isCancelled else {
                        self.viewState = .cancelled
                        return
                    }
                    self.viewState = .error(.l2Recoverable(
                        message: "Unable to load this memory. Please try again."
                    ))
                }
                return
            }

            if let stub = self.stubMemory {
                self.memory = stub
                self.viewState = .completed
            } else {
                self.viewState = .error(.l2Recoverable(
                    message: "Unable to load this memory. Please try again."
                ))
            }
        }
    }

    /// WP7: PHAsset 图片本体加载——详情页媒体预览生产接线。
    /// 本地仅提取（isNetworkAccessAllowed=false，与摄入策略一致）；无资产静默跳过。
    func loadPhotoImage(assetId: String) {
        guard photoImage == nil, photoResolutionPhase != .loading else { return }
        photoResolutionPhase = .loading
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetId],
            options: nil
        ).firstObject else {
            photoResolutionPhase = .unavailable
            return
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, _ in
            self?.photoImage = image
            self?.photoResolutionPhase = image == nil ? .unavailable : .resolved
        }
    }

    /// 预加载确定性记忆详情（Preview / 测试 / XCUITest fixture 注入）。
    ///
    /// - Parameter model: MemoryDetailModel（来自 fixture loader）
    func loadPreloaded(_ model: MemoryDetailModel) {
        requestedMemoryID = nil
        isFixtureBacked = true
        stubMemory = model
        memory = model
        photoImage = nil
        photoResolutionPhase = .idle
        viewState = .completed
        if let confidence = model.sourceLanguageConfidence, confidence < 0.9 {
            memory?.translatedText = nil
            translationPhase = .uncertain
        } else {
            translationPhase = model.translatedText == nil ? .idle : .translated
        }
    }

    /// 切换原文/译文 (US-DIS-002 AC-4)。
    ///
    /// 源语言 ≠ 首选语言时可用。展开详情时触发按需翻译 (AC-1)：
    /// 优先查 translationCache (AC-2)，未命中调 TranslationService；
    /// 成功后写入缓存 TTL=7d (AC-5)。
    func toggleTranslation() {
        guard let current = memory, current.needsTranslation else { return }
        memory?.translationVisible.toggle()

        if memory?.translationVisible == true {
            // 展开 — 触发按需翻译 (AC-1)。已有译文则不重复请求。
            guard current.translatedText == nil else {
                translationPhase = .translated
                return
            }
            requestTranslation()
        } else {
            translationTask?.cancel()
            translationTask = nil
            translationPhase = .idle
        }
    }

    /// 按需翻译 — cache-first (AC-2) + 服务 fallback + 缓存写入 (AC-5)。
    private func requestTranslation() {
        guard let current = memory, current.needsTranslation, current.translationVisible else { return }

        translationTask?.cancel()
        translationPhase = .translating

        let text = current.originalText
        let source = current.sourceLanguage
        let target = current.preferredLanguage
        let key = TranslationCache.makeKey(
            sourceText: text,
            sourceLanguage: source,
            targetLanguage: target
        )

        translationTask = Task { [weak self] in
            guard let self else { return }

            // AC-2: 优先查缓存
            if let cached = await self.translationCache.lookup(key: key) {
                guard !Task.isCancelled else { return }
                self.applyTranslation(
                    cached.translatedText,
                    sourceLanguageConfidence: cached.sourceLanguageConfidence
                )
                return
            }

            // AC-2 fallback: TranslationService (Apple Translation, 🔮 Phase 3.9 真实模型)
            do {
                let result = try await self.translationService.translate(
                    text, from: source, to: target
                )
                guard !Task.isCancelled, self.memory?.translationVisible == true else { return }
                guard result.sourceLanguageConfidence >= 0.9 else {
                    self.applyTranslation(
                        result.translatedText,
                        sourceLanguageConfidence: result.sourceLanguageConfidence
                    )
                    return
                }
                // AC-5: 成功后写入缓存
                await self.translationCache.store(
                    sourceText: text,
                    sourceLanguage: source,
                    targetLanguage: target,
                    translatedText: result.translatedText,
                    sourceLanguageConfidence: result.sourceLanguageConfidence
                )
                self.applyTranslation(result.translatedText, sourceLanguageConfidence: result.sourceLanguageConfidence)
            } catch TranslationError.unsupportedLanguage {
                guard !Task.isCancelled, self.memory?.translationVisible == true else { return }
                self.translationPhase = .unavailable(
                    "Translation is unavailable for this language pair."
                )
            } catch {
                guard !Task.isCancelled, self.memory?.translationVisible == true else { return }
                self.translationPhase = .error(
                    "Translation is currently unavailable. Please try again."
                )
            }
        }
    }

    /// Applies only trustworthy translated text; uncertain output is never exposed or cached.
    private func applyTranslation(_ translatedText: String, sourceLanguageConfidence: Double) {
        guard var current = memory, current.translationVisible else { return }
        current.sourceLanguageConfidence = sourceLanguageConfidence
        if sourceLanguageConfidence < 0.9 {
            current.translatedText = nil
            memory = current
            translationPhase = .uncertain
            return
        }
        current.translatedText = translatedText
        memory = current
        translationPhase = .translated
    }

    /// 重试翻译 (L2 恢复路径) — 清空错误态，重新走 cache-first 流程。
    func retryTranslation() {
        guard memory?.translationVisible == true else { return }
        guard memory?.translatedText == nil else {
            translationPhase = .translated
            return
        }
        requestTranslation()
    }

    /// 呈现编辑 Sheet (US-AWK-007 AC-1)。
    ///
    /// 从当前记忆填充编辑表单。若记忆已被外部修改（conflict），
    /// 不进入表单，交由冲突 UI 处理。
    func presentEditSheet() {
        guard let current = memory else { return }
        // AC-4: 外部数据源已变更时，阻止直接编辑，先解决冲突
        guard current.conflict == nil else { return }
        editTitle = current.title
        editDescription = current.userDescription
        editTags = current.tags.joined(separator: ", ")
        editTimestamp = current.timestamp
        isEditing = true
        if !isFixtureBacked, let memoryEditService {
            Task {
                try? await memoryEditService.beginEditing(
                    memoryID: current.id,
                    traceID: UUID().uuidString
                )
            }
        }
    }

    /// 保存编辑 (US-AWK-007 AC-2)。
    ///
    /// Fixture previews may mutate their local display copy. Production fails visibly until
    /// the canonical repository exposes an edit/re-index transaction boundary.
    func saveEdit() {
        viewState = .loading
        guard var current = memory else { viewState = .idle; return }

        if !isFixtureBacked {
            guard let memoryEditService else {
                isEditing = false
                viewState = .error(.l2Recoverable(message: "Editing is unavailable because the production memory update boundary is not connected."))
                return
            }
            let request = MemoryEditRequest(
                memoryID: current.id,
                title: editTitle,
                description: editDescription,
                tags: editTags.split(separator: ",").map(String.init),
                timestamp: editTimestamp
            )
            let merge = isResolvingMerge
            isEditing = false
            isResolvingMerge = false
            Task { [weak self] in
                guard let self else { return }
                do {
                    if await self.syncLockChecker?.isMemoryLockedForSync(
                        memoryId: current.id.uuidString
                    ) == true {
                        throw MemoryEditError.syncInProgress
                    }
                    if merge {
                        try await memoryEditService.resolveConflict(
                            memoryID: current.id,
                            resolution: .merge(request),
                            traceID: UUID().uuidString
                        )
                        guard let snapshot = try await memoryEditService.loadSnapshot(memoryID: current.id, traceID: UUID().uuidString) else { throw MemoryEditError.memoryNotFound }
                        self.memory = Self.makeDetailModel(from: snapshot)
                    } else {
                        let result = try await memoryEditService.save(request, traceID: UUID().uuidString)
                        self.memory = Self.makeDetailModel(from: result.snapshot)
                    }
                    self.viewState = .completed
                } catch MemoryEditError.syncInProgress {
                    self.viewState = .error(.l4Conflict(
                        message: "This memory is being updated. Please edit it again after synchronization finishes."
                    ))
                } catch {
                    self.viewState = .error(.l2Recoverable(message: error.localizedDescription))
                }
            }
            return
        }

        // AC-4: 编辑期间外部变更 → 阻止保存（由 SyncPipeline 检测时置位 conflict）
        if current.conflict != nil {
            isEditing = false
            return
        }

        let trimmedTitle = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            current.title = trimmedTitle
        }
        current.originalText = editDescription
        current.userDescription = editDescription
        current.tags = editTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        current.timestamp = editTimestamp
        current.userEdited = true

        memory = current
        isEditing = false
        viewState = .completed
    }

    /// 呈现删除确认弹窗 (US-PRV-004 AC-1)。
    func presentDeleteConfirmation() {
        showDeleteConfirmation = true
    }

    var canDeleteOriginal: Bool {
        memory?.sourceDeletionCapability == .photoLibraryDeletable
            && (isFixtureBacked || sourceLifecycleService != nil)
    }

    /// 选择"仅从 Echo 移除" (US-PRV-004 AC-2)。
    ///
    /// Production delegates the transaction to CanonicalMemoryRepositoryActor, which removes
    /// canonical/vector/cache data and writes ExcludedAssets atomically for this user action.
    func removeFromEcho() {
        showDeleteConfirmation = false
        guard let current = memory else { return }

        if isFixtureBacked {
            hasRemovedMemory = true
            viewState = .idle
            memory = nil
            return
        }

        guard let canonicalRepository else {
            viewState = .error(.l3Blocking(
                message: "Memory removal is unavailable because storage is not connected."
            ))
            return
        }

        viewState = .loading
        Task { [weak self] in
            guard let self else { return }
            do {
                let deleted = try await canonicalRepository.deleteMemory(
                    memoryId: current.id,
                    sourceLocator: current.assetId,
                    sourceType: current.sourceType,
                    writeExcluded: true,
                    traceID: UUID().uuidString
                )
                guard deleted else {
                    self.viewState = .error(.l2Recoverable(
                        message: "This memory is no longer available."
                    ))
                    return
                }
                self.hasRemovedMemory = true
                self.memory = nil
                self.viewState = .idle
            } catch {
                self.viewState = .error(.l2Recoverable(
                    message: "Unable to remove this memory. Please try again."
                ))
            }
        }
    }

    /// 选择"同时删除原始文件" (US-PRV-004 AC-3)。
    ///
    /// 调用系统 API 删除原始文件，级联清除 Echo 数据，不写入 ExcludedAssets。
    func deleteOriginal() {
        viewState = .loading
        showDeleteConfirmation = false
        guard let current = memory else {
            viewState = .idle
            return
        }
        if isFixtureBacked {
            hasRemovedMemory = true
            viewState = .idle
            memory = nil
            return
        }
        guard canDeleteOriginal, let sourceLifecycleService else {
            viewState = .error(.l2Recoverable(
                message: EchoStrings.tr("The original source is not currently available for deletion.")
            ))
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                switch try await sourceLifecycleService.deletePhotoLibraryOriginal(
                    memoryID: current.id,
                    traceID: UUID().uuidString
                ) {
                case .deleted:
                    self.hasRemovedMemory = true
                    self.memory = nil
                    self.viewState = .idle
                case .retained(.userCancelled):
                    self.viewState = .completed
                case .retained:
                    self.viewState = .error(.l2Recoverable(
                        message: EchoStrings.tr("The original was not deleted. Your Echo memory was kept.")
                    ))
                case .pendingRecovery:
                    self.viewState = .error(.l2Recoverable(
                        message: EchoStrings.tr("Deletion could not be confirmed. Echo kept the memory and will check again.")
                    ))
                }
            } catch {
                self.viewState = .error(.l2Recoverable(
                    message: EchoStrings.tr("Unable to delete the original source. Your Echo memory was kept.")
                ))
            }
        }
    }

    private func resolvingSourceFacets(for model: MemoryDetailModel) async -> MemoryDetailModel {
        guard let sourceLifecycleService else { return model }
        do {
            let resolution = try await sourceLifecycleService.resolveSource(
                memoryID: model.id,
                traceID: UUID().uuidString
            )
            var resolved = model
            resolved.contentAvailability = resolution.contentAvailability
            resolved.sourcePresentation = resolution.presentation
            resolved.sourceDeletionCapability = resolution.sourceDeletionCapability
            return resolved
        } catch {
            var unavailable = model
            unavailable.sourceDeletionCapability = .unavailable
            return unavailable
        }
    }

    /// 解决冲突 (US-AWK-007 AC-4)。
    ///
    /// - keep: 保留用户编辑（.local）或使用外部版本（.external）
    func resolveConflict(keep: ConflictResolution) {
        viewState = .loading
        guard var current = memory, let conflict = current.conflict else {
            viewState = .completed
            return
        }

        if !isFixtureBacked {
            guard let memoryEditService else {
                viewState = .error(.l2Recoverable(message: "Conflict resolution is unavailable because the production update boundary is not connected."))
                return
            }
            if keep == .merge {
                editTitle = current.title
                editDescription = conflict.localDraft + "\n\n" + conflict.externalVersion
                editTags = current.tags.joined(separator: ", ")
                editTimestamp = current.timestamp
                isResolvingMerge = true
                isEditing = true
                viewState = .completed
                return
            }
            let coreResolution: MemoryConflictResolution = keep == .local ? .local : .external
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await memoryEditService.resolveConflict(
                        memoryID: current.id,
                        resolution: coreResolution,
                        traceID: UUID().uuidString
                    )
                    guard let snapshot = try await memoryEditService.loadSnapshot(memoryID: current.id, traceID: UUID().uuidString) else { throw MemoryEditError.memoryNotFound }
                    self.memory = Self.makeDetailModel(from: snapshot)
                    self.viewState = .completed
                } catch {
                    self.viewState = .error(.l2Recoverable(message: error.localizedDescription))
                }
            }
            return
        }

        switch keep {
        case .local:
            // 保留用户编辑，清除冲突标记，userLocked=true（后续同步跳过）
            current.conflict = nil
            current.userEdited = true

        case .external:
            // 使用外部新版本
            current.originalText = conflict.externalVersion
            current.conflict = nil
        case .merge:
            editTitle = current.title
            editDescription = conflict.localDraft + "\n\n" + conflict.externalVersion
            editTags = current.tags.joined(separator: ", ")
            editTimestamp = current.timestamp
            isResolvingMerge = true
            isEditing = true
        }

        memory = current
        viewState = .completed
    }

    /// 重试加载 (L2 恢复路径)。
    func retry() {
        if isFixtureBacked, let stub = stubMemory {
            loadPreloaded(stub)
            return
        }
        if let requestedMemoryID {
            viewState = .idle
            load(memoryId: requestedMemoryID)
            return
        }
        viewState = memory == nil ? .idle : .completed
    }

    /// 仅 Preview/调试使用 — 直接构造错误状态，不触发任何副作用。
    /// 生产路径的错误由 load() 的 catch 自然产生，不调用此方法。
    func simulateError(_ level: ErrorLevel) {
        viewState = .error(level)
    }

    /// 消除错误状态，返回 idle。
    func dismissError() {
        viewState = .idle
    }

    /// 取消当前加载任务。
    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        viewState = .cancelled
    }

    // MARK: - Lifecycle

    /// 视图消失时调用 — 取消进行中的任务；已完成内容保留。
    ///
    /// iOS 17+ NavigationStack push / TabView 切换会触发 onDisappear，
    /// 无条件取消会导致从详情切走再返回时卡在 loading（回归 2026-08-02 修复）。
    /// loading 状态离开 → cancelled（返回后回 idle）；completed 状态保留内容。
    func onDisappear() {
        loadTask?.cancel()
        loadTask = nil
        translationTask?.cancel()
        translationTask = nil
        if viewState == .loading {
            viewState = .cancelled
        }
    }
}
