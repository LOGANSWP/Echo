// ==========================================
// File: GenerationArtifactVerifier.swift
// Spec: US-SYN-004; ADR-009/023 section 1
// Task: 4.0k - Exact approved resource verification
// AC coverage: full inventory, missing/corrupt resources fail closed
// Architecture: AGENTS.md sections 4.2, R-005
// Generated: 2026-09-08
// ==========================================

import CryptoKit
import Foundation

nonisolated struct GenerationArtifactFile: Sendable {
    let path: String
    let sizeBytes: Int
    let sha256: String
}

nonisolated enum GenerationArtifactVerifier {
    static func verify(root: URL, files: [GenerationArtifactFile]) throws {
        do {
            try verifyFiles(root: root, files: files)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GenerationRuntimeError.invalidArtifact
        }
    }

    private static func verifyFiles(root: URL, files: [GenerationArtifactFile]) throws {
        let manager = FileManager.default
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true, !files.isEmpty,
            Set(files.map(\.path)).count == files.count
        else { throw GenerationRuntimeError.invalidArtifact }
        var actual: Set<String> = []
        // Explicit traversal propagates directory read errors, unlike a nil enumerator error handler.
        var directories = [root]
        while let directory = directories.popLast() {
            try Task.checkCancellation()
            for url in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw GenerationRuntimeError.invalidArtifact }
                if values.isDirectory == true {
                    directories.append(url)
                } else if values.isRegularFile == true {
                    actual.insert(String(url.path.dropFirst(root.path.count + 1)))
                } else {
                    throw GenerationRuntimeError.invalidArtifact
                }
            }
        }
        guard actual == Set(files.map(\.path)) else { throw GenerationRuntimeError.invalidArtifact }
        for file in files {
            try Task.checkCancellation()
            let parts = file.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                file.sizeBytes >= 0
            else { throw GenerationRuntimeError.invalidArtifact }
            let url = root.appendingPathComponent(file.path)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var digest = SHA256()
            var count = 0
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                count += chunk.count
                guard count <= file.sizeBytes else { throw GenerationRuntimeError.invalidArtifact }
                digest.update(data: chunk)
            }
            let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
            guard count == file.sizeBytes, hash == file.sha256 else { throw GenerationRuntimeError.invalidArtifact }
        }
    }
}
