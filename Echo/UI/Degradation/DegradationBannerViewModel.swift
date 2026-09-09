// ==========================================
// 文件: DegradationBannerViewModel.swift
// 对应规格: docs/01-spec/用户故事与验收标准规格书.md → US-RES-002 (低电量模式降级),
//            US-RES-003 (设备过热降级), US-RES-004 (模型加载失败),
//            US-DIS-003 (错误/降级文案本地化), US-DIS-004 AC-2 (VoiceOver announcement),
//            docs/ui/echo-memory-canvas-style.md §11.4 (降级横幅), §7.2 (Task surface),
//            docs/ui/architecture.md §6 (ViewModel 契约), §7 (适配器契约)
// 任务: 3.6 - 统一错误处理 UI (L1~L4) + 降级横幅 + 冷却期提醒
//       3F.10 - production runtime wiring: SystemMonitor low-power/thermal sources change
//               actual runtime behavior (US-RES-002 AC-1/AC-3/AC-5, US-RES-003 AC-1/AC-3/AC-5),
//               manual-only model retry (US-RES-004 AC-3), localized messages (DEF-41-1),
//               accessibility announcement (US-DIS-004 AC-2)
// AC 覆盖: US-RES-002 AC-1 ✅ (low-power source), AC-2 ✅ (Banner), AC-3 ✅ (auto-pause toggle default on),
//          AC-4 ✅ (exit auto-dismiss), AC-5 ✅ (audit fields),
//          US-RES-003 AC-1 ✅ (thermal .serious+), AC-2 ✅ (Banner), AC-3 ✅ (recovery dismiss), AC-5 ✅ (audit),
//          US-RES-004 AC-3 ✅ (manual retry only), AC-7 ✅ (banner + retry/settings),
//          US-DIS-004 AC-2 ✅ (announcement)
// 架构约束: AGENTS.md §8.1 (@MainActor + @Observable + state enum), §8.2 (idle→loading→completed),
//           §4.4 (L1~L4), §5.4 (hash-only audit), R-007 (no Combine),
//           docs/ui/architecture.md §6~7 (适配器契约), §2.5 (不保存第二份领域真相)
// 生成时间: 2026-08-02, 2026-08-12 (3F.10 production wiring)
// ==========================================

import SwiftUI
import Foundation

enum DegradationType: String, Sendable, Equatable, CaseIterable {
    case lowPower
    case thermal
    case modelDegraded
}

struct DegradationState: Sendable, Equatable {
    var type: DegradationType
    var message: String
    var iconName: String
    var tint: Color
    var showToggle: Bool
    var backgroundTasksPaused: Bool
    var showRetry: Bool
    var showSettings: Bool

    static func lowPower(paused: Bool) -> Self {
        Self(
            type: .lowPower,
            message: "Low Power Mode is enabled. Memory search precision may be reduced.",
            iconName: "battery.25",
            tint: .yellow,
            showToggle: true,
            backgroundTasksPaused: paused,
            showRetry: false,
            showSettings: false
        )
    }

    static func thermal() -> Self {
        Self(
            type: .thermal,
            message: "Device temperature is high. Some features have been temporarily simplified.",
            iconName: "thermometer.high",
            tint: .orange,
            showToggle: false,
            backgroundTasksPaused: false,
            showRetry: false,
            showSettings: false
        )
    }

    static func modelDegraded() -> Self {
        Self(
            type: .modelDegraded,
            message: "Functional limitations due to model loading issues.",
            iconName: "exclamationmark.triangle",
            tint: .red,
            showToggle: false,
            backgroundTasksPaused: false,
            showRetry: true,
            showSettings: true
        )
    }

    func localizedMessage(locale: Locale) -> String {
        EchoLocalization.localized(message, locale: locale)
    }
}

@MainActor
@Observable
final class DegradationBannerViewModel {
    enum UIState: Equatable {
        case idle
        case loading
        case active(DegradationState)
        case error(String)
    }

    static let lowPowerAutoPauseKey = GenerationResourcePolicy.lowPowerAutoPauseKey

    static var isAutoPauseOnLowPowerEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: lowPowerAutoPauseKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: lowPowerAutoPauseKey)
        }
    }

    private(set) var state: UIState = .idle
    private(set) var isBannerVisible: Bool = false
    private(set) var activeDegradation: DegradationState?
    private(set) var pendingAccessibilityAnnouncement: String?
    /// Fixture-driven mode (UI-test/Preview `-degradationFixture`): real SystemMonitor
    /// conditions must not override a deliberately injected fixture state.
    private(set) var isFixtureDriven: Bool = false

    let hasAutomaticRetryTimer: Bool = false

    private var dismissTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?

    private let systemMonitor: SystemMonitor?
    private let auditWriter: PrivacyActor?
    private let modelLoader: ModelLoaderActor?

    init(
        systemMonitor: SystemMonitor? = nil,
        auditWriter: PrivacyActor? = nil,
        modelLoader: ModelLoaderActor? = nil
    ) {
        self.systemMonitor = systemMonitor
        self.auditWriter = auditWriter
        self.modelLoader = modelLoader
    }

    // MARK: - Production Monitoring (US-RES-002 / US-RES-003)

    func startMonitoring() async {
        guard let systemMonitor, observationTask == nil else { return }
        await systemMonitor.start()
        applyCurrentConditions()
        observationTask = Task { [weak self] in
            guard let monitor = self?.systemMonitor else { return }
            for await _ in monitor.conditionChanges {
                self?.applyCurrentConditions()
            }
        }
    }

    func stopMonitoring() async {
        observationTask?.cancel()
        observationTask = nil
        await systemMonitor?.stop()
    }

    private func applyCurrentConditions() {
        guard let systemMonitor, !isFixtureDriven else { return }

        if systemMonitor.isLowPowerMode {
            if activeDegradation?.type != .lowPower {
                let paused = Self.isAutoPauseOnLowPowerEnabled
                if paused {
                    Task { await pauseActiveBackgroundTask() }
                }
                activate(.lowPower(paused: paused))
                writeDegradationAudit(active: true, kind: "lowPower", paused: paused)
            }
        } else if systemMonitor.isThermalDegraded {
            if activeDegradation?.type != .thermal {
                activate(.thermal())
                writeDegradationAudit(active: true, kind: "thermal", paused: false)
            }
        } else if activeDegradation?.type == .lowPower || activeDegradation?.type == .thermal {
            let kind = activeDegradation?.type == .thermal ? "thermal" : "lowPower"
            if kind == "lowPower" {
                Task { await resumeActiveBackgroundTask() }
            }
            writeDegradationAudit(active: false, kind: kind, paused: false)
            deactivate()
        }
    }

    private var pausedTaskID: String?

    private func pauseActiveBackgroundTask() async {
        guard pausedTaskID == nil,
              let activeID = await TaskQueueActor.shared.activeTaskID() else { return }
        await TaskQueueActor.shared.pause(taskId: activeID)
        pausedTaskID = activeID
    }

    private func resumeActiveBackgroundTask() async {
        guard let taskID = pausedTaskID else { return }
        await TaskQueueActor.shared.resume(taskId: taskID)
        pausedTaskID = nil
    }

    private func writeDegradationAudit(active: Bool, kind: String, paused: Bool) {
        guard let auditWriter else { return }
        let thermalRaw: String
        if let monitor = systemMonitor {
            thermalRaw = String(describing: monitor.thermalState)
        } else {
            thermalRaw = "unknown"
        }
        Task {
            let policy = await auditWriter.getPolicy()
            try? await auditWriter.writeAuditLog(
                eventType: .degradationWarning,
                traceID: UUID().uuidString,
                policyVersion: policy.policyVersion,
                success: true,
                sourceType: "degradation:\(kind)",
                content: "kind=\(kind)|degradationActive=\(active)|degradationWarningShown=\(active)|backgroundTasksPaused=\(paused)|deviceThermalState=\(thermalRaw)"
            )
        }
    }

    // MARK: - Fixture / Manual Activation

    func loadFixture(_ fixtureID: String) {
        isFixtureDriven = true
        state = .loading
        let fixture = DegradationFixtureLoader.load(fixtureID)
        if let degradation = fixture.degradation {
            activeDegradation = degradation
            isBannerVisible = true
            state = .active(degradation)
        } else {
            activeDegradation = nil
            isBannerVisible = false
            state = .idle
        }
    }

    func activate(_ degradation: DegradationState) {
        state = .loading
        activeDegradation = degradation
        isBannerVisible = true
        state = .active(degradation)
        pendingAccessibilityAnnouncement = degradation.message
    }

    func consumeAccessibilityAnnouncement() -> String? {
        defer { pendingAccessibilityAnnouncement = nil }
        return pendingAccessibilityAnnouncement
    }

    func dismissBanner() {
        retryTask?.cancel()
        dismissTask?.cancel()
        isBannerVisible = false
        activeDegradation = nil
        state = .idle
    }

    func toggleBackgroundTasks() {
        guard activeDegradation?.type == .lowPower, var current = activeDegradation else { return }
        current.backgroundTasksPaused.toggle()
        Self.isAutoPauseOnLowPowerEnabled = current.backgroundTasksPaused
        let paused = current.backgroundTasksPaused
        Task {
            if paused {
                await self.pauseActiveBackgroundTask()
            } else {
                await self.resumeActiveBackgroundTask()
            }
        }
        activeDegradation = current
        state = .active(current)
    }

    // MARK: - Model Retry (US-RES-004 AC-3: manual only, never automatic)

    func retryModelLoad() {
        retryTask?.cancel()
        state = .loading
        retryTask = Task { [weak self] in
            guard let self else { return }
            if let modelLoader = self.modelLoader {
                let states = await modelLoader.retryAllFailedModels()
                guard !Task.isCancelled else { return }
                let allLoaded = states.allSatisfy { state in
                    if case .loaded = state { return true }
                    return false
                }
                if allLoaded {
                    if let auditWriter = self.auditWriter {
                        let policy = await auditWriter.getPolicy()
                        try? await auditWriter.writeAuditLog(
                            eventType: .modelLoadRetrySuccess,
                            traceID: UUID().uuidString,
                            policyVersion: policy.policyVersion,
                            success: true,
                            sourceType: "manualRetry"
                        )
                    }
                    self.dismissBanner()
                } else {
                    self.state = .active(.modelDegraded())
                }
                return
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            state = .active(.modelDegraded())
        }
    }

    func deactivate() {
        retryTask?.cancel()
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isBannerVisible = false
            activeDegradation = nil
            state = .idle
        }
    }

    deinit {
        // dismissTask cleanup deferred — nonisolated deinit cannot access @MainActor state
    }
}
