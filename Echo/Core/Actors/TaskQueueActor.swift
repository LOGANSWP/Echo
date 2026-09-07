// ==========================================
// 文件: TaskQueueActor.swift
// 对应规格: docs/decisions/ADR-011-task-progress-boundary.md 决策-1 (串行契约)
//            docs/01-spec/用户故事与验收标准规格书.md → US-SYS-001 AC-3/4/6 (暂停/取消/断点续传)
//            AGENTS.md §4.3 (TaskQueue 契约), §4.5 (断点续传契约)
// 任务: 3F.5 - Production ingestion; 4.0g - Production task resume loop;
//       4.0j - Resource-deferred narrative work cleanup
// AC Coverage: serial execution, reserved unique taskId ownership,
//              pause without releasing the job, cancellation checkpoint retention,
//              pause-ownership cleanup, terminal progress cleanup, truthful active projection
// 架构约束: AGENTS.md §4.2 (Actor 隔离), §4.3 (TaskQueue 契约), R-007 (禁止 unchecked Sendable)
// PR#57 CodeRabbit fix: CR-1 取消/暂停排队任务 resume 等待方、暂停不阻塞后续任务;
//                       CR-21 cancel 即时移除队列条目（pendingCount 精确）
// 重要: 项目 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor，所有 struct stored/computed 需 nonisolated
// 生成时间: 2026-08-10
// ==========================================

import Foundation

/// 长任务串行队列 Actor（ADR-011 决策-1，AGENTS.md §4.3）。
///
/// ## 契约
/// - **串行执行**：同一时刻仅一个任务在运行，索引构建与数据同步互斥，避免资源争抢
/// - **进度持久化**：入队时经 `ProgressActor.save` 写入 `TaskProgress`；任务通过
///   `TaskContext.report` 原子更新进度
/// - **完成/最终失败后清理**：任务成功或抛出非取消错误后立即删除 `TaskProgress` 记录
///   （US-SYS-001 AC-4），避免表无限增长
/// - **取消保留进度**：取消或暂停不删除进度记录，重启后 UI 询问「继续/重新开始」（§4.5）
/// - **暂停**：任务挂起（不释放资源，可随时恢复）；运行中的任务经 `PauseToken` 协作式暂停
///
/// ## 协作式取消/暂停
/// - 任务体通过 `Task.isCancelled` 感知取消；队列对激活任务调用 `Task.cancel()`
/// - 任务体通过 `TaskContext.checkPaused()` 在检查点协作式挂起；恢复后由同一 job 继续
public actor TaskQueueActor {

    // MARK: - Singleton

    public static let shared = TaskQueueActor()

    // MARK: - Properties

    private let progressActor: ProgressActor
    private var queue: [QueuedJob] = []
    private var activeTask: Task<Void, Never>?
    private var activeJobId: String?
    private var activePauseToken: PauseToken?
    private var pausedJobIds: Set<String> = []
    private var cancelledJobIds: Set<String> = []
    private var reservations: [String: UUID] = [:]
    private var completions: [String: CheckedContinuation<Void, Error>] = [:]

    // MARK: - Initialization

    public init(progressActor: ProgressActor = .shared) {
        self.progressActor = progressActor
    }

    // MARK: - Public Task Model

    /// 队列任务（Sendable 值类型，跨 Actor 安全）。
    public struct QueuedJob: Sendable {
        public nonisolated let taskId: String
        public nonisolated let taskType: TaskType
        public nonisolated let totalCount: Int
        public nonisolated let resumeData: Data?
        public nonisolated let body: @Sendable (TaskContext) async throws -> Void

        public nonisolated init(
            taskId: String = UUID().uuidString,
            taskType: TaskType,
            totalCount: Int,
            resumeData: Data? = nil,
            body: @escaping @Sendable (TaskContext) async throws -> Void
        ) {
            self.taskId = taskId
            self.taskType = taskType
            self.totalCount = totalCount
            self.resumeData = resumeData
            self.body = body
        }
    }

    /// Controls whether enqueue creates a new checkpoint or adopts one loaded after relaunch.
    public enum ProgressPolicy: Sendable {
        case createNew
        case preserveExisting
    }

    /// Short-lived ownership token used to close the check/reset/enqueue reentrancy window.
    public nonisolated struct TaskReservation: Sendable, Equatable {
        fileprivate nonisolated let taskId: String
        fileprivate nonisolated let token: UUID
    }

    /// 任务上下文 — 提供进度上报与暂停/取消检查（跨 Actor 值类型）。
    public struct TaskContext: Sendable {
        nonisolated let taskId: String
        nonisolated let progressActor: ProgressActor
        nonisolated let pauseToken: PauseToken

        /// 原子更新已处理进度（US-SYS-001 AC-4 事务写入）。
        public func report(processedIndex: Int, lastProcessedId: String?) async throws {
            try await progressActor.updateProgress(
                taskId: taskId,
                lastProcessedIndex: processedIndex,
                lastProcessedId: lastProcessedId
            )
        }

        /// Wait at a cooperative safe point while paused, retaining this exact in-memory job.
        public func checkPaused() async throws {
            while await pauseToken.isPaused {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(20))
            }
            try Task.checkCancellation()
        }

        /// 检查取消信号。
        public func checkCancelled() throws {
            if Task.isCancelled {
                throw CancellationError()
            }
        }
    }

    // MARK: - Public API

    /// 入队一个任务并立即持久化初始进度；若队列空闲则开始串行执行。
    ///
    /// - Throws: `TaskQueueError.taskAlreadyQueued` 若同 taskId 已在队列/运行中
    public func enqueue(
        _ job: QueuedJob,
        progressPolicy: ProgressPolicy = .createNew
    ) async throws {
        let reservation = try makeReservation(taskId: job.taskId, allowingPrepaused: true)
        try await enqueue(job, progressPolicy: progressPolicy, reservation: reservation)
    }

    /// Atomically reserves an exact task identity before any cross-actor preparation work.
    public func reserve(taskId: String) throws -> TaskReservation {
        try makeReservation(taskId: taskId, allowingPrepaused: false)
    }

    private func makeReservation(
        taskId: String,
        allowingPrepaused: Bool
    ) throws -> TaskReservation {
        guard !queue.contains(where: { $0.taskId == taskId }),
              activeJobId != taskId,
              (allowingPrepaused || !pausedJobIds.contains(taskId)),
              reservations[taskId] == nil else {
            throw TaskQueueError.taskAlreadyQueued(taskId: taskId)
        }
        let reservation = TaskReservation(taskId: taskId, token: UUID())
        reservations[taskId] = reservation.token
        return reservation
    }

    /// Releases a reservation that did not reach queue acceptance.
    public func release(_ reservation: TaskReservation) {
        guard reservations[reservation.taskId] == reservation.token else { return }
        reservations.removeValue(forKey: reservation.taskId)
    }

    /// Adopts a caller-held reservation and releases it after acceptance or failure.
    public func enqueue(
        _ job: QueuedJob,
        progressPolicy: ProgressPolicy,
        reservation: TaskReservation
    ) async throws {
        guard reservation.taskId == job.taskId,
              reservations[job.taskId] == reservation.token else {
            throw TaskQueueError.invalidReservation(taskId: job.taskId)
        }
        defer { reservations.removeValue(forKey: job.taskId) }
        guard !queue.contains(where: { $0.taskId == job.taskId }), activeJobId != job.taskId else {
            throw TaskQueueError.taskAlreadyQueued(taskId: job.taskId)
        }
        switch progressPolicy {
        case .createNew:
            let progress = TaskProgress(
                taskId: job.taskId,
                taskType: job.taskType,
                totalCount: job.totalCount,
                resumeData: job.resumeData
            )
            try await progressActor.save(progress: progress)
        case .preserveExisting:
            guard let existing = try await progressActor.load(taskId: job.taskId) else {
                throw TaskQueueError.missingCheckpoint(taskId: job.taskId)
            }
            guard existing.rawTaskType == job.taskType.rawValue,
                  existing.totalCount == job.totalCount else {
                throw TaskQueueError.checkpointMismatch(taskId: job.taskId)
            }
        }
        queue.append(job)
        if activeTask == nil {
            await startNext()
        }
    }

    /// 取消指定任务：运行中 → 终止底层 Task（进度保留）；排队中 → 立即移除并恢复等待方。
    ///
    /// 未启动的 0/N 任务取消时清理初始记录；已有恢复进度则保留 checkpoint。
    /// 两者都会 resume `enqueueAndWait` 等待方并立即移出 `pendingCount`。
    @discardableResult
    public func cancel(taskId: String) async -> Bool {
        if activeJobId == taskId {
            cancelledJobIds.insert(taskId)
            activeTask?.cancel()
            // Do not publish cancellation to callers until the cooperative body has unwound
            // and its final checkpoint write (if any) is complete.
            while activeJobId == taskId {
                await Task.yield()
            }
            return true
        } else if let index = queue.firstIndex(where: { $0.taskId == taskId }) {
            let job = queue.remove(at: index)
            cancelledJobIds.remove(job.taskId)
            pausedJobIds.remove(job.taskId)
            if let progress = try? await progressActor.load(taskId: job.taskId),
               progress.lastProcessedIndex == 0 {
                _ = try? await progressActor.delete(taskId: job.taskId)
            }
            if let completion = completions.removeValue(forKey: job.taskId) {
                completion.resume(throwing: TaskQueueError.cancelled(taskId: job.taskId))
            }
            return true
        }
        pausedJobIds.remove(taskId)
        return false
    }

    /// Cancels system-deferred work and removes its checkpoint after cooperative unwind.
    /// User cancellation must continue to use `cancel(taskId:)` so resumability is preserved.
    @discardableResult
    public func cancelAndDiscard(taskId: String) async -> Bool {
        let cancelled = await cancel(taskId: taskId)
        _ = try? await progressActor.delete(taskId: taskId)
        pausedJobIds.remove(taskId)
        return cancelled
    }

    /// 暂停指定任务：运行中 → 经 PauseToken 协作式挂起；排队中 → 标记暂停（不启动）。
    @discardableResult
    public func pause(taskId: String) async -> Bool {
        guard activeJobId == taskId || queue.contains(where: { $0.taskId == taskId }) else {
            return false
        }
        pausedJobIds.insert(taskId)
        if activeJobId == taskId {
            await activePauseToken?.setPaused(true)
        }
        return true
    }

    /// 恢复指定任务（解除暂停）。
    @discardableResult
    public func resume(taskId: String) async -> Bool {
        guard pausedJobIds.remove(taskId) != nil else { return false }
        if activeJobId == taskId {
            await activePauseToken?.setPaused(false)
        } else if activeTask == nil {
            await startNext()
        }
        return true
    }

    /// 当前是否有任务在运行。
    public var isRunning: Bool {
        get async { activeTask != nil }
    }

    /// 当前运行任务 ID（nil 表示空闲）。
    public func activeTaskID() async -> String? {
        activeJobId
    }

    /// 队列中待处理任务数（不含运行中）。
    public func pendingCount() async -> Int {
        queue.count
    }

    /// IDs owned by this process, including running, queued, and paused jobs.
    public func ownedTaskIDs() async -> Set<String> {
        var ids = activeTaskIDsValue()
        ids.formUnion(reservations.keys)
        return ids
    }

    /// IDs with an actual running, queued, or paused in-memory job; excludes preparation reservations.
    public func activeTaskIDs() async -> Set<String> {
        activeTaskIDsValue()
    }

    private func activeTaskIDsValue() -> Set<String> {
        var ids = Set(queue.map(\.taskId))
        if let activeJobId { ids.insert(activeJobId) }
        ids.formUnion(pausedJobIds)
        return ids
    }

    /// 是否暂停了指定任务。
    public func isPaused(taskId: String) async -> Bool {
        pausedJobIds.contains(taskId)
    }

    /// 入队并等待任务执行完毕（生产管线接入用）。
    ///
    /// 与 `enqueue` 相同的串行/进度语义，但阻塞直到任务完成或抛出其终止错误。
    /// - Throws: 任务体抛出的错误，或 `TaskQueueError`（取消/暂停）
    public func enqueueAndWait(_ job: QueuedJob) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard completions[job.taskId] == nil else {
                continuation.resume(throwing: TaskQueueError.taskAlreadyQueued(taskId: job.taskId))
                return
            }
            completions[job.taskId] = continuation
            Task {
                do {
                    try await self.enqueue(job)
                } catch {
                    // 入队本身失败（重复 ID 等）→ 立即恢复调用方
                    if let completion = completions.removeValue(forKey: job.taskId) {
                        completion.resume(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: - Internal Execution

    /// 串行执行：取队中第一个可运行任务执行，直到队列空。
    ///
    /// - 已取消任务：清理进度并 resume 其 `enqueueAndWait` 等待方（CR-1）
    /// - 已暂停任务：保留在队尾，跳过继续找下一个可运行任务，避免阻塞后续任务（CR-1）
    private func startNext() async {
        guard activeTask == nil else { return }
        var scanned = 0
        let originalCount = queue.count
        while scanned < originalCount, !queue.isEmpty {
            let job = queue.removeFirst()
            scanned += 1

            if cancelledJobIds.contains(job.taskId) {
                cancelledJobIds.remove(job.taskId)
                _ = try? await progressActor.delete(taskId: job.taskId)
                if let completion = completions.removeValue(forKey: job.taskId) {
                    completion.resume(throwing: TaskQueueError.cancelled(taskId: job.taskId))
                }
                continue
            }
            if pausedJobIds.contains(job.taskId) {
                queue.append(job)
                continue
            }

            activeJobId = job.taskId
            let token = PauseToken()
            activePauseToken = token
            activeTask = Task {
                let outcome = await Self.run(
                    job: job,
                    token: token,
                    progressActor: progressActor
                )
                await self.finish(job.taskId, outcome: outcome)
            }
            return
        }
    }

    /// 执行单个任务并依据结果处理进度（完成/失败清理；取消/暂停保留）。
    private static func run(
        job: QueuedJob,
        token: PauseToken,
        progressActor: ProgressActor
    ) async -> TaskQueueOutcome {
        let context = TaskContext(
            taskId: job.taskId,
            progressActor: progressActor,
            pauseToken: token
        )
        do {
            try await job.body(context)
            _ = try? await progressActor.delete(taskId: job.taskId)
            return .completed
        } catch is CancellationError {
            return .cancelled
        } catch TaskQueueError.paused {
            return .paused
        } catch {
            _ = try? await progressActor.delete(taskId: job.taskId)
            return .failed(error)
        }
    }

    /// 任务执行结果分类（供收尾决定 continuation 恢复语义）。
    private enum TaskQueueOutcome {
        case completed
        case cancelled
        case paused
        case failed(Error)
    }

    private func finish(_ taskId: String, outcome: TaskQueueOutcome) async {
        activeJobId = nil
        activeTask = nil
        activePauseToken = nil
        pausedJobIds.remove(taskId)
        cancelledJobIds.remove(taskId)
        if let completion = completions.removeValue(forKey: taskId) {
            switch outcome {
            case .completed:
                completion.resume()
            case .cancelled:
                completion.resume(throwing: TaskQueueError.cancelled(taskId: taskId))
            case .paused:
                completion.resume(throwing: TaskQueueError.paused(taskId: taskId))
            case .failed(let error):
                completion.resume(throwing: error)
            }
        }
        await startNext()
    }
}

// MARK: - Pause Token

/// 协作式暂停信号（actor，跨任务边界传递）。
public actor PauseToken {
    public private(set) var isPaused = false
    public func setPaused(_ paused: Bool) {
        isPaused = paused
    }
}

// MARK: - Task Queue Error

/// TaskQueueActor 统一错误类型
public enum TaskQueueError: Error, LocalizedError, Sendable {
    /// 任务已存在（重复入队被拒绝）
    case taskAlreadyQueued(taskId: String)
    /// 任务被暂停（协作式挂起信号）
    case paused(taskId: String)
    /// 任务被取消
    case cancelled(taskId: String)
    case missingCheckpoint(taskId: String)
    case checkpointMismatch(taskId: String)
    case invalidReservation(taskId: String)

    public var errorDescription: String? {
        switch self {
        case .taskAlreadyQueued(let id):
            return "Task already queued: \(id)"
        case .paused(let id):
            return "Task paused: \(id)"
        case .cancelled(let id):
            return "Task cancelled: \(id)"
        case .missingCheckpoint(let id):
            return "Saved checkpoint missing: \(id)"
        case .checkpointMismatch(let id):
            return "Saved checkpoint does not match task: \(id)"
        case .invalidReservation(let id):
            return "Task reservation is no longer valid: \(id)"
        }
    }
}
