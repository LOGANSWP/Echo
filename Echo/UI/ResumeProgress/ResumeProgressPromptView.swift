// ==========================================
// 文件: ResumeProgressPromptView.swift
// i18n: User-facing strings resolve through Localizable.xcstrings (zh-Hans + en-US).
// 对应规格: docs/01-spec/用户故事与验收标准规格书.md → US-SYS-001 AC-3 (取消后询问继续/重新开始),
//            AC-4 (断点续传 — 继续保留进度 / 重新开始清除进度),
//            docs/02-architecture/架构设计文档.md §6.2 (恢复流程),
//            docs/ui/echo-memory-canvas-style.md §3.3 (Task surface — Alert/confirmationDialog),
//            §11.2 (L1 Toast) / §12.1 (L3 全屏) / §10.1.3 (Task 空态)
//            docs/ui/architecture.md §3 (Surface View), §8 (Task surface family)
// 任务: 4.0c - Task 平衡画布; 4.0g - 生产任务恢复闭环
// AC coverage: real checkpoint detection, X/Y presentation, and production recovery delegation.
//          (2026-08-02 PR review W-1: error 态改真实布局槽位, 不再依赖零高 frame 溢出; W-3: 弹窗文案统一英文)
// 架构约束: AGENTS.md §8.1 (ViewModel 驱动), §17.7 (Task surface 禁止 masonry),
//           echo-memory-canvas apple-native 基础; 系统 confirmationDialog 容器
// 生成时间: 2026-09-02
// ==========================================

import SwiftUI

// MARK: - ResumeProgressPromptView

/// 断点续传恢复提示 — 当长任务重启且存在未完成进度时，展示继续/重新开始确认弹窗。
///
/// ## Surface Family: Task
/// - 布局: 系统 confirmationDialog（echo-memory-canvas §3.3, §7.2）
/// - Masonry: 绝对禁止 (Task surface, §3.3)
/// - 系统容器: confirmationDialog + 可选内联 L2 错误状态
///
/// ## 状态驱动
/// - checking: 无弹窗（检查中，短暂过渡）
/// - prompt: 系统 confirmationDialog，展示 "X / Y completed" + Continue/Restart
/// - none: 无弹窗（无未完成进度，任务直接从 0 开始）
/// - resumed / restarted: 弹窗关闭（决策已记录）
/// - error: 内联 L2 错误 + 重试按钮（真实布局槽位，见 HomeView）
///
/// ## 用法
/// 嵌入任务启动宿主视图（如 HomeView / BackgroundTaskPanelView 等）。宿主调用
/// `viewModel.checkForPendingProgress(taskType:)` 触发检查；当 `isPromptPresented`
/// 变为 true 时本视图自动展示 confirmationDialog。
struct ResumeProgressPromptView: View {
    // MARK: - ViewModel

    @State private var viewModel: ResumeProgressViewModel
    @Environment(\.echoDesignProfile) private var designProfile

    init(viewModel: ResumeProgressViewModel = ResumeProgressViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    // MARK: - Body

    var body: some View {
        content
            .background(EchoColorToken.groupedBackground.color.opacity(0.001))
            .environment(\.echoDesignProfile, designProfile)
            .confirmationDialog(
                dialogTitle,
                isPresented: Binding(
                    get: { viewModel.isPromptPresented },
                    set: { if !$0 { viewModel.dismissPrompt() } }
                ),
                titleVisibility: .visible
            ) {
                Button("Continue") {
                    viewModel.continueTask()
                }
                .accessibilityIdentifier("resume-prompt-continue")

                Button("Restart", role: .destructive) {
                    viewModel.restartTask()
                }
                .accessibilityIdentifier("resume-prompt-restart")
            } message: {
                Text(dialogMessage)
            }
            .accessibilityIdentifier("resume-progress-prompt")
    }

    // MARK: - Content

    /// 非 error 态渲染空占位 host（零布局占用，仅作 confirmationDialog 挂载锚点），
    /// error 态渲染内联 L2 横幅（真实布局槽位, 2026-08-02 W-1）。
    /// 空 host 为 Color.clear（无内容无溢出），横幅不再依赖零高 frame 的非裁剪溢出。
    @ViewBuilder
    private var content: some View {
        if case .error(let level) = viewModel.viewState {
            errorState(level)
        } else if case .recovering = viewModel.viewState {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(EchoStrings.tr("Recovering interrupted task"))
        } else {
            Color.clear
                .frame(height: 0)
        }
    }

    // MARK: - Error State (L2)

    /// 内联 L2 错误 — 进度检查失败（echo-memory-canvas §11.2 L1 Toast 语义,
    /// 此处为可交互重试的轻量提示）。
    private func errorState(_ level: ResumeProgressViewModel.ErrorLevel) -> some View {
        EchoContainer(level: .card) {
            VStack(alignment: .leading, spacing: EchoSpacingToken.normal.points) {
                EchoStatusPresentation(
                    role: .warning,
                    systemImage: "exclamationmark.triangle.fill",
                    title: EchoStrings.tr("Unable to check saved progress"),
                    message: EchoStrings.tr(errorMessage(for: level))
                )
                if case .l3Blocking = level {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                            .buttonStyle(EchoActionButtonStyle(role: .recovery))
                    }
                } else if case .restartRequired = level {
                    Button(EchoStrings.tr("Restart")) { viewModel.restartAfterIdentityChange() }
                        .buttonStyle(EchoActionButtonStyle(role: .recovery))
                } else {
                    Button(action: { viewModel.retry() }) {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(EchoActionButtonStyle(role: .recovery))
                    .accessibilityIdentifier("resume-prompt-retry")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unable to check saved progress")
    }

    private func errorMessage(for level: ResumeProgressViewModel.ErrorLevel) -> String {
        switch level {
        case .l2Recoverable(let msg), .l3Blocking(let msg):
            return msg

        case .restartRequired:
            return "Generation inputs or settings changed. Restart is required."
        }
    }

    // MARK: - Dialog Text (US-SYS-001 AC-3/AC-4)

    /// 恢复提示标题。
    private var dialogTitle: String {
        EchoStrings.tr("Resume interrupted task")
    }

    /// 恢复提示正文 — 展示已完成进度 X / Y（3F.10: localized format, DEF-42-002）。
    private var dialogMessage: String {
        guard case .prompt(let progress) = viewModel.viewState else {
            return ""
        }
        let template = EchoStrings.tr("An interrupted task was found with %lld of %lld items completed. Continue where you left off?")
        return String(format: template, progress.lastProcessedIndex, progress.totalCount)
    }
}

// MARK: - Preview

#Preview("Prompt") {
    let vm = ResumeProgressViewModel()
    vm.loadFixture("resume-progress-pending")
    vm.checkForPendingProgress(taskType: .fullIndex)
    return ResumeProgressPromptView(viewModel: vm)
        .padding()
}

#Preview("None") {
    let vm = ResumeProgressViewModel()
    vm.loadFixture("resume-progress-none")
    vm.checkForPendingProgress(taskType: .dataSourceSync)
    return ResumeProgressPromptView(viewModel: vm)
        .padding()
}

#Preview("Error") {
    let vm = ResumeProgressViewModel()
    vm.simulateCheckError()
    return ResumeProgressPromptView(viewModel: vm)
        .padding()
}
