// ==========================================
// File: 4.0l_PhotoRuntimeTests.swift
// Spec: US-ING-004 AC-6/8; ADR-025 approved runtime contract
// Task: 4.0l - Actual bundled vision model smoke test
// AC coverage: real pixels, bounded output and missing-artifact failure
// Evidence: simulator module test only; not PhotoKit E2E or final quality qualification
// Generated: 2026-09-09
// ==========================================

import CoreGraphics
import CoreML
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Echo

@Suite("4.0l Photo Runtime", .serialized)
struct PhotoRuntimeTests {
    @Test("AC-6: transposed Core ML outputs retain logical embedding order")
    func test_AC6_tensorStrides() throws {
        var storage: [Float] = [0, 1, 2, 3, 4, 5]
        let values = try storage.withUnsafeMutableBytes { bytes in
            let tensor = try MLMultiArray(
                dataPointer: #require(bytes.baseAddress),
                shape: [2, 3],
                dataType: .float32,
                strides: [1, 2],
                deallocator: nil
            )
            return PhotoTensorValues.logicalFloats(tensor)
        }
        #expect(values == [0, 2, 4, 1, 3, 5])
    }

    @Test("AC-6: real bundled visual inference produces a bounded caption without a description")
    func test_AC6_actualPixels() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("photo-runtime-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path.path + suffix) }
        }
        let db = DatabaseManager(databaseURL: path)
        try await db.open()
        let privacy = PrivacyActor(db: db)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["photo"]))
        let runtime = BundledPhotoUnderstandingActor(privacyActor: privacy)
        let before = try GenerationMemorySample.capture("before-photo")
        let started = ProcessInfo.processInfo.systemUptime
        let output = try await runtime.describe(imageData: Self.image(), traceID: "photo-runtime-smoke")
        let after = try GenerationMemorySample.capture("after-photo-release")
        let evidence: [String: Any] = [
            "scope": "simulator-native-module-only", "caption": output.text,
            "outputTokenCount": output.outputTokenCount,
            "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
            "beforePhysicalFootprint": before.physicalFootprintBytes,
            "afterReleasePhysicalFootprint": after.physicalFootprintBytes,
            "processPeakPhysicalFootprint": after.kernelPhysicalFootprintPeakBytes,
        ]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(
                to: FileManager.default.temporaryDirectory.appendingPathComponent("echo-photo-runtime-evidence.json")
            )
        #expect(!output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(output.text.utf8.count <= 4096)
        #expect(output.language == "en-US")
        #expect((1...128).contains(output.outputTokenCount))
        let repeated = try await runtime.describe(imageData: Self.image(), traceID: "photo-runtime-repeat")
        #expect(!repeated.text.isEmpty)
        let afterRepeat = try GenerationMemorySample.capture("after-repeat-release")
        #expect(afterRepeat.kernelPhysicalFootprintPeakBytes < 1_500_000_000)
        let missing = BundledPhotoUnderstandingActor(privacyActor: privacy, resourceRoot: nil)
        await #expect(throws: GenerationRuntimeError.invalidArtifact) {
            _ = try await missing.describe(imageData: Self.image(), traceID: "photo-model-missing")
        }
        // A failed model call must release ownership; an unrelated lease cannot release it.
        let lease = try await GenerativeModelSessionActor.shared.acquire()
        await GenerativeModelSessionActor.shared.release(UUID())
        await #expect(throws: NarrativeReportError.resourceDeferred) {
            _ = try await runtime.describe(imageData: Self.image(), traceID: "photo-resource-busy")
        }
        let textRuntime = BundledGenerationActor(resourceRoot: nil, privacyActor: privacy)
        await #expect(throws: NarrativeReportError.resourceDeferred) {
            try await textRuntime.validateAvailability(traceID: "text-resource-busy")
        }
        await GenerativeModelSessionActor.shared.release(lease)
        await db.close()
    }

    static func image(withText: Bool = false) throws -> Data {
        let width = 512
        let height = 256
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let radius = min(width, height) / 4
        for y in 0..<height {
            for x in 0..<width {
                if (x - width / 2) * (x - width / 2) + (y - height / 2) * (y - height / 2) <= radius * radius {
                    rgba[(y * width + x) * 4 + 1] = 0
                    rgba[(y * width + x) * 4 + 2] = 0
                }
            }
        }
        let color = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try #require(CGDataProvider(data: Data(rgba) as CFData))
        var image = try #require(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: color,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
        if withText {
            let context = try #require(
                CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: color,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(
                    string: "OPEN",
                    attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                            "Helvetica-Bold" as CFString,
                            32,
                            nil
                        ),
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
                    ]
                )
            )
            context.textPosition = CGPoint(x: 20, y: 20)
            CTLineDraw(line, context)
            image = try #require(context.makeImage())
        }
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
