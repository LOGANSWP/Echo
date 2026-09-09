// ==========================================
// File: GenerationResourcePolicy.swift
// Spec: US-SYN-004; ADR-023 sections 2/4
// Task: 4.0k - Safe resource deferral during decoding
// AC coverage: low-power preference and serious/critical thermal interruption
// Architecture: AGENTS.md section 4.3; resource deferral does not create L2
// Generated: 2026-09-08
// ==========================================

import Foundation

/// Shares the existing user preference with scheduling and in-flight generation.
nonisolated enum GenerationResourcePolicy {
    static let lowPowerAutoPauseKey = "echo.lowPowerAutoPauseEnabled"

    static func check() throws {
        try Task.checkCancellation()
        let process = ProcessInfo.processInfo
        let autoPause = UserDefaults.standard.object(forKey: lowPowerAutoPauseKey) as? Bool ?? true
        guard !(process.isLowPowerModeEnabled && autoPause),
            process.thermalState != .serious, process.thermalState != .critical
        else {
            throw NarrativeReportError.resourceDeferred
        }
    }
}
