// ==========================================
// File: 4.0j_NarrativeReportSchedulerTests.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md → US-SYN-004
//       docs/decisions/ADR-021-narrative-report-scheduling-persistence.md
// Task: 4.0j - Persisted monthly and yearly narrative report scheduling
// AC coverage: AC-1 through AC-8
// Architecture: AGENTS.md §4.2, §4.3, §4.5, §7.3, §9.4
// Generated: 2026-09-07
// ==========================================

import Foundation
import Testing
@testable import Echo

private actor StubNarrativeReportGenerator: NarrativeReportGenerating {
    enum Mode: Sendable { case success, l2Failure, waitsForCancellation }
    private let mode: Mode
    private(set) var requests: [NarrativeReportGenerationRequest] = []

    init(mode: Mode) {
        self.mode = mode
    }

    func generate(
        request: NarrativeReportGenerationRequest,
        traceID: String
    ) async throws -> NarrativeReportEnvelope {
        requests.append(request)
        switch mode {
        case .success:
            break

        case .l2Failure:
            throw NarrativeReportError.generationUnavailable

        case .waitsForCancellation:
            try await Task.sleep(for: .seconds(30))
            throw NarrativeReportError.generationUnavailable
        }
        let ids = request.sources.map(\.memoryID)
        return NarrativeReportEnvelope(
            title: request.period.periodKey,
            periodType: request.period.periodType,
            periodKey: request.period.periodKey,
            paragraphs: [
                NarrativeReportParagraph(
                    id: ids.first ?? UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    text: request.sources.compactMap(\.text).joined(separator: " | "),
                    sourceMemoryIDs: ids,
                    groundingStatus: ids.isEmpty ? .noSource : .cited
                ),
            ],
            coverage: request.coverage
        )
    }
}

@Suite("4.0j Narrative Report Scheduler", .serialized)
struct NarrativeReportSchedulerTests {
    private func makeDatabase() async throws -> (DatabaseManager, PrivacyActor) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-4-0j-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let database = DatabaseManager(databaseURL: url)
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(UserPolicy(
            preferredLanguage: "en-US",
            authorizedSourceTypes: ["note", "photo", "voice", "video"],
            policyVersion: 11
        ))
        return (database, privacy)
    }

    @Test("AC-1/2: completed periods freeze civil boundaries and order month before year")
    func test_AC1_AC2_periodPlannerFreezesBoundariesAndOrdering() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
        let eligibleFrom = try #require(
            ISO8601DateFormatter().date(from: "2025-12-15T12:00:00Z")
        )
        let now = try #require(
            ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")
        )

        let periods = try NarrativeReportPeriodPlanner.completedPeriods(
            at: now,
            eligibleFrom: eligibleFrom,
            calendar: calendar
        )

        #expect(periods.map(\.periodType) == [.month, .year])
        #expect(periods.map(\.periodKey) == ["month:2025-12", "year:2025"])
        #expect(periods[0].coverageStart == eligibleFrom)
        #expect(periods[0].partialBaseline)
        #expect(periods[0].calendarIdentifier == "gregorian")
        #expect(periods[0].timeZoneIdentifier == "America/Chicago")
        #expect(periods[0].endInstant == periods[1].endInstant)
        #expect(periods.allSatisfy { $0.endInstant > eligibleFrom })
    }

    @Test("AC-1: schedule defaults on and re-enabling resets the eligibility baseline")
    func test_AC1_schedulePersistenceAndReenableBaseline() async throws {
        let (database, privacy) = try await makeDatabase()
        let actor = NarrativeReportActor(database: database, privacyActor: privacy)
        let initial = try await actor.loadSchedule()
        #expect(initial.monthlyEnabled)
        #expect(initial.yearlyEnabled)
        #expect(initial.monthlyEligibleFrom == nil)
        #expect(initial.yearlyEligibleFrom == nil)

        let firstBaseline = Date(timeIntervalSince1970: 1_700_000_000)
        try await database.executeWrite(
            sql: "INSERT OR REPLACE INTO ConsentStore (id, hasConsented, consentVersion, consentedAt, policyVersion, updatedAt) VALUES (1, 1, 1, ?, 11, ?)",
            bindings: [.double(firstBaseline.timeIntervalSince1970), .double(firstBaseline.timeIntervalSince1970)]
        )
        try await database.executeWrite(
            sql: "INSERT INTO Memory (memoryId, sourceLocator, canonicalText, sourceType, createdAt, updatedAt, recoverability) VALUES (?, ?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(UUID().uuidString), .text("private-note-locator"), .text("A local memory"),
                .text("note"), .double(firstBaseline.timeIntervalSince1970),
                .double(firstBaseline.timeIntervalSince1970), .text("full"),
            ]
        )

        #expect(try await actor.establishEligibilityIfNeeded(at: firstBaseline))
        #expect(try await actor.loadSchedule().monthlyEligibleFrom == firstBaseline)
        #expect(try await actor.loadSchedule().yearlyEligibleFrom == firstBaseline)

        let disabledAt = firstBaseline.addingTimeInterval(60)
        try await actor.setEnabled(false, for: .month, at: disabledAt)
        #expect(try await actor.loadSchedule().monthlyEnabled == false)

        let reenabledAt = disabledAt.addingTimeInterval(60)
        try await actor.setEnabled(true, for: .month, at: reenabledAt)
        let reopened = try await actor.loadSchedule()
        #expect(reopened.monthlyEnabled)
        #expect(reopened.yearlyEnabled)
        #expect(reopened.monthlyEligibleFrom == reenabledAt)
        #expect(reopened.yearlyEligibleFrom == firstBaseline)
    }

    @Test("AC-1: disabled schedules cannot claim stale periods or backfill after re-enable")
    func test_AC1_disabledScheduleSkipsMaterializedPeriods() async throws {
        let (database, privacy) = try await makeDatabase()
        let queue = TaskQueueActor(progressActor: ProgressActor(db: database))
        let actor = NarrativeReportActor(
            database: database,
            privacyActor: privacy,
            taskQueue: queue,
            pendingOps: PendingOpsActor(db: database)
        )
        let baseline = try #require(ISO8601DateFormatter().date(from: "2025-11-15T12:00:00Z"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"))
        try await database.executeWrite(
            sql: "UPDATE NarrativeReportSchedule SET monthlyEligibleFrom = ?, yearlyEligibleFrom = ? WHERE id = 1",
            bindings: [.double(baseline.timeIntervalSince1970), .double(baseline.timeIntervalSince1970)]
        )
        let calendar = NarrativeReportCalendarContext(timeZoneIdentifier: "America/Chicago")

        let first = try #require(try await actor.materializeAndClaimNext(
            at: now,
            calendarContext: calendar,
            trigger: .foreground,
            taskID: "disabled-schedule-first"
        ))
        #expect(first.periodKey == "month:2025-11")
        try await actor.setEnabled(false, for: .month, at: now)
        try await actor.releaseClaimForResource(taskID: "disabled-schedule-first")

        let whileDisabled = try #require(try await actor.materializeAndClaimNext(
            at: now,
            calendarContext: calendar,
            trigger: .foreground,
            taskID: "disabled-schedule-year"
        ))
        #expect(whileDisabled.periodKey == "year:2025")

        let reenabledAt = now.addingTimeInterval(60)
        try await actor.setEnabled(true, for: .month, at: reenabledAt)
        let afterReenable = try await actor.materializeAndClaimNext(
            at: reenabledAt,
            calendarContext: calendar,
            trigger: .foreground,
            taskID: "disabled-schedule-after-reenable"
        )
        #expect(afterReenable == nil)
        let staleMonthlyRows = try await database.executeQuery(
            sql: "SELECT state FROM NarrativeReportPeriod WHERE periodType = 'month'",
            bindings: []
        )
        #expect(!staleMonthlyRows.isEmpty)
        #expect(staleMonthlyRows.allSatisfy { $0["state"]?.stringValue == "eligible" })
    }

    @Test("AC-1: eligibility establishment is a no-op when only a disabled baseline is missing")
    func test_AC1_disabledMissingBaselineDoesNotAdvanceRevision() async throws {
        let (database, privacy) = try await makeDatabase()
        let actor = NarrativeReportActor(database: database, privacyActor: privacy)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try await database.executeWrite(
            sql: "INSERT OR REPLACE INTO ConsentStore (id, hasConsented, consentVersion, consentedAt, policyVersion, updatedAt) VALUES (1, 1, 1, ?, 11, ?)",
            bindings: [.double(now.timeIntervalSince1970), .double(now.timeIntervalSince1970)]
        )
        try await insertMemory(UUID(), into: database, at: now)
        try await actor.setEnabled(false, for: .month, at: now)

        #expect(try await actor.establishEligibilityIfNeeded(at: now))
        #expect(try await actor.loadSchedule().monthlyEligibleFrom == nil)
        #expect(try await actor.loadSchedule().yearlyEligibleFrom == now)
        #expect(try await actor.establishEligibilityIfNeeded(at: now.addingTimeInterval(60)) == false)
    }

    @Test("AC-4: low-power deferral respects the user's independent auto-pause setting")
    func test_AC4_lowPowerResourcePolicyRespectsUserSetting() async {
        let deferred = await AppDelegate.narrativeReportResourceAvailability(
            lowPowerModeEnabled: true,
            autoPauseOnLowPowerEnabled: true,
            thermallyConstrained: false
        )
        let userAllowsWork = await AppDelegate.narrativeReportResourceAvailability(
            lowPowerModeEnabled: true,
            autoPauseOnLowPowerEnabled: false,
            thermallyConstrained: false
        )
        let thermalStillDefers = await AppDelegate.narrativeReportResourceAvailability(
            lowPowerModeEnabled: true,
            autoPauseOnLowPowerEnabled: false,
            thermallyConstrained: true
        )

        #expect(deferred == .lowPower)
        #expect(userAllowsWork == .available)
        #expect(thermalStillDefers == .thermalConstrained)
    }

    @Test("AC-4: unavailable production generation fails closed before claiming a period")
    func test_AC4_unavailableGeneratorDoesNotCreateFalseL2Work() async throws {
        let (database, privacy) = try await makeDatabase()
        let pending = PendingOpsActor(db: database)
        let actor = NarrativeReportActor(
            database: database,
            privacyActor: privacy,
            taskQueue: TaskQueueActor(progressActor: ProgressActor(db: database)),
            pendingOps: pending
        )
        let baseline = try #require(ISO8601DateFormatter().date(from: "2025-12-01T06:00:00Z"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"))
        try await database.executeWrite(
            sql: "UPDATE NarrativeReportSchedule SET monthlyEligibleFrom = ?, yearlyEnabled = 0",
            bindings: [.double(baseline.timeIntervalSince1970)]
        )
        try await insertMemory(UUID(), into: database, at: baseline.addingTimeInterval(3_600))

        let result = try await actor.scanAndEnqueue(
            at: now,
            calendarContext: .init(timeZoneIdentifier: "America/Chicago"),
            trigger: .foreground
        )

        #expect(result == .generationUnavailable)
        #expect(try await count("NarrativeReportPeriod", in: database) == 0)
        #expect(try await pending.count() == 0)
    }

    @Test("AC-2: concurrent scans CAS-claim only one earliest eligible period")
    func test_AC2_concurrentScansClaimOneEarliestPeriod() async throws {
        let (database, privacy) = try await makeDatabase()
        let actorA = NarrativeReportActor(database: database, privacyActor: privacy)
        let actorB = NarrativeReportActor(database: database, privacyActor: privacy)
        let baseline = try #require(ISO8601DateFormatter().date(from: "2025-11-15T12:00:00Z"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"))
        try await database.executeWrite(
            sql: "UPDATE NarrativeReportSchedule SET monthlyEligibleFrom = ?, yearlyEligibleFrom = ? WHERE id = 1",
            bindings: [.double(baseline.timeIntervalSince1970), .double(baseline.timeIntervalSince1970)]
        )
        let calendarContext = NarrativeReportCalendarContext(
            timeZoneIdentifier: "America/Chicago"
        )

        async let first = actorA.materializeAndClaimNext(
            at: now,
            calendarContext: calendarContext,
            trigger: .foreground,
            taskID: "report-task-a"
        )
        async let second = actorB.materializeAndClaimNext(
            at: now,
            calendarContext: calendarContext,
            trigger: .background,
            taskID: "report-task-b"
        )
        let claims = try await [first, second].compactMap { $0 }

        #expect(claims.count == 2)
        #expect(Set(claims.map(\.periodKey)).count == 2)
        #expect(claims.map(\.periodKey).sorted() == ["month:2025-11", "month:2025-12"])
        #expect(claims.allSatisfy { $0.state == .claimed })
        let rows = try await database.executeQuery(
            sql: "SELECT periodKey, state FROM NarrativeReportPeriod WHERE state = 'claimed' ORDER BY endInstant, periodType",
            bindings: []
        )
        #expect(rows.count == 2)
    }

    @Test("AC-3/8: publication atomically commits report, sources, completion and typed audit")
    func test_AC3_AC8_atomicPublicationAndTypedAudit() async throws {
        let (database, privacy) = try await makeDatabase()
        let sourceID = UUID()
        let now = Date(timeIntervalSince1970: 1_767_268_800)
        try await insertMemory(sourceID, into: database, at: now)
        let period = try await insertClaimedPeriod(into: database, now: now)
        let checkpoint = await privacy.validate(
            operation: .search,
            traceID: "narrative-publication-trace",
            sourceTypes: ["note"]
        )
        let audit = try await privacy.prepareNarrativeReportAuditPayload(
            checkpoint: checkpoint,
            period: period,
            sourceTypes: ["note", "note"]
        )
        let envelope = makeEnvelope(period: period, sourceID: sourceID)

        try await database.publishNarrativeReport(NarrativeReportPublication(
            period: period,
            envelope: envelope,
            sources: [NarrativeReportSource(memoryID: sourceID, sourceType: "note", ordinal: 0)],
            audit: audit,
            createdAt: now
        ))

        #expect(try await count("NarrativeReport", in: database) == 1)
        #expect(try await count("NarrativeReportSource", in: database) == 1)
        let periodRows = try await database.executeQuery(
            sql: "SELECT state, taskId FROM NarrativeReportPeriod WHERE periodKey = ?",
            bindings: [.text(period.periodKey)]
        )
        #expect(periodRows.first?["state"]?.stringValue == "completed")
        #expect(periodRows.first?["taskId"]?.stringValue == nil)

        let logs = try await privacy.fetchAuditLogs(eventType: .narrativeReportGenerated)
        let log = try #require(logs.first)
        #expect(log.periodType == "month")
        #expect(log.dataSourcesUsed == #"["note"]"#)
        #expect(log.periodKeyDigest == audit.periodKeyDigest)
        #expect(log.periodKeyDigest?.count == 64)
        #expect(log.contentHash == nil)
        #expect(log.memoryIdDigest == nil)
        #expect(log.shareHandoffIdDigest == nil)
    }

    @Test("AC-3: every publication-stage failure rolls back all visible success")
    func test_AC3_publicationFailureRollsBackEveryStage() async throws {
        for stage in NarrativePublicationFailureStage.allCases {
            let (database, privacy) = try await makeDatabase()
            let sourceID = UUID()
            let now = Date(timeIntervalSince1970: 1_767_268_800)
            try await insertMemory(sourceID, into: database, at: now)
            let period = try await insertClaimedPeriod(into: database, now: now)
            let checkpoint = await privacy.validate(
                operation: .search,
                traceID: "rollback-\(stage)",
                sourceTypes: ["note"]
            )
            let audit = try await privacy.prepareNarrativeReportAuditPayload(
                checkpoint: checkpoint,
                period: period,
                sourceTypes: ["note"]
            )
            await database.setNarrativePublicationFailureStageForTesting(stage)

            await #expect(throws: NarrativeReportError.injectedPublicationFailure) {
                try await database.publishNarrativeReport(NarrativeReportPublication(
                    period: period,
                    envelope: makeEnvelope(period: period, sourceID: sourceID),
                    sources: [NarrativeReportSource(memoryID: sourceID, sourceType: "note", ordinal: 0)],
                    audit: audit,
                    createdAt: now
                ))
            }

            #expect(try await count("NarrativeReport", in: database) == 0)
            #expect(try await count("NarrativeReportSource", in: database) == 0)
            #expect(try await countNarrativeAudit(in: database) == 0)
            let rows = try await database.executeQuery(
                sql: "SELECT state FROM NarrativeReportPeriod WHERE periodKey = ?",
                bindings: [.text(period.periodKey)]
            )
            #expect(rows.first?["state"]?.stringValue == "claimed")
        }
    }

    @Test("AC-4/5/6: queued generation is bounded, grounded, persisted and recoverable")
    func test_AC4_AC5_AC6_queuedBoundedGroundedGeneration() async throws {
        let (database, privacy) = try await makeDatabase()
        let progress = ProgressActor(db: database)
        let queue = TaskQueueActor(progressActor: progress)
        let pending = PendingOpsActor(db: database)
        let generator = StubNarrativeReportGenerator(mode: .success)
        let actor = NarrativeReportActor(
            database: database,
            privacyActor: privacy,
            taskQueue: queue,
            pendingOps: pending,
            generator: generator,
            omittedPartitions: ["people", "healthKit"]
        )
        let baseline = try #require(ISO8601DateFormatter().date(from: "2025-12-01T06:00:00Z"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"))
        try await database.executeWrite(
            sql: "UPDATE NarrativeReportSchedule SET monthlyEligibleFrom = ?, yearlyEnabled = 0",
            bindings: [.double(baseline.timeIntervalSince1970)]
        )
        let sourceID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        try await insertMemory(sourceID, into: database, at: baseline.addingTimeInterval(3_600))

        let result = try await actor.scanAndEnqueue(
            at: now,
            calendarContext: .init(timeZoneIdentifier: "America/Chicago"),
            trigger: .foreground
        )
        guard case .enqueued(let taskID, let periodKey) = result else {
            Issue.record("Expected a queued narrative report")
            return
        }
        #expect(periodKey == "month:2025-12")
        try await waitUntil { try await self.count("NarrativeReport", in: database) == 1 }
        #expect(try await progress.load(taskId: taskID) == nil)

        let request = try #require(await generator.requests.first)
        #expect(request.sources.map(\.memoryID) == [sourceID])
        #expect(request.sourceBatches.count <= NarrativeReportLimits.maximumBatches)
        #expect(request.sources.count <= NarrativeReportLimits.maximumSources)
        #expect(request.sources.allSatisfy {
            ($0.text?.count ?? 0) <= NarrativeReportLimits.maximumExcerptCharacters
        })
        #expect(request.coverage.omittedPartitions == ["healthKit", "people"])
        #expect(request.coverage.submittedSourceCount == 1)
        let reports = try await actor.listReports()
        let report = try #require(reports.first)
        #expect(report.envelope.paragraphs.first?.groundingStatus == .cited)
        #expect(report.envelope.paragraphs.first?.sourceMemoryIDs == [sourceID])

        let descriptor = try NarrativeReportResumePayload(
            periodType: .month,
            periodKey: periodKey
        ).encodedDescriptor(sourceTypes: ["note"])
        #expect(descriptor.count <= TaskResumeDescriptor.maximumEncodedBytes)
        #expect(!(String(data: descriptor, encoding: .utf8) ?? "")
            .contains("A private local memory"))
    }

    @Test("AC-3/4: noData is terminal for automatic scans and writes no generation audit")
    func test_AC3_AC4_noDataDoesNotGenerateOrAudit() async throws {
        let (database, privacy) = try await makeDatabase()
        let progress = ProgressActor(db: database)
        let actor = NarrativeReportActor(
            database: database,
            privacyActor: privacy,
            taskQueue: TaskQueueActor(progressActor: progress),
            pendingOps: PendingOpsActor(db: database),
            generator: StubNarrativeReportGenerator(mode: .success)
        )
        let baseline = try #require(ISO8601DateFormatter().date(from: "2025-12-01T06:00:00Z"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"))
        try await database.executeWrite(
            sql: "UPDATE NarrativeReportSchedule SET monthlyEligibleFrom = ?, yearlyEnabled = 0",
            bindings: [.double(baseline.timeIntervalSince1970)]
        )

        let result = try await actor.scanAndEnqueue(
            at: now,
            calendarContext: .init(timeZoneIdentifier: "America/Chicago"),
            trigger: .launch
        )
        #expect(result == .noData(periodKey: "month:2025-12"))
        #expect(try await count("NarrativeReport", in: database) == 0)
        #expect(try await countNarrativeAudit(in: database) == 0)
        let second = try await actor.scanAndEnqueue(
            at: now,
            calendarContext: .init(timeZoneIdentifier: "America/Chicago"),
            trigger: .foreground
        )
        #expect(second == .none)
    }

    @Test("AC-4: L2 waits for explicit retry while resource pressure only defers")
    func test_AC4_manualL2RetryAndResourceDeferral() async throws {
        let (database, privacy) = try await makeDatabase()
        let progress = ProgressActor(db: database)
        let queue = TaskQueueActor(progressActor: progress)
        let pending = PendingOpsActor(db: database)
        let failingActor = NarrativeReportActor(
            database: database,
            privacyActor: privacy,
            taskQueue: queue,
            pendingOps: pending,
            generator: StubNarrativeReportGenerator(mode: .l2Failure)
        )
        let baseline = try #require(ISO8601DateFormatter().date(from: "2025-12-01T06:00:00Z"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"))
        try await database.executeWrite(
            sql: "UPDATE NarrativeReportSchedule SET monthlyEligibleFrom = ?, yearlyEnabled = 0",
            bindings: [.double(baseline.timeIntervalSince1970)]
        )
        try await insertMemory(UUID(), into: database, at: baseline.addingTimeInterval(3_600))

        let deferred = try await failingActor.scanAndEnqueue(
            at: now,
            calendarContext: .init(timeZoneIdentifier: "America/Chicago"),
            trigger: .background,
            resources: .lowPower
        )
        #expect(deferred == .deferredForResources)
        #expect(try await count("NarrativeReportPeriod", in: database) == 0)

        _ = try await failingActor.scanAndEnqueue(
            at: now,
            calendarContext: .init(timeZoneIdentifier: "America/Chicago"),
            trigger: .foreground
        )
        try await waitUntil {
            let rows = try await database.executeQuery(
                sql: "SELECT state FROM NarrativeReportPeriod WHERE periodKey = 'month:2025-12'",
                bindings: []
            )
            return rows.first?["state"]?.stringValue == "retryRequired"
        }
        #expect(try await pending.count() == 1)

        let automatic = try await failingActor.scanAndEnqueue(
            at: now,
            calendarContext: .init(timeZoneIdentifier: "America/Chicago"),
            trigger: .launch
        )
        #expect(automatic == .none)

        let succeedingActor = NarrativeReportActor(
            database: database,
            privacyActor: privacy,
            taskQueue: queue,
            pendingOps: pending,
            generator: StubNarrativeReportGenerator(mode: .success)
        )
        _ = try await succeedingActor.retryReport(
            periodType: .month,
            periodKey: "month:2025-12"
        )
        try await waitUntil { try await self.count("NarrativeReport", in: database) == 1 }
        #expect(try await pending.count() == 0)
    }

    @Test("AC-4: retry enqueue failure returns the period to manual L2")
    func test_AC4_retryEnqueueFailureDoesNotLeaveClaimOrphaned() async throws {
        let (database, privacy) = try await makeDatabase()
        let pending = PendingOpsActor(db: database)
        let unopenedDatabase = DatabaseManager(
            databaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("echo-4-0j-unopened-\(UUID().uuidString)")
                .appendingPathExtension("sqlite")
        )
        let actor = NarrativeReportActor(
            database: database,
            privacyActor: privacy,
            taskQueue: TaskQueueActor(progressActor: ProgressActor(db: unopenedDatabase)),
            pendingOps: pending,
            generator: StubNarrativeReportGenerator(mode: .success)
        )
        let now = Date(timeIntervalSince1970: 1_767_268_800)
        let sourceID = UUID()
        try await insertMemory(sourceID, into: database, at: now.addingTimeInterval(-3_600))
        let period = try await insertClaimedPeriod(into: database, now: now)
        try await database.executeWrite(
            sql: "UPDATE NarrativeReportPeriod SET state = 'retryRequired', claimedAt = NULL, taskId = NULL WHERE periodType = ? AND periodKey = ?",
            bindings: [.text(period.periodType.rawValue), .text(period.periodKey)]
        )

        await #expect(throws: (any Error).self) {
            try await actor.retryReport(periodType: period.periodType, periodKey: period.periodKey)
        }

        let rows = try await database.executeQuery(
            sql: "SELECT state, taskId FROM NarrativeReportPeriod WHERE periodType = ? AND periodKey = ?",
            bindings: [.text(period.periodType.rawValue), .text(period.periodKey)]
        )
        #expect(rows.first?["state"]?.stringValue == "retryRequired")
        #expect(rows.first?["taskId"]?.stringValue == nil)
        #expect(try await pending.count() == 1)
    }

    @Test("AC-4: system expiration cancels before releasing claim and creates no L2")
    func test_AC4_systemExpirationDefersWithoutFalseRetry() async throws {
        let (database, privacy) = try await makeDatabase()
        let progress = ProgressActor(db: database)
        let queue = TaskQueueActor(progressActor: progress)
        let pending = PendingOpsActor(db: database)
        let actor = NarrativeReportActor(
            database: database,
            privacyActor: privacy,
            taskQueue: queue,
            pendingOps: pending,
            generator: StubNarrativeReportGenerator(mode: .waitsForCancellation)
        )
        let baseline = try #require(ISO8601DateFormatter().date(from: "2025-12-01T06:00:00Z"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"))
        try await database.executeWrite(
            sql: "UPDATE NarrativeReportSchedule SET monthlyEligibleFrom = ?, yearlyEnabled = 0",
            bindings: [.double(baseline.timeIntervalSince1970)]
        )
        try await insertMemory(UUID(), into: database, at: baseline.addingTimeInterval(3_600))

        let result = try await actor.scanAndEnqueue(
            at: now,
            calendarContext: .init(timeZoneIdentifier: "America/Chicago"),
            trigger: .background
        )
        guard case .enqueued(let taskID, _) = result else {
            Issue.record("Expected an enqueued background report")
            return
        }
        try await waitUntil { await queue.activeTaskIDs().contains(taskID) }

        try await actor.releaseClaimForResource(taskID: taskID)

        let rows = try await database.executeQuery(
            sql: "SELECT state, taskId FROM NarrativeReportPeriod WHERE periodKey = 'month:2025-12'",
            bindings: []
        )
        #expect(rows.first?["state"]?.stringValue == "eligible")
        #expect(rows.first?["taskId"]?.stringValue == nil)
        #expect(try await progress.load(taskId: taskID) == nil)
        #expect(try await pending.count() == 0)
        #expect(try await count("NarrativeReport", in: database) == 0)
    }

    @Test("AC-7: user deletion and source deletion invalidate reports without regeneration")
    func test_AC7_reportAndMemoryDeletionInvalidatePeriod() async throws {
        for deleteSource in [false, true] {
            let (database, privacy) = try await makeDatabase()
            let actor = NarrativeReportActor(
                database: database,
                privacyActor: privacy,
                generator: StubNarrativeReportGenerator(mode: .success)
            )
            let sourceID = UUID()
            let now = Date(timeIntervalSince1970: 1_767_268_800)
            try await insertMemory(sourceID, into: database, at: now)
            let period = try await insertClaimedPeriod(into: database, now: now)
            let reportID = try await publish(
                period: period,
                sourceID: sourceID,
                at: now,
                database: database,
                privacy: privacy
            )

            if deleteSource {
                try await database.executeWrite(
                    sql: "DELETE FROM Memory WHERE memoryId = ?",
                    bindings: [.text(sourceID.uuidString)]
                )
            } else {
                try await actor.deleteReport(reportID: reportID)
            }

            #expect(try await count("NarrativeReport", in: database) == 0)
            #expect(try await count("NarrativeReportSource", in: database) == 0)
            let rows = try await database.executeQuery(
                sql: "SELECT state FROM NarrativeReportPeriod WHERE periodKey = ?",
                bindings: [.text(period.periodKey)]
            )
            #expect(rows.first?["state"]?.stringValue == "invalidated")
            #expect(try await actor.scanAndEnqueue(
                at: now.addingTimeInterval(86_400),
                calendarContext: .init(timeZoneIdentifier: "America/Chicago"),
                trigger: .foreground
            ) == .none)
        }
    }

    @Test("AC-7: full consent revocation clears every narrative-report table")
    func test_AC7_consentRevocationPurgesNarrativeState() async throws {
        let (database, privacy) = try await makeDatabase()
        let consent = ConsentStoreActor(db: database, privacyActor: privacy)
        try await consent.loadState()
        try await consent.acceptConsent(consentVersion: 1, policyVersion: 11)
        let sourceID = UUID()
        let now = Date(timeIntervalSince1970: 1_767_268_800)
        try await insertMemory(sourceID, into: database, at: now)
        let period = try await insertClaimedPeriod(into: database, now: now)
        _ = try await publish(
            period: period,
            sourceID: sourceID,
            at: now,
            database: database,
            privacy: privacy
        )

        let result = try await consent.revokeConsent()

        #expect(result.success)
        #expect(try await count("NarrativeReportSchedule", in: database) == 0)
        #expect(try await count("NarrativeReportPeriod", in: database) == 0)
        #expect(try await count("NarrativeReport", in: database) == 0)
        #expect(try await count("NarrativeReportSource", in: database) == 0)
    }

    private func insertMemory(
        _ id: UUID,
        into database: DatabaseManager,
        at date: Date
    ) async throws {
        try await database.executeWrite(
            sql: "INSERT INTO Memory (memoryId, sourceLocator, canonicalText, sourceType, createdAt, updatedAt, recoverability) VALUES (?, ?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(id.uuidString), .text("private-source"), .text("A private local memory"),
                .text("note"), .double(date.timeIntervalSince1970),
                .double(date.timeIntervalSince1970), .text("full"),
            ]
        )
    }

    private func insertClaimedPeriod(
        into database: DatabaseManager,
        now: Date
    ) async throws -> NarrativeReportPeriod {
        let start = now.addingTimeInterval(-31 * 86_400)
        let period = NarrativeReportPeriod(
            periodType: .month,
            periodKey: "month:2025-12",
            calendarIdentifier: "gregorian",
            timeZoneIdentifier: "America/Chicago",
            startInstant: start,
            endInstant: now,
            coverageStart: start,
            partialBaseline: false,
            state: .claimed,
            revision: 1,
            claimedAt: now,
            taskID: "narrative-task"
        )
        try await database.executeWrite(
            sql: """
                INSERT INTO NarrativeReportPeriod
                  (periodType, periodKey, calendarIdentifier, timeZoneIdentifier,
                   startInstant, endInstant, coverageStart, partialBaseline, state,
                   revision, claimedAt, taskId, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, 0, 'claimed', 1, ?, ?, ?)
                """,
            bindings: [
                .text(period.periodType.rawValue), .text(period.periodKey),
                .text(period.calendarIdentifier), .text(period.timeZoneIdentifier),
                .double(period.startInstant.timeIntervalSince1970),
                .double(period.endInstant.timeIntervalSince1970),
                .double(period.coverageStart.timeIntervalSince1970),
                .double(now.timeIntervalSince1970), .text(period.taskID ?? ""),
                .double(now.timeIntervalSince1970),
            ]
        )
        return period
    }

    private func makeEnvelope(
        period: NarrativeReportPeriod,
        sourceID: UUID
    ) -> NarrativeReportEnvelope {
        NarrativeReportEnvelope(
            title: period.periodKey,
            periodType: period.periodType,
            periodKey: period.periodKey,
            paragraphs: [
                NarrativeReportParagraph(
                    id: UUID(),
                    text: "A grounded paragraph.",
                    sourceMemoryIDs: [sourceID],
                    groundingStatus: .cited
                ),
            ],
            coverage: NarrativeReportCoverage(
                partialBaseline: period.partialBaseline,
                coverageStart: period.coverageStart,
                coverageEnd: period.endInstant,
                submittedSourceCount: 1
            )
        )
    }

    private func publish(
        period: NarrativeReportPeriod,
        sourceID: UUID,
        at now: Date,
        database: DatabaseManager,
        privacy: PrivacyActor
    ) async throws -> UUID {
        let checkpoint = await privacy.validate(
            operation: .search,
            traceID: UUID().uuidString,
            sourceTypes: ["note"]
        )
        let audit = try await privacy.prepareNarrativeReportAuditPayload(
            checkpoint: checkpoint,
            period: period,
            sourceTypes: ["note"]
        )
        let reportID = UUID()
        try await database.publishNarrativeReport(NarrativeReportPublication(
            reportID: reportID,
            period: period,
            envelope: makeEnvelope(period: period, sourceID: sourceID),
            sources: [NarrativeReportSource(memoryID: sourceID, sourceType: "note", ordinal: 0)],
            audit: audit,
            createdAt: now
        ))
        return reportID
    }

    private func count(_ table: String, in database: DatabaseManager) async throws -> Int {
        let rows = try await database.executeQuery(
            sql: "SELECT COUNT(*) AS count FROM \(table)",
            bindings: []
        )
        return Int(rows.first?["count"]?.intValue ?? 0)
    }

    private func countNarrativeAudit(in database: DatabaseManager) async throws -> Int {
        let rows = try await database.executeQuery(
            sql: "SELECT COUNT(*) AS count FROM AuditLog WHERE eventType = 'narrativeReportGenerated'",
            bindings: []
        )
        return Int(rows.first?["count"]?.intValue ?? 0)
    }

    private func waitUntil(
        _ predicate: @escaping @Sendable () async throws -> Bool
    ) async throws {
        for _ in 0..<100 {
            if try await predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for narrative report state")
    }
}
