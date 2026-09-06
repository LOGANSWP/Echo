// ==========================================
// File: PhotoKitChangeObserver.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md → US-SRC-012, US-PRV-007
//       docs/decisions/ADR-008-source-import-boundaries.md decision 1
// Task: 3F.2 + 4.0h - PhotoKit observation and deletion reconciliation
// AC coverage: seed the pre-change fetch before registration; emit deduplicated ChangeEvents
// Architecture: AGENTS.md section 4.2; R-007; no PHAsset crosses an actor boundary
// Generated: 2026-08-05 | Updated: 2026-09-06
// ==========================================

import Foundation
@preconcurrency import Photos

// MARK: - Change Event Builder

/// Builds ChangeEvents from asset identifier arrays (pure function, testable).
///
/// US-SRC-012 AC-1: inserted -> `.added`, changed -> `.modified`, removed -> `.removed`
public enum ChangeEventBuilder {
    public nonisolated static func events(
        inserted: [String],
        changed: [String],
        removed: [String]
    ) -> [ChangeEvent] {
        var events: [ChangeEvent] = []
        events.append(contentsOf: inserted.map {
            ChangeEvent(assetId: $0, source: .photo, changeType: .added)
        })
        events.append(contentsOf: changed.map {
            ChangeEvent(assetId: $0, source: .photo, changeType: .modified)
        })
        events.append(contentsOf: removed.map {
            ChangeEvent(assetId: $0, source: .photo, changeType: .removed)
        })
        return events
    }
}

// MARK: - Change Coalescer

/// In-batch change deduplicator (ADR-008 decision-1).
///
/// Pure function: keeps only the first occurrence of each `assetId|changeType`
/// (PhotoKit may repeat the same asset within a single delivery). Cross-delivery
/// window dedupe is handled by SyncPipeline actor recency state.
public struct ChangeCoalescer: Sendable {
    /// Dedupe window (seconds) — used by SyncPipeline actor recency pruning
    public nonisolated let window: TimeInterval

    public nonisolated init(window: TimeInterval = 2.0) {
        self.window = window
    }

    /// Returns non-duplicate events (by `assetId|changeType`, ignoring `existing` occurrences).
    public nonisolated func dedupe(_ events: [ChangeEvent], existing: [ChangeEvent]) -> [ChangeEvent] {
        var seen = Set<String>()
        for event in existing {
            seen.insert("\(event.assetId)|\(event.changeType.rawValue)")
        }
        var result: [ChangeEvent] = []
        for event in events {
            let key = "\(event.assetId)|\(event.changeType.rawValue)"
            if seen.insert(key).inserted {
                result.append(event)
            }
        }
        return result
    }
}

// MARK: - PhotoKit Change Observer

/// PhotoKit photo-library change observer (US-SRC-012 AC-1) — thin Photos boundary,
/// no mutable instance state.
///
/// - Implements `PHPhotoLibraryChangeObserver`; `photoLibraryDidChange` extracts
///   inserted/changed/removed asset localIdentifiers, builds `[ChangeEvent]`, dedupes,
///   then delivers
/// - All members `nonisolated`: safely constructed and registered from the
///   SyncPipeline actor (non-MainActor)
/// - Delivery closure is a `@Sendable` value type carrying only value-type ChangeEvents
/// - The monitored pre-change fetch result is cached in a dedicated @MainActor singleton
///   (`MonitoredFetchResult`), avoiding instance @MainActor state (Swift 6 rejects
///   nonisolated callbacks capturing self with a sending data race; verified on CI
///   Xcode 16.4)
public final class PhotoKitChangeObserver: NSObject, PHPhotoLibraryChangeObserver {

    /// Change-event delivery closure (@Sendable value type carrying only value-type ChangeEvents)
    public nonisolated let onPhotoLibraryChange: (@Sendable ([ChangeEvent]) -> Void)?
    private nonisolated let coalescer: ChangeCoalescer

    public nonisolated init(
        onPhotoLibraryChange: (@Sendable ([ChangeEvent]) -> Void)? = nil,
        coalescer: ChangeCoalescer = ChangeCoalescer()
    ) {
        self.onPhotoLibraryChange = onPhotoLibraryChange
        self.coalescer = coalescer
        super.init()
    }

    // MARK: - PHPhotoLibraryChangeObserver

    /// PhotoKit callback: extracts identifiers, builds events, dedupes, delivers.
    ///
    /// Apple documents that `photoLibraryDidChange` is invoked on an arbitrary
    /// background queue (not the main thread), so `MainActor.assumeIsolated` must not
    /// be used (it traps off the main thread). MonitoredFetchResult is a @MainActor
    /// singleton (PHFetchResult is non-Sendable), so the work hops via
    /// `Task { @MainActor }`; the closure captures only Sendable locals
    /// (deliver + coalescer), never self (NSObject non-Sendable), satisfying
    /// Xcode 16.4 Swift 6 strict concurrency.
    public nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Hoist locals so the Task closure never captures self
        let deliver = onPhotoLibraryChange
        let coalescer = self.coalescer
        Task { @MainActor in
            guard let identifiers = MonitoredFetchResult.assetIdentifiers(from: changeInstance)
            else { return }
            let events = ChangeEventBuilder.events(
                inserted: identifiers.inserted,
                changed: identifiers.changed,
                removed: identifiers.removed
            )
            guard !events.isEmpty else { return }
            let deduped = coalescer.dedupe(events, existing: [])
            guard !deduped.isEmpty else { return }
            deliver?(deduped)
        }
    }

    /// Processes asset identifier changes (internal testable entry; called by photoLibraryDidChange after extraction).
    ///
    /// - Returns: deduped change events actually delivered (empty if no valid changes)
    internal nonisolated func consumeForTesting(
        inserted: [String],
        changed: [String],
        removed: [String]
    ) -> [ChangeEvent] {
        let events = ChangeEventBuilder.events(inserted: inserted, changed: changed, removed: removed)
        guard !events.isEmpty else { return [] }
        // In-batch dedupe (ADR-008 decision-1); cross-delivery dedupe handled by SyncPipeline
        let deduped = coalescer.dedupe(events, existing: [])
        guard !deduped.isEmpty else { return [] }
        onPhotoLibraryChange?(deduped)
        return deduped
    }
}

// MARK: - Monitored Fetch Result

/// Cache of the monitored pre-change fetch result (CodeRabbit #2).
///
/// `PHChange.changeDetails(for:)` only returns a delta for the fetch result that
/// represents the pre-change state; passing a fresh result makes the system report
/// "no changes" and drop the ChangeEvent (US-SRC-012 AC-1).
///
/// Threading: PHFetchResult is not Sendable, so this is a @MainActor singleton;
/// seeding is a plain assignment and `PHAsset.fetchAssets` is thread-safe, so the
/// caller may seed from any thread. `assetIdentifiers` is only ever invoked from
/// `photoLibraryDidChange`, which hops to MainActor via Task.
/// (Swift 6 rejects nonisolated static mutable state and NSLock-held globals;
/// @MainActor isolation is the only compliant storage — CI Xcode 16.4 verified.)
@MainActor
internal enum MonitoredFetchResult {
    private static var result: PHFetchResult<PHAsset>?

    /// Establishes the pre-change baseline before observer registration.
    static func seedIfNeeded() {
        if result == nil {
            result = PHAsset.fetchAssets(with: nil)
        }
    }

    /// Extracts inserted/changed/removed asset localIdentifiers from PHChange.
    ///
    /// Uses the pre-change fetch result seeded before observer registration. The fallback
    /// keeps direct test use safe, while production registration always establishes the
    /// baseline first. Called from `photoLibraryDidChange` on MainActor (via Task).
    static func assetIdentifiers(from changeInstance: PHChange)
        -> (inserted: [String], changed: [String], removed: [String])? {
        seedIfNeeded()
        guard let fetch = result,
              let details = changeInstance.changeDetails(for: fetch) else { return nil }
        result = details.fetchResultAfterChanges
        return (
            inserted: details.insertedObjects.map(\.localIdentifier),
            changed: details.changedObjects.map(\.localIdentifier),
            removed: details.removedObjects.map(\.localIdentifier)
        )
    }
}
