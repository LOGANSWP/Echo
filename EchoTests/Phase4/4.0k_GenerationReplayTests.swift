// ==========================================
// File: 4.0k_GenerationReplayTests.swift
// Spec: US-SYN-004; ADR-023 section 5
// Task: 4.0k - Rebuild lost in-memory generation prefixes
// AC coverage: preserved checkpoints, actual replay calls and cancellation
// Evidence scope: contract tests with an explicit model double
// Generated: 2026-09-08
// ==========================================

import Foundation
import Testing

@testable import Echo

private actor ReplayRecordingProvider: StructuredLLMProvider {
    let progress: ProgressActor
    let cancelFirst: Bool
    private(set) var requests: [GenerationRequest] = []
    private(set) var observedIndexes: [Int] = []

    init(progress: ProgressActor, cancelFirst: Bool) {
        self.progress = progress
        self.cancelFirst = cancelFirst
    }

    func validateAvailability(traceID: String) async throws {}
    func tokenCount(request: GenerationRequest) async throws -> Int { 300 }
    func generate(prompt: String, preferredLanguage: String) async throws -> String {
        throw GenerationRuntimeError.invalidRequest
    }

    func generate(request: GenerationRequest) async throws -> GenerationResult {
        requests.append(request)
        observedIndexes.append(try await progress.load(taskId: "replay")?.lastProcessedIndex ?? -1)
        if cancelFirst { throw CancellationError() }
        let ids = request.allowedMemoryIDs.map { "\"\($0.uuidString)\"" }.joined(separator: ",")
        return GenerationResult(
            envelope:
                "{\"schemaVersion\":1,\"paragraphs\":[{\"text\":\"The family walked together in the garden during the afternoon.\",\"sourceMemoryIDs\":[\(ids)]}]}",
            inputTokenCount: 300,
            outputTokenCount: 80,
            predictionCount: 379,
            elapsedSeconds: 1,
            artifactIdentity: "explicit-test-double"
        )
    }
}

@Suite("4.0k Generation Replay", .serialized)
@MainActor
struct GenerationReplayTests {
    @Test("AC-7: Continue rebuilds the missing prefix without resetting progress", arguments: [false, true])
    func test_AC7_replayPreservesCheckpoint(cancelFirst: Bool) async throws {
        let database = DatabaseManager(
            databaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("4.0k-replay-\(UUID().uuidString).sqlite")
        )
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["note"]))
        let progress = ProgressActor(db: database)
        let descriptor = try TaskResumeDescriptor(operation: .search, sourceTypes: ["note"], payload: Data()).encoded()
        try await progress.save(
            progress: TaskProgress(
                taskId: "replay",
                taskType: .narrativeReport,
                lastProcessedIndex: 1,
                totalCount: 2,
                resumeData: descriptor
            )
        )
        let provider = ReplayRecordingProvider(progress: progress, cancelFirst: cancelFirst)
        let pipeline = CreativePipeline(
            llmProvider: provider,
            aligner: LanguageAligner(llmProvider: provider),
            privacyActor: privacy
        )
        let generator = CreativeNarrativeReportGenerator(pipeline: pipeline)
        let sources = (0..<2).map { _ in
            CreativeSource(
                memoryID: UUID(),
                assetID: "",
                sourceType: "note",
                text: "The family walked in the garden.",
                timestamp: 1
            )
        }
        let start = Date(timeIntervalSince1970: 1_764_547_200)
        let end = Date(timeIntervalSince1970: 1_767_225_600)
        let period = NarrativeReportPeriod(
            periodType: .month,
            periodKey: "month:2025-12",
            calendarIdentifier: "gregorian",
            timeZoneIdentifier: "UTC",
            startInstant: start,
            endInstant: end,
            coverageStart: start,
            partialBaseline: false,
            state: .claimed,
            revision: 1,
            claimedAt: end,
            taskID: "replay"
        )
        let request = NarrativeReportGenerationRequest(
            period: period,
            sourceBatches: sources.map { [$0] },
            coverage: NarrativeReportCoverage(
                partialBaseline: false,
                coverageStart: start,
                coverageEnd: end,
                submittedSourceCount: 2
            )
        )
        let context = TaskQueueActor.TaskContext(taskId: "replay", progressActor: progress, pauseToken: PauseToken())
        if cancelFirst {
            await #expect(throws: CancellationError.self) {
                try await generator.generate(request: request, context: context, traceID: "replay")
            }
            #expect(await provider.observedIndexes == [1])
            #expect(try await progress.load(taskId: "replay")?.lastProcessedIndex == 1)
        } else {
            let report = try await generator.generate(request: request, context: context, traceID: "replay")
            #expect(report.modelCallCount == 3)
            #expect(await provider.observedIndexes == [1, 1, 2])
            #expect(try await progress.load(taskId: "replay")?.lastProcessedIndex == 2)
        }
        #expect(await provider.requests.first?.allowedMemoryIDs == [sources[0].memoryID])
        #expect(try await progress.load(taskId: "replay")?.resumeData == descriptor)
    }
}
