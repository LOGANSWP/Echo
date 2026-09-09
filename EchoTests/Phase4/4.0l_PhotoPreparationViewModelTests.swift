// Task 4.0l; US-ING-004 AC-8: UI reads state and retries only on explicit action.
import Foundation
import Testing

@testable import Echo

private actor PhotoPreparationUIProbe: PhotoPreparationServicing {
    private(set) var calls = 0
    var current: PhotoUnderstandingStatus = .failed
    var correction = false
    func setCorrection(_ value: Bool) { correction = value }
    func canCreate(memoryID: UUID, traceID: String) async throws -> Bool { correction || current == .ready }
    private(set) var retries: [Bool] = []
    func setStatus(_ status: PhotoUnderstandingStatus) { current = status }
    func status(memoryID: UUID, traceID: String) async throws -> PhotoUnderstandingStatus { current }
    func readMaterial(memoryID: UUID, traceID: String) async throws -> PhotoUnderstandingMaterial? {
        guard current == .ready else { return nil }
        return PhotoUnderstandingMaterial(
            caption: "A red circle",
            captionLanguage: "en-US",
            ocrText: "OPEN",
            ocrLanguage: "en-US",
            usesUserCorrection: false
        )
    }
    func schedule(memoryID: UUID, traceID: String, retry: Bool) async throws -> Bool {
        retries.append(retry)
        calls += 1
        current = .queued
        return true
    }
}

@Suite("4.0l Photo Preparation UI", .serialized)
struct PhotoPreparationViewModelTests {
    @Test("AC-7: every selected photo needs material; metadata never unlocks generation")
    @MainActor func test_AC7_generationGate() async {
        let first = UUID(), second = UUID()
        let creation = CreationViewModel()
        creation.loadSourceMemories([first, second].map {
            CreativeSource(memoryID: $0, assetID: "", sourceType: "photo", text: "Title and tags", timestamp: 1)
        })
        creation.selectTemplate(.letter)
        #expect(!creation.canGenerate)
        creation.generate()
        #expect(creation.viewState == .idle)
        creation.updatePhotoReadiness(memoryID: first, ready: true)
        #expect(!creation.canGenerate)
        creation.updatePhotoReadiness(memoryID: second, ready: true)
        #expect(creation.canGenerate)
        creation.updatePhotoReadiness(memoryID: first, ready: false)
        #expect(!creation.canGenerate)
        creation.loadSourceMemories([])
        #expect(creation.canGenerate)
    }

    @Test("AC-7: a written correction unlocks creation even when understanding failed")
    @MainActor func test_AC7_correctionGate() async {
        let service = PhotoPreparationUIProbe()
        let model = PhotoPreparationViewModel(memoryID: UUID(), service: service)
        await model.refresh()
        #expect(!model.canCreate)
        await service.setCorrection(true)
        await model.refresh()
        #expect(model.canCreate)
        await service.setCorrection(false)
        await model.refresh()
        #expect(!model.canCreate)
    }

    @Test("AC-7: ready state exposes separate model/OCR text and clears unavailable material")
    @MainActor func test_AC7_visibleMaterial() async {
        let service = PhotoPreparationUIProbe()
        let model = PhotoPreparationViewModel(memoryID: UUID(), service: service)
        await service.setStatus(.ready)
        await model.refresh()
        #expect(model.material?.caption == "A red circle")
        #expect(model.material?.ocrText == "OPEN")
        await service.setStatus(.unprepared)
        await model.refresh()
        #expect(model.material == nil)
        #expect(await service.calls == 0)
    }

    @Test("AC-6: opening a selected photo prepares only missing material without automatic retry")
    @MainActor func test_AC6_onDemandAccess() async {
        let service = PhotoPreparationUIProbe()
        let model = PhotoPreparationViewModel(memoryID: UUID(), service: service)
        await service.setStatus(.unprepared)
        await model.prepareOnAccess()
        await model.prepareOnAccess()
        #expect(await service.calls == 1)
        #expect(await service.retries == [false])
        await service.setStatus(.ready)
        await model.prepareOnAccess()
        await service.setStatus(.failed)
        await model.prepareOnAccess()
        #expect(await service.calls == 1)
    }

    @Test("AC-8: refreshing a failed preparation never retries it")
    @MainActor func test_AC8_explicitRetry() async {
        let service = PhotoPreparationUIProbe()
        let model = PhotoPreparationViewModel(memoryID: UUID(), service: service)
        await model.refresh()
        await model.refresh()
        #expect(model.state == .completed(.failed))
        #expect(await service.calls == 0)
        await model.prepare()
        #expect(await service.calls == 1)
        #expect(model.state == .completed(.queued))
    }
}
