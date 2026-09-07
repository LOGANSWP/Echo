// ==========================================
// 文件: LiveAppAdapters.swift
// 对应规格: docs/05-planning/phase3f-execution-plan.md → 3F.7 (UI 到 Core 全域接线)
//            docs/ui/architecture.md §7 (适配器契约)
// Task: 3F.7 + 4.0h - UI-to-Core production wiring and source lifecycle
// AC 覆盖: 默认 live adapter、无 fixture fallback、真实设置值、跨 surface journey
// 架构约束: AGENTS.md §8.1 (@MainActor @Observable 薄适配器), §17.4 (Core 只读消费),
//           AGENTS.md §4.2 (仅持有不可变 actor 引用), R-007
// 重要: 项目 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor，所有 struct stored/computed 需 nonisolated
// Generated: 2026-08-11 | Updated: 2026-09-05
// ==========================================

import Foundation

/// 生产 live 适配器 — 将 UI ViewModel 与 composition 持有的 live Core 依赖接线。
///
/// 设计原则（docs/ui/architecture.md §7 + AGENTS.md §17.4）：
/// - 薄适配器：仅做线程隔离、状态映射与 UI 事件转发，不复制业务规则
/// - 无 fixture fallback：默认构造使用 live 依赖；fixture 仅限 #if DEBUG / Preview
/// - 唯一依赖图：经 AppComposition.shared 装配（ADR-007 §决策-1）
@MainActor
public enum LiveAppAdapters {

    /// 从 composition 装配生产 SearchPipeline（3F.6 多通道检索 + 反馈）。
    ///
    /// - Returns: 生产 SearchPipeline；无活跃 text generation 路由或该代向量存储未物化时返回 nil
    ///   （route-unavailable，由调用方显式进入 L3 状态，不静默回退到空向量库）
    public static func makeSearchPipeline(
        composition: AppComposition = .shared
    ) async -> SearchPipeline? {
        let registry = composition.generationRegistry
        guard let activeStore = await resolveActiveTextStore(registry: registry) else {
            return nil
        }
        // WP4 5c/5d：构造多通道查询工厂——配对 SigLIP2 文本塔真实接线（工件缺失时
        // SigLIP2TextEmbedder 运行时 fail-closed，queryFactory 照常注入）
        let queryFactory: (any QueryRepresentationFactory)? = {
            guard let textCtx = composition.textContextualEmbedder else { return nil }
            return DefaultQueryRepresentationFactory(
                textEmbedder: textCtx,
                visionEmbedder: SigLIP2TextEmbedder()
            )
        }()
        return SearchPipeline(
            embedder: composition.textEmbedder,
            privacyActor: composition.privacyActor,
            vectorStore: activeStore,
            feedbackActor: .shared,
            canonicalRepository: makeCanonicalRepository(composition: composition),
            queryFactory: queryFactory,
            generationRegistry: composition.generationRegistry
        )
    }

    /// 从 composition 装配生产 FeedbackPipeline。
    public static func makeFeedbackPipeline(
        composition: AppComposition = .shared
    ) -> FeedbackPipeline {
        FeedbackPipeline(
            feedbackActor: .shared,
            privacyActor: composition.privacyActor,
            pendingOpsActor: .shared,
            generationRegistry: composition.generationRegistry
        )
    }

    /// 装配生产 DataOverviewService。
    public static func makeDataOverviewService(
        composition: AppComposition = .shared
    ) -> DataOverviewService {
        DataOverviewService(
            db: composition.databaseManager,
            generationRegistry: composition.generationRegistry,
            modelLoader: composition.modelLoader,
            privacyActor: composition.privacyActor
        )
    }

    /// 装配生产 DeviceMigrationActor。
    public static func makeDeviceMigrationActor(
        composition: AppComposition = .shared
    ) -> DeviceMigrationActor {
        DeviceMigrationActor(
            db: composition.databaseManager,
            canonicalRepository: composition.canonicalRepository,
            excludedAssets: composition.excludedAssetsActor,
            privacyActor: composition.privacyActor,
            generationRegistry: composition.generationRegistry,
            textEmbedder: composition.textEmbedder
        )
    }

    /// 装配生产展示层翻译服务 (US-DIS-002, ADR-013 决策 1) —
    /// Apple Translation（LanguageAvailability 检查 + 术语表优先 + 绝不编造质量分数）。
    static func makeTranslationService() -> any TranslationService {
        AppleTranslationService()
    }

    /// 装配生产持久翻译缓存 (US-DIS-002 AC-5, ADR-013 决策 2) —
    /// TTL=7d 持久化跨重启；独立于 Core 存储，仅缓存译文。
    static func makePersistentTranslationCache() -> any TranslationCaching {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("EchoTranslationCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PersistentTranslationCache(directory: dir)
    }

    /// 装配生产创作管线 (ADR-013 决策 3: grounded creation)。
    ///
    /// 离线 LLM 运行时落地时返回 CreativePipeline；运行时未获批/未落地返回 nil
    /// （调用方走 fixture 确定性路径或 L2 错误，ADR-009 决策 4 fail-closed）。
    /// preferredLanguage 读取 UserPolicy (R-004: AI 输出语言匹配用户策略)。
    static func makeCreativePipeline(
        composition: AppComposition = .shared
    ) async -> CreativePipeline? {
        guard let llmProvider = LiveAppAdapters.resolveLLMProvider() else { return nil }
        let policy = await composition.privacyActor.getPolicy()
        return CreativePipeline(
            llmProvider: llmProvider,
            aligner: LanguageAligner(
                llmProvider: llmProvider,
                preferredLanguage: policy.preferredLanguage
            ),
            privacyActor: composition.privacyActor
        )
    }

    static func makeCreationExportCoordinator(
        composition: AppComposition = .shared
    ) -> CreationExportCoordinator {
        composition.creationExportCoordinator
    }

    /// 解析离线 LLM 推理来源 (ADR-009 决策 4)。
    ///
    /// 当前未获批捆绑 LLM 运行时（model-provenance-register 无 LLM 工件）→ 返回 nil。
    /// LLM 运行时获批接入后在此装配（fail-closed：无运行时则不提供 grounded 生成）。
    private static func resolveLLMProvider() -> (any LLMProvider)? {
        nil
    }

    /// 装配生产 CanonicalMemoryRepositoryActor（详情页编辑/删除）。
    public static func makeCanonicalRepository(
        composition: AppComposition = .shared
    ) -> CanonicalMemoryRepositoryActor {
        composition.canonicalRepository
    }

    /// Shared PhotoKit-backed source lifecycle used by Detail and foreground recovery.
    public static func makeFocusSourceLifecycleActor(
        composition: AppComposition = .shared
    ) -> FocusSourceLifecycleActor {
        composition.focusSourceLifecycleActor
    }

    /// Shared production edit boundary used by Detail and Sync.
    public static func makeMemoryEditActor(
        composition: AppComposition = .shared
    ) -> MemoryEditActor {
        composition.memoryEditActor
    }

    /// Live sync-lock proxy. It resolves the pipeline at call time because AppDelegate attaches
    /// the production pipeline after the SwiftUI hierarchy may already exist.
    static func makeSyncLockChecker() -> any MemorySyncLockChecking {
        ProductionSyncLockChecker()
    }

    // MARK: - Private Helpers

    /// 异步解析活跃 text generation 向量存储（内部辅助，无需公开）。
    static func resolveActiveTextStore(
        registry: GenerationRegistryActor
    ) async -> VectorStoreActor? {
        guard let route = try? await registry.loadActiveRoute() else { return nil }
        return await registry.vectorStore(for: route.textGeneration)
    }
}

private actor ProductionSyncLockChecker: MemorySyncLockChecking {
    func isMemoryLockedForSync(memoryId: String) async -> Bool {
        let pipeline = await MainActor.run { AppComposition.shared.productionSyncPipeline }
        return await pipeline?.isMemoryLockedForSync(memoryId: memoryId) ?? false
    }
}
