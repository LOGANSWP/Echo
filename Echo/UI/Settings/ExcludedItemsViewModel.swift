// ==========================================
// File: ExcludedItemsViewModel.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md → US-PRV-007 AC-3, US-SRC-008
// Task: 4.0h - Cascade cleanup presentation
// AC coverage: one-time user-visible cleanup notice; userNotified becomes true only after presentation
// Architecture: AGENTS.md §8.1 (@MainActor @Observable state machine), ADR-019
// Generated: 2026-09-05
// ==========================================

import Foundation
import Observation

@MainActor
@Observable
final class ExcludedItemsViewModel {
    enum ViewState: Equatable, Sendable {
        case idle
        case loading
        case completed(pendingCleanupCount: Int, wasPresentedThisSession: Bool)
        case error
        case cancelled
    }

    private(set) var state: ViewState = .idle
    private let excludedAssets: ExcludedAssetsActor

    init(excludedAssets: ExcludedAssetsActor) {
        self.excludedAssets = excludedAssets
    }

    func load() async {
        state = .loading
        do {
            let count = try await excludedAssets.pendingCleanupNoticeCount()
            state = .completed(pendingCleanupCount: count, wasPresentedThisSession: false)
        } catch is CancellationError {
            state = .cancelled
        } catch {
            state = .error
        }
    }

    /// Called only after the notice has entered the visible SwiftUI hierarchy.
    func markCleanupNoticePresented(visibleCount: Int) async {
        state = .loading
        do {
            _ = try await excludedAssets.markCleanupNoticesPresented(traceID: UUID().uuidString)
            state = .completed(
                pendingCleanupCount: visibleCount,
                wasPresentedThisSession: true
            )
        } catch is CancellationError {
            state = .cancelled
        } catch {
            state = .error
        }
    }
}
