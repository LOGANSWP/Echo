// Task 4.0l; US-ING-004 AC-8 / US-SYN-004: unprepared photos are not noData.
// Injected scheduler seam only, not real-model or PhotoKit E2E evidence.
// Generated: 2026-09-09
import Foundation
import Testing

@testable import Echo

private actor PhotoReportProbe: NarrativeReportGenerating {
    private(set) var requests: [NarrativeReportGenerationRequest] = []
    func generate(request: NarrativeReportGenerationRequest, traceID: String) async throws -> NarrativeReportEnvelope {
        requests.append(request)
        return NarrativeReportEnvelope(
            title: request.period.periodKey,
            periodType: request.period.periodType,
            periodKey: request.period.periodKey,
            paragraphs: [
                NarrativeReportParagraph(
                    id: UUID(),
                    text: "A red circle",
                    sourceMemoryIDs: request.sources.map(\.memoryID),
                    groundingStatus: .cited
                ),
            ],
            coverage: request.coverage
        )
    }
}

@Suite("4.0l Photo Report", .serialized)
struct PhotoReportTests {
    @Test("AC-8: pending photos wait and ready photo material publishes", arguments: [0, 1, 257])
    func test_AC8_pendingIsNotNoData(count: Int) async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("photo-report-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path.path + suffix) }
        }
        let db = DatabaseManager(databaseURL: path)
        try await db.open()
        let privacy = PrivacyActor(db: db)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["photo"]))
        let progress = ProgressActor(db: db)
        let generator = PhotoReportProbe()
        let queue = TaskQueueActor(progressActor: progress)
        let scheduler = NarrativeReportActor(
            database: db,
            privacyActor: privacy,
            taskQueue: queue,
            pendingOps: PendingOpsActor(db: db),
            generator: generator
        )
        let baseline = try #require(ISO8601DateFormatter().date(from: "2025-12-01T06:00:00Z"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"))
        try await db.executeWrite(
            sql: "UPDATE NarrativeReportSchedule SET monthlyEligibleFrom = ?, yearlyEnabled = 0",
            bindings: [.double(baseline.timeIntervalSince1970)]
        )
        let id = UUID()
        try await db.executeWrite(
            sql:
                "INSERT INTO Memory (memoryId, sourceLocator, sourceType, createdAt, updatedAt) VALUES (?, 'photo:report', 'photo', ?, ?)",
            bindings: [
                .text(id.uuidString), .double(baseline.timeIntervalSince1970 + 100),
                .double(baseline.timeIntervalSince1970 + 100),
            ]
        )
        if count == 257 {
            for index in 0..<256 {
                try await db.executeWrite(
                    sql: "INSERT INTO Memory (memoryId, sourceLocator, sourceType, createdAt, updatedAt) VALUES (?, ?, 'photo', ?, 1)",
                    bindings: [.text(UUID().uuidString), .text("photo:pending-\(index)"), .double(baseline.timeIntervalSince1970 + Double(index) / 10)]
                )
            }
        }
        if count > 0 {
            try await db.executeWrite(
                sql: "INSERT INTO Representation VALUES (?, ?, 'visionDense', 'siglip2-v1', 'source-v1')",
                bindings: [.text(UUID().uuidString), .text(id.uuidString)]
            )
            try await db.executeWrite(
                sql: """
                    INSERT INTO PhotoDerivedContent
                    (memoryId, kind, sourceVersion, modelVersion, processingVersion, language, state, body, updatedAt)
                    VALUES (?, 'caption', 'source-v1', ?, ?, 'en-US', 'ready', 'A red circle', ?)
                    """,
                bindings: [
                    .text(id.uuidString), .text(ApprovedPhotoUnderstandingArtifact.identity),
                    .text(ApprovedPhotoUnderstandingArtifact.processingVersion), .double(now.timeIntervalSince1970),
                ]
            )
            _ = try await scheduler.scanAndEnqueue(
                at: now,
                calendarContext: .init(timeZoneIdentifier: "America/Chicago"),
                trigger: .launch
            )
            for _ in 0..<200 {
                if await queue.ownedTaskIDs().isEmpty { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(await generator.requests.first?.sources.first?.text == "A red circle")
            #expect(await generator.requests.first?.coverage.truncatedSourceCount == (count == 257 ? 256 : 0))
            #expect(try await db.executeQuery(sql: "SELECT 1 FROM NarrativeReport", bindings: []).count == 1)
            #expect(try await db.executeQuery(sql: "SELECT 1 FROM PendingOperations", bindings: []).isEmpty)
            await db.close()
            return
        }
        for trigger in [NarrativeReportScanTrigger.launch, .foreground] {
            let result = try await scheduler.scanAndEnqueue(
                at: now,
                calendarContext: .init(timeZoneIdentifier: "America/Chicago"),
                trigger: trigger
            )
            #expect(result == .deferredForResources)
        }
        #expect(await generator.requests.isEmpty)
        #expect(
            try await db.executeQuery(
                sql: "SELECT 1 FROM NarrativeReportPeriod WHERE state IN ('noData','retryRequired','completed')",
                bindings: []
            ).isEmpty
        )
        #expect(try await db.executeQuery(sql: "SELECT 1 FROM PendingOperations", bindings: []).isEmpty)
        await db.close()
    }
}
