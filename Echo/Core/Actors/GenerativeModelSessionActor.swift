// ==========================================
// File: GenerativeModelSessionActor.swift
// Spec: ADR-025 approved single-session/release budget; ADR-023
// Task: 4.0l - Prevent simultaneous visual and text model residency
// Architecture: value-only lease, no user content; busy work defers for resources
// Generated: 2026-09-09
// ==========================================

import Foundation

actor GenerativeModelSessionActor {
    static let shared = GenerativeModelSessionActor()
    private var owner: UUID?

    func acquire() throws -> UUID {
        try Task.checkCancellation()
        guard owner == nil else { throw NarrativeReportError.resourceDeferred }
        let lease = UUID()
        owner = lease
        return lease
    }

    func release(_ lease: UUID) {
        if owner == lease { owner = nil }
    }
}
