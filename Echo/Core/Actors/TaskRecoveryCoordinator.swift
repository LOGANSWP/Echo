// ==========================================
// File: TaskRecoveryCoordinator.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md → US-SYS-001 AC-3/AC-4/AC-7
// Task: 4.0g - Production task resume loop
// AC Coverage: typed reconstruction, reserved exact taskId, authorization recheck,
//              idempotent Continue/Restart, fail-closed unsupported types,
//              L2 persistence, structured audit with outcome
// Architecture: AGENTS.md §4.2, §4.3, §4.5, §7.3
// Generated: 2026-09-04
// Task 4.0k (2026-09-08): generation L3/denial and explicit Restart error propagation.
// Traceability: US-SYN-001/004 and ADR-023; device/quality qualification remains pending.
// ==========================================

import Foundation

/// Core-only allow-list that turns a validated value descriptor into a queued job.
/// UI code can request recovery but cannot install arbitrary launchers.
public actor TaskRecoveryRegistry {
    typealias Launcher = @Sendable (TaskRecoveryRequest) async throws -> TaskQueueActor.QueuedJob

    private var launchers: [TaskType: Launcher] = [:]

    func register(taskType: TaskType, launcher: @escaping Launcher) {
        guard taskType != .unknown else { return }
        launchers[taskType] = launcher
    }

    func makeJob(for request: TaskRecoveryRequest) async throws -> TaskQueueActor.QueuedJob {
        guard request.progress.taskType != .unknown,
              let launcher = launchers[request.progress.taskType] else {
            throw TaskRecoveryError.unsupportedTaskType(request.progress.rawTaskType)
        }
        return try await launcher(request)
    }

    func supports(taskType: TaskType) -> Bool {
        taskType != .unknown && launchers[taskType] != nil
    }
}

/// Owns cross-process recovery attempts and serializes each exact task identity.
public actor TaskRecoveryCoordinator {
    private let progressActor: ProgressActor
    private let taskQueue: TaskQueueActor
    private let registry: TaskRecoveryRegistry
    private let privacyActor: PrivacyActor
    private let pendingOpsActor: PendingOpsActor?
    private let auditWriter: PrivacyActor?
    private var recoveringTaskIDs: Set<String> = []

    public init(
        progressActor: ProgressActor = .shared,
        taskQueue: TaskQueueActor = .shared,
        registry: TaskRecoveryRegistry,
        privacyActor: PrivacyActor = .shared,
        pendingOpsActor: PendingOpsActor? = .shared,
        auditWriter: PrivacyActor? = .shared
    ) {
        self.progressActor = progressActor
        self.taskQueue = taskQueue
        self.registry = registry
        self.privacyActor = privacyActor
        self.pendingOpsActor = pendingOpsActor
        self.auditWriter = auditWriter
    }

    /// Returns every orphaned/interrupted row and excludes jobs owned by this process.
    public func pendingRecords(taskType: TaskType? = nil) async throws -> [TaskProgress] {
        let owned = await taskQueue.ownedTaskIDs()
        return try await progressActor.loadAll()
            .filter { !owned.contains($0.taskId) }
            .filter { taskType == nil || $0.taskType == taskType }
            .sorted {
                if $0.updatedAt == $1.updatedAt { return $0.taskId < $1.taskId }
                return $0.updatedAt < $1.updatedAt
            }
    }

    public func continueTask(_ snapshot: TaskProgress) async throws -> TaskRecoveryOutcome {
        try beginRecovery(taskId: snapshot.taskId)
        defer { recoveringTaskIDs.remove(snapshot.taskId) }
        do {
            let current = try await currentProgress(matching: snapshot)
            let reservation = try await reserve(taskId: current.taskId)
            do {
                let request = try makeRequest(progress: current, choice: .continue)
                try await validatePrivacy(request.descriptor)
                let job = try await registry.makeJob(for: request)
                try validate(job: job, progress: current)
                try await taskQueue.enqueue(
                    job,
                    progressPolicy: .preserveExisting,
                    reservation: reservation
                )
            } catch {
                await taskQueue.release(reservation)
                throw error
            }
            await recordAudit(progress: current, choice: "continue", outcome: "resumed", success: true)
            return .resumed
        } catch {
            try await propagateBlockingFailure(error, progress: snapshot, choice: "continue")
            let mapped = Self.map(error)
            await recordFailure(snapshot, choice: "continue", error: mapped)
            throw mapped
        }
    }

    public func restartTask(_ snapshot: TaskProgress) async throws -> TaskRecoveryOutcome {
        try beginRecovery(taskId: snapshot.taskId)
        defer { recoveringTaskIDs.remove(snapshot.taskId) }
        do {
            let current = try await currentProgress(matching: snapshot)
            let reservation = try await reserve(taskId: current.taskId)
            let reset: TaskProgress
            do {
                let request = try makeRequest(progress: current, choice: .restart)
                try await validatePrivacy(request.descriptor)
                let job = try await registry.makeJob(for: request)
                try validate(job: job, progress: current, allowsNewDescriptor: true)
                if let data = job.resumeData {
                    try await validatePrivacy(TaskResumeDescriptor.decode(data))
                }
                reset = try await progressActor.resetForRestart(current, resumeData: job.resumeData, totalCount: job.totalCount)
                try await taskQueue.enqueue(
                    job,
                    progressPolicy: .preserveExisting,
                    reservation: reservation
                )
            } catch {
                await taskQueue.release(reservation)
                throw error
            }
            await recordAudit(progress: reset, choice: "restart", outcome: "restarted", success: true)
            return .restarted
        } catch {
            try await propagateBlockingFailure(error, progress: snapshot, choice: "restart")
            let mapped = Self.map(error)
            await recordFailure(snapshot, choice: "restart", error: mapped)
            throw mapped
        }
    }

    private func beginRecovery(taskId: String) throws {
        guard recoveringTaskIDs.insert(taskId).inserted else {
            throw TaskRecoveryError.recoveryAlreadyInProgress
        }
    }

    /// Preserve typed recovery actions; only identity changes create a manual L2 record.
    private func propagateBlockingFailure(_ error: Error, progress: TaskProgress, choice: String) async throws {
        guard let runtimeError = error as? GenerationRuntimeError,
              runtimeError.severity == .l3Blocking || runtimeError == .privacyDenied || runtimeError == .restartRequired else {
            return
        }
        if runtimeError == .restartRequired {
            await recordFailure(progress, choice: choice, error: runtimeError)
            throw runtimeError
        }
        await recordAudit(progress: progress, choice: choice, outcome: String(describing: runtimeError), success: false)
        throw runtimeError
    }

    private func currentProgress(matching snapshot: TaskProgress) async throws -> TaskProgress {
        guard let current = try await progressActor.load(taskId: snapshot.taskId) else {
            throw TaskRecoveryError.progressMissing
        }
        guard abs(current.updatedAt.timeIntervalSince1970 - snapshot.updatedAt.timeIntervalSince1970) < 0.001,
              current.rawTaskType == snapshot.rawTaskType,
              current.lastProcessedIndex == snapshot.lastProcessedIndex,
              current.totalCount == snapshot.totalCount else {
            throw TaskRecoveryError.staleProgress
        }
        return current
    }

    /// Reports whether a persisted row has a registered production reconstruction path.
    public func supportsRecovery(for progress: TaskProgress) async -> Bool {
        await registry.supports(taskType: progress.taskType)
    }

    private func reserve(taskId: String) async throws -> TaskQueueActor.TaskReservation {
        do {
            return try await taskQueue.reserve(taskId: taskId)
        } catch TaskQueueError.taskAlreadyQueued {
            throw TaskRecoveryError.taskOwnedByCurrentSession
        } catch {
            throw TaskRecoveryError.enqueueFailed
        }
    }

    private func makeRequest(
        progress: TaskProgress,
        choice: TaskRecoveryChoice
    ) throws -> TaskRecoveryRequest {
        guard let data = progress.resumeData else {
            throw TaskRecoveryError.descriptorUnavailable
        }
        do {
            return TaskRecoveryRequest(
                progress: progress,
                descriptor: try TaskResumeDescriptor.decode(data),
                choice: choice
            )
        } catch {
            throw TaskRecoveryError.descriptorInvalid
        }
    }

    private func validatePrivacy(_ descriptor: TaskResumeDescriptor) async throws {
        let checkpoint = await privacyActor.validate(
            operation: descriptor.operation,
            traceID: UUID().uuidString,
            sourceTypes: descriptor.sourceTypes
        )
        guard checkpoint.isAllowed else { throw TaskRecoveryError.privacyDenied }
    }

    private func validate(job: TaskQueueActor.QueuedJob, progress: TaskProgress, allowsNewDescriptor: Bool = false) throws {
        guard job.taskId == progress.taskId,
              job.taskType.rawValue == progress.rawTaskType,
              allowsNewDescriptor || job.totalCount == progress.totalCount,
              allowsNewDescriptor || job.resumeData == progress.resumeData else {
            throw TaskRecoveryError.launcherMismatch
        }
    }

    private func recordFailure(
        _ progress: TaskProgress,
        choice: String,
        error: any Error
    ) async {
        if let pendingOpsActor {
            let digest = AuditContentHasher.sha256Hex(progress.taskId)
            let parameters = Data("taskDigest=\(digest)|choice=\(choice)".utf8)
            try? await pendingOpsActor.add(operation: PendingOperation(
                operationId: "task-recovery-\(digest)-\(choice)",
                operationType: "taskRecovery",
                parameters: parameters,
                lastError: String(describing: error)
            ))
        }
        await recordAudit(
            progress: progress,
            choice: choice,
            outcome: String(describing: error),
            success: false
        )
    }

    private func recordAudit(
        progress: TaskProgress,
        choice: String,
        outcome: String,
        success: Bool
    ) async {
        guard let auditWriter else { return }
        let policy = await auditWriter.getPolicy()
        try? await auditWriter.writeAuditLog(
            eventType: .backgroundTaskInterrupted,
            traceID: UUID().uuidString,
            policyVersion: policy.policyVersion,
            success: success,
            sourceType: progress.rawTaskType,
            action: "recover",
            resumePoint: progress.lastProcessedIndex,
            userChoiceOnRestart: choice,
            outcome: outcome
        )
    }

    nonisolated private static func map(_ error: Error) -> TaskRecoveryError {
        if let recoveryError = error as? TaskRecoveryError { return recoveryError }
        if error is TaskResumeDescriptorError { return .descriptorInvalid }
        return .enqueueFailed
    }
}
