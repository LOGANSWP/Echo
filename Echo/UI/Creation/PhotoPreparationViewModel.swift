// Task 4.0l; US-ING-004 AC-7/8: truthful preparation and explicit retry.
// Architecture: MainActor Observation adapter; all work belongs to Core.
import Foundation
import Observation

nonisolated protocol PhotoPreparationServicing: Sendable {
    func canCreate(memoryID: UUID, traceID: String) async throws -> Bool
    func status(memoryID: UUID, traceID: String) async throws -> PhotoUnderstandingStatus
    func readMaterial(memoryID: UUID, traceID: String) async throws -> PhotoUnderstandingMaterial?
    func schedule(memoryID: UUID, traceID: String, retry: Bool) async throws -> Bool
}

extension PhotoUnderstandingActor: PhotoPreparationServicing {}

@MainActor @Observable
final class PhotoPreparationViewModel {
    deinit {}
    enum State: Equatable {
        case idle, loading
        case completed(PhotoUnderstandingStatus)
        case error
    }

    private(set) var state: State = .idle
    private(set) var canCreate = false
    private(set) var material: PhotoUnderstandingMaterial?
    private let service: any PhotoPreparationServicing
    private let memoryID: UUID

    init(memoryID: UUID, service: any PhotoPreparationServicing) {
        self.memoryID = memoryID
        self.service = service
    }

    func refresh() async {
        state = .loading
        material = nil
        canCreate = (try? await service.canCreate(memoryID: memoryID, traceID: UUID().uuidString)) == true
        do {
            let status = try await service.status(memoryID: memoryID, traceID: UUID().uuidString)
            if status == .ready {
                guard let result = try await service.readMaterial(memoryID: memoryID, traceID: UUID().uuidString) else {
                    state = .error
                    return
                }
                material = result
            }
            state = .completed(status)
        } catch {
            state = .error
        }
    }

    /// Entering a selected photo is a demand signal, not consent to retry an earlier failure.
    func prepareOnAccess() async {
        state = .loading
        material = nil
        do {
            let current = try await service.status(memoryID: memoryID, traceID: UUID().uuidString)
            if current == .unprepared {
                _ = try await service.schedule(memoryID: memoryID, traceID: UUID().uuidString, retry: false)
            }
            await refresh()
        } catch { await refresh() }
    }

    func prepare() async {
        state = .loading
        material = nil
        do {
            _ = try await service.schedule(memoryID: memoryID, traceID: UUID().uuidString, retry: true)
            await refresh()
        } catch { await refresh() }
    }
}
