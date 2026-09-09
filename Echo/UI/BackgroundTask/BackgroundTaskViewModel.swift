// ==========================================
// 文件: BackgroundTaskViewModel.swift
// i18n: Strings resolved via Localizable.xcstrings (zh-Hans + en-US) — migrated by 3F.10.
// 对应规格: docs/01-spec/用户故事与验收标准规格书.md → US-SYS-001 (实时后台任务状态面板),
//            docs/ui/echo-memory-canvas-style.md §13 (后台任务面板 — Task surface family),
//            docs/ui/architecture.md §6 (ViewModel 契约), §7 (适配器契约)
// 任务: 3.5 - 实时后台任务面板
//       3F.10 - production audit wiring (US-SYS-001 AC-7: .backgroundTaskUIAccessed /
//               .backgroundTaskInterrupted with action=pause/cancel + resumePoint) + localization
// AC 覆盖: US-SYS-001 AC-1 ✅ (活跃任务列表展示), AC-2 ✅ (进度百分比/计数),
//          AC-3 ✅ (pause/cancel forwarded to TaskQueueActor), AC-4 ✅ (SQLite TaskProgress read),
//          AC-5 ✅ (auto-hide when inactive), AC-6 ✅ (Core serial queue),
//          AC-7 ✅ (.backgroundTaskUIAccessed / .backgroundTaskInterrupted 审计)
// 架构约束: AGENTS.md §8.1 (@MainActor + @Observable + state enum), §8.2 (状态流转),
//           §4.2 (仅持有不可变引用), §5.4 (hash-only 审计),
//           docs/ui/architecture.md §6~7 (适配器契约), §2.5 (Adapter 不保存第二份领域真相)
// 生成时间: 2026-08-02, 2026-08-12 (3F.10 audit + i18n)
// ==========================================

import SwiftUI
import Foundation

// MARK: - Task Status

enum BackgroundTaskStatus: Equatable, Sendable {
    case running
    case paused
    case cancelled
}

// MARK: - Background Task UI Model

struct BackgroundTaskModel: Identifiable, Sendable, Equatable {
    let taskId: String
    let taskType: TaskType
    let processedCount: Int
    let totalCount: Int
    var status: BackgroundTaskStatus

    var id: String { taskId }

    init(from progress: TaskProgress) {
        self.taskId = progress.taskId
        self.taskType = progress.taskType
        self.processedCount = progress.lastProcessedIndex
        self.totalCount = progress.totalCount
        self.status = .running
    }

    var displayName: String {
        switch taskType {
        case .dataSourceSync: return "Syncing photos"
        case .fullIndex:      return "Building vector index"
        case .modelLoad:      return "Loading AI model"
        case .narrativeReport: return "Creating narrative report"
        case .photoUnderstanding: return "Preparing photo material"
        case .unknown:        return "Unsupported saved task"
        }
    }

    @MainActor
    var localizedDisplayName: String {
        EchoStrings.tr(displayName)
    }

    var systemImage: String {
        switch taskType {
        case .dataSourceSync: return "arrow.triangle.2.circlepath"
        case .fullIndex:      return "cube.box.fill"
        case .modelLoad:      return "cpu"
        case .narrativeReport: return "book.pages"
        case .photoUnderstanding: return "photo.badge.checkmark"
        case .unknown:        return "exclamationmark.triangle"
        }
    }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return min(Double(processedCount) / Double(totalCount), 1)
    }

    var progressPercentText: String {
        "\(Int(progress * 100))%"
    }

    var progressCountText: String {
        "\(processedCount)/\(totalCount)"
    }

    var statusLabel: String {
        switch status {
        case .running:  return "Running"
        case .paused:   return "Paused"
        case .cancelled: return "Cancelled"
        }
    }

    @MainActor
    var localizedStatusLabel: String {
        EchoStrings.tr(statusLabel)
    }

    @MainActor
    var accessibilityLabel: String {
        let template = EchoStrings.tr("%lld of %lld processed, %@")
        return String(format: template, processedCount, totalCount, "\(localizedDisplayName), \(localizedStatusLabel)")
    }
}

// MARK: - BackgroundTaskViewModel

@MainActor
@Observable
final class BackgroundTaskViewModel {
    enum ViewState: Equatable, Sendable {
        case idle
        case loading
        case completed
        case error(ErrorLevel)
        case cancelled
    }

    enum ErrorLevel: Equatable, Sendable {
        case l2Recoverable(message: String)
        case l3Blocking(message: String)
    }

    // MARK: - Published State

    private(set) var viewState: ViewState = .idle
    private(set) var tasks: [BackgroundTaskModel] = []
    private(set) var isPanelPresented: Bool = false
    private(set) var pendingCancelTaskId: String?

    // MARK: - Dependencies

    private let progressActor: ProgressActor?
    private let auditWriter: PrivacyActor?
    private let taskQueue: TaskQueueActor?
    /// 实时轮询间隔（测试注入小值；3F.11 fix：面板读取真实 TaskProgress）
    private let pollIntervalNanoseconds: UInt64

    private var loadTask: Task<Void, Never>?
    private var stubTasks: [TaskProgress] = []
    private var isFixtureBacked = false
    private var simulateError = false

    init(progressActor: ProgressActor? = nil,
         auditWriter: PrivacyActor? = nil,
         taskQueue: TaskQueueActor? = nil,
         pollIntervalNanoseconds: UInt64 = 1_000_000_000) {
        self.progressActor = progressActor
        self.auditWriter = auditWriter
        self.taskQueue = taskQueue
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    deinit {}

    // MARK: - Computed Properties

    var hasActiveTasks: Bool {
        tasks.contains { $0.status == .running }
    }

    // MARK: - Actions

    func openPanel() {
        isPanelPresented = true
        writeAudit(event: .backgroundTaskUIAccessed, action: "open", resumePoint: nil)
        loadTasks()
    }

    func closePanel() {
        loadTask?.cancel()
        loadTask = nil
        isPanelPresented = false
        pendingCancelTaskId = nil
        tasks = []
        viewState = .idle
    }

    func loadTasks() {
        guard viewState != .loading else { return }
        loadTask?.cancel()
        viewState = .loading

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                if self.simulateError {
                    throw BackgroundTaskError.loadFailed
                }

                if self.isFixtureBacked {
                    self.tasks = self.stubTasks.map(BackgroundTaskModel.init)
                    self.viewState = .completed
                    return
                }

                if let progressActor = self.progressActor {
                    // 3F.11 fix: 真实 TaskProgress 实时轮询（US-SYS-001 AC-2）——面板打开期间
                    // 持续读取 SQLite TaskProgress；任务完成即消失（§4.5 完成即清理）。
                    while !Task.isCancelled {
                        let rows = try await progressActor.loadAll()
                        guard !Task.isCancelled else { return }
                        let activeTaskIDs = if let taskQueue = self.taskQueue {
                            await taskQueue.activeTaskIDs()
                        } else {
                            Set(rows.map(\.taskId))
                        }
                        var mappedTasks: [BackgroundTaskModel] = []
                        mappedTasks.reserveCapacity(rows.count)
                        for row in rows where activeTaskIDs.contains(row.taskId) {
                            var task = BackgroundTaskModel(from: row)
                            if let taskQueue = self.taskQueue,
                               await taskQueue.isPaused(taskId: row.taskId) {
                                task.status = .paused
                            }
                            mappedTasks.append(task)
                        }
                        self.tasks = mappedTasks
                        self.viewState = .completed
                        try await Task.sleep(nanoseconds: self.pollIntervalNanoseconds)
                    }
                    return
                }

                try await Task.sleep(nanoseconds: 300_000_000)

                guard !Task.isCancelled else {
                    self.viewState = .cancelled
                    return
                }

                self.tasks = self.stubTasks.map(BackgroundTaskModel.init)
                self.viewState = .completed
            } catch is CancellationError {
                self.viewState = .cancelled
            } catch {
                guard !Task.isCancelled else {
                    self.viewState = .cancelled
                    return
                }
                self.viewState = .error(.l2Recoverable(
                    message: "Unable to load background tasks. Please try again."
                ))
            }
        }
    }

    func retry() {
        loadTasks()
    }

    func pauseTask(_ taskId: String) {
        guard let idx = tasks.firstIndex(where: { $0.taskId == taskId }) else { return }
        if let taskQueue {
            Task { [weak self] in
                let paused = await taskQueue.pause(taskId: taskId)
                guard let self else { return }
                guard paused,
                      let currentIndex = self.tasks.firstIndex(where: { $0.taskId == taskId }),
                      await taskQueue.isPaused(taskId: taskId) else {
                    self.viewState = .error(.l2Recoverable(
                        message: "Unable to pause this task because it is no longer active."
                    ))
                    return
                }
                self.tasks[currentIndex].status = .paused
                self.writeAudit(
                    event: .backgroundTaskInterrupted,
                    action: "pause",
                    resumePoint: self.tasks[currentIndex].processedCount,
                    outcome: "paused"
                )
            }
            return
        }
        tasks[idx].status = .paused
        writeAudit(
            event: .backgroundTaskInterrupted,
            action: "pause",
            resumePoint: tasks[idx].processedCount,
            outcome: "paused"
        )
    }

    func resumeTask(_ taskId: String) {
        guard let idx = tasks.firstIndex(where: { $0.taskId == taskId }) else { return }
        guard tasks[idx].status == .paused else { return }
        if let taskQueue {
            Task { [weak self] in
                let resumed = await taskQueue.resume(taskId: taskId)
                guard let self else { return }
                guard resumed,
                      let currentIndex = self.tasks.firstIndex(where: { $0.taskId == taskId }) else {
                    self.viewState = .error(.l2Recoverable(
                        message: "Unable to resume this task because it is no longer active."
                    ))
                    return
                }
                self.tasks[currentIndex].status = .running
            }
            return
        }
        tasks[idx].status = .running
    }

    func requestCancelTask(_ taskId: String) {
        pendingCancelTaskId = taskId
    }

    func confirmCancelTask(_ taskId: String) {
        guard let idx = tasks.firstIndex(where: { $0.taskId == taskId }) else {
            pendingCancelTaskId = nil
            return
        }
        let resumePoint = tasks[idx].processedCount
        if let taskQueue {
            pendingCancelTaskId = nil
            Task { [weak self] in
                let cancelled = await taskQueue.cancel(taskId: taskId)
                guard let self else { return }
                guard cancelled else {
                    self.viewState = .error(.l2Recoverable(
                        message: "Unable to cancel this task because it is no longer active."
                    ))
                    return
                }
                var finalResumePoint = resumePoint
                if let progressActor = self.progressActor,
                   let finalProgress = try? await progressActor.load(taskId: taskId) {
                    finalResumePoint = finalProgress.lastProcessedIndex
                }
                if let currentIndex = self.tasks.firstIndex(where: { $0.taskId == taskId }) {
                    self.tasks[currentIndex].status = .cancelled
                    self.tasks.remove(at: currentIndex)
                }
                self.writeAudit(
                    event: .backgroundTaskInterrupted,
                    action: "cancel",
                    resumePoint: finalResumePoint,
                    outcome: "cancelled"
                )
            }
            return
        }
        tasks[idx].status = .cancelled
        tasks.remove(at: idx)
        pendingCancelTaskId = nil
        writeAudit(
            event: .backgroundTaskInterrupted,
            action: "cancel",
            resumePoint: resumePoint,
            outcome: "cancelled"
        )
    }

    func dismissCancelConfirmation() {
        pendingCancelTaskId = nil
    }

    // MARK: - Audit (US-SYS-001 AC-7)

    private func writeAudit(
        event: AuditEvent,
        action: String,
        resumePoint: Int?,
        outcome: String? = nil
    ) {
        guard let auditWriter else { return }
        Task {
            let policy = await auditWriter.getPolicy()
            try? await auditWriter.writeAuditLog(
                eventType: event,
                traceID: UUID().uuidString,
                policyVersion: policy.policyVersion,
                success: true,
                sourceType: "action=\(action)",
                action: action,
                resumePoint: resumePoint,
                outcome: outcome
            )
        }
    }

    // MARK: - Fixture Injection

    func loadPreloadedTasks(_ items: [TaskProgress]) {
        isFixtureBacked = true
        stubTasks = items
        tasks = items.map(BackgroundTaskModel.init)
        viewState = .completed
    }

    func simulateLoadError(_ message: String = "Unable to load background tasks") {
        simulateError = true
        viewState = .error(.l2Recoverable(message: message))
    }
}

// MARK: - Errors

enum BackgroundTaskError: Error {
    case loadFailed

    var userFacingMessageKey: String {
        "Unable to load background tasks"
    }
}
