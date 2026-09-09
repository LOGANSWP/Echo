// Task 4.0l; US-ING-004 AC-8: PhotoKit transport byte budget.
// Generated: 2026-09-09
import Foundation
import Testing

@testable import Echo

@Suite("4.0l Photo Resource")
struct PhotoResourceTests {
    @Test("AC-8: missing bundled models produce an audited blocking failure")
    func test_AC8_modelFailureAudit() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("photo-model-failure-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path.path + suffix) }
        }
        let db = DatabaseManager(databaseURL: path)
        try await db.open()
        let privacy = PrivacyActor(db: db)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["photo"]))
        let runtime = BundledPhotoUnderstandingActor(privacyActor: privacy, resourceRoot: nil)
        await #expect(throws: GenerationRuntimeError.invalidArtifact) {
            _ = try await runtime.describe(imageData: Data(), traceID: "missing-photo-model")
        }
        #expect(try await privacy.fetchAuditLogs(eventType: .modelLoadFailed).contains { !$0.success })
        await db.close()
    }
    @Test("AC-7: real Vision OCR returns visible image text separately")
    func test_AC7_actualOCR() async throws {
        let output = try #require(
            await VisionPhotoOCRService().recognizeText(
                imageData: PhotoRuntimeTests.image(withText: true),
                preferredLanguages: ["en-US", "zh-Hans"],
                traceID: "photo-real-ocr"
            )
        )
        #expect(output.normalizedText.contains("OPEN"))
    }
    @Test("AC-8: incremental image bytes reject overflow and retain terminal failure")
    func test_AC8_bytes() throws {
        var buffer = BoundedPhotoBytes(limit: 3)
        try buffer.append(Data([1, 2]))
        try buffer.append(Data([3]))
        #expect(try buffer.finish() == Data([1, 2, 3]))
        #expect(throws: GenerationRuntimeError.contextLimit) { try buffer.append(Data([4])) }
        #expect(throws: GenerationRuntimeError.contextLimit) { try buffer.finish() }
        #expect(throws: GenerationRuntimeError.contextLimit) { try buffer.append(Data()) }
    }

    @Test("AC-8: empty resource cannot become a successful image")
    func test_AC8_empty() {
        let buffer = BoundedPhotoBytes(limit: 3)
        #expect(throws: GenerationRuntimeError.invalidRequest) { try buffer.finish() }
    }
}
