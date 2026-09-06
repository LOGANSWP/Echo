// ==========================================
// 文件: ExcludedAssetsActor.swift
// 对应规格: docs/01-spec/用户故事与验收标准规格书.md → US-PRV-001/004/007, US-SRC-008
//            docs/02-architecture/架构设计文档.md §2.2 (Actor 隔离服务)
// 任务: 1.4 - 集成 SQLite，创建 ExcludedAssets 等表 (Stub)
//       2.2 - ExcludedAssetsActor 实现（含恢复、一键恢复、变更监测）
//       4.0h - One-time cascade cleanup notice and truthful userNotified audit
// AC 覆盖: US-SRC-008 AC-3 (写入 ExcludedAssets), AC-4 (被排除项不重新导入),
//          AC-5 (恢复+文件存在性校验), AC-6 (重新授权一键恢复),
//          AC-7 (变更监测+分页), AC-8 (审计事件)
// 架构约束: AGENTS.md §4.2 (Actor 隔离), R-007/R-008, AGENTS.md §5.2 (ExcludedAssets 写入条件),
//           AGENTS.md §7.1 (PrivacyCheckpoint 强制注入), AC-8 审计事件以规格书为准
// 避坑: EXCL-001 (系统自动删除不写入), EXCL-004 (恢复前校验存在性), EXCL-005 (不自动轮询)
// 重要: 项目 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor，所有 struct stored/computed 需 nonisolated
// 豁免说明: 本类为存储型 Service Actor (§5.1)，非 Pipeline Actor (§7.1)。
//          PrivacyCheckpoint.validate() 由调用方（Pipeline/ViewModel）在入口处执行；
//          本 Actor 通过 writeAuditLog() 记录操作审计，满足 §7.3 审计覆盖要求。
// 测试策略: 核心 SQL + 审计逻辑由 ExcludedAssetsActorTests 覆盖（17 个测试）。
//          restore()/checkForChanges() 的 PHAsset 边界场景在 Phase 4 ExcludedAssetsBoundaryTests 中覆盖。
// Generated: 2026-07-04 | Updated: 2026-09-05 (4.0h)
// ==========================================

import Foundation
@preconcurrency import Photos

// MARK: - Restore Result

/// 恢复操作的结果 (US-SRC-008 AC-5)
public enum RestoreResult: Sendable, Equatable {
    /// 原始文件存在，已从排除列表移除，可触发重新导入
    case restored
    /// 原始文件已被删除，已自动从排除列表清理
    case fileMissing
}

// MARK: - Change Info

/// 已排除资产的变更状态 (US-SRC-008 AC-7)
public struct ChangeInfo: Sendable, Equatable {
    public nonisolated let assetId: String
    public nonisolated let sourceType: String
    public nonisolated let status: ChangeStatus
    public nonisolated let modificationDate: Date?
    public nonisolated let excludedAt: Date

    public enum ChangeStatus: String, Sendable, Equatable {
        /// 原始文件未发生变化
        case unchanged
        /// 原始文件已被修改（modificationDate > excludedAt）
        case changed
        /// 原始文件已不存在
        case fileMissing
    }

    public nonisolated init(
        assetId: String,
        sourceType: String,
        status: ChangeStatus,
        modificationDate: Date?,
        excludedAt: Date
    ) {
        self.assetId = assetId
        self.sourceType = sourceType
        self.status = status
        self.modificationDate = modificationDate
        self.excludedAt = excludedAt
    }
}

// MARK: - ExcludedAssets Actor

/// 用户排除资产 Actor — 管理 ExcludedAssets SQLite 表。
///
/// ## ExcludedAssets 写入条件（仅有三种）- AGENTS.md §5.2
/// 1. 用户选择"仅从 Echo 移除" → 写入 (US-PRV-004)
/// 2. 重新授权时用户选择"一键恢复排除项" → 批量移除 (US-PRV-001)
/// 3. 用户从已排除项目界面手动恢复 → 移除 (US-SRC-008)
///
/// ## AC 覆盖 (US-SRC-008)
/// - AC-3: 所有排除操作统一写入本地 ExcludedAssets 表
/// - AC-4: ExcludedAssets 表中的条目不被重新导入
/// - AC-5: 恢复前校验原始文件存在性（EXCL-004）
/// - AC-6: 重新授权后一键恢复（EXCL-003）
/// - AC-7: 变更监测（基于修改时间戳，每次打开查询+手动刷新，不轮询 EXCL-005）
/// - AC-8: 审计记录 .excluded, .excludedRestored, .excludedRestoreFailedFileMissing,
///          .excludedChangeDetected, .excludedBatchRestored, .excludedAutoCleaned
///
/// PHAsset 集成通过 @preconcurrency import Photos 和私有辅助方法处理。
/// 测试通过 audit log 验证核心逻辑；PHAsset 边界场景在 Phase 4 集成测试覆盖。
public actor ExcludedAssetsActor {

    public static let shared = ExcludedAssetsActor()
    private let db: DatabaseManager
    private let privacyActor: PrivacyActor

    init(db: DatabaseManager = .shared, privacyActor: PrivacyActor = .shared) {
        self.db = db
        self.privacyActor = privacyActor
    }

    // MARK: - Query Methods

    /// 检查指定 Asset ID 是否在排除列表中 (AC-4: 被排除项不重新导入)
    public func contains(assetId: String) async throws -> Bool {
        let rows = try await db.executeQuery(
            sql: "SELECT 1 FROM ExcludedAssets WHERE assetId = ? LIMIT 1",
            bindings: [.text(assetId)]
        )
        return !rows.isEmpty
    }

    /// 将资产加入排除列表（条件 1：用户主动"仅从 Echo 移除"）
    ///
    /// AC-3: 写入 ExcludedAssets 表
    /// AC-8: 记录 .excluded 审计事件
    ///
    /// - Parameters:
    ///   - assetId: PHAsset.localIdentifier
    ///   - sourceType: 数据源类型（如 "photo", "note", "voice"）
    ///   - traceID: 审计追踪 ID
    public func add(assetId: String, sourceType: String, traceID: String = UUID().uuidString) async throws {
        try await db.executeWrite(
            sql: "INSERT OR REPLACE INTO ExcludedAssets (assetId, sourceType, excludedAt) VALUES (?, ?, ?)",
            bindings: [.text(assetId), .text(sourceType), .int(Int64(Date().timeIntervalSince1970 * 1000))]
        )
        try? await privacyActor.writeAuditLog(
            eventType: .excluded,
            traceID: traceID,
            policyVersion: await privacyActor.getPolicy().policyVersion,
            success: true,
            sourceType: sourceType,
            affectedCount: 1,
            excludedWritten: true
        )
    }

    /// 从排除列表移除单个资产（条件 3：用户手动恢复，不含文件校验）
    ///
    /// 注意：此方法不验证原始文件存在性，仅移除排除记录。
    /// 需要文件存在性校验请使用 `restore(assetId:sourceType:traceID:)`。
    @discardableResult
    public func remove(assetId: String) async throws -> Bool {
        let exists = try await contains(assetId: assetId)
        guard exists else { return false }
        try await db.executeWrite(
            sql: "DELETE FROM ExcludedAssets WHERE assetId = ?",
            bindings: [.text(assetId)]
        )
        return true
    }

    /// 获取排除列表总数
    public func count() async throws -> Int {
        let rows = try await db.executeQuery(
            sql: "SELECT COUNT(*) AS cnt FROM ExcludedAssets",
            bindings: []
        )
        return rows.first?["cnt"]?.intValue.map(Int.init) ?? 0
    }

    /// 获取指定数据源的排除项数量
    public func countForSource(_ sourceType: String) async throws -> Int {
        let rows = try await db.executeQuery(
            sql: "SELECT COUNT(*) AS cnt FROM ExcludedAssets WHERE sourceType = ?",
            bindings: [.text(sourceType)]
        )
        return rows.first?["cnt"]?.intValue.map(Int.init) ?? 0
    }

    // MARK: - Cascade Cleanup Notice (4.0h / ADR-019)

    /// Removes an invalid exclusion after an original-file cascade and persists a pending notice.
    /// The notice stores only the asset digest; `userNotified` remains false at this stage.
    @discardableResult
    public func recordCascadeCleanup(
        assetId: String,
        sourceType: String,
        traceID: String
    ) async throws -> Bool {
        guard try await contains(assetId: assetId) else { return false }
        let digest = AuditContentHasher.sha256Hex(assetId)
        try await db.executeTransaction([
            .init(
                sql: "DELETE FROM ExcludedAssets WHERE assetId = ?",
                bindings: [.text(assetId)]
            ),
            .init(
                sql: "INSERT OR REPLACE INTO ExcludedCleanupNotice (assetIdDigest, sourceType, createdAt, presentedAt) VALUES (?, ?, ?, NULL)",
                bindings: [.text(digest), .text(sourceType), .double(Date().timeIntervalSince1970)]
            ),
        ])
        return true
    }

    public func pendingCleanupNoticeCount() async throws -> Int {
        let rows = try await db.executeQuery(
            sql: "SELECT COUNT(*) AS cnt FROM ExcludedCleanupNotice WHERE presentedAt IS NULL",
            bindings: []
        )
        return rows.first?["cnt"]?.intValue.map(Int.init) ?? 0
    }

    /// Called by the UI only after the notice enters the visible hierarchy.
    @discardableResult
    public func markCleanupNoticesPresented(traceID: String) async throws -> Int {
        let rows = try await db.executeQuery(
            sql: "SELECT assetIdDigest, sourceType FROM ExcludedCleanupNotice WHERE presentedAt IS NULL ORDER BY createdAt",
            bindings: []
        )
        guard !rows.isEmpty else { return 0 }
        let now = Date().timeIntervalSince1970
        try await db.executeWrite(
            sql: "UPDATE ExcludedCleanupNotice SET presentedAt = ? WHERE presentedAt IS NULL",
            bindings: [.double(now)]
        )
        let policyVersion = await privacyActor.getPolicy().policyVersion
        for row in rows {
            try? await privacyActor.writeAuditLog(
                eventType: .excludedAutoCleaned,
                traceID: traceID,
                policyVersion: policyVersion,
                success: true,
                sourceType: row["sourceType"]?.stringValue,
                affectedCount: 1,
                subjectKind: "asset",
                subjectHash: row["assetIdDigest"]?.stringValue,
                excludedAutoCleaned: true,
                userNotified: true
            )
        }
        return rows.count
    }

    /// 分页列出排除资产 (AC-7: 分页懒加载，默认每页 50 条)
    public func listAll(limit: Int = 50, offset: Int = 0) async throws -> [(assetId: String, sourceType: String, excludedAt: Date)] {
        let rows = try await db.executeQuery(
            sql: "SELECT assetId, sourceType, excludedAt FROM ExcludedAssets ORDER BY excludedAt DESC LIMIT ? OFFSET ?",
            bindings: [.int(Int64(limit)), .int(Int64(offset))]
        )
        return rows.compactMap { row in
            guard let id = row["assetId"]?.stringValue,
                  let source = row["sourceType"]?.stringValue,
                  let ts = row["excludedAt"]?.intValue else { return nil }
            return (id, source, Date(timeIntervalSince1970: TimeInterval(ts) / 1000))
        }
    }

    // MARK: - Restore with File Validation (AC-5)

    /// 恢复单个排除资产——校验原始文件存在性后再从排除列表移除。
    ///
    /// ## AC-5 行为 (EXCL-004):
    /// - 若原始文件存在 → 从 ExcludedAssets 移除，返回 `.restored`
    /// - 若原始文件已删除 → 从 ExcludedAssets 移除，返回 `.fileMissing`
    ///
    /// ## AC-8 审计:
    /// - 成功恢复 → `.excludedRestored`
    /// - 文件缺失 → `.excludedRestoreFailedFileMissing`
    ///
    /// - Parameters:
    ///   - assetId: PHAsset.localIdentifier
    ///   - sourceType: 数据源类型
    ///   - traceID: 审计追踪 ID
    /// - Returns: 恢复结果
    public func restore(assetId: String, sourceType: String, traceID: String = UUID().uuidString) async throws -> RestoreResult {
        let fileExists = fetchPHAsset(by: assetId) != nil
        let policyVersion = await privacyActor.getPolicy().policyVersion

        try await db.executeWrite(
            sql: "DELETE FROM ExcludedAssets WHERE assetId = ?",
            bindings: [.text(assetId)]
        )

        if fileExists {
            try? await privacyActor.writeAuditLog(
                eventType: .excludedRestored,
                traceID: traceID,
                policyVersion: policyVersion,
                success: true,
                sourceType: sourceType,
                affectedCount: 1
            )
            return .restored
        } else {
            try? await privacyActor.writeAuditLog(
                eventType: .excludedRestoreFailedFileMissing,
                traceID: traceID,
                policyVersion: policyVersion,
                success: false,
                sourceType: sourceType,
                affectedCount: 1
            )
            return .fileMissing
        }
    }

    // MARK: - Batch Restore (AC-6)

    /// 一键恢复指定数据源的所有排除项（条件 2：重新授权后一键恢复）
    ///
    /// ## AC-6 行为 (EXCL-003):
    /// - 用户重新授权数据源后调用
    /// - 将该数据源对应的所有 ExcludedAssets 记录移除
    /// - 触发重新导入（由调用方负责）
    ///
    /// ## AC-8 审计: `.excludedBatchRestored`
    ///
    /// - Parameters:
    ///   - sourceType: 数据源类型
    ///   - traceID: 审计追踪 ID
    /// - Returns: 被移除的排除项数量
    @discardableResult
    public func batchRestore(sourceType: String, traceID: String = UUID().uuidString) async throws -> Int {
        let countBefore = try await countForSource(sourceType)
        try await db.executeWrite(
            sql: "DELETE FROM ExcludedAssets WHERE sourceType = ?",
            bindings: [.text(sourceType)]
        )
        try? await privacyActor.writeAuditLog(
            eventType: .excludedBatchRestored,
            traceID: traceID,
            policyVersion: await privacyActor.getPolicy().policyVersion,
            success: true,
            sourceType: sourceType,
            affectedCount: countBefore
        )
        return countBefore
    }

    // MARK: - Change Detection (AC-7)

    /// 检查已排除资产的变更状态（基于 PHAsset 修改时间戳）。
    ///
    /// ## AC-7 行为 (EXCL-005):
    /// - 在用户每次打开"已排除项目"界面时调用（非实时后台）
    /// - 比较每个排除项的 PHAsset.modificationDate 与 ExcludedAssets.excludedAt
    ///   - modificationDate > excludedAt → `.changed`
    ///   - PHAsset 不存在 → `.fileMissing`
    ///   - 否则 → `.unchanged`
    ///
    /// ## AC-8 审计: `.excludedChangeDetected` (仅当检测到变更时)
    ///
    /// - Parameter assetIds: 要检查的资产 ID 列表（当前加载的条目）
    /// - Returns: 变更信息列表，与输入顺序一致
    public func checkForChanges(assetIds: [String]) async throws -> [ChangeInfo] {
        guard !assetIds.isEmpty else { return [] }

        let policyVersion = await privacyActor.getPolicy().policyVersion

        // 批量查询排除项元数据
        let placeholders = String(repeating: "?,", count: assetIds.count).dropLast()
        let rows = try await db.executeQuery(
            sql: "SELECT assetId, sourceType, excludedAt FROM ExcludedAssets WHERE assetId IN (\(placeholders))",
            bindings: assetIds.map { .text($0) }
        )

        let excludedMap: [String: (sourceType: String, excludedAt: Date)] = Dictionary(
            uniqueKeysWithValues: rows.compactMap { row in
                guard let id = row["assetId"]?.stringValue,
                      let source = row["sourceType"]?.stringValue,
                      let ts = row["excludedAt"]?.intValue else { return nil }
                return (id, (source, Date(timeIntervalSince1970: TimeInterval(ts) / 1000)))
            }
        )

        var results: [ChangeInfo] = []

        for assetId in assetIds {
            guard let excludedInfo = excludedMap[assetId] else { continue }
            let excludedAt = excludedInfo.excludedAt

            if let asset = fetchPHAsset(by: assetId) {
                if let modDate = asset.modificationDate, modDate > excludedAt {
                    results.append(ChangeInfo(
                        assetId: assetId,
                        sourceType: excludedInfo.sourceType,
                        status: .changed,
                        modificationDate: modDate,
                        excludedAt: excludedAt
                    ))
                    try? await privacyActor.writeAuditLog(
                        eventType: .excludedChangeDetected,
                        traceID: UUID().uuidString,
                        policyVersion: policyVersion,
                        success: true,
                        sourceType: excludedInfo.sourceType,
                        affectedCount: 1
                    )
                } else {
                    results.append(ChangeInfo(
                        assetId: assetId,
                        sourceType: excludedInfo.sourceType,
                        status: .unchanged,
                        modificationDate: asset.modificationDate,
                        excludedAt: excludedAt
                    ))
                }
            } else {
                results.append(ChangeInfo(
                    assetId: assetId,
                    sourceType: excludedInfo.sourceType,
                    status: .fileMissing,
                    modificationDate: nil,
                    excludedAt: excludedAt
                ))
            }
        }

        return results
    }

    // MARK: - Cleanup (US-PRV-007 AC-2)

    /// 清理无效排除记录（级联删除时调用，US-PRV-007 AC-2）
    ///
    /// EXCL-002: 级联删除时检查排除表并自动清理无效记录
    /// AC-8: 审计 `.excludedAutoCleaned`
    public func cleanupInvalidRecord(assetId: String, traceID: String = UUID().uuidString) async throws {
        try await db.executeWrite(
            sql: "DELETE FROM ExcludedAssets WHERE assetId = ?",
            bindings: [.text(assetId)]
        )
        try? await privacyActor.writeAuditLog(
            eventType: .excludedAutoCleaned,
            traceID: traceID,
            policyVersion: await privacyActor.getPolicy().policyVersion,
            success: true,
            affectedCount: 1
        )
    }

    // MARK: - Private Helpers

    /// 通过 localIdentifier 获取 PHAsset（内部使用，PHAsset 不跨 Actor 边界传递）。
    ///
    /// @preconcurrency import Photos 抑制 Sendable 警告。
    /// PHAsset 属性读取仅在 Actor 内部进行，安全。
    private func fetchPHAsset(by localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }
}
