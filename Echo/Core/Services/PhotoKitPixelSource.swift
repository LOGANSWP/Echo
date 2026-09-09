// ==========================================
// File: PhotoKitPixelSource.swift
// Spec: US-ING-004 AC-4/6/8; ADR-025
// Task: 4.0l - Bounded current local PhotoKit pixels
// Architecture: system callback transport, Sendable values, no network or persisted image copy
// Generated: 2026-09-09
// ==========================================
import CryptoKit
import Foundation
import Photos
import Synchronization

nonisolated public struct PhotoKitPixelSource: PhotoPixelSourceReading {
    public init() {}

    public func currentRevision(assetID: String) async throws -> String {
        try Self.resolve(assetID).revision
    }

    public func read(assetID: String, expectedRevision: String) async throws -> Data {
        let selected = try Self.resolve(assetID)
        guard selected.revision == expectedRevision else { throw GenerationRuntimeError.restartRequired }
        let bridge = PhotoResourceReadBridge()
        let timer = Task {
            do {
                try await Task.sleep(for: .seconds(60))
                bridge.fail(GenerationRuntimeError.deadline)
            } catch {}
        }
        defer { timer.cancel() }
        let data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard bridge.install(continuation) else { return }
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = false
                let request = PHAssetResourceManager.default().requestData(
                    for: selected.resource,
                    options: options,
                    dataReceivedHandler: { bridge.append($0) },
                    completionHandler: { error in
                        if error != nil {
                            bridge.fail(GenerationRuntimeError.invalidRequest)
                        } else {
                            bridge.complete()
                        }
                    }
                )
                bridge.setRequest(request)
            }
        } onCancel: {
            bridge.fail(CancellationError())
        }
        try Task.checkCancellation()
        guard try Self.resolve(assetID).revision == expectedRevision else {
            throw GenerationRuntimeError.restartRequired
        }
        return data
    }

    private static func resolve(_ assetID: String) throws -> (resource: PHAssetResource, revision: String) {
        let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorization == .authorized || authorization == .limited else {
            throw GenerationRuntimeError.privacyDenied
        }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject,
            asset.mediaType == .image
        else { throw GenerationRuntimeError.restartRequired }
        let all = PHAssetResource.assetResources(for: asset)
        let edited = all.filter { $0.type == .fullSizePhoto }
        let candidates = edited.isEmpty ? all.filter { $0.type == .photo } : edited
        guard candidates.count == 1, let resource = candidates.first else {
            throw GenerationRuntimeError.invalidRequest
        }
        let width = resource.pixelWidth
        let height = resource.pixelHeight
        guard width > 0, height > 0, width <= 16_384, height <= 16_384,
            width * height <= 100_000_000
        else { throw GenerationRuntimeError.contextLimit }
        let identity = [
            asset.localIdentifier, String(asset.modificationDate?.timeIntervalSince1970 ?? 0),
            String(width), String(height), String(resource.type.rawValue), resource.originalFilename,
            resource.uniformTypeIdentifier,
        ]
        let encoded = try JSONEncoder().encode(identity)
        let revision = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
        return (resource, revision)
    }
}

/// Synchronizes the system's callbacks with cancellation; no business closures cross actors.
nonisolated private final class PhotoResourceReadBridge: Sendable {
    deinit {}
    private struct State: Sendable {
        var buffer = BoundedPhotoBytes(limit: 32_000_000)
        var continuation: CheckedContinuation<Data, any Error>?
        var earlyFailure: (any Error)?
        var finished = false
        var request: PHAssetResourceDataRequestID?
    }
    private let state = Mutex(State())

    func install(_ continuation: CheckedContinuation<Data, any Error>) -> Bool {
        let error = state.withLock { value -> (any Error)? in
            if value.finished { return value.earlyFailure ?? CancellationError() }
            value.continuation = continuation
            return nil
        }
        if let error {
            continuation.resume(throwing: error)
            return false
        }
        return true
    }

    func setRequest(_ request: PHAssetResourceDataRequestID) {
        let cancel = state.withLock { value in
            value.request = request
            return value.finished
        }
        if cancel { PHAssetResourceManager.default().cancelDataRequest(request) }
    }

    func append(_ chunk: Data) {
        let error = state.withLock { value -> (any Error)? in
            guard !value.finished else { return nil }
            do {
                try value.buffer.append(chunk)
                return nil
            } catch { return error }
        }
        if let error { fail(error) }
    }

    func complete() { finish(error: nil) }
    func fail(_ error: any Error) { finish(error: error) }

    private func finish(error: (any Error)?) {
        let result = state.withLock { value -> (CheckedContinuation<Data, any Error>?, Result<Data, any Error>, PHAssetResourceDataRequestID?)? in
            guard !value.finished else { return nil }
            value.finished = true
            let outcome: Result<Data, any Error>
            if let error { outcome = .failure(error) } else { outcome = Result { try value.buffer.finish() } }
            if case .failure(let failure) = outcome { value.earlyFailure = failure }
            let continuation = value.continuation
            value.continuation = nil
            value.buffer = BoundedPhotoBytes(limit: 32_000_000)
            return (continuation, outcome, value.request)
        }
        guard let result else { return }
        if case .failure = result.1, let request = result.2 {
            PHAssetResourceManager.default().cancelDataRequest(request)
        }
        result.0?.resume(with: result.1)
    }
}
