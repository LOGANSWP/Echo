// Task 4.0l; US-ING-004 AC-8; ADR-025 approved 32 MB encoded-image budget.
// PhotoKit callback transport only; no persisted pixels or source authority.
// Generated: 2026-09-09
import Foundation

nonisolated struct BoundedPhotoBytes: Sendable {
    let limit: Int
    private var bytes = Data()
    private var exceeded = false
    init(limit: Int) { self.limit = limit }

    mutating func append(_ chunk: Data) throws {
        guard !exceeded, limit >= 0, bytes.count <= limit, chunk.count <= limit - bytes.count else {
            exceeded = true
            bytes = Data()
            throw GenerationRuntimeError.contextLimit
        }
        bytes.append(chunk)
    }

    func finish() throws -> Data {
        guard !exceeded else { throw GenerationRuntimeError.contextLimit }
        guard !bytes.isEmpty else { throw GenerationRuntimeError.invalidRequest }
        return bytes
    }
}
