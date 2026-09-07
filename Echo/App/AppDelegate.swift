// ==========================================
// 文件: AppDelegate.swift
// 对应规格: AGENTS.md §10.1 强制目录结构
//            docs/decisions/ADR-008-source-import-boundaries.md §决策-1 (PhotoKit 授权与变更观察),
//            §决策-3 (App Group 队列消费)
// 任务: 1.1 - 创建 Xcode 项目，配置 Swift 6 并发严格模式
//       3F.1 - Production composition root (ADR-007 §决策-1)
//       3F.2 + 4.0h - PhotoKit, Share Extension, and live source lifecycle
//       4.0j - Opportunistic persisted narrative-report scheduling (ADR-021)
// 用途: BGTask 注册 (US-SYS-001 后台任务面板) + 来源边界装配
// 3F.8 review fix (C-1/W-4): onGeofenceEvent 回调 → eventStream for-await 消费; awakeningPipeline 属性持有
// 架构约束: 遵循 AGENTS.md §9 (后台任务与断点续传), deny-by-default (ADR-007 §决策-2)
// Generated: 2026-07-04 | Updated: 2026-09-07 (4.0j BGProcessingTask lifecycle)
// ==========================================

import UIKit
import Photos
import PhotosUI
import BackgroundTasks

/// Echo 应用代理 — 负责后台任务注册与生命周期管理
/// 后台任务包括：定时扫描、数据同步、索引构建（US-SYS-001）
final class AppDelegate: NSObject, UIApplicationDelegate {

    private static let narrativeReportBackgroundIdentifier = "com.echo.narrative-report-processing"

    /// 相册变更同步管线（US-SRC-012 AC-1）— 持有防释放
    private var syncPipeline: SyncPipeline?
    /// Share 队列摄入管线（ADR-008 §决策-3）— 持有防释放
    private var ingestPipeline: IngestPipeline?
    /// PhotoKit 来源适配器（iOS 26 limited 选择器主动弹出）— 持有防释放
    private var photoSourceAdapter: PhotoKitSourceAdapter?
    /// 3F.8: 系统适配器 — 定位服务（地理围栏事件流）— 持有防释放
    private var locationProvider: (any LocationProviding)?
    /// 3F.8: HealthKit 系统适配器（US-SRC-010 live provider + US-AWK-003 情绪）— 持有防释放
    private var healthKitSystemProvider: HealthKitSystemProvider?
    /// 3F.8: 本地通知调度 — 持有防释放
    private var notificationAdapter: (any NotificationScheduling)?
    /// 3F.8: 通知响应路由（US-AWK-005 点击跳转）
    private let notificationRouter: NotificationResponseRouting = NotificationResponseRouter()
    /// 3F.8: 唤醒卡片持久化存储（ADR-012 决策-5）
    private let awakeningCardRepository = AwakeningCardRepositoryActor()
    /// 3F.8: 唤醒管线（含地理围栏事件流消费）— 持有防释放（W-4 review fix）
    private var awakeningPipeline: AwakeningPipeline?
    private var narrativeReportBackgroundWork: Task<Void, Never>?
    private var narrativeReportBackgroundTaskID: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        registerNarrativeReportBackgroundTask()
        scheduleNarrativeReportBackgroundTask()
        // 生产装配：确保 composition root 已初始化（幂等，主装配在 EchoApp.task）
        _ = AppComposition.shared
        Task { @MainActor in
            await configureSources()
        }
        // iOS 26 limited 适配：系统不再自动弹照片选择器，回前台时主动呈现（3F.2 review fix）
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.presentLimitedLibraryPickerIfNeeded()
                // 3F.11 fix: 回前台时排空 Share 队列 — 运行期分享的信封此前要等下次启动才消费
                await self?.drainSharedImportsIfNeeded()
                _ = try? await AppComposition.shared.focusSourceLifecycleActor
                    .recoverPendingPhotoLibraryDeletions(traceID: UUID().uuidString)
                await self?.scanNarrativeReports(trigger: .foreground)
            }
        }
        return true
    }

    /// 3F.11 fix: 排空 Share Extension 队列（ADR-008 §决策-3 恰好一次消费）。
    ///
    /// 分享发生在 App 运行期时信封入队但无消费触发——drain 仅在启动装配时执行一次。
    /// 回前台排空保证运行期分享及时摄入（用户从分享面板返回 Echo 即触发）。
    private func drainSharedImportsIfNeeded() async {
        guard let ingestPipeline else { return }
        _ = try? await ingestPipeline.drainSharedImports(from: .shared)
    }

    /// 来源边界装配（3F.2）：相册变更监听 + Share 队列排空。
    ///
    /// - deny-by-default：仅已同意状态下装配来源（ADR-007 §决策-2）
    /// - 相册变更经 `PhotoKitChangeObserver` 去重后驱动 `SyncPipeline.sync`
    /// - Share 队列经 `IngestPipeline.drainSharedImports` 恰好一次消费
    /// - 推理服务（E5/SigLIP2/Whisper）为运行时服务实现，模型工件由 3F.3 接入；
    ///   当前未加载模型时摄入在嵌入阶段失败并回滚，3F.3 接入后自动产生真实向量
    private func configureSources() async {
        // 单元/UI 测试宿主（XCTest）跳过生产来源装配：PhotoKit observer 注册会触发照片
        // 授权弹窗，遮挡 fixture 驱动的 XCUITest 界面（3F.2 review 发现，CreationUITests 失败）
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let composition = AppComposition.shared
        await composition.bootstrap()
        // 3F.2 review fix: bootstrap() 幂等 guard 使并发调用立即返回，等待真正完成
        // 后再检查 startupState，避免 observer 因竞态永不注册（照片授权弹窗不出现）
        await composition.awaitBootstrapCompletion()
        // 3F.2 review fix #3: 首次启动时 bootstrap 落在 .requiresConsent（deny-by-default），
        // 若立即 return 则 observer 永不注册；等待用户在 Onboarding 完成同意（→ .ready）再装配。
        // 拒绝同意（.consentDeclined）或不可用终态会退出等待。
        while composition.startupState == .requiresConsent {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard composition.startupState == .ready
                || composition.startupState == .modelUnavailable
                || composition.startupState == .indexUnavailable else {
            return
        }

        // PhotoKit 来源适配器（iOS 26 limited 选择器主动弹出；3F.2 review fix）。
        // 提前创建：didBecomeActive 在用户点 Limit Access 后立即触发，若 adapter 晚于
        // 队列排空才创建，选择器会延迟出现（与 iOS 18 系统即时自动弹不一致）。
        photoSourceAdapter = PhotoKitSourceAdapter(
            library: RealPhotoLibrary(),
            privacyActor: composition.privacyActor,
            configuration: .production
        )

        // 相册变更监听（US-SRC-012 AC-1, ADR-008 §决策-1）
        // 3F.5 生产接线：经 GenerationRegistryActor 消费 per-generation 向量存储（ADR-010），
        // 摄入/同步经 TaskQueueActor 串行 + ProgressActor 持久化。
        // CR-19: sync 与 ingest 共享单一 CanonicalMemoryRepositoryActor（同一 DB/registry，单一串行域）。
        // 3F.11 fix: 生产初始 generation 引导（text+vision 路由）——此前生产从未引导初始代，
        // loadActiveRoute() 返回 nil 导致所有生产摄入抛 productionRouteUnavailable。
        // fail-closed：引导失败则停止来源装配（Settings 照片导入将显示 L3 可诊断错误）。
        guard (try? await composition.generationRegistry.ensureInitialGenerations()) != nil else {
            return
        }
        let registry = composition.generationRegistry
        let canonicalRepository = composition.canonicalRepository
        let sync = SyncPipeline(
            embedder: composition.visionEmbedder,
            privacyActor: composition.privacyActor,
            vectorStore: VectorStoreActor(dimension: SigLIP2Embedder.dimension),
            excludedAssets: composition.excludedAssetsActor,
            progressActor: .shared,
            canonicalRepository: canonicalRepository,
            generationRegistry: registry,
            memoryEditActor: composition.memoryEditActor
        )
        do {
            try await composition.memoryEditActor.attachExternalChangeApplier(
                sync,
                traceID: UUID().uuidString
            )
        } catch {
            return
        }
        await sync.registerPhotoLibraryObserver()
        syncPipeline = sync        // Share 队列排空（US-SRC-001/003, ADR-008 §决策-3）— 恰好一次消费
        // 3F.11 fix: 注入生产同步管线 — Settings 照片授权/首次全量导入入口（US-SRC-001 AC-3/AC-5）
        composition.attachProductionSyncPipeline(sync)
        let ingest = IngestPipeline(
            embedder: composition.textEmbedder,
            asrEngine: composition.asrEngine,
            privacyActor: composition.privacyActor,
            vectorStore: VectorStoreActor(dimension: E5Embedder.dimension),
            excludedAssets: composition.excludedAssetsActor,
            canonicalRepository: canonicalRepository,
            generationRegistry: registry,
            taskQueue: .shared,
            progressActor: .shared,
            visionEmbedder: composition.visionEmbedder,
            ocrService: VisionPhotoOCRService()
        )
        ingestPipeline = ingest
        await composition.attachProductionIngestPipeline(ingest)
        _ = try? await ingest.drainSharedImports(from: .shared)

        if let creativePipeline = await LiveAppAdapters.makeCreativePipeline(composition: composition) {
            try? await composition.narrativeReportActor.attachGenerator(
                CreativeNarrativeReportGenerator(pipeline: creativePipeline)
            )
        }
        _ = try? await composition.narrativeReportActor.establishEligibilityIfNeeded()
        await scanNarrativeReports(trigger: .launch)

        // 3F.8: 唤醒系统适配器装配（ADR-012 决策-3: 真实系统适配器接入生产）。
        // - 定位服务: CoreLocationProvider 地理围栏 enter/exit 事件 → AwakeningPipeline
        // - HealthKit: HealthKitSystemProvider 同时符合 HealthKitProvider（情绪）与
        //   CrossAppSourceProvider（US-SRC-010 3F.6 fusion）
        // - 通知: LocalNotificationAdapter 调度（请求与响应路由分离 — NotificationResponseRouter）
        // - 卡片: AwakeningCardRepositoryActor 持久化 + 去重（决策-5）
        let locProvider = CoreLocationProvider()
        locationProvider = locProvider
        healthKitSystemProvider = HealthKitSystemProvider()
        let notifAdapter = LocalNotificationAdapter()
        notificationAdapter = notifAdapter
        _ = notificationRouter
        // 3F.11 fix: 注入唤醒系统适配器 — Awakening 设置页读取真实权限状态（ADR-012 决策-2/3）
        composition.attachAwakeningAdapters(
            locationProvider: locProvider,
            healthStore: healthKitSystemProvider?.store,
            notificationScheduler: notifAdapter
        )
        try? await awakeningCardRepository.ensureSchema()

        let awakening = AwakeningPipeline(
            privacyActor: composition.privacyActor,
            searchPipeline: SearchPipeline(
                embedder: composition.textEmbedder,
                privacyActor: composition.privacyActor,
                vectorStore: VectorStoreActor(dimension: E5Embedder.dimension)
            ),
            stateStore: GeofenceStateStore(),
            healthKitProvider: healthKitSystemProvider,
            sentimentProvider: nil,
            locationProvider: locProvider,
            notificationScheduler: notifAdapter,
            cardRepository: awakeningCardRepository
        )
        // 地理围栏事件 → 唤醒管线（US-AWK-001 AC-1 仅 enter 触发, AC-2 exit 重置）
        // 3F.8 review fix (C-1/W-4): eventStream for-await 消费 + awakeningPipeline 属性持有
        awakeningPipeline = awakening
        Task { @MainActor [weak self] in
            guard let self, let pipeline = self.awakeningPipeline else { return }
            for await event in locProvider.eventStream {
                switch event {
                case .enter(let regionId):
                    _ = await pipeline.handleGeofenceEnter(regionId: regionId)
                case .exit(let regionId):
                    _ = await pipeline.handleGeofenceExit(regionId: regionId)
                }
            }
        }

        // 兜底补弹：didBecomeActive 可能早于本方法执行（configureSources 异步），
        // 此处确保装配完成后仍未弹出时补一次（3F.2 review fix #2）
        await presentLimitedLibraryPickerIfNeeded()
    }

    // MARK: - Narrative report background scheduling (4.0j / ADR-021)

    private func registerNarrativeReportBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.narrativeReportBackgroundIdentifier,
            using: nil
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in
                self?.handleNarrativeReportBackgroundTask(processingTask)
            }
        }
    }

    private func scheduleNarrativeReportBackgroundTask() {
        let request = BGProcessingTaskRequest(
            identifier: Self.narrativeReportBackgroundIdentifier
        )
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date().addingTimeInterval(12 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleNarrativeReportBackgroundTask(_ backgroundTask: BGProcessingTask) {
        scheduleNarrativeReportBackgroundTask()
        narrativeReportBackgroundWork?.cancel()
        let work = Task { @MainActor [weak self] in
            guard let self else {
                backgroundTask.setTaskCompleted(success: false)
                return
            }
            let success = await runNarrativeReportBackgroundScan()
            narrativeReportBackgroundTaskID = nil
            backgroundTask.setTaskCompleted(success: success)
        }
        narrativeReportBackgroundWork = work
        backgroundTask.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                narrativeReportBackgroundWork?.cancel()
                if let taskID = narrativeReportBackgroundTaskID {
                    try? await AppComposition.shared.narrativeReportActor.releaseClaimForResource(
                        taskID: taskID
                    )
                }
            }
        }
    }

    private func runNarrativeReportBackgroundScan() async -> Bool {
        let composition = AppComposition.shared
        await composition.bootstrap()
        await composition.awaitBootstrapCompletion()
        guard composition.startupState == .ready
                || composition.startupState == .modelUnavailable
                || composition.startupState == .indexUnavailable else { return false }
        _ = try? await composition.narrativeReportActor.establishEligibilityIfNeeded()
        do {
            let result = try await composition.narrativeReportActor.scanAndEnqueue(
                calendarContext: .init(timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier),
                trigger: .background,
                resources: Self.narrativeReportResourceAvailability()
            )
            switch result {
            case .enqueued(let taskID, let periodKey):
                narrativeReportBackgroundTaskID = taskID
                while await TaskQueueActor.shared.activeTaskIDs().contains(taskID) {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(100))
                }
                return try await composition.narrativeReportActor.listReports()
                    .contains { $0.periodKey == periodKey }
            case .retryRequired:
                return false
            case .none, .noData, .deferredForResources, .generationUnavailable:
                return true
            }
        } catch {
            return false
        }
    }

    private func scanNarrativeReports(trigger: NarrativeReportScanTrigger) async {
        let composition = AppComposition.shared
        guard composition.startupState == .ready
                || composition.startupState == .modelUnavailable
                || composition.startupState == .indexUnavailable else { return }
        _ = try? await composition.narrativeReportActor.establishEligibilityIfNeeded()
        _ = try? await composition.narrativeReportActor.scanAndEnqueue(
            calendarContext: .init(timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier),
            trigger: trigger,
            resources: Self.narrativeReportResourceAvailability()
        )
    }

    private static func narrativeReportResourceAvailability() -> NarrativeReportResourceAvailability {
        narrativeReportResourceAvailability(
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            autoPauseOnLowPowerEnabled: DegradationBannerViewModel.isAutoPauseOnLowPowerEnabled,
            thermallyConstrained: {
                switch ProcessInfo.processInfo.thermalState {
                case .serious, .critical: true
                default: false
                }
            }()
        )
    }

    /// Pure policy projection used by production scheduling and AC regression tests.
    static func narrativeReportResourceAvailability(
        lowPowerModeEnabled: Bool,
        autoPauseOnLowPowerEnabled: Bool,
        thermallyConstrained: Bool
    ) -> NarrativeReportResourceAvailability {
        if lowPowerModeEnabled, autoPauseOnLowPowerEnabled { return .lowPower }
        if thermallyConstrained { return .thermalConstrained }
        return .available
    }

    /// iOS 26 limited 适配：授权为 limited 且尚无已选照片时，主动呈现系统照片选择器
    /// （iOS 26 起系统在点「Limit Access」后不再自动弹出，需 App 调用 presentLimitedLibraryPicker）。
    ///
    /// 仅在 iOS 26+ 生效：iOS 18/19 系统会自动弹出选择器，若在此主动调用会叠弹第二个，
    /// 且用户选照片后 becomeActive 时资产已非空，本检查天然返回 false。
    @MainActor
    private func presentLimitedLibraryPickerIfNeeded() async {
        guard #available(iOS 26, *) else { return }
        guard let adapter = photoSourceAdapter else { return }
        guard await adapter.shouldPresentLimitedLibraryPicker() else { return }
        guard let rootVC = Self.keyWindowRootViewController() else { return }
        await PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootVC)
        await adapter.markLimitedLibraryPickerPresented()
    }

    /// 获取当前活跃 window 的 rootViewController（presentLimitedLibraryPicker 需要 presenter）。
    @MainActor
    private static func keyWindowRootViewController() -> UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.activationState == .foregroundActive else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                return window.rootViewController
            }
        }
        return nil
    }
}
