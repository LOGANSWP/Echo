// ==========================================
// 文件: SyncPipeline.swift
// 对应规格: docs/01-spec/用户故事与验收标准规格书.md → US-SRC-012 (数据源变更自动同步)
//            docs/02-architecture/架构设计文档.md §3.2 (SyncPipeline 时序图)
//            docs/02-architecture/数据流全链路技术说明文档.md §4 (变更同步数据流)
// 任务: 2.10 - SyncPipeline：相册变更监听 + 增量替换
// AC 覆盖: US-SRC-012 AC-1 (变更检测: photo 自动同步 — R-5.2 移除 note/calendar 自动扫描),
//          AC-2 (哈希跳过: >100KB + availableMem<300MB + totalMem≤2GB — W1 fixed),
//          AC-3 (自动同步开关: isAutoSyncEnabled — Phase 3 UI),
//          AC-4 (增量替换: sync() delete+reingest, 不写ExcludedAssets),
//          AC-5 (ExcludedAssets校验: fail-closed),
//          AC-6 (L4冲突: lockMemoryForSync/isMemoryLockedForSync),
//          AC-7 (进度报告: ProgressActor),
//          AC-8 (手动触发: — Phase 3 US-SRC-013),
//          AC-9 (审计: sourceType富化 replaced/skipped/hashSkipped — W2 fixed),
//          US-AWK-007 AC-4 (4.0e: persistent conflicts and source-change replay),
//          US-PRV-007 (4.0h: pre-change observer baseline; trusted removals cascade and clean exclusions)
// 架构约束: AGENTS.md §4.1 (Pipeline 契约), R-006 (PrivacyCheckpoint),
//           AGENTS.md §4.4 (L1~L4 错误分级), §5.2 (ExcludedAssets 写入规则),
//           AGENTS.md §8.3 (后台任务面板进度订阅)
// 重要: 项目 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor，所有 struct stored/computed 需 nonisolated
// 生成时间: 2026-07-12
// PR#57 review fix: W-03 canonical 删除 do/catch 抛 SyncError.canonicalDeleteFailed（L3）,
//                   不再 try? 静默吞错，失败计入 failedCount → 审计 success=false（D-005）
// PR#57 CodeRabbit fix: CR-3 方案A 生产替换经 canonical 确定性 ID upsert + 活跃路由向量（PIPE-012）,
//                       CR-9 defer 统一释放 AC-6 锁（修复 W-03 引入的锁泄漏）,
//                       CR-11 UUID guard 解析 + deleteMemory false 显式计失败
// PR#57 CodeRabbit fix (round 2): N-2 AC-6 锁引用计数（交叠 sync 不误释放）,
//                                 N-3 canonical 配置缺 registry 时 fail-closed
// PR#57 CodeRabbit fix (round 3): O-1 .removed 删除前锁定待删 ID（AC-6）;
//                                 O-2 无 vision 路由时显式失败（不回退写 text generation）
// ==========================================

import Foundation
import Photos
import ProximaKit
import CryptoKit

// MARK: - Sync Error

/// SyncPipeline 统一错误类型（L1~L4 分级，AGENTS.md §4.4）
public enum SyncError: Error, LocalizedError, Sendable, Equatable {
    /// 隐私校验拒绝 — 用户未授权所需数据源
    case privacyDenied(sourceTypes: [String])
    /// 资产已被用户手动排除（US-SRC-008）
    case assetExcluded(assetId: String)
    /// ExcludedAssets 查询失败（数据库读错误，fail-closed）
    case excludedAssetsLookupFailed(underlying: Error)
    /// 嵌入生成失败 — 模型未加载或推理失败（L3 阻断）
    case embeddingFailed(underlying: Error)
    /// 元数据编码失败
    case metadataEncodingFailed(underlying: Error)
    /// 向量存储操作失败
    case vectorStoreFailed(underlying: Error)
    /// canonical 事务删除失败（3F.5 生产路径，D-005）— 数据库完整性错误，计入 failed 不静默吞错
    case canonicalDeleteFailed(underlying: Error)
    /// 生产替换写入失败（CR-3 方案A）— canonical 替换经活跃路由写入失败，L3 阻断
    case productionReplacementFailed(underlying: Error)
    /// 内存锁定冲突 — 在同步期间尝试编辑（L4）
    case memoryLockedDuringSync(memoryId: String)
    /// 哈希对比跳过 — 非错误，仅为记录（内容过大或内存不足）
    case hashSkippedDueToConstraints(reason: String)
    /// 同步任务被取消（R-1.8）— 任务取消时优雅退出循环
    case cancelled

    /// L1~L4 错误分级
    nonisolated public var errorLevel: Int {
        switch self {
        case .privacyDenied:              return 2
        case .assetExcluded:              return 2
        case .excludedAssetsLookupFailed: return 2
        case .embeddingFailed:            return 3
        case .metadataEncodingFailed:     return 2
        case .vectorStoreFailed:          return 2
        case .canonicalDeleteFailed:      return 3
        case .productionReplacementFailed: return 3
        case .memoryLockedDuringSync:     return 4
        case .hashSkippedDueToConstraints: return 1
        case .cancelled:                  return 1
        }
    }

    public var errorDescription: String? {
        switch self {
        case .privacyDenied(let types):
            return "Privacy denied for source types: \(types.joined(separator: ","))"

        case .assetExcluded(let assetId):
            return "Asset excluded by user: \(assetId)"

        case .excludedAssetsLookupFailed(let error):
            return "ExcludedAssets lookup failed: \(error.localizedDescription)"

        case .embeddingFailed(let error):
            return "Embedding failed: \(error.localizedDescription)"

        case .metadataEncodingFailed(let error):
            return "Metadata encoding failed: \(error.localizedDescription)"

        case .vectorStoreFailed(let error):
            return "Vector store operation failed: \(error.localizedDescription)"

        case .canonicalDeleteFailed(let error):
            return "Canonical memory delete failed: \(error.localizedDescription)"

        case .productionReplacementFailed(let error):
            return "Production replacement write failed: \(error.localizedDescription)"

        case .memoryLockedDuringSync(let memoryId):
            return "Memory \(memoryId) is locked during sync — 该记忆正在同步更新中，请稍后再编辑"

        case .hashSkippedDueToConstraints(let reason):
            return "Hash comparison skipped due to constraints: \(reason)"

        case .cancelled:
            return "Sync cancelled by user or system"
        }
    }

    // MARK: Equatable
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.privacyDenied(let a), .privacyDenied(let b)): return a == b
        case (.assetExcluded(let a), .assetExcluded(let b)): return a == b
        case (.excludedAssetsLookupFailed, .excludedAssetsLookupFailed): return true
        case (.embeddingFailed, .embeddingFailed): return true
        case (.metadataEncodingFailed, .metadataEncodingFailed): return true
        case (.vectorStoreFailed, .vectorStoreFailed): return true
        case (.canonicalDeleteFailed, .canonicalDeleteFailed): return true
        case (.productionReplacementFailed, .productionReplacementFailed): return true
        case (.memoryLockedDuringSync(let a), .memoryLockedDuringSync(let b)): return a == b
        case (.hashSkippedDueToConstraints(let a), .hashSkippedDueToConstraints(let b)): return a == b
        case (.cancelled, .cancelled): return true
        default: return false
        }
    }
}

// MARK: - Change Source

/// 自动同步数据源类型（R-5.2 决策 2026-08-01）。
///
/// 仅 `.photo` 支持自动同步（PhotoKit 全量读取）。
/// 备忘录/语音备忘录通过 Share Extension 显式分享摄入（ingestText/ingestVoice），
/// 不参与自动同步——iOS 公开 API 无法自动读取系统备忘录/日历（R-5.2 路径 A）。
public enum ChangeSource: String, Sendable, Codable, Equatable {
    case photo
}

// MARK: - Change Type

/// 变更类型
public enum ChangeType: String, Sendable, Codable, Equatable {
    case added
    case modified
    case removed
}

// MARK: - Change Event

/// 检测到的变更事件（AC-1, AC-2）
public struct ChangeEvent: Sendable, Equatable {
    nonisolated public let assetId: String
    nonisolated public let source: ChangeSource
    nonisolated public let changeType: ChangeType
    /// 新内容的哈希值（用于确认内容确实变更）
    nonisolated public let newContentHash: String?
    /// 是否因约束条件跳过了哈希对比（AC-2）
    nonisolated public let hashSkipped: Bool

    nonisolated public init(
        assetId: String,
        source: ChangeSource,
        changeType: ChangeType,
        newContentHash: String? = nil,
        hashSkipped: Bool = false
    ) {
        self.assetId = assetId
        self.source = source
        self.changeType = changeType
        self.newContentHash = newContentHash
        self.hashSkipped = hashSkipped
    }
}

// MARK: - Sync Result

/// 同步操作结果
public struct SyncResult: Sendable, Equatable {
    nonisolated public let replacedCount: Int
    nonisolated public let skippedCount: Int
    nonisolated public let failedCount: Int
    nonisolated public let hashSkippedCount: Int

    nonisolated public init(
        replacedCount: Int = 0,
        skippedCount: Int = 0,
        failedCount: Int = 0,
        hashSkippedCount: Int = 0
    ) {
        self.replacedCount = replacedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.hashSkippedCount = hashSkippedCount
    }
}

// MARK: - Sync Pipeline

/// 数据源变更同步管线 — 监听相册/备忘录/日历变更，执行增量替换。
///
/// ## Pipeline 契约（AGENTS.md §4.1）
/// - 纯函数性: 相同输入产生相同输出（通过依赖注入的 embedder + actors）
/// - 无状态: Pipeline 本身不持有可变状态
/// - 副作用隔离: 所有副作用通过 Actor 调用实现
/// - 审计强制: 每个 execute 方法入口调用 PrivacyActor.validate()（R-006）
/// - 错误分级: 所有 throws 映射到 L1~L4 统一错误矩阵（AGENTS.md §4.4）
///
/// ## 数据流（架构文档 §4.2）
/// ```
/// sync → PrivacyActor.validate(.sync)
///      → for each change:
///          → ExcludedAssets.contains(assetId) → skip if excluded
///          → VectorStore.search(…filter by assetId) → delete old memories
///          → Embedder.embedText/embedImage → MemoryEntry → VectorStore.ingest
///          → ProgressActor.updateProgress
///      → PrivacyActor.writeAuditLog(.dataSourceChangeSynced)
///      → ProgressActor.delete(taskId)
/// ```
public actor SyncPipeline: MemoryExternalChangeApplying {
    // MARK: - Dependencies

    private let embedder: any EmbedderProtocol
    private let privacyActor: PrivacyActor
    private let vectorStore: VectorStoreActor
    private let excludedAssets: ExcludedAssetsActor
    private let progressActor: ProgressActor
    /// 生产同步路由（3F.5）— 非 nil 时删除/替换经 canonical repo 事务清除（D-005）
    private let canonicalRepository: CanonicalMemoryRepositoryActor?
    /// 分代索引注册表（CR-3 方案A）— 生产替换路径经活跃路由写入 canonical + 每代向量
    private let generationRegistry: GenerationRegistryActor?
    private let memoryEditActor: MemoryEditActor?
    private let photoPreparation: PhotoUnderstandingActor?

    /// 当前同步中锁定的内存 ID 引用计数（AC-6: 防止并发编辑，N-2 修复）
    ///
    /// Set 无法区分两个交叠 sync 调用对同一记忆的锁所有权——先完成者的释放会使
    /// 后完成者失去保护。改用引用计数：每次锁定 +1，仅归零才移除，保证交叠同步
    /// 期间锁持续有效。
    private var lockedMemoryIds: [String: Int] = [:]
    /// A conflict resolution may replay one persisted change without recording the same conflict again.
    private var externallyResolvedMemoryIDs: Set<UUID> = []

    /// 相册变更观察者（US-SRC-012 AC-1, ADR-008 §决策-1）— 由 PHPhotoLibrary 注册，Actor 持有引用防止释放
    private var photoObserver: PhotoKitChangeObserver?

    /// 跨投递变更去重窗口内的已投递键（`assetId|changeType` → 投递时间，ADR-008 §决策-1）
    private var recentChangeKeys: [String: Date] = [:]
    /// 去重窗口（秒）
    nonisolated private let changeDedupeWindow: TimeInterval = 2.0

    // MARK: - Initialization

    public init(
        embedder: any EmbedderProtocol,
        privacyActor: PrivacyActor = .shared,
        vectorStore: VectorStoreActor,
        excludedAssets: ExcludedAssetsActor = .shared,
        progressActor: ProgressActor = .shared,
        canonicalRepository: CanonicalMemoryRepositoryActor? = nil,
        generationRegistry: GenerationRegistryActor? = nil,
        memoryEditActor: MemoryEditActor? = nil,
        photoPreparation: PhotoUnderstandingActor? = nil
    ) {
        self.embedder = embedder
        self.privacyActor = privacyActor
        self.vectorStore = vectorStore
        self.excludedAssets = excludedAssets
        self.progressActor = progressActor
        self.canonicalRepository = canonicalRepository
        self.generationRegistry = generationRegistry
        self.memoryEditActor = memoryEditActor
        self.photoPreparation = photoPreparation
    }

    // MARK: - Sync Execution (AC-4, AC-5, AC-7, AC-9)

    /// 执行增量同步：删除旧记忆 → 重新摄入新内容。
    ///
    /// - Parameters:
    ///   - changes: 检测到的变更事件列表
    ///   - traceID: 审计追溯 ID（默认自动生成）
    /// - Returns: `SyncResult` 包含替换/跳过/失败计数
    public func sync(
        changes: [ChangeEvent],
        traceID: String = UUID().uuidString
    ) async throws -> SyncResult {
        let startTime = Date()
        let taskId = "sync-\(UUID().uuidString.prefix(8))"

        // Step 0: Early return for empty changes
        guard !changes.isEmpty else {
            return SyncResult()
        }

        // Step 1: PrivacyCheckpoint (R-006)
        let sourceTypes = Array(Set(changes.map { $0.source.rawValue }))
        let checkpoint = await privacyActor.validate(
            operation: .sync,
            traceID: traceID,
            sourceTypes: sourceTypes
        )
        guard checkpoint.isAllowed else {
            // R-006: Privacy denied → return zero-count result (don't throw, don't process)
            return SyncResult()
        }

        // Step 2: Initialize progress (AC-7)
        let progress = TaskProgress(
            taskId: taskId,
            taskType: .dataSourceSync,
            totalCount: changes.count
        )
        try? await progressActor.save(progress: progress)

        var replacedCount = 0
        var skippedCount = 0
        var failedCount = 0
        var hashSkippedCount = 0

        // Step 3: Process each change
        for (index, change) in changes.enumerated() {
            // R-1.8: 取消检查 — 任务取消时优雅退出
            if Task.isCancelled {
                // W2: 取消路径写入审计（success=false + cancelled 标记），
                // 使部分完成的同步可审计。进度行保留（§4.5: 下次询问是否继续）。
                let auditSource = sourceTypes.joined(separator: ",")
                    + "|replaced=\(replacedCount)"
                    + "|skipped=\(skippedCount)"
                    + "|hashSkipped=\(hashSkippedCount)"
                    + "|failed=\(failedCount)"
                    + "|cancelled=1"
                try? await privacyActor.writeAuditLog(
                    eventType: .dataSourceChangeSynced,
                    traceID: traceID,
                    policyVersion: checkpoint.policyVersion,
                    success: false,
                    sourceType: auditSource,
                    affectedCount: replacedCount,
                    excludedWritten: false,
                    sourceLanguage: nil,
                    elapsedMs: Int(Date().timeIntervalSince(startTime) * 1000)
                )
                throw SyncError.cancelled
            }

            // Removed is a trusted PhotoKit observation and must clean a now-invalid exclusion.
            // Added/modified remain fail-closed against ExcludedAssets.
            if change.changeType != .removed {
                do {
                    let isExcluded = try await excludedAssets.contains(assetId: change.assetId)
                    if isExcluded {
                        skippedCount += 1
                        try? await progressActor.updateProgress(
                            taskId: taskId,
                            lastProcessedIndex: index + 1,
                            lastProcessedId: change.assetId
                        )
                        continue
                    }
                } catch {
                    // Fail closed: an exclusion lookup failure is a privacy risk, so skip the asset.
                    skippedCount += 1
                    try? await progressActor.updateProgress(
                        taskId: taskId,
                        lastProcessedIndex: index + 1,
                        lastProcessedId: change.assetId
                    )
                    continue
                }
            }

            // AC-2: Track hash skip
            if change.hashSkipped {
                hashSkippedCount += 1
            }

            // Process the change based on type
            do {
                switch change.changeType {
                case .modified, .added:
                    // R-1.1: 原子性修复 — 先生成新向量并摄入，成功后再删除旧记忆。
                    // 原实现先删旧再摄入：若 embedding 生成或写入失败，旧记忆已永久丢失。
                    // 新实现失败时旧记录仍在，无数据损失。
                    //
                    // 注意：旧记忆 ID 必须在摄入新记忆【之前】查询——新记忆的 assetId
                    // 与旧记忆相同，摄入后查找会把新记忆也当作旧记录误删。
                    let oldMemoryIds = try await findMemories(byAssetId: change.assetId)

                    if let memoryEditActor {
                        var shouldSkip = false
                        for memoryIDString in oldMemoryIds {
                            guard let memoryID = UUID(uuidString: memoryIDString) else { continue }
                            if externallyResolvedMemoryIDs.contains(memoryID) { continue }
                            let disposition = try await memoryEditActor.handleExternalChange(
                                memoryID: memoryID,
                                externalVersionSummary: "\(change.source.rawValue) source changed",
                                pendingChange: PendingMemorySourceChange(
                                    assetID: change.assetId,
                                    source: change.source.rawValue,
                                    changeType: change.changeType.rawValue,
                                    newContentHash: change.newContentHash,
                                    hashSkipped: change.hashSkipped
                                ),
                                traceID: traceID
                            )
                            if disposition != .proceed { shouldSkip = true }
                        }
                        if shouldSkip {
                            skippedCount += 1
                            try? await progressActor.updateProgress(
                                taskId: taskId,
                                lastProcessedIndex: index + 1,
                                lastProcessedId: change.assetId
                            )
                            continue
                        }
                    } else if let canonicalRepository {
                        var isLocked = false
                        for memoryIDString in oldMemoryIds {
                            guard let memoryID = UUID(uuidString: memoryIDString) else { continue }
                            if try await canonicalRepository.loadMemory(memoryId: memoryID)?.userLocked == true {
                                isLocked = true
                            }
                        }
                        if isLocked {
                            skippedCount += 1
                            continue
                        }
                    }

                    // AC-6 (W1): 删除旧记忆窗口期加锁，阻止并发用户编辑（L4 冲突保护）
                    for memId in oldMemoryIds {
                        lockMemory(memId)
                    }
                    // CR-9/N-2: defer 统一释放锁（引用计数 -1，归零才移除）——
                    // 成功与抛错路径均覆盖，且交叠 sync 不误释放对方所有权
                    defer {
                        for memId in oldMemoryIds {
                            unlockMemory(memId)
                        }
                    }

                    let newEmbedding = try await generateEmbedding(for: change)

                    if let canonicalRepository {
                        // N-3: canonical 配置但缺 generationRegistry 时 fail-closed——
                        // findMemories 已返回 canonical ID，回退 legacy 写随机 UUID 会造成
                        // canonical 陈旧 + legacy 孤儿向量（后续 .removed 只删 canonical）。
                        guard let generationRegistry else {
                            throw SyncError.productionReplacementFailed(
                                underlying: IngestError.productionNotConfigured
                            )
                        }
                        // CR-3 方案A（PIPE-012）：生产替换经 canonical 确定性 ID upsert + 活跃路由向量，
                        // 不再写 legacy store 也不删旧 canonical（INSERT OR REPLACE 覆盖）。
                        guard let route = try await generationRegistry.loadActiveRoute() else {
                            throw SyncError.productionReplacementFailed(
                                underlying: IngestError.productionRouteUnavailable
                            )
                        }
                        let memoryId = CanonicalMemoryRepositoryActor.deterministicID(
                            sourceLocator: change.assetId,
                            sourceType: change.source.rawValue
                        )
                        // Photo-derived reports belong to the capture period, not the synchronization date.
                        let captureDate: Date
                        if photoPreparation != nil {
                            guard let asset = PHAsset.fetchAssets(
                                withLocalIdentifiers: [change.assetId], options: nil
                            ).firstObject else {
                                throw GenerationRuntimeError.privacyDenied
                            }
                            captureDate = asset.creationDate ?? Date()
                        } else {
                            captureDate = try await canonicalRepository.loadMemory(memoryId: memoryId)?.createdAt ?? Date()
                        }
                        if photoPreparation != nil,
                            try await canonicalRepository.loadMemory(memoryId: memoryId)?.createdAt == captureDate,
                            try await canonicalRepository.loadRepresentations(memoryId: memoryId).contains(where: {
                                $0.modality == .visionDense && $0.contentHash == Self.sha256(of: newEmbedding)
                            }) {
                            // Re-observing identical pixels preserves both queued work and published material.
                            // Description work is requested only from the selected detail or creation surface.
                            skippedCount += 1
                            continue
                        }
                        let memory = Memory(
                            memoryId: memoryId,
                            sourceLocator: change.assetId,
                            canonicalText: nil,
                            sourceType: change.source.rawValue,
                            createdAt: captureDate,
                            recoverability: .full
                        )
                        let rep = Representation(
                            representationId: CanonicalMemoryRepositoryActor.photoRepresentationID(memoryID: memoryId),
                            memoryId: memoryId,
                            modality: .visionDense,
                            preprocessVersion: "siglip2-v1",
                            contentHash: Self.sha256(of: newEmbedding)
                        )
                        // O-2: 图片同步仅产出 .visionDense 表示——无 vision 路由时显式失败，
                        // 不再把 vision 向量回退写入 text generation（维度/检索错乱）。
                        guard let generation = route.visionGeneration else {
                            throw SyncError.productionReplacementFailed(
                                underlying: IngestError.productionRouteUnavailable
                            )
                        }
                        do {
                            try await canonicalRepository.commit(
                                memory: memory,
                                representations: [rep],
                                vectorsByGeneration: [
                                    generation: [CanonicalVectorEntry(id: memoryId, vector: newEmbedding)]
                                ],
                                traceID: traceID
                            )
                        } catch {
                            throw SyncError.productionReplacementFailed(underlying: error)
                        }
                    } else {
                        let newMemory = MemoryEntry(
                            assetId: change.assetId,
                            embedding: newEmbedding,
                            sourceType: change.source.rawValue,
                            timestamp: Date(),
                            exifMetadata: nil,
                            privacyBlurApplied: false,
                            traceID: traceID
                        )
                        let metadata = try newMemory.encodeMetadata()
                        try await vectorStore.ingest(
                            vector: newEmbedding,
                            id: newMemory.id,
                            metadata: metadata
                        )

                        // 新记录写入成功后才删除旧记忆（AC-4, R-003: 不写 ExcludedAssets）
                        for memId in oldMemoryIds {
                            _ = await vectorStore.delete(id: try Self.requireUUID(memId))
                        }
                    }

                    replacedCount += 1

                case .removed:
                    // Delete old memories without re-ingestion
                    let oldMemoryIds = try await findMemories(byAssetId: change.assetId)
                    // O-1: 删除前锁定待删 ID（AC-6）——deleteMemory 是 await 挂起点，
                    // 若不加锁，并发编辑可通过 isMemoryLockedForSync 检查后被同步删除。
                    // 引用计数语义与 .modified/.added 一致：+1 → delete → -1。
                    for memId in oldMemoryIds {
                        lockMemory(memId)
                    }
                    defer {
                        for memId in oldMemoryIds {
                            unlockMemory(memId)
                        }
                    }
                    if let canonicalRepository {
                        do {
                            _ = try await canonicalRepository.cascadeDeleteFromOriginal(
                                assetId: change.assetId,
                                sourceType: change.source.rawValue,
                                traceID: traceID
                            )
                        } catch {
                            throw SyncError.canonicalDeleteFailed(underlying: error)
                        }
                    } else {
                        for memId in oldMemoryIds {
                            _ = await vectorStore.delete(id: try Self.requireUUID(memId))
                        }
                    }
                    replacedCount += 1
                }
            } catch {
                // Individual asset failure does not block others (AC-4 partial failure)
                failedCount += 1
                // AC-6 锁统一经 defer 释放（R-1.1 修复后成功路径亦释放）
            }

            // Update progress
            try? await progressActor.updateProgress(
                taskId: taskId,
                lastProcessedIndex: index + 1,
                lastProcessedId: change.assetId
            )
        }

        // Step 4: Audit log (AC-9)
        // AC-9 requires: changeType, sourceType, affectedCount, replacedFlag=true,
        // excludedNotWritten=true, hashSkipped. Encoded in sourceType as:
        // "photo,note|replaced=3|skipped=1|hashSkipped=2|failed=1"
        let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let auditSourceDetail = sourceTypes.joined(separator: ",")
            + "|replaced=\(replacedCount)"
            + "|skipped=\(skippedCount)"
            + "|hashSkipped=\(hashSkippedCount)"
            + "|failed=\(failedCount)"
        try? await privacyActor.writeAuditLog(
            eventType: .dataSourceChangeSynced,
            traceID: traceID,
            policyVersion: checkpoint.policyVersion,
            success: failedCount == 0,  // R-1.2: 有失败项时 success 必须为 false
            sourceType: auditSourceDetail,
            affectedCount: replacedCount,
            excludedWritten: false,  // red line R-003: 系统自动删除不写 ExcludedAssets
            sourceLanguage: nil,
            elapsedMs: elapsedMs
        )

        // Step 5: Cleanup progress (AC-7: 任务完成后删除进度记录)
        _ = try? await progressActor.delete(taskId: taskId)

        return SyncResult(
            replacedCount: replacedCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            hashSkippedCount: hashSkippedCount
        )
    }

    // MARK: - Memory Locking (AC-6)

    public func applyResolvedExternalChange(
        _ change: PendingMemorySourceChange,
        memoryID: UUID,
        traceID: String
    ) async throws {
        let checkpoint = await privacyActor.validate(operation: .sync, traceID: traceID)
        guard checkpoint.isAllowed else {
            throw SyncError.privacyDenied(sourceTypes: [change.source])
        }
        guard let source = ChangeSource(rawValue: change.source),
              let changeType = ChangeType(rawValue: change.changeType) else {
            throw MemoryEditError.externalReplayUnavailable
        }
        externallyResolvedMemoryIDs.insert(memoryID)
        defer { externallyResolvedMemoryIDs.remove(memoryID) }
        let result = try await sync(
            changes: [ChangeEvent(
                assetId: change.assetID,
                source: source,
                changeType: changeType,
                newContentHash: change.newContentHash,
                hashSkipped: change.hashSkipped
            ),
            ],
            traceID: traceID
        )
        guard result.replacedCount == 1, result.failedCount == 0 else {
            throw MemoryEditError.externalReplayUnavailable
        }
    }

    /// 锁定指定内存，阻止并发用户编辑（AC-6: L4 冲突处理，引用计数 +1）。
    public func lockMemoryForSync(memoryId: String) async {
        lockMemory(memoryId)
    }

    /// 检查内存是否因同步而被锁定（AC-6；计数 > 0 即 locked）。
    public func isMemoryLockedForSync(memoryId: String) async -> Bool {
        (lockedMemoryIds[memoryId] ?? 0) > 0
    }

    /// 锁定内存（引用计数 +1）。
    private func lockMemory(_ memoryId: String) {
        lockedMemoryIds[memoryId, default: 0] += 1
    }

    /// 解锁内存（引用计数 -1，归零才移除；交叠调用各自归还自己的计数）。
    private func unlockMemory(_ memoryId: String) {
        guard let count = lockedMemoryIds[memoryId], count > 1 else {
            lockedMemoryIds.removeValue(forKey: memoryId)
            return
        }
        lockedMemoryIds[memoryId] = count - 1
    }

    // MARK: - Change Detection (AC-1, AC-2)

    /// 注册相册变更监听（AC-1: PHPhotoLibraryChangeObserver, ADR-008 §决策-1 变更去重）。
    ///
    /// 调用此方法后，当用户在系统相册中编辑照片/视频时，
    /// `PhotoKitChangeObserver` 收到变更通知，经批内去重后投递给 `processPhotoChanges`
    /// （跨投递窗口去重），最终驱动 `sync(changes:)` 增量替换。
    /// 使用方（AppDelegate 启动装配）持有此 Pipeline 引用即可；observer 由 Actor 持有，防止被系统释放。
    /// 注册相册变更监听（AC-1: PHPhotoLibraryChangeObserver, ADR-008 §决策-1 变更去重）。
    ///
    /// 调用此方法后，当用户在系统相册中编辑照片/视频时，
    /// `PhotoKitChangeObserver` 收到变更通知，经批内去重后投递给 `processPhotoChanges`
    /// （跨投递窗口去重），最终驱动 `sync(changes:)` 增量替换。
    /// 使用方（AppDelegate 启动装配）持有此 Pipeline 引用即可；observer 由 Actor 持有，防止被系统释放。
    ///
    /// 保持 actor 方法（非 @MainActor）：PHPhotoLibrary.registerChangeObserver 不需主线程
    /// （ObjC 头），observer 不外发跨隔离域；MonitoredFetchResult 在注册前于 MainActor
    /// 建立 pre-change baseline，避免首个回调丢失删除事件。
    public func registerPhotoLibraryObserver() async {
        guard photoObserver == nil else { return }
        // `changeDetails(for:)` requires a fetch result from before the change.
        // Seed it before registration so the first delivered change is not lost.
        await MonitoredFetchResult.seedIfNeeded()
        let observer = PhotoKitChangeObserver { [weak self] events in
            guard let self else { return }
            Task { await self.processPhotoChanges(events) }
        }
        photoObserver = observer
        PHPhotoLibrary.shared().register(observer)
    }

    /// 处理相册变更事件：窗口内去重（ADR-008 §决策-1）后驱动增量同步（AC-4）。
    private func processPhotoChanges(_ events: [ChangeEvent]) async {
        let now = Date()
        recentChangeKeys = recentChangeKeys.filter { now.timeIntervalSince($0.value) < changeDedupeWindow }
        var deduped: [ChangeEvent] = []
        for event in events {
            let key = "\(event.assetId)|\(event.changeType.rawValue)"
            if recentChangeKeys[key] != nil { continue }
            recentChangeKeys[key] = now
            deduped.append(event)
        }
        guard !deduped.isEmpty else { return }
        _ = try? await sync(changes: deduped)
    }

    // MARK: - Initial Full Library Import (3F.11 fix)

    /// 首次全量导入：枚举相册全部资产，以 `.added` 变更驱动生产增量同步
    /// （复用 canonical 确定性 ID upsert + 每代向量 + TaskProgress + 审计，US-SRC-012 AC-1）。
    ///
    /// - 入口 PrivacyCheckpoint(.sync, photo)（R-006），拒绝时返回空结果且不写审计
    /// - 仅导入本地已下载资产（US-SRC-001 AC-6）
    /// - 排除项 fail-closed（AC-5，经 sync() 既有路径）
    /// - 导入完成后写 `.dataSourceConnected` 审计（US-SRC-001 AC-5，hash-only）
    /// - Parameters:
    ///   - adapter: 照片来源适配器（真实 PhotoKit 或测试注入 Fake）
    ///   - traceID: 审计追溯 ID
    /// - Returns: 同步结果（replaced/skipped/failed 计数）
    public func importPhotoLibrary(
        adapter: PhotoKitSourceAdapter,
        traceID: String = UUID().uuidString
    ) async throws -> SyncResult {
        let checkpoint = await privacyActor.validate(
            operation: .sync,
            traceID: traceID,
            sourceTypes: ["photo"]
        )
        guard checkpoint.isAllowed else {
            return SyncResult()
        }

        let refs = await adapter.fetchAllAssets()
        var changes: [ChangeEvent] = []
        for ref in refs {
            if await adapter.isLocallyAvailable(assetId: ref.assetId) {
                changes.append(ChangeEvent(assetId: ref.assetId, source: .photo, changeType: .added))
            }
        }

        // US-SRC-001 AC-5 — 数据源接入审计（hash-only，不含原文）：
        // 授权触发即记录（与导入结果解耦，保证可观测性）
        await adapter.recordDataSourceConnected(traceID: traceID)

        let result = try await sync(changes: changes, traceID: traceID)

        return result
    }

    // MARK: - Auto-sync Toggle (AC-3, AC-8)

    /// 用户是否启用了后台自动同步（AC-3: 默认开启）
    ///
    /// 存储在 UserDefaults 中，键名: `sync_autoSyncEnabled`
    nonisolated public var isAutoSyncEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "sync_autoSyncEnabled") == nil {
                return true  // AC-3: 默认开启
            }
            return UserDefaults.standard.bool(forKey: "sync_autoSyncEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "sync_autoSyncEnabled")
        }
    }

    // MARK: - Private Helpers

    /// 在 VectorStore 中查找指定 assetId 的所有记忆 ID。
    ///
    /// 使用 `VectorStoreActor.allEntries()` 精确全量枚举（R-1.5），
    /// 替代零向量 ANN 搜索——ANN 不保证返回全部条目，会导致漏删旧记忆。
    /// - Parameter assetId: PHAsset.localIdentifier 或其他数据源标识符
    /// - Returns: 匹配的记忆 UUID 字符串列表
    private func findMemories(byAssetId assetId: String) async throws -> [String] {
        if let canonicalRepository {
            // 3F.5 生产路径：canonical 按 sourceLocator 定位（与写入时的确定性 ID 一致）
            return try await canonicalRepository.memoryIDs(forSourceLocator: assetId)
        }
        let entries = await vectorStore.allEntries()
        guard !entries.isEmpty else { return [] }

        var matchingIds: [String] = []
        for entry in entries {
            guard let metadata = entry.metadata,
                  let decoded = try? MemoryEntry.decodeMetadata(from: metadata),
                  decoded.assetId == assetId else {
                continue
            }
            matchingIds.append(entry.id.uuidString)
        }
        return matchingIds
    }

    /// 根据变更事件为内容生成嵌入向量。
    ///
    /// - AC-4: 生成新嵌入用于重新摄入
    private func generateEmbedding(for change: ChangeEvent) async throws -> [Float] {
        // 仅 photo 自动同步（R-5.2）：备忘录/语音备忘录走 Share 摄入，不经同步
        switch change.source {
        case .photo:
            return try await embedder.embedImage(assetId: change.assetId)
        }
    }

    /// 解析记忆 ID 为 UUID；非法时抛 `SyncError.canonicalDeleteFailed`（CR-11，
    /// 不再回退随机 UUID 静默跳过删除）。
    nonisolated private static func requireUUID(_ memoryId: String) throws -> UUID {
        guard let uuid = UUID(uuidString: memoryId) else {
            throw SyncError.canonicalDeleteFailed(
                underlying: CanonicalRepositoryError.invalidMemoryID(memoryId: memoryId)
            )
        }
        return uuid
    }

    /// 向量 SHA-256 摘要（Representation contentHash，CR-3 方案A）。
    nonisolated private static func sha256(of vector: [Float]) -> String {
        let data = vector.withUnsafeBytes { Data($0) }
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
