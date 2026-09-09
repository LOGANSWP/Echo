// ==========================================
// 文件: CanonicalMemoryRepositoryActor.swift
// 对应规格: docs/decisions/ADR-010-canonical-generation-lifecycle.md 决策-1/2/4/5/7
//            docs/01-spec/用户故事与验收标准规格书.md → US-ING-006, US-PRV-004/006/007,
//            US-AWK-007, US-FBK-001/002/003
//            AGENTS.md D-002/D-003/D-004/D-005, §5 存储契约
// Task: 3F.4 - Canonical storage and generation lifecycle; 4.0a - Discovery recent-memory API;
//       4.0h - PhotoKit external-result gate and recoverable deletion intent
//       4.0k - Atomic effective-text reads for manual grounded creation (US-SYN-003 AC-2)
// AC 覆盖: 确定性 ID (RFC 4122 派生), 事务 CRUD (canonical+vector+FTS 同事务/补偿),
//          崩溃点故障注入 (无 half-write), 全删除边界 (D-005), 级联删除 (US-PRV-007),
//          仅从 Echo 移除写 ExcludedAssets (US-PRV-004), 反馈 generation 身份
//          2026-08-09 PR#56 修复: F-1 deleteMemory 清理未加载 generation 的磁盘副本,
//          F-3 searchCanonical FTS5 语法转义 (token 化短语 AND)
//          2026-08-09 PR#56 二轮: CR-3 FTS 行与 representation 解耦 (每记忆一行),
//          CR-1 deleteMemory 缺参回退 memory 定位, Nitpick-1 故障注入 DEBUG-only
//          2026-08-11 3F.6: searchCanonical ORDER BY rank (DEF-56-006, FTS5 bm25 相关性排序)
//          2026-09-01 4.0a: 无副作用 fetchRecentMemories，供 live Discovery adapter 使用
// 架构约束: AGENTS.md §4.2 (Actor 隔离), R-007, R-008 (跨 Actor await)
// 重要: 项目 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor，所有 struct stored/computed 需 nonisolated
// Generated: 2026-08-09 | Updated: 2026-09-05 (4.0h)
// PR#57 review fix: W-03 新增 DEBUG-only .deleteFail 故障点 + CanonicalRepositoryError.deleteInjected，
//                   供 SyncPipeline canonical 删除失败路径测试（D-005 不静默吞错）
// PR#57 CodeRabbit fix: CR-11 新增 memoryNotFound/invalidMemoryID 显式错误（deleteMemory false 与非法 UUID 不再静默）
// PR#65 review fix: resume deletion from the persisted phase, preserve exclusion intent,
//                  and remove every representation vector plus IndexBuildItem residue.
// PR#65 third review fix: vector persistence is a fail-stop phase boundary, and resumed
//                        deletion removes the exact persisted journal operation.
// PR#76 review fixes: external cascades are source-type scoped, override stale Echo-only
//                     exclusion intents, recover incomplete journals, and commit mandatory
//                     completion audits atomically before journal removal.
// ==========================================

import Foundation
import CryptoKit

/// Canonical 存储仓库 Actor — 持有规范事实源与 generation 写入协调（ADR-010 决策-1）。
///
/// ## 事务语义 (US-ING-006 AC-1/2)
/// - Memory/Representation/FTS 写入在 SQLite `executeTransaction` 中原子提交；
/// - 向量写入 VectorStoreActor 在 SQLite 提交之后执行；任一失败触发补偿回滚
///   （删除已写向量 + 删除 canonical 行），保证不产生「向量存在但原文丢失」。
public actor CanonicalMemoryRepositoryActor {
    public static let shared = CanonicalMemoryRepositoryActor()

    private let db: DatabaseManager
    nonisolated let generationRegistry: GenerationRegistryActor
    private let excludedAssets: ExcludedAssetsActor
    private let privacyActor: PrivacyActor

    /// 故障注入点（测试用）— 模拟事务边界处的崩溃/失败。DEBUG only。
    #if DEBUG
        private var fault: FaultPoint?
    #endif

    public init(
        db: DatabaseManager = .shared,
        generationRegistry: GenerationRegistryActor = .shared,
        excludedAssets: ExcludedAssetsActor = .shared,
        privacyActor: PrivacyActor = .shared
    ) {
        self.db = db
        self.generationRegistry = generationRegistry
        self.excludedAssets = excludedAssets
        self.privacyActor = privacyActor
    }

    // MARK: - Deterministic ID

    /// 确定性记忆 ID — RFC 4122 派生（SHA-256 命名空间，版本 5 / 变体 8），不依赖输入顺序。
    ///
    /// 相同 `sourceLocator` + `sourceType` 恒产生相同 UUID，与摄入顺序无关
    /// （ADR-010 决策-1）。
    nonisolated public static func deterministicID(sourceLocator: String, sourceType: String) -> UUID {
        let namespace = "echo-memory-v1"
        let raw = Data("\(namespace)|\(sourceType)|\(sourceLocator)".utf8)
        let digest = SHA256.hash(data: raw)
        var b = Array(digest.prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                b[0], b[1], b[2], b[3],
                b[4], b[5], b[6], b[7],
                b[8], b[9], b[10], b[11],
                b[12], b[13], b[14], b[15]
            )
        )
    }

    // MARK: - 确定性 representation ID 派生（WP3 步骤 1a-1f）

    /// 照片 representation ID 恒等于 canonical memory ID
    /// （vectorId == representationId == memoryId，交接计划 WP3 步骤 1a-1b2）。
    nonisolated public static func photoRepresentationID(memoryID: UUID) -> UUID {
        memoryID
    }

    /// OCR 表示 ID：deterministicID(memoryID|ocr, ocr_text)——与照片视觉表示解耦
    /// （vectorId == representationId，ADR-015 D-7 一对一），避免与 memoryID/视觉表示冲突。
    nonisolated public static func ocrRepresentationID(memoryID: UUID) -> UUID {
        deterministicID(
            sourceLocator: "\(memoryID.uuidString)|ocr",
            sourceType: "ocr_text"
        )
    }

    /// 视频帧 representation ID：与既有帧向量 ID 公式完全一致
    /// （deterministicID(assetId|frameN, video_frame)），零语义漂移。
    nonisolated public static func videoFrameRepresentationID(sourceLocator: String, frameIndex: Int) -> UUID {
        deterministicID(
            sourceLocator: "\(sourceLocator)|frame\(frameIndex)",
            sourceType: "video_frame"
        )
    }

    /// 音频 representation ID：父 memory + 固定 「audio」 组件 key 的确定性派生
    /// （交接计划 WP3 步骤 1e-1f）。
    nonisolated public static func audioRepresentationID(memoryID: UUID) -> UUID {
        deterministicID(
            sourceLocator: "\(memoryID.uuidString.lowercased())|audio",
            sourceType: "video_audio"
        )
    }

    // MARK: - Fault Injection (DEBUG only — Nitpick-1: release 不暴露删数据钩子)

    /// 删除管线协作方（缓存失效）——属性常驻（deleteMemory/purge 的 cache 失效使用处
    /// 在 Release 下仍被引用）；注入 setter 保持 DEBUG-only（Nitpick-1：release 不暴露
    /// 删数据钩子），未注入时使用处跳过（与单元夹具场景一致）。
    private var deletionCacheActor: SearchResultCacheActor?

    #if DEBUG
        public enum FaultPoint: Sendable, Equatable {
            /// 在向量写入前注入失败（模拟向量存储故障）→ 触发补偿回滚
            case vectorWrite
            /// 在 canonical 提交后、向量写入前注入崩溃 → 补偿清理 canonical
            case afterCanonicalWrite
            /// 在 deleteMemory 向量清理前注入失败（模拟 DB 删除故障，3F.5 W-03）
            case deleteFail
            /// WP3 steps 3k-3t2: 删除管线阶段注入点
            case cacheInvalidation
            case vectorDeletePersist
            case auditPurge
            case canonicalTransaction
        }

        public func configureDeletionCollaborators(cache: SearchResultCacheActor) {
            deletionCacheActor = cache
        }

        public func setFault(_ fault: FaultPoint?) {
            self.fault = fault
        }
    #endif

    // MARK: - Transactional Commit (US-ING-006)

    /// 事务性写入一条 canonical 记忆 + 其表示 + FTS + 可选向量。
    ///
    /// - Parameters:
    ///   - memory: 规范记忆实体
    ///   - representations: 该记忆的表示通道
    ///   - vectorsByGeneration: generationId → 待写入向量条目
    ///   - traceID: 审计追踪 ID
    public func commit(
        memory: Memory,
        representations: [Representation],
        vectorsByGeneration: [String: [CanonicalVectorEntry]],
        traceID: String
    ) async throws {
        // Phase 1: SQLite 事务 — canonical + representation + FTS 原子提交
        try await writeCanonicalTransaction(memory: memory, representations: representations)

        #if DEBUG
            if fault == .afterCanonicalWrite {
                // 崩溃点：canonical 已提交但向量未写 → 补偿清理，保证无 half-write
                try await compensateCanonical(memoryId: memory.memoryId)
                try await writeTransactionAudit(traceID: traceID, rolledBack: true)
                throw CanonicalRepositoryError.crashAfterCanonicalWrite
            }

            // Phase 2: 向量写入（逐 generation）
            if fault == .vectorWrite {
                try await compensateCanonical(memoryId: memory.memoryId)
                try await writeTransactionAudit(traceID: traceID, rolledBack: true)
                throw CanonicalRepositoryError.vectorWriteInjected
            }
        #endif

        do {
            for (generationId, entries) in vectorsByGeneration {
                guard let store = await generationRegistry.vectorStore(for: generationId) else {
                    throw CanonicalRepositoryError.generationMissing(generationId: generationId)
                }
                for entry in entries {
                    try await store.ingest(vector: entry.vector, id: entry.id, metadata: entry.metadata)
                }
            }
            // CR-147 (CodeRabbit): 持久化受影响 generation 的 store，保证重启后向量不丢失
            // （canonical 行/FTS 已提交，若 .pxkt 磁盘副本无新向量，重启后语义检索失效）
            for generationId in vectorsByGeneration.keys {
                try await generationRegistry.persistStore(generationId: generationId)
            }
        } catch {
            // 补偿回滚：删除已写向量 + canonical 行
            for (generationId, entries) in vectorsByGeneration {
                guard let store = await generationRegistry.vectorStore(for: generationId) else { continue }
                for entry in entries {
                    _ = await store.delete(id: entry.id)
                }
            }
            try await compensateCanonical(memoryId: memory.memoryId)
            try await writeTransactionAudit(traceID: traceID, rolledBack: true)
            throw CanonicalRepositoryError.vectorWriteFailed(underlying: error)
        }

        try await writeTransactionAudit(traceID: traceID, rolledBack: false)
    }

    // MARK: - Reads

    /// Task 4.0k / US-SYN-003: atomically read the same persisted text used by editing.
    /// The caller owns the operation checkpoint; this read never changes original text.
    public func loadCreationSource(memoryID: UUID) async throws -> CreativeSource? {
        let rows = try await db.executeQuery(
            sql: """
                SELECT m.*, e.title, e.description, e.tagsJSON, e.updatedAt AS editUpdatedAt
                FROM Memory m LEFT JOIN MemoryUserEdit e ON e.memoryId = m.memoryId
                WHERE m.memoryId = ?
                """,
            bindings: [.text(memoryID.uuidString)]
        )
        guard let row = rows.first, let memory = Self.rowToMemory(row) else { return nil }
        let tags: [String]
        if let json = row["tagsJSON"]?.stringValue {
            tags = try JSONDecoder().decode([String].self, from: Data(json.utf8))
        } else {
            tags = []
        }
        let text = MemoryEditActor.effectiveText(
            title: row["title"]?.stringValue ?? "",
            description: row["description"]?.stringValue ?? "",
            tags: tags,
            canonicalText: memory.canonicalText
        )
        return CreativeSource(
            memoryID: memory.memoryId,
            assetID: "",
            sourceType: memory.sourceType,
            text: text,
            timestamp: (memory.originalTimestamp ?? memory.createdAt).timeIntervalSince1970,
            revision: max(memory.updatedAt.timeIntervalSince1970, row["editUpdatedAt"]?.doubleValue ?? 0)
        )
    }

    public func loadMemory(memoryId: UUID) async throws -> Memory? {
        let rows = try await db.executeQuery(
            sql:
                "SELECT memoryId, sourceLocator, canonicalText, sourceType, createdAt, updatedAt, recoverability, originalTimestamp, userEdited, userLocked FROM Memory WHERE memoryId = ?",
            bindings: [.text(memoryId.uuidString)]
        )
        return rows.first.flatMap { Self.rowToMemory($0) }
    }

    /// Returns recent canonical memories for the read-only Discovery adapter.
    ///
    /// This API does not create a second store or mutate ranking/index state. The UI adapter
    /// applies UserPolicy and live source-resolution checks before an item becomes displayable.
    public func fetchRecentMemories(limit: Int) async throws -> [Memory] {
        guard limit > 0 else { return [] }
        let rows = try await db.executeQuery(
            sql: """
                SELECT memoryId, sourceLocator, canonicalText, sourceType, createdAt, updatedAt,
                       recoverability, originalTimestamp, userEdited, userLocked
                FROM Memory
                ORDER BY COALESCE(originalTimestamp, createdAt) DESC, memoryId ASC
                LIMIT ?
                """,
            bindings: [.int(Int64(limit))]
        )
        return rows.compactMap(Self.rowToMemory)
    }

    /// 按 sourceLocator 定位全部关联记忆 ID（3F.5 生产同步路由）。
    ///
    /// 供 SyncPipeline 删除/替换路径查询；与摄入写入时的确定性 ID 语义一致
    /// （同一 sourceLocator + sourceType 恒映射同一记忆）。
    public func memoryIDs(forSourceLocator sourceLocator: String) async throws -> [String] {
        let rows = try await db.executeQuery(
            sql: "SELECT memoryId FROM Memory WHERE sourceLocator = ?",
            bindings: [.text(sourceLocator)]
        )
        return rows.compactMap { $0["memoryId"]?.stringValue }
    }

    /// Returns every canonical PhotoKit identity used by foreground deletion reconciliation.
    func loadPhotoSourceReferences() async throws -> [PhotoSourceMemoryReference] {
        let rows = try await db.executeQuery(
            sql:
                "SELECT memoryId, sourceLocator, sourceType FROM Memory WHERE sourceType IN ('photo', 'video') ORDER BY sourceType, sourceLocator, memoryId",
            bindings: []
        )
        return rows.compactMap { row in
            guard let rawMemoryID = row["memoryId"]?.stringValue,
                let memoryID = UUID(uuidString: rawMemoryID),
                let sourceLocator = row["sourceLocator"]?.stringValue,
                let sourceType = row["sourceType"]?.stringValue
            else { return nil }
            return PhotoSourceMemoryReference(
                memoryID: memoryID,
                sourceLocator: sourceLocator,
                sourceType: sourceType
            )
        }
    }

    public func loadRepresentations(memoryId: UUID) async throws -> [Representation] {
        let rows = try await db.executeQuery(
            sql:
                "SELECT representationId, memoryId, modality, preprocessVersion, contentHash FROM Representation WHERE memoryId = ? ORDER BY representationId",
            bindings: [.text(memoryId.uuidString)]
        )
        return rows.compactMap { Self.rowToRepresentation($0) }
    }

    // FTS5 canonical 文本检索（US-ING-006 AC-3：FTS5 与主事务同步提交）。
    //
    // F-3: 用户查询中的 FTS5 语法字符（引号、`*`、括号、AND/OR 等）会导致
    // MATCH 运行时错误或异常结果。查询按空白分词，每 token 作为短语（引号包裹 +
    // 内嵌引号转义）以隐式 AND 组合，杜绝语法注入；空查询返回空数组。
    // MARK: - Vector→Memory Forward Mapping (WP1 步骤 3/4)

    /// WP1 步骤 3：单个向量 ID → canonical memory 的类型化映射。
    ///
    /// 经 Representation 表按 representationId 反查 memoryId；
    /// 查无即返回 `.missing`（是否 fail-closed 排除由调用方决定）。
    public func mapVectorID(_ vectorID: UUID, generationID: String) async throws -> CanonicalMappingResult {
        let rows = try await db.executeQuery(
            sql: "SELECT memoryId, modality FROM Representation WHERE representationId = ?",
            bindings: [.text(vectorID.uuidString)]
        )
        guard let row = rows.first else {
            return .missing(vectorID: vectorID, generationID: generationID)
        }
        // WP6 步骤 2c/2d：同一 representationId 对应多个候选 memory 即歧义——fail-closed，
        // 歧义向量不具备参与 RRF、迁移复用或路由验证资格（迁移算法 I.3）。
        if rows.count > 1 {
            let candidates = rows.compactMap { $0["memoryId"]?.stringValue.flatMap { UUID(uuidString: $0) } }
            return .ambiguous(vectorID: vectorID, generationID: generationID, candidateMemoryIDs: candidates)
        }
        guard let idString = row["memoryId"]?.stringValue,
            let memoryID = UUID(uuidString: idString),
            let modalityRaw = row["modality"]?.stringValue,
            let modality = Modality(rawValue: modalityRaw)
        else {
            return .missing(vectorID: vectorID, generationID: generationID)
        }
        // ADR-015 D-7: vectorId == representationId，一对一绑定
        return .mapped(
            CanonicalVectorBinding(
                vectorID: vectorID,
                representationID: vectorID,
                memoryID: memoryID,
                modality: modality,
                generationID: generationID
            )
        )
    }

    /// WP1 步骤 4：批量映射 —— 调用方单次仓库交互，结果按入参 ID 键控。
    public func mapVectorIDs(_ vectorIDs: [UUID], generationID: String) async throws -> [UUID: CanonicalMappingResult] {
        var results: [UUID: CanonicalMappingResult] = [:]
        for vectorID in vectorIDs {
            results[vectorID] = try await mapVectorID(vectorID, generationID: generationID)
        }
        return results
    }

    public func searchCanonical(matching query: String, limit: Int = 50) async throws -> [UUID] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map {
            "\"" + String($0).replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        guard !tokens.isEmpty else { return [] }
        let ftsQuery = tokens.joined(separator: " ")
        // DEF-56-006: FTS5 rank（bm25 负分）升序 = 最相关优先，排序先于 LIMIT 截断
        let rows = try await db.executeQuery(
            sql: "SELECT memoryId FROM MemoryFTS WHERE MemoryFTS MATCH ? ORDER BY rank LIMIT ?",
            bindings: [.text(ftsQuery), .int(Int64(limit))]
        )
        return rows.compactMap { row in
            row["memoryId"]?.stringValue.flatMap { UUID(uuidString: $0) }
        }
    }

    // MARK: - Deletion Boundary (D-005 / US-PRV-004/007)

    /// Persists the external deletion intent before PhotoKit without starting D-005 effects.
    public func preparePhotoLibraryDeletion(
        memoryId: UUID,
        traceID: String
    ) async throws -> MemoryDeletionJournal {
        if let existing = try await db.loadDeletionJournals(memoryId: memoryId).first {
            guard existing.intentKind == .photoLibraryAndEcho,
                existing.phase == .planned,
                existing.sourceDeletionState == .prepared
            else {
                throw CanonicalRepositoryError.deletionAlreadyInProgress(memoryId: memoryId.uuidString)
            }
            return existing
        }
        guard let memory = try await loadMemory(memoryId: memoryId) else {
            throw CanonicalRepositoryError.memoryNotFound(memoryId: memoryId.uuidString)
        }
        let representations = try await loadRepresentations(memoryId: memoryId)
        let vectorIDs = Array(Set([memoryId] + representations.map(\.representationId)))
            .sorted { $0.uuidString < $1.uuidString }
        let generations = try await generationRegistry.loadGenerations()
        let journal = MemoryDeletionJournal(
            operationID: "del-\(memoryId.uuidString.lowercased())",
            memoryID: memoryId,
            auditSubjectHash: AuditSubject.memory(memoryId).subjectHash,
            traceID: traceID,
            phase: .planned,
            vectorIDsByGeneration: generations.map {
                GenerationVectorIDs(generationID: $0.generationId, vectorIDs: vectorIDs)
            },
            sourceLocator: memory.sourceLocator,
            sourceType: memory.sourceType,
            writeExcluded: false,
            intentKind: .photoLibraryAndEcho,
            sourceDeletionState: .prepared,
            sourceDeletionOutcome: .notRequested
        )
        try await db.upsertDeletionJournal(journal)
        return journal
    }

    /// Persists the PhotoKit completion or reconciliation result independently of the D-005 phase.
    public func updatePhotoLibraryDeletion(
        memoryId: UUID,
        state: SourceDeletionState,
        outcome: SourceDeletionOutcome
    ) async throws -> MemoryDeletionJournal {
        guard let journal = try await db.loadDeletionJournals(memoryId: memoryId).first,
            journal.intentKind == .photoLibraryAndEcho
        else {
            throw CanonicalRepositoryError.memoryNotFound(memoryId: memoryId.uuidString)
        }
        let updated = MemoryDeletionJournal(
            operationID: journal.operationID,
            memoryID: journal.memoryID,
            auditSubjectHash: journal.auditSubjectHash,
            traceID: journal.traceID,
            phase: journal.phase,
            vectorIDsByGeneration: journal.vectorIDsByGeneration,
            sourceLocator: journal.sourceLocator,
            sourceType: journal.sourceType,
            writeExcluded: journal.writeExcluded,
            intentKind: journal.intentKind,
            sourceDeletionState: state,
            sourceDeletionOutcome: outcome
        )
        try await db.upsertDeletionJournal(updated)
        return updated
    }

    /// Closes an effect-free intent after a definitive cancellation, denial, or non-deletable result.
    public func abandonPhotoLibraryDeletion(memoryId: UUID) async throws {
        guard let journal = try await db.loadDeletionJournals(memoryId: memoryId).first else { return }
        guard journal.intentKind == .photoLibraryAndEcho, journal.phase == .planned else {
            throw CanonicalRepositoryError.deletionAlreadyInProgress(memoryId: memoryId.uuidString)
        }
        try await db.deleteDeletionJournal(operationID: journal.operationID)
    }

    /// 删除一条记忆，事务性覆盖 canonical + 向量 + FTS + translationCache + 审计。
    ///
    /// - Parameter writeExcluded: 用户选择「仅从 Echo 移除」时为 true →
    ///   写入 ExcludedAssets (US-PRV-004 AC-2)；级联删除时为 false (US-PRV-007 AC-2)。
    /// - Returns: `true` 若记忆存在并被删除
    @discardableResult
    public func deleteMemory(
        memoryId: UUID,
        sourceLocator: String? = nil,
        sourceType: String? = nil,
        writeExcluded: Bool,
        traceID: String
    ) async throws -> Bool {
        let operationID = "del-\(memoryId.uuidString.lowercased())"
        let subject = AuditSubject.memory(memoryId)
        let existingJournal = try await db.loadDeletionJournals(memoryId: memoryId).first
        let memory = try await loadMemory(memoryId: memoryId)
        guard memory != nil || existingJournal != nil else { return false }

        if let existingJournal,
            existingJournal.intentKind == .photoLibraryAndEcho,
            existingJournal.sourceDeletionState != .confirmedDeleted {
            throw CanonicalRepositoryError.externalDeletionNotConfirmed(memoryId: memoryId.uuidString)
        }

        let effectiveLocator = existingJournal?.sourceLocator ?? sourceLocator ?? memory?.sourceLocator
        let effectiveType = existingJournal?.sourceType ?? sourceType ?? memory?.sourceType
        let effectiveWriteExcluded = existingJournal?.writeExcluded ?? writeExcluded

        var journal: MemoryDeletionJournal
        if let existingJournal {
            journal = existingJournal
        } else {
            let representations = try await loadRepresentations(memoryId: memoryId)
            let vectorIDs = Array(Set([memoryId] + representations.map(\.representationId)))
                .sorted { $0.uuidString < $1.uuidString }
            let generations = try await generationRegistry.loadGenerations()
            journal = MemoryDeletionJournal(
                operationID: operationID,
                memoryID: memoryId,
                auditSubjectHash: subject.subjectHash,
                traceID: traceID,
                phase: .planned,
                vectorIDsByGeneration: generations.map {
                    GenerationVectorIDs(generationID: $0.generationId, vectorIDs: vectorIDs)
                },
                sourceLocator: effectiveLocator,
                sourceType: effectiveType,
                writeExcluded: effectiveWriteExcluded,
                intentKind: effectiveWriteExcluded ? .echoOnly : .externalCascade,
                sourceDeletionState: effectiveWriteExcluded ? .notApplicable : .confirmedDeleted,
                sourceDeletionOutcome: effectiveWriteExcluded ? .notRequested : .confirmedDeleted
            )
            try await db.upsertDeletionJournal(journal)
        }

        #if DEBUG
            if fault == .deleteFail {
                throw CanonicalRepositoryError.deleteInjected
            }
        #endif

        if journal.phase.ordinal < MemoryDeletionPhase.cacheInvalidated.ordinal {
            if let cache = deletionCacheActor {
                _ = try await cache.invalidate(memoryID: memoryId)
                #if DEBUG
                    if fault == .cacheInvalidation {
                        throw CanonicalRepositoryError.deleteInjected
                    }
                #endif
            }
            journal = try await advanceDeletionJournal(journal, to: .cacheInvalidated)
        }

        if journal.phase.ordinal < MemoryDeletionPhase.vectorsDeleted.ordinal {
            var vectorPersistenceError: Error?
            for plan in journal.vectorIDsByGeneration {
                if let store = await generationRegistry.vectorStore(for: plan.generationID) {
                    for vectorID in plan.vectorIDs {
                        _ = await store.delete(id: vectorID)
                    }
                    do {
                        try await generationRegistry.persistStore(generationId: plan.generationID)
                    } catch {
                        vectorPersistenceError = vectorPersistenceError ?? error
                    }
                } else {
                    let url = await generationRegistry.storeFileURL(for: plan.generationID)
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    do {
                        let diskStore = try VectorStoreActor.load(from: url)
                        for vectorID in plan.vectorIDs {
                            _ = await diskStore.delete(id: vectorID)
                        }
                        try await diskStore.save(to: url)
                    } catch {
                        vectorPersistenceError = vectorPersistenceError ?? error
                    }
                }
            }
            #if DEBUG
                if fault == .vectorDeletePersist {
                    vectorPersistenceError = vectorPersistenceError ?? CanonicalRepositoryError.deleteInjected
                }
            #endif
            // Durable vector cleanup is a phase boundary. Keep the journal at
            // cacheInvalidated so the entire idempotent phase can be replayed.
            if let vectorPersistenceError {
                throw vectorPersistenceError
            }
            journal = try await advanceDeletionJournal(journal, to: .vectorsDeleted)
        }

        if journal.phase.ordinal < MemoryDeletionPhase.auditPurged.ordinal {
            _ = try await privacyActor.purgeAuditRecords(subject: subject, traceID: journal.traceID)
            #if DEBUG
                if fault == .auditPurge {
                    throw CanonicalRepositoryError.deleteInjected
                }
            #endif
            journal = try await advanceDeletionJournal(journal, to: .auditPurged)
        }

        if journal.phase.ordinal < MemoryDeletionPhase.canonicalDeleted.ordinal {
            let storedRepresentationIDs = try await loadRepresentations(memoryId: memoryId)
                .map(\.representationId)
            let plannedVectorIDs = journal.vectorIDsByGeneration.flatMap(\.vectorIDs)
            let representationIDs = Array(Set(storedRepresentationIDs + plannedVectorIDs))
            let indexCleanup = representationIDs.map {
                DatabaseManager.DBWrite(
                    sql: "DELETE FROM IndexBuildItem WHERE representationId = ?",
                    bindings: [.text($0.uuidString)]
                )
            }
            try await db.executeTransaction(
                indexCleanup + [
                    .init(sql: "DELETE FROM MemoryFTS WHERE memoryId = ?", bindings: [.text(memoryId.uuidString)]),
                    .init(
                        sql: "DELETE FROM translationCache WHERE memoryId = ?",
                        bindings: [.text(memoryId.uuidString)]
                    ),
                    .init(sql: "DELETE FROM Memory WHERE memoryId = ?", bindings: [.text(memoryId.uuidString)]),
                ]
            )
            #if DEBUG
                if fault == .canonicalTransaction {
                    throw CanonicalRepositoryError.deleteInjected
                }
            #endif
            journal = try await advanceDeletionJournal(journal, to: .canonicalDeleted)
        }

        var excludedActuallyWritten = false
        var excludedAutoCleaned = false
        if effectiveWriteExcluded, let locator = effectiveLocator, let st = effectiveType {
            try await excludedAssets.add(assetId: locator, sourceType: st, traceID: journal.traceID)
            excludedActuallyWritten = true
        } else if journal.intentKind == .externalCascade,
            let locator = effectiveLocator,
            let st = effectiveType {
            let removed = try await excludedAssets.recordCascadeCleanup(
                assetId: locator,
                sourceType: st,
                traceID: journal.traceID
            )
            let hasCleanupNotice = try await excludedAssets.hasCleanupNotice(assetId: locator)
            excludedAutoCleaned = removed || hasCleanupNotice
        }

        // Mandatory completion evidence is committed atomically before the journal is removed.
        // If the transaction fails, the canonicalDeleted journal remains recoverable and no
        // partial completion evidence can be duplicated by the next foreground retry.
        let policy = await privacyActor.getPolicy()
        var completionAuditWrites = [
            PrivacyActor.makeAuditWrite(
                eventType: .memoryDeleted,
                traceID: journal.traceID,
                policyVersion: policy.policyVersion,
                success: true,
                sourceType: effectiveType,
                excludedWritten: excludedActuallyWritten,
                content: nil,
                preservedOriginal: journal.intentKind == .echoOnly,
                sourceDeletionRequested: journal.intentKind == .photoLibraryAndEcho,
                sourceDeletionCompleted: journal.intentKind == .photoLibraryAndEcho ? true : nil,
                sourceDeletionOutcome: journal.intentKind == .photoLibraryAndEcho
                    ? journal.sourceDeletionOutcome.rawValue : nil
            ),
        ]
        if journal.intentKind == .externalCascade {
            completionAuditWrites.append(
                PrivacyActor.makeAuditWrite(
                    eventType: .cascadeDeleteFromOriginal,
                    traceID: journal.traceID,
                    policyVersion: policy.policyVersion,
                    success: true,
                    sourceType: effectiveType,
                    affectedCount: 1,
                    excludedWritten: false,
                    excludedAutoCleaned: excludedAutoCleaned,
                    userNotified: false
                )
            )
        }
        try await db.executeTransaction(completionAuditWrites)

        // Completed：journal 自移除（防 subject 经 journal 重引入）
        journal = try await advanceDeletionJournal(journal, to: .completed)
        try await db.deleteDeletionJournal(operationID: journal.operationID)
        return true
    }

    private func advanceDeletionJournal(
        _ journal: MemoryDeletionJournal,
        to phase: MemoryDeletionPhase
    ) async throws -> MemoryDeletionJournal {
        let updated = MemoryDeletionJournal(
            operationID: journal.operationID,
            memoryID: journal.memoryID,
            auditSubjectHash: journal.auditSubjectHash,
            traceID: journal.traceID,
            phase: phase,
            vectorIDsByGeneration: journal.vectorIDsByGeneration,
            sourceLocator: journal.sourceLocator,
            sourceType: journal.sourceType,
            writeExcluded: journal.writeExcluded,
            intentKind: journal.intentKind,
            sourceDeletionState: journal.sourceDeletionState,
            sourceDeletionOutcome: journal.sourceDeletionOutcome
        )
        try await db.upsertDeletionJournal(updated)
        return updated
    }

    /// Converts only a trusted original-file cascade into the no-exclusion deletion intent.
    private func promoteEchoOnlyJournalToExternalCascade(memoryID: UUID) async throws {
        guard let journal = try await db.loadDeletionJournals(memoryId: memoryID).first,
            journal.intentKind == .echoOnly
        else { return }
        try await db.upsertDeletionJournal(
            MemoryDeletionJournal(
                operationID: journal.operationID,
                memoryID: journal.memoryID,
                auditSubjectHash: journal.auditSubjectHash,
                traceID: journal.traceID,
                phase: journal.phase,
                vectorIDsByGeneration: journal.vectorIDsByGeneration,
                sourceLocator: journal.sourceLocator,
                sourceType: journal.sourceType,
                writeExcluded: false,
                intentKind: .externalCascade,
                sourceDeletionState: .confirmedDeleted,
                sourceDeletionOutcome: .confirmedDeleted
            )
        )
    }

    /// WP3 steps 5a-5f：consent revoke 三接通组合入口——
    /// cache 全量失效 + AuditLog 全量 purge + deletion journal 清理。
    public func purgeEverythingForConsent() async throws {
        if let cache = deletionCacheActor {
            _ = try await cache.invalidateAll()
        }
        _ = try await privacyActor.purgeAllAuditRecords()
        _ = try await db.deleteAllDeletionJournals()
    }

    /// Cascades a confirmed original-file deletion without adding an ExcludedAssets record.
    ///
    /// - Returns: 删除统计（内存删除数 + 是否清理了无效排除记录）
    public func cascadeDeleteFromOriginal(
        assetId: String,
        sourceType: String,
        traceID: String
    ) async throws -> CascadeDeleteResult {
        let rows = try await db.executeQuery(
            sql: "SELECT memoryId FROM Memory WHERE sourceLocator = ? AND sourceType = ?",
            bindings: [.text(assetId), .text(sourceType)]
        )
        let matchingJournalIDs: [UUID] = try await db.loadAllDeletionJournals().compactMap { journal in
            guard journal.sourceLocator == assetId,
                journal.sourceType == sourceType,
                journal.intentKind == .echoOnly
            else { return nil }
            return journal.memoryID
        }
        let memoryIDs = Set(
            rows.compactMap {
                $0["memoryId"]?.stringValue.flatMap { UUID(uuidString: $0) }
            } + matchingJournalIDs
        ).sorted { $0.uuidString < $1.uuidString }
        var deleted = 0
        for mid in memoryIDs {
            try await promoteEchoOnlyJournalToExternalCascade(memoryID: mid)
            if try await deleteMemory(memoryId: mid, sourceType: sourceType, writeExcluded: false, traceID: traceID) {
                deleted += 1
            }
        }

        var excludedAutoCleaned = try await excludedAssets.hasCleanupNotice(assetId: assetId)
        if deleted == 0 {
            excludedAutoCleaned =
                try await excludedAssets.recordCascadeCleanup(
                    assetId: assetId,
                    sourceType: sourceType,
                    traceID: traceID
                ) || excludedAutoCleaned
            let policy = await privacyActor.getPolicy()
            try await privacyActor.writeAuditLog(
                eventType: .cascadeDeleteFromOriginal,
                traceID: traceID,
                policyVersion: policy.policyVersion,
                success: true,
                sourceType: sourceType,
                affectedCount: 0,
                excludedWritten: false,
                excludedAutoCleaned: excludedAutoCleaned,
                userNotified: false
            )
        }
        return CascadeDeleteResult(deletedCount: deleted, excludedAutoCleaned: excludedAutoCleaned)
    }

    // MARK: - Internal Transaction Helpers

    private func writeCanonicalTransaction(memory: Memory, representations: [Representation]) async throws {
        var writes: [DatabaseManager.DBWrite] = [
            .init(
                sql: """
                    INSERT OR REPLACE INTO Memory (memoryId, sourceLocator, canonicalText, sourceType, createdAt, updatedAt, recoverability, originalTimestamp, userEdited, userLocked)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                bindings: [
                    .text(memory.memoryId.uuidString),
                    .text(memory.sourceLocator),
                    memory.canonicalText.map(DBBinding.text) ?? .null,
                    .text(memory.sourceType),
                    .double(memory.createdAt.timeIntervalSince1970),
                    .double(memory.updatedAt.timeIntervalSince1970),
                    .text(memory.recoverability.rawValue),
                    memory.originalTimestamp.map { .double($0.timeIntervalSince1970) } ?? .null,
                    .int(memory.userEdited ? 1 : 0),
                    .int(memory.userLocked ? 1 : 0),
                ]
            ),
            .init(
                sql: "DELETE FROM Representation WHERE memoryId = ?",
                bindings: [.text(memory.memoryId.uuidString)]
            ),
            .init(
                sql: "DELETE FROM MemoryFTS WHERE memoryId = ?",
                bindings: [.text(memory.memoryId.uuidString)]
            ),
            // CR-3 (PR#56 review): 每记忆恰好一行 FTS，与 representation 数量解耦
            .init(
                sql: "INSERT INTO MemoryFTS (memoryId, canonicalText, sourceType) VALUES (?, ?, ?)",
                bindings: [
                    .text(memory.memoryId.uuidString),
                    memory.canonicalText.map(DBBinding.text) ?? .null,
                    .text(memory.sourceType),
                ]
            ),
        ]
        for rep in representations {
            writes.append(
                .init(
                    sql: """
                        INSERT OR REPLACE INTO Representation (representationId, memoryId, modality, preprocessVersion, contentHash)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    bindings: [
                        .text(rep.representationId.uuidString),
                        .text(rep.memoryId.uuidString),
                        .text(rep.modality.rawValue),
                        .text(rep.preprocessVersion),
                        .text(rep.contentHash),
                    ]
                )
            )
        }
        try await db.executeTransaction(writes)
    }

    private func compensateCanonical(memoryId: UUID) async throws {
        try await db.executeTransaction([
            .init(sql: "DELETE FROM MemoryFTS WHERE memoryId = ?", bindings: [.text(memoryId.uuidString)]),
            .init(sql: "DELETE FROM Memory WHERE memoryId = ?", bindings: [.text(memoryId.uuidString)]),
        ])
    }

    private func writeTransactionAudit(traceID: String, rolledBack: Bool) async throws {
        let policy = await privacyActor.getPolicy()
        try? await privacyActor.writeAuditLog(
            eventType: .ingestTransaction,
            traceID: traceID,
            policyVersion: policy.policyVersion,
            success: !rolledBack,
            affectedCount: 1,
            content: rolledBack ? "rolledBack=true" : "rolledBack=false"
        )
    }

    // MARK: - Row Mapping

    private static func rowToMemory(_ row: [String: DBValue]) -> Memory? {
        guard let memoryId = row["memoryId"]?.stringValue.flatMap({ UUID(uuidString: $0) }),
            let sourceLocator = row["sourceLocator"]?.stringValue,
            let sourceType = row["sourceType"]?.stringValue
        else { return nil }
        return Memory(
            memoryId: memoryId,
            sourceLocator: sourceLocator,
            canonicalText: row["canonicalText"]?.stringValue,
            sourceType: sourceType,
            createdAt: Date(timeIntervalSince1970: row["createdAt"]?.doubleValue ?? 0),
            updatedAt: Date(timeIntervalSince1970: row["updatedAt"]?.doubleValue ?? 0),
            recoverability: Recoverability(rawValue: row["recoverability"]?.stringValue ?? "full") ?? .full,
            originalTimestamp: row["originalTimestamp"]?.doubleValue.map { Date(timeIntervalSince1970: $0) },
            userEdited: (row["userEdited"]?.intValue ?? 0) == 1,
            userLocked: (row["userLocked"]?.intValue ?? 0) == 1
        )
    }

    private static func rowToRepresentation(_ row: [String: DBValue]) -> Representation? {
        guard let repId = row["representationId"]?.stringValue.flatMap({ UUID(uuidString: $0) }),
            let mid = row["memoryId"]?.stringValue.flatMap({ UUID(uuidString: $0) }),
            let modalityRaw = row["modality"]?.stringValue,
            let modality = Modality(rawValue: modalityRaw)
        else { return nil }
        return Representation(
            representationId: repId,
            memoryId: mid,
            modality: modality,
            preprocessVersion: row["preprocessVersion"]?.stringValue ?? "",
            contentHash: row["contentHash"]?.stringValue ?? ""
        )
    }
}

// MARK: - Supporting Types

/// 待写入 generation 向量存储的条目。
public struct CanonicalVectorEntry: Sendable {
    nonisolated public let id: UUID
    nonisolated public let vector: [Float]
    nonisolated public let metadata: Data?

    nonisolated public init(id: UUID, vector: [Float], metadata: Data? = nil) {
        self.id = id
        self.vector = vector
        self.metadata = metadata
    }
}

/// 级联删除结果（US-PRV-007）。
public struct CascadeDeleteResult: Sendable, Equatable {
    nonisolated public let deletedCount: Int
    nonisolated public let excludedAutoCleaned: Bool

    nonisolated public init(deletedCount: Int, excludedAutoCleaned: Bool) {
        self.deletedCount = deletedCount
        self.excludedAutoCleaned = excludedAutoCleaned
    }
}

// MARK: - Error Types

public enum CanonicalRepositoryError: Error, LocalizedError, Sendable {
    case crashAfterCanonicalWrite
    case vectorWriteInjected
    case deleteInjected
    case generationMissing(generationId: String)
    case vectorWriteFailed(underlying: Error)
    /// deleteMemory 未找到对应记忆（CR-11：false 结果显式化为错误，不再静默跳过）
    case memoryNotFound(memoryId: String)
    /// 记忆 ID 字符串无法解析为 UUID（CR-11：不再回退随机 UUID 静默跳过删除）
    case invalidMemoryID(memoryId: String)
    case deletionAlreadyInProgress(memoryId: String)
    case externalDeletionNotConfirmed(memoryId: String)

    public var errorDescription: String? {
        switch self {
        case .crashAfterCanonicalWrite:
            return "Injected crash after canonical write (test fault)"

        case .vectorWriteInjected:
            return "Injected vector write failure (test fault)"

        case .deleteInjected:
            return "Injected canonical delete failure (test fault)"

        case .generationMissing(let generationId):
            return "Generation vector store missing: \(generationId)"

        case .vectorWriteFailed(let error):
            return "Vector write failed: \(error.localizedDescription)"

        case .memoryNotFound(let memoryId):
            return "Canonical memory not found: \(memoryId)"

        case .invalidMemoryID(let memoryId):
            return "Invalid memory UUID: \(memoryId)"

        case .deletionAlreadyInProgress(let memoryId):
            return "A deletion is already in progress for memory: \(memoryId)"

        case .externalDeletionNotConfirmed(let memoryId):
            return "External source deletion is not confirmed for memory: \(memoryId)"
        }
    }
}
