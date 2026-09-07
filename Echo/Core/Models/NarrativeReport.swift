// ==========================================
// File: NarrativeReport.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md → US-SYN-004
//       docs/decisions/ADR-021-narrative-report-scheduling-persistence.md
//       docs/decisions/ADR-022-offline-generation-runtime-gate.md
// Task: 4.0j - Persisted narrative report scheduling and storage foundation
// AC coverage: AC-1/2 plus storage/state contracts supporting AC-3/4/6/7/8;
//              production generation and AC-5 close in task 4.0k
// Architecture: AGENTS.md §4.2, §4.3, §4.5, §7.3
// Generated: 2026-09-07
// ==========================================

import Foundation

public nonisolated enum NarrativeReportPeriodType: String, Sendable, Codable, CaseIterable {
    case month
    case year

    nonisolated var tieBreakPriority: Int {
        switch self {
        case .month: 0
        case .year: 1
        }
    }
}

public nonisolated enum NarrativeReportPeriodState: String, Sendable, Codable, Equatable {
    case eligible
    case claimed
    case retryRequired
    case completed
    case noData
    case invalidated
}

public nonisolated enum NarrativeReportScanTrigger: String, Sendable, Codable, Equatable {
    case launch
    case foreground
    case background
    case userInitiated
}

/// A value-only calendar description that is safe to cross actor boundaries.
/// Narrative reports intentionally use the Gregorian calendar; the time zone is
/// captured when a period is materialized and never recomputed for that period.
public nonisolated struct NarrativeReportCalendarContext: Sendable, Codable, Equatable {
    public nonisolated let timeZoneIdentifier: String

    public nonisolated init(timeZoneIdentifier: String) {
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public nonisolated func makeCalendar() throws -> Calendar {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw NarrativeReportError.invalidCalendarBoundary
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

public nonisolated struct NarrativeReportSchedule: Sendable, Codable, Equatable {
    public nonisolated let monthlyEnabled: Bool
    public nonisolated let yearlyEnabled: Bool
    public nonisolated let monthlyEligibleFrom: Date?
    public nonisolated let yearlyEligibleFrom: Date?
    public nonisolated let updatedAt: Date

    public nonisolated init(
        monthlyEnabled: Bool = true,
        yearlyEnabled: Bool = true,
        monthlyEligibleFrom: Date? = nil,
        yearlyEligibleFrom: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.monthlyEnabled = monthlyEnabled
        self.yearlyEnabled = yearlyEnabled
        self.monthlyEligibleFrom = monthlyEligibleFrom
        self.yearlyEligibleFrom = yearlyEligibleFrom
        self.updatedAt = updatedAt
    }

    public nonisolated func eligibleFrom(for type: NarrativeReportPeriodType) -> Date? {
        switch type {
        case .month: monthlyEligibleFrom
        case .year: yearlyEligibleFrom
        }
    }
}

public nonisolated struct NarrativeReportPeriod: Sendable, Codable, Equatable, Identifiable {
    public nonisolated var id: String { periodKey }
    public nonisolated let periodType: NarrativeReportPeriodType
    public nonisolated let periodKey: String
    public nonisolated let calendarIdentifier: String
    public nonisolated let timeZoneIdentifier: String
    public nonisolated let startInstant: Date
    public nonisolated let endInstant: Date
    public nonisolated let coverageStart: Date
    public nonisolated let partialBaseline: Bool
    public nonisolated let state: NarrativeReportPeriodState
    public nonisolated let revision: Int
    public nonisolated let claimedAt: Date?
    public nonisolated let taskID: String?

    public nonisolated init(
        periodType: NarrativeReportPeriodType,
        periodKey: String,
        calendarIdentifier: String,
        timeZoneIdentifier: String,
        startInstant: Date,
        endInstant: Date,
        coverageStart: Date,
        partialBaseline: Bool,
        state: NarrativeReportPeriodState = .eligible,
        revision: Int = 0,
        claimedAt: Date? = nil,
        taskID: String? = nil
    ) {
        self.periodType = periodType
        self.periodKey = periodKey
        self.calendarIdentifier = calendarIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.startInstant = startInstant
        self.endInstant = endInstant
        self.coverageStart = coverageStart
        self.partialBaseline = partialBaseline
        self.state = state
        self.revision = revision
        self.claimedAt = claimedAt
        self.taskID = taskID
    }
}

public nonisolated enum NarrativeReportLimits {
    public nonisolated static let version = 1
    public nonisolated static let maximumSources = 256
    public nonisolated static let maximumExcerptCharacters = 512
    public nonisolated static let maximumBatches = 16
    public nonisolated static let maximumAggregationLayers = 3
    public nonisolated static let maximumModelInputBytes = 128 * 1_024
    public nonisolated static let maximumEnvelopeBytes = 256 * 1_024
    public nonisolated static let maximumParagraphs = 64
    public nonisolated static let maximumReferencesPerParagraph = 16
}

public nonisolated struct NarrativeReportCoverage: Sendable, Codable, Equatable {
    public nonisolated let partialBaseline: Bool
    public nonisolated let coverageStart: Date
    public nonisolated let coverageEnd: Date
    public nonisolated let submittedSourceCount: Int
    public nonisolated let truncatedSourceCount: Int
    public nonisolated let omittedPartitions: [String]
    public nonisolated let limitsVersion: Int
    public nonisolated let aggregationLayerCount: Int

    public nonisolated init(
        partialBaseline: Bool,
        coverageStart: Date,
        coverageEnd: Date,
        submittedSourceCount: Int,
        truncatedSourceCount: Int = 0,
        omittedPartitions: [String] = [],
        limitsVersion: Int = NarrativeReportLimits.version,
        aggregationLayerCount: Int = 1
    ) {
        self.partialBaseline = partialBaseline
        self.coverageStart = coverageStart
        self.coverageEnd = coverageEnd
        self.submittedSourceCount = submittedSourceCount
        self.truncatedSourceCount = truncatedSourceCount
        self.omittedPartitions = Array(Set(omittedPartitions)).sorted()
        self.limitsVersion = limitsVersion
        self.aggregationLayerCount = aggregationLayerCount
    }
}

public nonisolated struct NarrativeReportParagraph: Sendable, Codable, Equatable, Identifiable {
    public nonisolated let id: UUID
    public nonisolated let text: String
    public nonisolated let sourceMemoryIDs: [UUID]
    public nonisolated let groundingStatus: GroundingStatus

    public nonisolated init(
        id: UUID,
        text: String,
        sourceMemoryIDs: [UUID],
        groundingStatus: GroundingStatus
    ) {
        self.id = id
        self.text = text
        var seen: Set<UUID> = []
        self.sourceMemoryIDs = sourceMemoryIDs.filter { seen.insert($0).inserted }
        self.groundingStatus = groundingStatus
    }
}

public nonisolated struct NarrativeReportEnvelope: Sendable, Codable, Equatable {
    public nonisolated static let currentSchemaVersion = 1
    public nonisolated let schemaVersion: Int
    public nonisolated let title: String
    public nonisolated let periodType: NarrativeReportPeriodType
    public nonisolated let periodKey: String
    public nonisolated let paragraphs: [NarrativeReportParagraph]
    public nonisolated let coverage: NarrativeReportCoverage

    public nonisolated init(
        schemaVersion: Int = Self.currentSchemaVersion,
        title: String,
        periodType: NarrativeReportPeriodType,
        periodKey: String,
        paragraphs: [NarrativeReportParagraph],
        coverage: NarrativeReportCoverage
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.periodType = periodType
        self.periodKey = periodKey
        self.paragraphs = paragraphs
        self.coverage = coverage
    }

    public nonisolated func encoded() throws -> Data {
        guard schemaVersion == Self.currentSchemaVersion,
              paragraphs.count <= NarrativeReportLimits.maximumParagraphs,
              paragraphs.allSatisfy({
                  !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && $0.sourceMemoryIDs.count <= NarrativeReportLimits.maximumReferencesPerParagraph
              }),
              coverage.limitsVersion == NarrativeReportLimits.version,
              (1...NarrativeReportLimits.maximumAggregationLayers)
                  .contains(coverage.aggregationLayerCount) else {
            throw NarrativeReportError.invalidReportEnvelope
        }
        let data = try JSONEncoder().encode(self)
        guard data.count <= NarrativeReportLimits.maximumEnvelopeBytes else {
            throw NarrativeReportError.invalidReportEnvelope
        }
        return data
    }

    public nonisolated static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= NarrativeReportLimits.maximumEnvelopeBytes,
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            throw NarrativeReportError.invalidReportEnvelope
        }
        _ = try value.encoded()
        return value
    }
}

public nonisolated struct NarrativeReportSource: Sendable, Codable, Equatable {
    public nonisolated let memoryID: UUID
    public nonisolated let sourceType: String
    public nonisolated let ordinal: Int
    public nonisolated let availability: CitationSourceAvailability

    public nonisolated init(
        memoryID: UUID,
        sourceType: String,
        ordinal: Int,
        availability: CitationSourceAvailability = .available
    ) {
        self.memoryID = memoryID
        self.sourceType = SearchPipeline.normalizeSourceType(sourceType)
        self.ordinal = ordinal
        self.availability = availability
    }
}

public nonisolated struct PersistedNarrativeReport: Sendable, Equatable, Identifiable {
    public nonisolated let id: UUID
    public nonisolated let periodType: NarrativeReportPeriodType
    public nonisolated let periodKey: String
    public nonisolated let envelope: NarrativeReportEnvelope
    public nonisolated let sources: [NarrativeReportSource]
    public nonisolated let createdAt: Date

    public nonisolated var sourceTypes: [String] {
        Array(Set(sources.map(\.sourceType))).sorted()
    }

    public nonisolated init(
        id: UUID,
        periodType: NarrativeReportPeriodType,
        periodKey: String,
        envelope: NarrativeReportEnvelope,
        sources: [NarrativeReportSource] = [],
        createdAt: Date
    ) {
        self.id = id
        self.periodType = periodType
        self.periodKey = periodKey
        self.envelope = envelope
        self.sources = sources.sorted { $0.ordinal < $1.ordinal }
        self.createdAt = createdAt
    }
}

/// Validated, content-free values prepared by PrivacyActor and committed by DatabaseManager.
public nonisolated struct NarrativeReportAuditPayload: Sendable, Equatable {
    public nonisolated let traceID: String
    public nonisolated let policyVersion: Int
    public nonisolated let periodType: NarrativeReportPeriodType
    public nonisolated let dataSourcesUsedJSON: String
    public nonisolated let periodKeyDigest: String
    public nonisolated let timestamp: Date

    public nonisolated init(
        traceID: String,
        policyVersion: Int,
        periodType: NarrativeReportPeriodType,
        dataSourcesUsedJSON: String,
        periodKeyDigest: String,
        timestamp: Date = Date()
    ) {
        self.traceID = traceID
        self.policyVersion = policyVersion
        self.periodType = periodType
        self.dataSourcesUsedJSON = dataSourcesUsedJSON
        self.periodKeyDigest = periodKeyDigest
        self.timestamp = timestamp
    }
}

public nonisolated struct NarrativeReportPublication: Sendable {
    public nonisolated let reportID: UUID
    public nonisolated let period: NarrativeReportPeriod
    public nonisolated let envelope: NarrativeReportEnvelope
    public nonisolated let sources: [NarrativeReportSource]
    public nonisolated let audit: NarrativeReportAuditPayload
    public nonisolated let createdAt: Date

    public nonisolated init(
        reportID: UUID = UUID(),
        period: NarrativeReportPeriod,
        envelope: NarrativeReportEnvelope,
        sources: [NarrativeReportSource],
        audit: NarrativeReportAuditPayload,
        createdAt: Date = Date()
    ) {
        self.reportID = reportID
        self.period = period
        self.envelope = envelope
        self.sources = sources.sorted { $0.ordinal < $1.ordinal }
        self.audit = audit
        self.createdAt = createdAt
    }
}

public nonisolated struct NarrativeReportGenerationRequest: Sendable, Equatable {
    public nonisolated let period: NarrativeReportPeriod
    public nonisolated let sourceBatches: [[CreativeSource]]
    public nonisolated let coverage: NarrativeReportCoverage

    public nonisolated init(
        period: NarrativeReportPeriod,
        sourceBatches: [[CreativeSource]],
        coverage: NarrativeReportCoverage
    ) {
        self.period = period
        self.sourceBatches = sourceBatches
        self.coverage = coverage
    }

    public nonisolated var sources: [CreativeSource] {
        sourceBatches.flatMap { $0 }
    }
}

public nonisolated struct NarrativeReportPreparedInput: Sendable, Equatable {
    public nonisolated let request: NarrativeReportGenerationRequest
    public nonisolated let sources: [NarrativeReportSource]

    public nonisolated init(
        request: NarrativeReportGenerationRequest,
        sources: [NarrativeReportSource]
    ) {
        self.request = request
        self.sources = sources
    }
}

public nonisolated struct NarrativeReportResumePayload: Sendable, Codable, Equatable {
    public nonisolated static let currentSchemaVersion = 1
    public nonisolated let schemaVersion: Int
    public nonisolated let periodType: NarrativeReportPeriodType
    public nonisolated let periodKey: String
    public nonisolated let aggregationCursor: Int
    public nonisolated let limitsVersion: Int

    public nonisolated init(
        schemaVersion: Int = Self.currentSchemaVersion,
        periodType: NarrativeReportPeriodType,
        periodKey: String,
        aggregationCursor: Int = 0,
        limitsVersion: Int = NarrativeReportLimits.version
    ) {
        self.schemaVersion = schemaVersion
        self.periodType = periodType
        self.periodKey = periodKey
        self.aggregationCursor = aggregationCursor
        self.limitsVersion = limitsVersion
    }

    public nonisolated func encodedDescriptor(sourceTypes: [String]) throws -> Data {
        guard schemaVersion == Self.currentSchemaVersion,
              limitsVersion == NarrativeReportLimits.version,
              aggregationCursor >= 0,
              periodKey.hasPrefix("\(periodType.rawValue):") else {
            throw NarrativeReportError.invalidReportEnvelope
        }
        let payload = try JSONEncoder().encode(self)
        return try TaskResumeDescriptor(
            operation: .search,
            sourceTypes: Array(Set(sourceTypes)).sorted(),
            payload: payload
        ).encoded()
    }

    public nonisolated static func decodeDescriptor(_ data: Data) throws -> Self {
        let descriptor = try TaskResumeDescriptor.decode(data)
        guard descriptor.operation == .search,
              let payload = try? JSONDecoder().decode(Self.self, from: descriptor.payload),
              payload.schemaVersion == Self.currentSchemaVersion,
              payload.limitsVersion == NarrativeReportLimits.version,
              payload.aggregationCursor >= 0,
              payload.periodKey.hasPrefix("\(payload.periodType.rawValue):") else {
            throw NarrativeReportError.invalidReportEnvelope
        }
        return payload
    }
}

public nonisolated enum NarrativeReportResourceAvailability: Sendable, Equatable {
    case available
    case lowPower
    case thermalConstrained
    case systemExpiration

    public nonisolated var canStart: Bool { self == .available }
}

public nonisolated enum NarrativeReportScanResult: Sendable, Equatable {
    case none
    case deferredForResources
    case generationUnavailable
    case noData(periodKey: String)
    case enqueued(taskID: String, periodKey: String)
    case retryRequired(periodKey: String)
}

public nonisolated enum NarrativeReportAggregator {
    public nonisolated static func prepare(
        period: NarrativeReportPeriod,
        rows: [[String: DBValue]],
        authorizedSourceTypes: Set<String>,
        omittedPartitions: [String]
    ) -> NarrativeReportPreparedInput {
        var accepted: [CreativeSource] = []
        var sources: [NarrativeReportSource] = []
        var usedBytes = 0
        var eligibleCount = 0

        let orderedRows = rows.sorted { lhs, rhs in
            let lhsType = SearchPipeline.normalizeSourceType(lhs["sourceType"]?.stringValue ?? "")
            let rhsType = SearchPipeline.normalizeSourceType(rhs["sourceType"]?.stringValue ?? "")
            if lhsType != rhsType { return lhsType < rhsType }
            let lhsTime = lhs["memoryTimestamp"]?.doubleValue ?? 0
            let rhsTime = rhs["memoryTimestamp"]?.doubleValue ?? 0
            if lhsTime != rhsTime { return lhsTime < rhsTime }
            return (lhs["memoryId"]?.stringValue ?? "") < (rhs["memoryId"]?.stringValue ?? "")
        }
        for row in orderedRows {
            guard let rawID = row["memoryId"]?.stringValue,
                  let memoryID = UUID(uuidString: rawID),
                  let rawType = row["sourceType"]?.stringValue,
                  let timestamp = row["memoryTimestamp"]?.doubleValue else { continue }
            let sourceType = SearchPipeline.normalizeSourceType(rawType)
            guard authorizedSourceTypes.contains(sourceType) else { continue }
            eligibleCount += 1
            guard accepted.count < NarrativeReportLimits.maximumSources else { continue }
            let rawText = row["canonicalText"]?.stringValue ?? ""
            let excerpt = String(rawText.prefix(NarrativeReportLimits.maximumExcerptCharacters))
            let projectedBytes = usedBytes + excerpt.utf8.count + memoryID.uuidString.utf8.count + 32
            guard projectedBytes <= NarrativeReportLimits.maximumModelInputBytes else { continue }
            usedBytes = projectedBytes
            accepted.append(CreativeSource(
                memoryID: memoryID,
                assetID: "",
                sourceType: sourceType,
                text: excerpt.isEmpty ? nil : excerpt,
                timestamp: timestamp
            ))
            sources.append(NarrativeReportSource(
                memoryID: memoryID,
                sourceType: sourceType,
                ordinal: sources.count
            ))
        }

        let batchSize = max(
            1,
            Int(ceil(Double(max(accepted.count, 1)) / Double(NarrativeReportLimits.maximumBatches)))
        )
        let batches = stride(from: 0, to: accepted.count, by: batchSize).map { start in
            Array(accepted[start..<min(start + batchSize, accepted.count)])
        }
        let coverage = NarrativeReportCoverage(
            partialBaseline: period.partialBaseline,
            coverageStart: period.coverageStart,
            coverageEnd: period.endInstant,
            submittedSourceCount: accepted.count,
            truncatedSourceCount: max(0, eligibleCount - accepted.count),
            omittedPartitions: omittedPartitions
        )
        return NarrativeReportPreparedInput(
            request: NarrativeReportGenerationRequest(
                period: period,
                sourceBatches: batches,
                coverage: coverage
            ),
            sources: sources
        )
    }
}

public nonisolated enum NarrativeReportPeriodPlanner {
    public nonisolated static func completedPeriods(
        at now: Date,
        eligibleFrom: Date,
        calendar: Calendar
    ) throws -> [NarrativeReportPeriod] {
        guard eligibleFrom < now else { return [] }
        var candidates: [NarrativeReportPeriod] = []
        candidates.append(contentsOf: try periods(
            type: .month,
            at: now,
            eligibleFrom: eligibleFrom,
            calendar: calendar
        ))
        candidates.append(contentsOf: try periods(
            type: .year,
            at: now,
            eligibleFrom: eligibleFrom,
            calendar: calendar
        ))
        return candidates.sorted {
            if $0.endInstant == $1.endInstant {
                return $0.periodType.tieBreakPriority < $1.periodType.tieBreakPriority
            }
            return $0.endInstant < $1.endInstant
        }
    }

    private nonisolated static func periods(
        type: NarrativeReportPeriodType,
        at now: Date,
        eligibleFrom: Date,
        calendar: Calendar
    ) throws -> [NarrativeReportPeriod] {
        let component: Calendar.Component = type == .month ? .month : .year
        guard let currentInterval = calendar.dateInterval(of: component, for: now) else {
            throw NarrativeReportError.invalidCalendarBoundary
        }
        var cursor = eligibleFrom
        var results: [NarrativeReportPeriod] = []
        while cursor < currentInterval.start {
            guard let interval = calendar.dateInterval(of: component, for: cursor) else {
                throw NarrativeReportError.invalidCalendarBoundary
            }
            guard interval.end > eligibleFrom else {
                cursor = interval.end
                continue
            }
            results.append(makePeriod(
                type: type,
                interval: interval,
                eligibleFrom: eligibleFrom,
                calendar: calendar
            ))
            guard interval.end > cursor else {
                throw NarrativeReportError.invalidCalendarBoundary
            }
            cursor = interval.end
        }
        return results
    }

    private nonisolated static func makePeriod(
        type: NarrativeReportPeriodType,
        interval: DateInterval,
        eligibleFrom: Date,
        calendar: Calendar
    ) -> NarrativeReportPeriod {
        let components = calendar.dateComponents([.year, .month], from: interval.start)
        let key: String
        switch type {
        case .month:
            key = String(format: "month:%04d-%02d", components.year ?? 0, components.month ?? 0)
        case .year:
            key = String(format: "year:%04d", components.year ?? 0)
        }
        let coverageStart = max(interval.start, eligibleFrom)
        return NarrativeReportPeriod(
            periodType: type,
            periodKey: key,
            calendarIdentifier: calendarIdentifier(calendar.identifier),
            timeZoneIdentifier: calendar.timeZone.identifier,
            startInstant: interval.start,
            endInstant: interval.end,
            coverageStart: coverageStart,
            partialBaseline: coverageStart > interval.start
        )
    }

    private nonisolated static func calendarIdentifier(_ identifier: Calendar.Identifier) -> String {
        identifier == .gregorian ? "gregorian" : String(describing: identifier)
    }
}

public nonisolated enum NarrativeReportError: Error, Sendable, Equatable {
    case invalidCalendarBoundary
    case scheduleUnavailable
    case periodUnavailable
    case privacyDenied
    case generationUnavailable
    case invalidReportEnvelope
    case invalidatedPeriod
    case resourceDeferred
    case publicationConflict
    case injectedPublicationFailure
}
