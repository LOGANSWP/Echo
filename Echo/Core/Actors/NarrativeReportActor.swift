// ==========================================
// File: NarrativeReportActor.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md → US-SYN-004
//       docs/decisions/ADR-021-narrative-report-scheduling-persistence.md
//       docs/decisions/ADR-022-offline-generation-runtime-gate.md
// Task: 4.0j - Persisted narrative report scheduling and storage foundation
// AC coverage: AC-1/2 plus the scheduling/publication seams for AC-3/4/6/7/8;
//              production generation and AC-5 close in task 4.0k
// Architecture: AGENTS.md §4.2, §4.3, §4.5, §7.3
// Generated: 2026-09-07
// Task 4.0k (2026-09-08): approved provider gate, snapshot identity, resource deferral and actual contributors.
// Traceability: US-SYN-001/004 and ADR-023; device/quality qualification remains pending.
// ==========================================

import Foundation

nonisolated public protocol NarrativeReportGenerating: Sendable {
    nonisolated var maximumSourceCount: Int { get }
    func configurationIdentity(traceID: String) async throws -> String
    func validateAvailability(traceID: String) async throws
    func generate(request: NarrativeReportGenerationRequest, context: TaskQueueActor.TaskContext?, traceID: String)
        async throws -> NarrativeReportEnvelope
    func generate(
        request: NarrativeReportGenerationRequest,
        traceID: String
    ) async throws -> NarrativeReportEnvelope
}

public extension NarrativeReportGenerating {
    nonisolated var maximumSourceCount: Int { 256 }
    nonisolated func configurationIdentity(traceID: String) async throws -> String { "injected-generator-v1" }
    nonisolated func validateAvailability(traceID: String) async throws {}
    nonisolated func generate(
        request: NarrativeReportGenerationRequest,
        context: TaskQueueActor.TaskContext?,
        traceID: String
    ) async throws -> NarrativeReportEnvelope {
        try await generate(request: request, traceID: traceID)
    }
}

public actor NarrativeReportActor {
    public static let shared = NarrativeReportActor()

    private let database: DatabaseManager
    private let privacyActor: PrivacyActor
    private let taskQueue: TaskQueueActor
    private let pendingOps: PendingOpsActor
    private var generator: (any NarrativeReportGenerating)?
    private let omittedPartitions: [String]
    private let sourceRepository: CanonicalMemoryRepositoryActor

    public init(
        database: DatabaseManager = .shared,
        privacyActor: PrivacyActor = .shared,
        taskQueue: TaskQueueActor = .shared,
        pendingOps: PendingOpsActor = .shared,
        generator: (any NarrativeReportGenerating)? = nil,
        omittedPartitions: [String] = ["healthKit", "people"],
        sourceRepository: CanonicalMemoryRepositoryActor? = nil
    ) {
        self.database = database
        self.privacyActor = privacyActor
        self.taskQueue = taskQueue
        self.pendingOps = pendingOps
        self.generator = generator
        self.omittedPartitions = omittedPartitions.sorted()
        self.sourceRepository = sourceRepository ?? CanonicalMemoryRepositoryActor(db: database, privacyActor: privacyActor)
    }

    public func attachGenerator(
        _ generator: any NarrativeReportGenerating,
        traceID: String = UUID().uuidString
    ) async throws {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
        self.generator = generator
    }

    public func loadSchedule(
        traceID: String = UUID().uuidString
    ) async throws -> NarrativeReportSchedule {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
        try await database.executeWrite(
            sql: """
                INSERT OR IGNORE INTO NarrativeReportSchedule
                  (id, monthlyEnabled, yearlyEnabled, monthlyEligibleFrom,
                   yearlyEligibleFrom, revision, updatedAt)
                VALUES (1, 1, 1, NULL, NULL, 0, ?)
                """,
            bindings: [.double(Date().timeIntervalSince1970)]
        )
        let rows = try await database.executeQuery(
            sql: """
                SELECT monthlyEnabled, yearlyEnabled, monthlyEligibleFrom,
                       yearlyEligibleFrom, updatedAt
                FROM NarrativeReportSchedule WHERE id = 1
                """,
            bindings: []
        )
        guard let row = rows.first else { throw NarrativeReportError.scheduleUnavailable }
        return NarrativeReportSchedule(
            monthlyEnabled: (row["monthlyEnabled"]?.intValue ?? 0) != 0,
            yearlyEnabled: (row["yearlyEnabled"]?.intValue ?? 0) != 0,
            monthlyEligibleFrom: row["monthlyEligibleFrom"]?.doubleValue.map(Date.init(timeIntervalSince1970:)),
            yearlyEligibleFrom: row["yearlyEligibleFrom"]?.doubleValue.map(Date.init(timeIntervalSince1970:)),
            updatedAt: row["updatedAt"]?.doubleValue.map(Date.init(timeIntervalSince1970:)) ?? .distantPast
        )
    }

    /// Establishes new-install baselines only after durable consent and a canonical memory exist.
    @discardableResult
    public func establishEligibilityIfNeeded(
        at now: Date = Date(),
        traceID: String = UUID().uuidString
    ) async throws -> Bool {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
        // Consent revocation removes this row. Recreate it before applying both baselines
        // so the first post-consent scan establishes eligibility in the same pass.
        _ = try await loadSchedule(traceID: traceID)
        let changed = try await database.executeWrite(
            sql: """
                UPDATE NarrativeReportSchedule
                SET monthlyEligibleFrom = CASE
                        WHEN monthlyEnabled = 1 THEN COALESCE(monthlyEligibleFrom, ?) ELSE monthlyEligibleFrom END,
                    yearlyEligibleFrom = CASE
                        WHEN yearlyEnabled = 1 THEN COALESCE(yearlyEligibleFrom, ?) ELSE yearlyEligibleFrom END,
                    revision = revision + 1,
                    updatedAt = ?
                WHERE id = 1
                  AND ((monthlyEnabled = 1 AND monthlyEligibleFrom IS NULL)
                    OR (yearlyEnabled = 1 AND yearlyEligibleFrom IS NULL))
                  AND EXISTS (SELECT 1 FROM ConsentStore WHERE id = 1 AND hasConsented = 1)
                  AND EXISTS (SELECT 1 FROM Memory LIMIT 1)
                """,
            bindings: [
                .double(now.timeIntervalSince1970),
                .double(now.timeIntervalSince1970),
                .double(now.timeIntervalSince1970),
            ]
        )
        return changed > 0
    }

    /// Persists one independent switch. Re-enabling resets only that type's baseline.
    public func setEnabled(
        _ enabled: Bool,
        for periodType: NarrativeReportPeriodType,
        at now: Date = Date(),
        traceID: String = UUID().uuidString
    ) async throws {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
        let enabledColumn: String
        let baselineColumn: String
        switch periodType {
        case .month:
            enabledColumn = "monthlyEnabled"
            baselineColumn = "monthlyEligibleFrom"

        case .year:
            enabledColumn = "yearlyEnabled"
            baselineColumn = "yearlyEligibleFrom"
        }
        let prior = try await loadSchedule(traceID: traceID)
        let wasEnabled = periodType == .month ? prior.monthlyEnabled : prior.yearlyEnabled
        let baseline: DBBinding = enabled && !wasEnabled ? .double(now.timeIntervalSince1970) : .null
        let baselineAssignment = enabled && !wasEnabled ? "\(baselineColumn) = ?," : ""
        var bindings: [DBBinding] = [.int(enabled ? 1 : 0)]
        if enabled && !wasEnabled { bindings.append(baseline) }
        bindings.append(.double(now.timeIntervalSince1970))
        try await database.executeWrite(
            sql: """
                UPDATE NarrativeReportSchedule
                SET \(enabledColumn) = ?, \(baselineAssignment)
                    revision = revision + 1, updatedAt = ?
                WHERE id = 1
                """,
            bindings: bindings
        )
    }

    /// Materializes frozen boundaries and claims at most one earliest eligible period.
    public func materializeAndClaimNext(
        at now: Date = Date(),
        calendarContext: NarrativeReportCalendarContext,
        trigger: NarrativeReportScanTrigger,
        taskID: String,
        traceID: String = UUID().uuidString
    ) async throws -> NarrativeReportPeriod? {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
        _ = trigger
        let calendar = try calendarContext.makeCalendar()
        let schedule = try await loadSchedule(traceID: traceID)
        var periods: [NarrativeReportPeriod] = []
        if schedule.monthlyEnabled, let baseline = schedule.monthlyEligibleFrom {
            periods.append(
                contentsOf: try NarrativeReportPeriodPlanner.completedPeriods(
                    at: now,
                    eligibleFrom: baseline,
                    calendar: calendar
                ).filter { $0.periodType == .month }
            )
        }
        if schedule.yearlyEnabled, let baseline = schedule.yearlyEligibleFrom {
            periods.append(
                contentsOf: try NarrativeReportPeriodPlanner.completedPeriods(
                    at: now,
                    eligibleFrom: baseline,
                    calendar: calendar
                ).filter { $0.periodType == .year }
            )
        }
        if !periods.isEmpty {
            let nowValue = now.timeIntervalSince1970
            try await database.executeTransaction(
                periods.map { period in
                    DatabaseManager.DBWrite(
                        sql: """
                            INSERT OR IGNORE INTO NarrativeReportPeriod
                              (periodType, periodKey, calendarIdentifier, timeZoneIdentifier,
                               startInstant, endInstant, coverageStart, partialBaseline, state,
                               revision, claimedAt, taskId, updatedAt)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'eligible', 0, NULL, NULL, ?)
                            """,
                        bindings: [
                            .text(period.periodType.rawValue),
                            .text(period.periodKey),
                            .text(period.calendarIdentifier),
                            .text(period.timeZoneIdentifier),
                            .double(period.startInstant.timeIntervalSince1970),
                            .double(period.endInstant.timeIntervalSince1970),
                            .double(period.coverageStart.timeIntervalSince1970),
                            .int(period.partialBaseline ? 1 : 0),
                            .double(nowValue),
                        ]
                    )
                }
            )
        }
        guard
            let row = try await database.claimEarliestNarrativeReportPeriod(
                taskID: taskID,
                claimedAt: now
            )
        else { return nil }
        return Self.period(from: row)
    }

    /// Runs one bounded lifecycle scan and transfers an exact claim to TaskQueueActor.
    public func scanAndEnqueue(
        at now: Date = Date(),
        calendarContext: NarrativeReportCalendarContext,
        trigger: NarrativeReportScanTrigger,
        resources: NarrativeReportResourceAvailability = .available,
        traceID: String = UUID().uuidString
    ) async throws -> NarrativeReportScanResult {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
        guard resources.canStart else { return .deferredForResources }
        guard let generator else { return .generationUnavailable }
        try await generator.validateAvailability(traceID: traceID)
        let taskID = "narrative-report-\(UUID().uuidString.lowercased())"
        guard
            let period = try await materializeAndClaimNext(
                at: now,
                calendarContext: calendarContext,
                trigger: trigger,
                taskID: taskID,
                traceID: traceID
            )
        else { return .none }

        do {
            try Task.checkCancellation()
            let prepared = try await prepareInput(for: period)
            try Task.checkCancellation()
            guard !prepared.sources.isEmpty else {
                try await completeWithoutData(period: period, now: now)
                return .noData(periodKey: period.periodKey)
            }
            let job = try await makeJob(
                period: period,
                taskID: taskID,
                traceID: traceID
            )
            try await taskQueue.enqueue(job)
            return .enqueued(taskID: taskID, periodKey: period.periodKey)
        } catch NarrativeReportError.resourceDeferred {
            try await releaseClaimForResource(taskID: taskID, traceID: traceID)
            return .deferredForResources
        } catch is CancellationError {
            try await releaseClaimForResource(taskID: taskID, traceID: traceID)
            throw CancellationError()
        } catch {
            try await markRetryRequired(period: period, error: error)
            return .retryRequired(periodKey: period.periodKey)
        }
    }

    /// Reclaims a noData/L2 period only after an explicit user action.
    public func retryReport(
        periodType: NarrativeReportPeriodType,
        periodKey: String,
        traceID: String = UUID().uuidString
    ) async throws -> String {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
        guard let generator else { throw NarrativeReportError.generationUnavailable }
        try await generator.validateAvailability(traceID: traceID)
        let taskID = "narrative-report-\(UUID().uuidString.lowercased())"
        let changed = try await database.executeWrite(
            sql: """
                UPDATE NarrativeReportPeriod
                SET state = 'claimed', revision = revision + 1,
                    claimedAt = ?, taskId = ?, updatedAt = ?
                WHERE periodType = ? AND periodKey = ?
                  AND state IN ('retryRequired', 'noData')
                """,
            bindings: [
                .double(Date().timeIntervalSince1970), .text(taskID),
                .double(Date().timeIntervalSince1970), .text(periodType.rawValue),
                .text(periodKey),
            ]
        )
        guard changed == 1,
            let period = try await loadPeriod(type: periodType, key: periodKey)
        else {
            throw NarrativeReportError.invalidatedPeriod
        }
        do {
            try Task.checkCancellation()
            let prepared = try await prepareInput(for: period)
            try Task.checkCancellation()
            guard !prepared.sources.isEmpty else {
                try await completeWithoutData(period: period, now: Date())
                return taskID
            }
            let job = try await makeJob(
                period: period,
                taskID: taskID,
                traceID: traceID
            )
            try await taskQueue.enqueue(job)
            return taskID
        } catch is CancellationError {
            try await releaseClaimForResource(taskID: taskID, traceID: traceID)
            throw CancellationError()
        } catch {
            try await markRetryRequired(period: period, error: error)
            throw error
        }
    }

    /// Releases a system-owned execution claim. This is a defer, never an L2 failure.
    public func releaseClaimForResource(
        taskID: String,
        traceID: String = UUID().uuidString
    ) async throws {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
        // Wait for the queue-owned body to unwind before releasing its database claim.
        // Otherwise a publication can race the UPDATE below and create a false L2 retry.
        _ = await taskQueue.cancelAndDiscard(taskId: taskID)
        try await database.executeWrite(
            sql: """
                UPDATE NarrativeReportPeriod
                SET state = 'eligible', revision = revision + 1,
                    claimedAt = NULL, taskId = NULL, updatedAt = ?
                WHERE state = 'claimed' AND taskId = ?
                """,
            bindings: [.double(Date().timeIntervalSince1970), .text(taskID)]
        )
    }

    public func makeRecoveryJob(for request: TaskRecoveryRequest) async throws -> TaskQueueActor.QueuedJob {
        let checkpoint = await privacyActor.validate(
            operation: request.descriptor.operation,
            traceID: UUID().uuidString,
            sourceTypes: request.descriptor.sourceTypes
        )
        guard checkpoint.isAllowed,
            request.progress.taskType == .narrativeReport,
            let resumeData = request.progress.resumeData
        else {
            throw TaskRecoveryError.launcherMismatch
        }
        guard let generator else { throw NarrativeReportError.generationUnavailable }
        try await generator.validateAvailability(traceID: checkpoint.traceID)
        let payload = try NarrativeReportResumePayload.decodeDescriptor(resumeData)
        guard let period = try await loadPeriod(type: payload.periodType, key: payload.periodKey),
            period.state == .claimed,
            period.taskID == request.progress.taskId
        else {
            throw TaskRecoveryError.staleProgress
        }
        return try await makeJob(
            period: period,
            taskID: request.progress.taskId,
            traceID: checkpoint.traceID,
            preservedResumeData: request.choice == .continue ? resumeData : nil,
            expectedIdentity: payload.executionIdentity
        )
    }

    public func listReports(traceID: String = UUID().uuidString) async throws -> [PersistedNarrativeReport] {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
        let rows = try await database.executeQuery(
            sql:
                "SELECT reportId, periodType, periodKey, envelope, createdAt FROM NarrativeReport ORDER BY createdAt DESC",
            bindings: []
        )
        let policy = await privacyActor.getPolicy()
        var reports: [PersistedNarrativeReport] = []
        for row in rows {
            guard let reportID = row["reportId"]?.stringValue else { continue }
            let sourceRows = try await database.executeQuery(
                sql:
                    "SELECT memoryId, sourceType, ordinal FROM NarrativeReportSource WHERE reportId = ? ORDER BY ordinal",
                bindings: [.text(reportID)]
            )
            let sources = sourceRows.compactMap {
                Self.source(from: $0, authorizedSourceTypes: policy.authorizedSourceTypes)
            }
            guard sources.count == sourceRows.count,
                sources.allSatisfy({ $0.availability == .available })
            else { continue }
            if let report = Self.report(from: row, sources: sources) {
                reports.append(report)
            }
        }
        return reports
    }

    public func loadReport(
        reportID: UUID,
        traceID: String = UUID().uuidString
    ) async throws -> PersistedNarrativeReport? {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
        let rows = try await database.executeQuery(
            sql: "SELECT reportId, periodType, periodKey, envelope, createdAt FROM NarrativeReport WHERE reportId = ?",
            bindings: [.text(reportID.uuidString)]
        )
        guard let row = rows.first else { return nil }
        let policy = await privacyActor.getPolicy()
        let sourceRows = try await database.executeQuery(
            sql: "SELECT memoryId, sourceType, ordinal FROM NarrativeReportSource WHERE reportId = ? ORDER BY ordinal",
            bindings: [.text(reportID.uuidString)]
        )
        let sources = sourceRows.compactMap {
            Self.source(from: $0, authorizedSourceTypes: policy.authorizedSourceTypes)
        }
        guard sources.count == sourceRows.count,
            sources.allSatisfy({ $0.availability == .available })
        else { return nil }
        return Self.report(
            from: row,
            sources: sources
        )
    }

    public func listRecoverablePeriods(
        traceID: String = UUID().uuidString
    ) async throws -> [NarrativeReportPeriod] {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
        let rows = try await database.executeQuery(
            sql: """
                SELECT * FROM NarrativeReportPeriod
                WHERE state IN ('retryRequired', 'noData')
                ORDER BY endInstant DESC,
                         CASE periodType WHEN 'month' THEN 0 ELSE 1 END ASC
                """,
            bindings: []
        )
        return rows.compactMap(Self.period(from:))
    }

    public func deleteReport(
        reportID: UUID,
        traceID: String = UUID().uuidString
    ) async throws {
        let checkpoint = await privacyActor.validate(operation: .delete, traceID: traceID)
        guard checkpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
        let rows = try await database.executeQuery(
            sql: "SELECT periodType, periodKey FROM NarrativeReport WHERE reportId = ?",
            bindings: [.text(reportID.uuidString)]
        )
        guard let row = rows.first,
            let type = row["periodType"]?.stringValue,
            let key = row["periodKey"]?.stringValue
        else { return }
        try await database.executeTransaction([
            .init(sql: "DELETE FROM NarrativeReport WHERE reportId = ?", bindings: [.text(reportID.uuidString)]),
            .init(
                sql:
                    "UPDATE NarrativeReportPeriod SET state = 'invalidated', revision = revision + 1, updatedAt = ? WHERE periodType = ? AND periodKey = ?",
                bindings: [.double(Date().timeIntervalSince1970), .text(type), .text(key)]
            ),
        ])
    }

    private func makeJob(
        period: NarrativeReportPeriod,
        taskID: String,
        traceID: String,
        preservedResumeData: Data? = nil,
        expectedIdentity: String? = nil
    ) async throws -> TaskQueueActor.QueuedJob {
        let prepared = try await prepareInput(for: period)
        let policy = await privacyActor.getPolicy()
        let configuration = try await generator?.configurationIdentity(traceID: traceID) ?? "unavailable"
        let identity = try NarrativeGenerationIdentity.digest(
            sources: prepared.request.sources,
            language: policy.preferredLanguage,
            policyVersion: policy.policyVersion,
            batches: prepared.request.sourceBatches,
            configuration: configuration
        )
        if preservedResumeData != nil, identity != expectedIdentity { throw GenerationRuntimeError.restartRequired }
        let resumeData =
            try preservedResumeData
            ?? NarrativeReportResumePayload(
                periodType: period.periodType,
                periodKey: period.periodKey,
                executionIdentity: identity
            ).encodedDescriptor(sourceTypes: prepared.sources.map(\.sourceType))
        return TaskQueueActor.QueuedJob(
            taskId: taskID,
            taskType: .narrativeReport,
            totalCount: min(prepared.sources.count, generator?.maximumSourceCount ?? 24),
            resumeData: resumeData
        ) { [self] context in
            try await executeClaimedPeriod(
                periodKey: (type: period.periodType, key: period.periodKey),
                taskID: taskID,
                context: context,
                traceID: traceID,
                expectedIdentity: identity
            )
        }
    }

    private func executeClaimedPeriod(
        periodKey: (type: NarrativeReportPeriodType, key: String),
        taskID: String,
        context: TaskQueueActor.TaskContext,
        traceID: String,
        expectedIdentity: String
    ) async throws {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed,
            let period = try await loadPeriod(type: periodKey.type, key: periodKey.key),
            period.state == .claimed, period.taskID == taskID
        else {
            throw NarrativeReportError.publicationConflict
        }
        do {
            try context.checkCancelled()
            try await context.checkPaused()
            let prepared = try await prepareInput(for: period)
            let policy = await privacyActor.getPolicy()
            let configuration = try await generator?.configurationIdentity(traceID: traceID) ?? "unavailable"
            guard
                try NarrativeGenerationIdentity.digest(
                    sources: prepared.request.sources,
                    language: policy.preferredLanguage,
                    policyVersion: policy.policyVersion,
                    batches: prepared.request.sourceBatches,
                    configuration: configuration
                ) == expectedIdentity
            else {
                throw GenerationRuntimeError.restartRequired
            }
            guard !prepared.sources.isEmpty else {
                try await completeWithoutData(period: period, now: Date())
                return
            }
            let sourceTypes = prepared.sources.map(\.sourceType)
            let sourceCheckpoint = await privacyActor.validate(
                operation: .search,
                traceID: traceID,
                sourceTypes: Array(Set(sourceTypes)).sorted()
            )
            guard sourceCheckpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
            guard let generator else { throw NarrativeReportError.generationUnavailable }
            let envelope = try await generator.generate(request: prepared.request, context: context, traceID: traceID)
            try context.checkCancelled()
            let contributingIDs = envelope.contributingMemoryIDs.map(Set.init) ?? Set(prepared.sources.map(\.memoryID))
            let contributingSources = prepared.sources.filter { contributingIDs.contains($0.memoryID) }.enumerated().map { index, source in
                NarrativeReportSource(
                    memoryID: source.memoryID,
                    sourceType: source.sourceType,
                    ordinal: index,
                    sourceRevision: source.sourceRevision,
                    contentDigest: source.contentDigest
                )
            }
            let finalCheckpoint = await privacyActor.validate(
                operation: .search,
                traceID: traceID,
                sourceTypes: Array(Set(contributingSources.map(\.sourceType))).sorted()
            )
            guard finalCheckpoint.isAllowed, finalCheckpoint.policyVersion == sourceCheckpoint.policyVersion else {
                throw GenerationRuntimeError.privacyDenied
            }
            try await GenerationSourceValidation(
                repository: sourceRepository,
                sources: prepared.request.sources.filter { contributingIDs.contains($0.memoryID) },
                excerptScalarLimit: 512
            ).validate()
            let audit = try await privacyActor.prepareNarrativeReportAuditPayload(
                checkpoint: finalCheckpoint,
                period: period,
                sourceTypes: contributingSources.map(\.sourceType)
            )
            try await database.publishNarrativeReport(
                NarrativeReportPublication(
                    period: period,
                    envelope: envelope,
                    sources: contributingSources,
                    audit: audit
                )
            )
            try await context.report(
                processedIndex: contributingSources.count,
                lastProcessedId: period.periodKey
            )
            _ = try? await pendingOps.remove(operationId: Self.pendingID(for: period))
        } catch is CancellationError {
            throw CancellationError()
        } catch NarrativeReportError.resourceDeferred {
            // This is already the queue-owned body. Cancelling and awaiting our
            // own job here would deadlock; release only its exact database claim.
            try await database.executeWrite(
                sql: """
                    UPDATE NarrativeReportPeriod
                    SET state = 'eligible', revision = revision + 1,
                        claimedAt = NULL, taskId = NULL, updatedAt = ?
                    WHERE state = 'claimed' AND taskId = ? AND revision = ?
                    """,
                bindings: [.double(Date().timeIntervalSince1970), .text(taskID), .int(Int64(period.revision))]
            )
            throw NarrativeReportError.resourceDeferred
        } catch {
            try await markRetryRequired(period: period, error: error)
        }
    }

    private func prepareInput(for period: NarrativeReportPeriod) async throws -> NarrativeReportPreparedInput {
        let policy = await privacyActor.getPolicy()
        let allowedTypes = policy.authorizedSourceTypes.sorted()
        guard !allowedTypes.isEmpty else {
            return NarrativeReportAggregator.prepare(
                period: period,
                rows: [],
                authorizedSourceTypes: [],
                omittedPartitions: omittedPartitions
            )
        }
        let placeholders = Array(repeating: "?", count: allowedTypes.count).joined(separator: ",")
        let rows = try await database.executeQuery(
            sql: """
                SELECT memoryId, substr(canonicalText, 1, 512) AS canonicalText, sourceType, updatedAt,
                       COALESCE(originalTimestamp, createdAt) AS memoryTimestamp,
                       COUNT(*) OVER () AS eligibleSourceCount
                FROM Memory
                WHERE COALESCE(originalTimestamp, createdAt) >= ?
                  AND COALESCE(originalTimestamp, createdAt) < ?
                  AND CASE sourceType WHEN 'text' THEN 'note'
                      WHEN 'video_frame' THEN 'video' WHEN 'video_audio' THEN 'video'
                      ELSE sourceType END IN (\(placeholders))
                  AND (sourceType = 'photo' OR length(trim(COALESCE(canonicalText, ''))) > 0)
                  AND NOT EXISTS (SELECT 1 FROM ExcludedAssets e WHERE e.assetId = Memory.sourceLocator)
                ORDER BY sourceType ASC, memoryTimestamp ASC, memoryId ASC
                LIMIT 256
                """,
            bindings: [
                .double(period.coverageStart.timeIntervalSince1970),
                .double(period.endInstant.timeIntervalSince1970),
            ] + allowedTypes.map(DBBinding.text)
        )
        var preparedRows: [[String: DBValue]] = []
        var waitingPhotos = false
        for var row in rows {
            if row["sourceType"]?.stringValue == "photo",
                let raw = row["memoryId"]?.stringValue, let id = UUID(uuidString: raw) {
                let source = try await sourceRepository.loadCreationSource(
                    memoryID: id,
                    maximumTextBytes: GenerationInputBudget.maximumBytes
                )
                let text = source?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.isEmpty { waitingPhotos = true; continue }
                row["canonicalText"] = .text(String(String.UnicodeScalarView(text.unicodeScalars.prefix(512))))
                row["updatedAt"] = .double(source?.revision ?? 0)
            }
            preparedRows.append(row)
        }
        if preparedRows.isEmpty, waitingPhotos { throw NarrativeReportError.resourceDeferred }
        return NarrativeReportAggregator.prepare(
            period: period,
            rows: preparedRows,
            authorizedSourceTypes: policy.authorizedSourceTypes,
            omittedPartitions: omittedPartitions
        )
    }

    private func completeWithoutData(period: NarrativeReportPeriod, now: Date) async throws {
        let changed = try await database.executeWrite(
            sql: """
                UPDATE NarrativeReportPeriod
                SET state = 'noData', revision = revision + 1,
                    claimedAt = NULL, taskId = NULL, updatedAt = ?
                WHERE periodType = ? AND periodKey = ? AND state = 'claimed'
                  AND revision = ? AND taskId = ?
                """,
            bindings: [
                .double(now.timeIntervalSince1970), .text(period.periodType.rawValue),
                .text(period.periodKey), .int(Int64(period.revision)),
                .text(period.taskID ?? ""),
            ]
        )
        guard changed == 1 else { throw NarrativeReportError.publicationConflict }
        _ = try? await pendingOps.remove(operationId: Self.pendingID(for: period))
    }

    private func markRetryRequired(period: NarrativeReportPeriod, error: Error) async throws {
        let changed = try await database.executeWrite(
            sql: """
                UPDATE NarrativeReportPeriod
                SET state = 'retryRequired', revision = revision + 1,
                    claimedAt = NULL, taskId = NULL, updatedAt = ?
                WHERE periodType = ? AND periodKey = ? AND state = 'claimed'
                  AND taskId = ?
                """,
            bindings: [
                .double(Date().timeIntervalSince1970), .text(period.periodType.rawValue),
                .text(period.periodKey), .text(period.taskID ?? ""),
            ]
        )
        guard changed == 1 else { return }
        // The period remains unavailable to lifecycle scans. A model repair or
        // authorization change must not masquerade as a recoverable L2 operation.
        if let runtimeError = error as? GenerationRuntimeError,
            runtimeError.severity == .l3Blocking || runtimeError == .privacyDenied {
            throw runtimeError
        }
        let parameters = try NarrativeReportResumePayload(
            periodType: period.periodType,
            periodKey: period.periodKey
        ).encodedDescriptor(sourceTypes: [])
        let operation = PendingOperation(
            operationId: Self.pendingID(for: period),
            operationType: "narrativeReport",
            parameters: parameters,
            lastError: String(describing: error)
        )
        if try await pendingOps.load(operationId: operation.operationId) == nil {
            try await pendingOps.add(operation: operation)
        } else {
            try await pendingOps.updateRetry(
                operationId: operation.operationId,
                lastError: operation.lastError
            )
        }
    }

    private func loadPeriod(
        type: NarrativeReportPeriodType,
        key: String
    ) async throws -> NarrativeReportPeriod? {
        let rows = try await database.executeQuery(
            sql: "SELECT * FROM NarrativeReportPeriod WHERE periodType = ? AND periodKey = ?",
            bindings: [.text(type.rawValue), .text(key)]
        )
        return rows.first.flatMap(Self.period(from:))
    }

    nonisolated private static func pendingID(for period: NarrativeReportPeriod) -> String {
        "narrative:\(period.periodType.rawValue):\(period.periodKey)"
    }

    nonisolated private static func report(
        from row: [String: DBValue],
        sources: [NarrativeReportSource]
    ) -> PersistedNarrativeReport? {
        guard let idRaw = row["reportId"]?.stringValue,
            let id = UUID(uuidString: idRaw),
            let typeRaw = row["periodType"]?.stringValue,
            let type = NarrativeReportPeriodType(rawValue: typeRaw),
            let key = row["periodKey"]?.stringValue,
            let data = row["envelope"]?.blobValue,
            let envelope = try? NarrativeReportEnvelope.decode(data),
            let created = row["createdAt"]?.doubleValue
        else { return nil }
        return PersistedNarrativeReport(
            id: id,
            periodType: type,
            periodKey: key,
            envelope: envelope,
            sources: sources,
            createdAt: Date(timeIntervalSince1970: created)
        )
    }

    nonisolated private static func source(
        from row: [String: DBValue],
        authorizedSourceTypes: Set<String>
    ) -> NarrativeReportSource? {
        guard let memoryRaw = row["memoryId"]?.stringValue,
            let memoryID = UUID(uuidString: memoryRaw),
            let sourceType = row["sourceType"]?.stringValue,
            let ordinal = row["ordinal"]?.intValue
        else { return nil }
        return NarrativeReportSource(
            memoryID: memoryID,
            sourceType: sourceType,
            ordinal: Int(ordinal),
            availability: authorizedSourceTypes.contains(
                SearchPipeline.normalizeSourceType(sourceType)
            ) ? .available : .unsupported
        )
    }

    nonisolated private static func period(from row: [String: DBValue]) -> NarrativeReportPeriod? {
        guard let rawType = row["periodType"]?.stringValue,
            let type = NarrativeReportPeriodType(rawValue: rawType),
            let key = row["periodKey"]?.stringValue,
            let calendarID = row["calendarIdentifier"]?.stringValue,
            let timeZoneID = row["timeZoneIdentifier"]?.stringValue,
            let start = row["startInstant"]?.doubleValue,
            let end = row["endInstant"]?.doubleValue,
            let coverage = row["coverageStart"]?.doubleValue,
            let rawState = row["state"]?.stringValue,
            let state = NarrativeReportPeriodState(rawValue: rawState)
        else { return nil }
        return NarrativeReportPeriod(
            periodType: type,
            periodKey: key,
            calendarIdentifier: calendarID,
            timeZoneIdentifier: timeZoneID,
            startInstant: Date(timeIntervalSince1970: start),
            endInstant: Date(timeIntervalSince1970: end),
            coverageStart: Date(timeIntervalSince1970: coverage),
            partialBaseline: (row["partialBaseline"]?.intValue ?? 0) != 0,
            state: state,
            revision: Int(row["revision"]?.intValue ?? 0),
            claimedAt: row["claimedAt"]?.doubleValue.map(Date.init(timeIntervalSince1970:)),
            taskID: row["taskId"]?.stringValue
        )
    }
}
