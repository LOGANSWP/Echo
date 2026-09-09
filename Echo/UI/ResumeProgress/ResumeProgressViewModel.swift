// ==========================================
// 文件: ResumeProgressViewModel.swift
// i18n: All user-facing strings are hardcoded English. Full String Catalog migration (zh-Hans + en-US) deferred to Phase 3.8.
// 对应规格: docs/01-spec/用户故事与验收标准规格书.md → US-SYS-001 AC-3 (取消后询问), AC-4 (断点续传),
//            docs/02-architecture/架构设计文档.md §6.2 (恢复流程 — 检测未完成进度 → 弹窗询问继续/重新开始),
//            docs/ui/echo-memory-canvas-style.md §3.3 (Task surface — Alert/confirmationDialog),
//            docs/ui/architecture.md §6 (ViewModel 契约), §7 (适配器契约)
// 任务: 3.7 - 断点续传集成到长任务; 4.0g - 生产任务恢复闭环
// AC coverage: all orphaned checkpoints remain visible; unsupported rows do not block later
// recoverable work; production Continue/Restart publishes success only after queue ownership.
//          (2026-08-02 PR review W-2: checkDelayNanoseconds 注入; W-3: 文案统一英文; W-4: progressActor 未接线占位 DEF-42-001)
// 架构约束: AGENTS.md §8.1 (@MainActor + @Observable + state enum), §8.2 (状态流转),
//           docs/ui/architecture.md §6~7 (适配器契约), §2.5 (Adapter 不保存第二份领域真相 — 仅转换展示字段)
// 生成时间: 2026-08-02
// ==========================================

import SwiftUI
import Foundation

// MARK: - ResumeProgressViewModel

/// 断点续传恢复提示 ViewModel — 当长任务重启且存在未完成进度时，提示用户继续或重新开始。
///
/// ## Surface Family: Task
/// - 布局: Alert / confirmationDialog（echo-memory-canvas §3.3, §7.2）
/// - Masonry: 禁止 (Task surface)
///
/// ## 职责 (docs/ui/architecture.md §7.1)
/// - 线程隔离: ProgressActor (actor) → @MainActor 状态
/// - 状态映射: TaskProgress → 恢复提示展示状态
/// - 错误映射: L2 → error state
/// - Intent 转发: 继续/重新开始 → ProgressActor / TaskQueueActor (Phase 3.9)
/// - 生命周期: Task 管理
///
/// ## 状态流转 (AGENTS.md §8.2)
/// ```
/// idle → checking → prompt(TaskProgress) → recovering → resumed
///                → none
///                → error(L2) → checking (retry)
/// ```
@MainActor
@Observable
final class ResumeProgressViewModel {
    // MARK: - State Enum

    /// ViewModel 统一状态枚举 (AGENTS.md §8.1)
    enum ViewState: Equatable, Sendable {
        /// 初始状态 — 未检查
        case idle
        /// 检查未完成进度中
        case checking
        /// 存在未完成进度 → 展示恢复提示弹窗
        case prompt(TaskProgress)
        /// 恢复协调器正在重建并交付队列
        case recovering(TaskProgress)
        /// 无未完成进度 → 直接从头开始
        case none
        /// 用户选择"继续" → 从保存的进度恢复
        case resumed
        /// 用户选择"重新开始" → 清除进度后从头开始
        case restarted
        /// 错误状态 — L2 可恢复
        case error(ErrorLevel)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.checking, .checking), (.none, .none),
                (.resumed, .resumed), (.restarted, .restarted):
                return true

            case (.prompt(let l), .prompt(let r)):
                return l.taskId == r.taskId
                    && l.taskType == r.taskType
                    && l.lastProcessedIndex == r.lastProcessedIndex
                    && l.totalCount == r.totalCount

            case (.recovering(let l), .recovering(let r)):
                return l.taskId == r.taskId

            case (.error(let l), .error(let r)):
                return l == r

            default:
                return false
            }
        }
    }

    /// 错误等级 — 对应 AGENTS.md §4.4
    enum ErrorLevel: Equatable, Sendable {
        /// L2 可恢复: Toast + 重试按钮
        case l2Recoverable(message: String)
        case l3Blocking(message: String)
        case restartRequired
    }

    deinit {}

    // MARK: - Published State

    /// 统一视图状态
    private(set) var viewState: ViewState = .idle
    /// 恢复提示弹窗是否已展示
    private(set) var isPromptPresented: Bool = false
    /// 最后一次展示的恢复目标（用于断言继续/重新开始意图）
    private(set) var lastResumeTarget: TaskProgress?
    /// 当前检查找到的全部恢复候选，不会按 taskType 丢弃旧记录。
    private(set) var pendingProgressRecords: [TaskProgress] = []

    // MARK: - Dependencies (Immutable Actor References)

    /// ProgressActor 引用 — 不可变 actor 引用 (docs/ui/architecture.md §6.4)
    /// 可选注入: Phase 3.9 完整集成后通过 DI 容器注入
    /// (2026-08-02 W-4: 当前未接线占位, 追踪 DEF-42-001)
    private let progressActor: ProgressActor?
    private let recoveryCoordinator: TaskRecoveryCoordinator?

    /// 模拟检查延迟 — 测试可注入 0 以 await 真实异步转换 (2026-08-02 W-2)
    private let checkDelayNanoseconds: UInt64

    /// 当前活跃的检查 Task
    private var checkTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?

    /// 当前检查的任务类型（用于重试）
    private var currentTaskType: TaskType?

    /// UI 切片模式 fixture 注入源
    private var stubFixture: ResumeProgressFixture?
    /// Distinguishes explicit Preview/test state from progress loaded from SQLite.
    private var isFixtureBacked = false

    /// 模拟加载失败标记（fixture 驱动 error 态）
    private var simulateError = false

    // MARK: - Initialization

    /// 初始化 ResumeProgressViewModel。
    ///
    /// - Parameters:
    ///   - progressActor: ProgressActor 实例（可选注入）。
    ///     Phase 3.9 完整集成后通过 DI 容器注入。
    ///   - checkDelayNanoseconds: 模拟检查延迟。测试可注入 0 以同步等待异步转换。
    init(
        progressActor: ProgressActor? = nil,
        recoveryCoordinator: TaskRecoveryCoordinator? = nil,
        checkDelayNanoseconds: UInt64 = 200_000_000
    ) {
        self.progressActor = progressActor
        self.recoveryCoordinator = recoveryCoordinator
        self.checkDelayNanoseconds = checkDelayNanoseconds
    }

    // MARK: - Actions

    /// 检查指定任务类型是否存在未完成进度（US-SYS-001 AC-3: 取消后再次启动相同任务时询问）。
    ///
    /// - Parameter taskType: 即将启动的任务类型
    func checkForPendingProgress(taskType: TaskType? = nil) {
        // 防止重复检查
        guard viewState != .checking else { return }

        // 取消已有 Task
        checkTask?.cancel()

        currentTaskType = taskType

        // Set checking synchronously (AGENTS.md §8.1: first line of action)
        viewState = .checking
        isPromptPresented = false

        checkTask = Task { [weak self] in
            guard let self else { return }

            do {
                if self.simulateError || self.stubFixture?.loadError == true {
                    throw ResumeProgressError.checkFailed
                }

                if self.isFixtureBacked, let fixture = self.stubFixture {
                    if let progress = fixture.pendingProgress {
                        self.presentPrompt(progress, fixtureBacked: true)
                    } else {
                        self.viewState = .none
                    }
                    return
                }

                if let recoveryCoordinator = self.recoveryCoordinator {
                    let pending = try await recoveryCoordinator.pendingRecords(taskType: taskType)
                    guard !Task.isCancelled else {
                        self.viewState = .idle
                        return
                    }
                    self.pendingProgressRecords = pending
                    if pending.isEmpty {
                        self.viewState = .none
                    } else {
                        await self.presentFirstRecoverableCandidate()
                    }
                    return
                }

                if let progressActor = self.progressActor {
                    let pending = try await progressActor.loadAll()
                        .filter { taskType == nil || $0.taskType == taskType }
                        .sorted { $0.updatedAt < $1.updatedAt }
                    guard !Task.isCancelled else {
                        self.viewState = .idle
                        return
                    }
                    self.pendingProgressRecords = pending
                    if let first = pending.first {
                        self.presentPrompt(first, fixtureBacked: false)
                    } else {
                        self.viewState = .none
                    }
                    return
                }

                // Explicit fixtures retain a controllable delay for deterministic UI tests.
                try await Task.sleep(nanoseconds: checkDelayNanoseconds)

                guard !Task.isCancelled else {
                    self.viewState = .idle
                    return
                }

                self.viewState = .error(
                    .l2Recoverable(
                        message: "Saved progress storage is not available."
                    )
                )
            } catch is CancellationError {
                self.viewState = .idle
            } catch {
                guard !Task.isCancelled else {
                    self.viewState = .idle
                    return
                }
                self.viewState = .error(
                    .l2Recoverable(
                        message: "Unable to check saved progress. Please try again."
                    )
                )
            }
        }
    }

    /// 用户选择"继续" — 从保存的进度恢复（US-SYS-001 AC-3）。
    ///
    func continueTask() {
        guard case .prompt(let progress) = viewState else { return }
        isPromptPresented = false
        viewState = .recovering(progress)
        if isFixtureBacked {
            lastResumeTarget = progress
            viewState = .resumed
            return
        }
        guard let recoveryCoordinator else {
            viewState = .error(.l2Recoverable(message: "Task recovery is not available."))
            return
        }
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await recoveryCoordinator.continueTask(progress)
                guard !Task.isCancelled else { return }
                self.lastResumeTarget = progress
                self.pendingProgressRecords.removeAll { $0.taskId == progress.taskId }
                self.viewState = .resumed
                await self.presentNextPending(after: .resumed)
            } catch {
                guard !Task.isCancelled else { return }
                self.lastResumeTarget = progress
                self.viewState = .error(
                    Self.recoveryError(
                        error,
                        message: "Unable to continue this task. Review access and try again."
                    )
                )
            }
        }
    }

    /// 用户选择"重新开始" — 清除进度后从头开始（US-SYS-001 AC-4）。
    ///
    func restartTask() {
        guard case .prompt(let progress) = viewState else { return }
        isPromptPresented = false
        viewState = .recovering(progress)
        if isFixtureBacked {
            lastResumeTarget = progress
            viewState = .restarted
            return
        }
        guard let recoveryCoordinator else {
            viewState = .error(.l2Recoverable(message: "Task recovery is not available."))
            return
        }
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await recoveryCoordinator.restartTask(progress)
                guard !Task.isCancelled else { return }
                self.lastResumeTarget = progress
                self.pendingProgressRecords.removeAll { $0.taskId == progress.taskId }
                self.viewState = .restarted
                await self.presentNextPending(after: .restarted)
            } catch {
                guard !Task.isCancelled else { return }
                self.viewState = .error(
                    Self.recoveryError(
                        error,
                        message: "Unable to restart this task. Review access and try again."
                    )
                )
            }
        }
    }

    func restartAfterIdentityChange() {
        guard case .error(.restartRequired) = viewState, let target = lastResumeTarget else { return }
        viewState = .prompt(target)
        restartTask()
    }

    private static func recoveryError(_ error: Error, message: String) -> ErrorLevel {
        if error as? GenerationRuntimeError == .restartRequired { return .restartRequired }
        if ErrorClassifier.classify(error) == .l3Blocking {
            return .l3Blocking(message: ErrorSeverity.l3Blocking.userFacingMessageKey)
        }
        return .l2Recoverable(message: message)
    }

    /// 关闭恢复提示弹窗（不改变任务状态）。
    func dismissPrompt() {
        isPromptPresented = false
        if case .prompt = viewState {
            viewState = .idle
        }
    }

    /// 重试检查 (L2 恢复路径)。
    ///
    /// fixture 模式下错误为一次性瞬态（simulateCheckError 仅注入 error 展示态），
    /// 重试清除该标记使检查流程恢复正常。
    func retry() {
        simulateError = false
        checkForPendingProgress(taskType: currentTaskType)
    }

    /// 重置到初始状态。
    func reset() {
        checkTask?.cancel()
        recoveryTask?.cancel()
        checkTask = nil
        recoveryTask = nil
        viewState = .idle
        isPromptPresented = false
        currentTaskType = nil
        pendingProgressRecords = []
        stubFixture = nil
        isFixtureBacked = false
        simulateError = false
    }

    // MARK: - Presentation

    /// 展示恢复提示弹窗。
    ///
    /// 非 private：Preview / 单元测试通过 fixture 钩子注入已发现的进度以驱动 prompt 态
    /// （等价于检查完成路径，与 ``BackgroundTaskViewModel.loadPreloadedTasks`` 同模式）。
    func presentPrompt(_ progress: TaskProgress) {
        presentPrompt(progress, fixtureBacked: true)
    }

    private func presentPrompt(_ progress: TaskProgress, fixtureBacked: Bool) {
        isFixtureBacked = fixtureBacked
        viewState = .prompt(progress)
        isPromptPresented = true
    }

    /// Keeps each orphaned task individually actionable while allowing the prior terminal
    /// outcome to be observed before the next confirmation dialog is presented.
    private func presentNextPending(after terminalState: ViewState) async {
        guard !pendingProgressRecords.isEmpty else { return }
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return
        }
        guard viewState == terminalState else { return }
        await presentFirstRecoverableCandidate()
    }

    /// Selects the first supported orphan without allowing an older unsupported record
    /// to block later recoverable work. Unsupported rows remain in the diagnostic list.
    private func presentFirstRecoverableCandidate() async {
        guard let recoveryCoordinator else {
            isPromptPresented = false
            viewState = .error(.l2Recoverable(message: "Task recovery is not available."))
            return
        }
        for candidate in pendingProgressRecords {
            if await recoveryCoordinator.supportsRecovery(for: candidate) {
                presentPrompt(candidate, fixtureBacked: false)
                return
            }
        }
        isFixtureBacked = false
        isPromptPresented = false
        viewState = .error(
            .l2Recoverable(
                message: "This saved task type is not supported by this app version."
            )
        )
    }

    // MARK: - Fixture Injection

    /// 注入确定性 fixture（Preview / 测试 / XCUITest / Live Sim Review）。
    ///
    /// - Parameter fixtureID: resume-progress-pending | resume-progress-none | resume-progress-error
    func loadFixture(_ fixtureID: String) {
        stubFixture = ResumeProgressFixtureLoader.load(fixtureID)
        isFixtureBacked = true
        simulateError = false
    }

    /// 注入加载错误状态（Preview / 测试 fixture 驱动 error 态）。
    func simulateCheckError(_ message: String = "Unable to check saved progress") {
        simulateError = true
        viewState = .error(.l2Recoverable(message: message))
    }
}

// MARK: - Errors

/// 断点续传进度检查错误
enum ResumeProgressError: Error {
    /// 检查失败
    case checkFailed

    var localizedDescription: String {
        "Unable to check saved progress"
    }
}
