// ==========================================
// File: NarrativeReportActor.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md → US-SYN-004
//       docs/decisions/ADR-021-narrative-report-scheduling-persistence.md
// Task: 4.0j - Persisted monthly and yearly narrative report scheduling
// AC coverage: AC-1 through AC-8
// Architecture: AGENTS.md §4.2, §4.3, §4.5, §7.3
// Generated: 2026-09-07
// ==========================================

import Foundation

public protocol NarrativeReportGenerating: Sendable {
    func generate(
        request: NarrativeReportGenerationRequest,
        traceID: String
    ) async throws -> NarrativeReportEnvelope
}

/// Production adapter over the existing offline grounded-generation pipeline.
public actor CreativeNarrativeReportGenerator: NarrativeReportGenerating {
    private let pipeline: CreativePipeline

    public init(pipeline: CreativePipeline) {
        self.pipeline = pipeline
    }

    public func generate(
        request: NarrativeReportGenerationRequest,
        traceID: String
    ) async throws -> NarrativeReportEnvelope {
        let output = try await pipeline.generate(
            template: .report,
            sources: request.sources,
            traceID: traceID
        )
        guard !output.didFallback, !output.paragraphs.isEmpty else {
            throw NarrativeReportError.generationUnavailable
        }
        let envelope = NarrativeReportEnvelope(
            title: request.period.periodKey,
            periodType: request.period.periodType,
            periodKey: request.period.periodKey,
            paragraphs: output.paragraphs.map {
                NarrativeReportParagraph(
                    id: $0.id,
                    text: $0.text,
                    sourceMemoryIDs: $0.anchors.map(\.memoryID),
                    groundingStatus: $0.groundingStatus
                )
            },
            coverage: request.coverage
        )
        _ = try envelope.encoded()
        return envelope
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

    public init(
        database: DatabaseManager = .shared,
        privacyActor: PrivacyActor = .shared,
        taskQueue: TaskQueueActor = .shared,
        pendingOps: PendingOpsActor = .shared,
        generator: (any NarrativeReportGenerating)? = nil,
        omittedPartitions: [String] = ["healthKit", "people"]
    ) {
        self.database = database
        self.privacyActor = privacyActor
        self.taskQueue = taskQueue
        self.pendingOps = pendingOps
        self.generator = generator
        self.omittedPartitions = omittedPartitions.sorted()
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
                  AND (monthlyEligibleFrom IS NULL OR yearlyEligibleFrom IS NULL)
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
            periods.append(contentsOf: try NarrativeReportPeriodPlanner.completedPeriods(
                at: now,
                eligibleFrom: baseline,
                calendar: calendar
            ).filter { $0.periodType == .month })
        }
        if schedule.yearlyEnabled, let baseline = schedule.yearlyEligibleFrom {
            periods.append(contentsOf: try NarrativeReportPeriodPlanner.completedPeriods(
                at: now,
                eligibleFrom: baseline,
                calendar: calendar
            ).filter { $0.periodType == .year })
        }
        if !periods.isEmpty {
            let nowValue = now.timeIntervalSince1970
            try await database.executeTransaction(periods.map { period in
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
            })
        }
        guard let row = try await database.claimEarliestNarrativeReportPeriod(
            taskID: taskID,
            claimedAt: now
        ) else { return nil }
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
        let taskID = "narrative-report-\(UUID().uuidString.lowercased())"
        guard let period = try await materializeAndClaimNext(
            at: now,
            calendarContext: calendarContext,
            trigger: trigger,
            taskID: taskID,
            traceID: traceID
        ) else { return .none }

        let prepared = try await prepareInput(for: period)
        guard !prepared.sources.isEmpty else {
            try await completeWithoutData(period: period, now: now)
            return .noData(periodKey: period.periodKey)
        }
        do {
            let job = try makeJob(
                period: period,
                taskID: taskID,
                sourceTypes: prepared.sources.map(\.sourceType),
                totalCount: prepared.sources.count,
                traceID: traceID
            )
            try await taskQueue.enqueue(job)
            return .enqueued(taskID: taskID, periodKey: period.periodKey)
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
              let period = try await loadPeriod(type: periodType, key: periodKey) else {
            throw NarrativeReportError.invalidatedPeriod
        }
        let prepared = try await prepareInput(for: period)
        guard !prepared.sources.isEmpty else {
            try await completeWithoutData(period: period, now: Date())
            return taskID
        }
        let job = try makeJob(
            period: period,
            taskID: taskID,
            sourceTypes: prepared.sources.map(\.sourceType),
            totalCount: prepared.sources.count,
            traceID: traceID
        )
        try await taskQueue.enqueue(job)
        return taskID
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
              let resumeData = request.progress.resumeData else {
            throw TaskRecoveryError.launcherMismatch
        }
        let payload = try NarrativeReportResumePayload.decodeDescriptor(resumeData)
        guard let period = try await loadPeriod(type: payload.periodType, key: payload.periodKey),
              period.state == .claimed,
              period.taskID == request.progress.taskId else {
            throw TaskRecoveryError.staleProgress
        }
        return try makeJob(
            period: period,
            taskID: request.progress.taskId,
            sourceTypes: request.descriptor.sourceTypes,
            totalCount: request.progress.totalCount,
            traceID: checkpoint.traceID
        )
    }

    public func listReports(traceID: String = UUID().uuidString) async throws -> [PersistedNarrativeReport] {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed else { throw NarrativeReportError.privacyDenied }
        let rows = try await database.executeQuery(
            sql: "SELECT reportId, periodType, periodKey, envelope, createdAt FROM NarrativeReport ORDER BY createdAt DESC",
            bindings: []
        )
        let policy = await privacyActor.getPolicy()
        var reports: [PersistedNarrativeReport] = []
        for row in rows {
            guard let reportID = row["reportId"]?.stringValue else { continue }
            let sourceRows = try await database.executeQuery(
                sql: "SELECT memoryId, sourceType, ordinal FROM NarrativeReportSource WHERE reportId = ? ORDER BY ordinal",
                bindings: [.text(reportID)]
            )
            let sources = sourceRows.compactMap {
                Self.source(from: $0, authorizedSourceTypes: policy.authorizedSourceTypes)
            }
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
        return Self.report(
            from: row,
            sources: sourceRows.compactMap {
                Self.source(from: $0, authorizedSourceTypes: policy.authorizedSourceTypes)
            }
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
              let key = row["periodKey"]?.stringValue else { return }
        try await database.executeTransaction([
            .init(sql: "DELETE FROM NarrativeReport WHERE reportId = ?", bindings: [.text(reportID.uuidString)]),
            .init(
                sql: "UPDATE NarrativeReportPeriod SET state = 'invalidated', revision = revision + 1, updatedAt = ? WHERE periodType = ? AND periodKey = ?",
                bindings: [.double(Date().timeIntervalSince1970), .text(type), .text(key)]
            ),
        ])
    }

    private func makeJob(
        period: NarrativeReportPeriod,
        taskID: String,
        sourceTypes: [String],
        totalCount: Int,
        traceID: String
    ) throws -> TaskQueueActor.QueuedJob {
        let resumeData = try NarrativeReportResumePayload(
            periodType: period.periodType,
            periodKey: period.periodKey
        ).encodedDescriptor(sourceTypes: sourceTypes)
        return TaskQueueActor.QueuedJob(
            taskId: taskID,
            taskType: .narrativeReport,
            totalCount: totalCount,
            resumeData: resumeData
        ) { [self] context in
            try await executeClaimedPeriod(
                type: period.periodType,
                key: period.periodKey,
                taskID: taskID,
                context: context,
                traceID: traceID
            )
        }
    }

    private func executeClaimedPeriod(
        type: NarrativeReportPeriodType,
        key: String,
        taskID: String,
        context: TaskQueueActor.TaskContext,
        traceID: String
    ) async throws {
        let checkpoint = await privacyActor.validate(operation: .search, traceID: traceID)
        guard checkpoint.isAllowed,
              let period = try await loadPeriod(type: type, key: key),
              period.state == .claimed, period.taskID == taskID else {
            throw NarrativeReportError.publicationConflict
        }
        do {
            try context.checkCancelled()
            try await context.checkPaused()
            let prepared = try await prepareInput(for: period)
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
            try await context.report(processedIndex: 0, lastProcessedId: period.periodKey)
            let envelope = try await generator.generate(request: prepared.request, traceID: traceID)
            try context.checkCancelled()
            let audit = try await privacyActor.prepareNarrativeReportAuditPayload(
                checkpoint: sourceCheckpoint,
                period: period,
                sourceTypes: sourceTypes
            )
            try await database.publishNarrativeReport(NarrativeReportPublication(
                period: period,
                envelope: envelope,
                sources: prepared.sources,
                audit: audit
            ))
            try await context.report(
                processedIndex: prepared.sources.count,
                lastProcessedId: period.periodKey
            )
            _ = try? await pendingOps.remove(operationId: Self.pendingID(for: period))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await markRetryRequired(period: period, error: error)
        }
    }

    private func prepareInput(for period: NarrativeReportPeriod) async throws -> NarrativeReportPreparedInput {
        let policy = await privacyActor.getPolicy()
        let rows = try await database.executeQuery(
            sql: """
                SELECT memoryId, canonicalText, sourceType,
                       COALESCE(originalTimestamp, createdAt) AS memoryTimestamp
                FROM Memory
                WHERE COALESCE(originalTimestamp, createdAt) >= ?
                  AND COALESCE(originalTimestamp, createdAt) < ?
                ORDER BY sourceType ASC, memoryTimestamp ASC, memoryId ASC
                """,
            bindings: [
                .double(period.coverageStart.timeIntervalSince1970),
                .double(period.endInstant.timeIntervalSince1970),
            ]
        )
        return NarrativeReportAggregator.prepare(
            period: period,
            rows: rows,
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

    private nonisolated static func pendingID(for period: NarrativeReportPeriod) -> String {
        "narrative:\(period.periodType.rawValue):\(period.periodKey)"
    }

    private nonisolated static func report(
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
              let created = row["createdAt"]?.doubleValue else { return nil }
        return PersistedNarrativeReport(
            id: id,
            periodType: type,
            periodKey: key,
            envelope: envelope,
            sources: sources,
            createdAt: Date(timeIntervalSince1970: created)
        )
    }

    private nonisolated static func source(
        from row: [String: DBValue],
        authorizedSourceTypes: Set<String>
    ) -> NarrativeReportSource? {
        guard let memoryRaw = row["memoryId"]?.stringValue,
              let memoryID = UUID(uuidString: memoryRaw),
              let sourceType = row["sourceType"]?.stringValue,
              let ordinal = row["ordinal"]?.intValue else { return nil }
        return NarrativeReportSource(
            memoryID: memoryID,
            sourceType: sourceType,
            ordinal: Int(ordinal),
            availability: authorizedSourceTypes.contains(
                SearchPipeline.normalizeSourceType(sourceType)
            ) ? .available : .unsupported
        )
    }

    private nonisolated static func period(from row: [String: DBValue]) -> NarrativeReportPeriod? {
        guard let rawType = row["periodType"]?.stringValue,
              let type = NarrativeReportPeriodType(rawValue: rawType),
              let key = row["periodKey"]?.stringValue,
              let calendarID = row["calendarIdentifier"]?.stringValue,
              let timeZoneID = row["timeZoneIdentifier"]?.stringValue,
              let start = row["startInstant"]?.doubleValue,
              let end = row["endInstant"]?.doubleValue,
              let coverage = row["coverageStart"]?.doubleValue,
              let rawState = row["state"]?.stringValue,
              let state = NarrativeReportPeriodState(rawValue: rawState) else { return nil }
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
