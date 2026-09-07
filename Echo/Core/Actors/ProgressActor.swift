// ==========================================
// 文件: ProgressActor.swift
// 对应规格: docs/02-architecture/架构设计文档.md §6 (断点续传与进度管理)
//            docs/01-spec/用户故事与验收标准规格书.md → US-SYS-001 (AC-4)
// 任务: 1.4 - 集成 SQLite；4.0g - 生产任务断点恢复
// AC 覆盖: US-SYS-001 AC-4 (raw task type 保留、恢复描述校验、事务性 Restart checkpoint)
// 架构约束: AGENTS.md §4.3 (长任务与队列契约), AGENTS.md §4.5 (断点续传契约)
// 生成时间: 2026-07-04
// ==========================================

import Foundation

public actor ProgressActor {

    public static let shared = ProgressActor()
    private let db: DatabaseManager

    internal init(db: DatabaseManager = .shared) {
        self.db = db
    }

    /// 保存或更新任务进度（原子 upsert）
    public func save(progress: TaskProgress) async throws {
        if let resumeData = progress.resumeData {
            _ = try TaskResumeDescriptor.decode(resumeData)
        }
        var bindings: [DBBinding] = [
            .text(progress.taskId),
            .text(progress.rawTaskType),
            .int(Int64(progress.lastProcessedIndex)),
            .int(Int64(progress.totalCount)),
            .double(progress.createdAt.timeIntervalSince1970),
            .double(progress.updatedAt.timeIntervalSince1970),
        ]
        bindings.append(progress.lastProcessedId.map { .text($0) } ?? .null)
        bindings.append(progress.resumeData.map { .blob($0) } ?? .null)

        try await db.executeWrite(
            sql: """
                INSERT OR REPLACE INTO TaskProgress
                  (taskId, taskType, lastProcessedIndex, totalCount, createdAt, updatedAt, lastProcessedId, resumeData)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            bindings: bindings
        )
    }

    /// 更新已处理索引
    public func updateProgress(taskId: String, lastProcessedIndex: Int, lastProcessedId: String?) async throws {
        guard let _ = try await load(taskId: taskId) else {
            throw DatabaseError.notFound(id: taskId)
        }
        try await db.executeWrite(
            sql: "UPDATE TaskProgress SET lastProcessedIndex = ?, lastProcessedId = ?, updatedAt = ? WHERE taskId = ?",
            bindings: [
                .int(Int64(lastProcessedIndex)),
                lastProcessedId.map { .text($0) } ?? .null,
                .double(Date().timeIntervalSince1970),
                .text(taskId),
            ]
        )
    }

    /// 加载指定任务的进度
    public func load(taskId: String) async throws -> TaskProgress? {
        let rows = try await db.executeQuery(
            sql: "SELECT taskId, taskType, lastProcessedId, lastProcessedIndex, totalCount, resumeData, createdAt, updatedAt FROM TaskProgress WHERE taskId = ?",
            bindings: [.text(taskId)]
        )
        guard let row = rows.first,
              let id = row["taskId"]?.stringValue,
              let typeStr = row["taskType"]?.stringValue else { return nil }

        return TaskProgress(
            taskId: id,
            rawTaskType: typeStr,
            lastProcessedIndex: row["lastProcessedIndex"]?.intValue.map(Int.init) ?? 0,
            totalCount: row["totalCount"]?.intValue.map(Int.init) ?? 0,
            lastProcessedId: row["lastProcessedId"]?.stringValue,
            resumeData: row["resumeData"]?.blobValue,
            updatedAt: row["updatedAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date(),
            createdAt: row["createdAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date()
        )
    }

    /// 是否存在未完成进度
    public func hasPendingProgress(taskType: TaskType) async throws -> Bool {
        let rows = try await db.executeQuery(
            sql: "SELECT COUNT(*) AS cnt FROM TaskProgress WHERE taskType = ?",
            bindings: [.text(taskType.rawValue)]
        )
        return (rows.first?["cnt"]?.intValue ?? 0) > 0
    }

    /// 加载全部活跃任务进度（3F.11 fix：后台任务面板真实数据源，US-SYS-001 AC-2）。
    public func loadAll() async throws -> [TaskProgress] {
        let rows = try await db.executeQuery(
            sql: "SELECT taskId, taskType, lastProcessedId, lastProcessedIndex, totalCount, resumeData, createdAt, updatedAt FROM TaskProgress",
            bindings: []
        )
        return rows.compactMap { row in
            guard let id = row["taskId"]?.stringValue,
                  let typeStr = row["taskType"]?.stringValue else { return nil }
            return TaskProgress(
                taskId: id,
                rawTaskType: typeStr,
                lastProcessedIndex: row["lastProcessedIndex"]?.intValue.map(Int.init) ?? 0,
                totalCount: row["totalCount"]?.intValue.map(Int.init) ?? 0,
                lastProcessedId: row["lastProcessedId"]?.stringValue,
                resumeData: row["resumeData"]?.blobValue,
                updatedAt: row["updatedAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date(),
                createdAt: row["createdAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date()
            )
        }
    }

    /// Atomically replaces an unchanged saved checkpoint with an index-zero retry record.
    /// The updatedAt precondition prevents a stale prompt from erasing newer progress.
    public func resetForRestart(_ progress: TaskProgress) async throws -> TaskProgress {
        let now = Date()
        let reset = TaskProgress(
            taskId: progress.taskId,
            rawTaskType: progress.rawTaskType,
            lastProcessedIndex: 0,
            totalCount: progress.totalCount,
            lastProcessedId: nil,
            resumeData: progress.resumeData,
            updatedAt: now,
            createdAt: progress.createdAt
        )
        let changed = try await db.executeConditionalTransaction(
            [DatabaseManager.DBWrite(
                sql: """
                    UPDATE TaskProgress
                    SET lastProcessedIndex = 0, lastProcessedId = NULL, updatedAt = ?
                    WHERE taskId = ?
                    """,
                bindings: [.double(now.timeIntervalSince1970), .text(progress.taskId)]
            )],
            conditionSQL: "SELECT taskId FROM TaskProgress WHERE taskId = ? AND updatedAt = ?",
            conditionBindings: [
                .text(progress.taskId),
                .double(progress.updatedAt.timeIntervalSince1970),
            ],
            expectedRowExists: true
        )
        guard changed else { throw TaskRecoveryError.staleProgress }
        return reset
    }

    /// 删除指定任务的进度（US-SYS-001 AC-4：任务完成后立即删除）
    @discardableResult
    public func delete(taskId: String) async throws -> Bool {
        let changes = try await db.executeWrite(
            sql: "DELETE FROM TaskProgress WHERE taskId = ?",
            bindings: [.text(taskId)]
        )
        return changes > 0
    }
}
