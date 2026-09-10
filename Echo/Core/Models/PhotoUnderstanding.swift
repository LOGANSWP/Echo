// ==========================================
// File: PhotoUnderstanding.swift
// Spec: US-ING-004 AC-6/7/8; ADR-025
// Task: 4.0l - Typed photo preparation and recovery values
// Architecture: original MemoryID; descriptors contain no pixels, prose or authorization snapshots
// Generated: 2026-09-09
// ==========================================

import Foundation

nonisolated public enum PhotoUnderstandingStatus: String, Sendable {
    case unprepared, queued, ready, failed, unavailable
}

nonisolated public struct PhotoUnderstandingMaterial: Sendable, Equatable {
    public let caption: String
    public let captionLanguage: String
    public let ocrText: String?
    public let ocrLanguage: String?
    public let usesUserCorrection: Bool
}

nonisolated public protocol PhotoPixelSourceReading: Sendable {
    func currentRevision(assetID: String) async throws -> String
    func read(assetID: String, expectedRevision: String) async throws -> Data
}

nonisolated struct PhotoUnderstandingWorkItem: Sendable, Codable, Equatable {
    let memoryID: UUID
    let sourceVersion: String
    let assetRevision: String
    let modelVersion: String
    let processingVersion: String
}
