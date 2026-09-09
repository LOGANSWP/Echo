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
// Task 4.0k (2026-09-08): bounded actual coverage, source revisions and content-free resume identity.
// Traceability: US-SYN-001/004 and ADR-023; device/quality qualification remains pending.
// ==========================================

import Foundation

nonisolated public enum NarrativeReportPeriodType: String, Sendable, Codable, CaseIterable {
    case month
    case year

    nonisolated var tieBreakPriority: Int {
        switch self {
        case .month: 0
        case .year: 1
        }
    }
}

nonisolated public enum NarrativeReportPeriodState: String, Sendable, Codable, Equatable {
    case eligible
    case claimed
    case retryRequired
    case completed
    case noData
    case invalidated
}

nonisolated public enum NarrativeReportScanTrigger: String, Sendable, Codable, Equatable {
    case launch
    case foreground
    case background
    case userInitiated
}

/// A value-only calendar description that is safe to cross actor boundaries.
/// Narrative reports intentionally use the Gregorian calendar; the time zone is
/// captured when a period is materialized and never recomputed for that period.
nonisolated public struct NarrativeReportCalendarContext: Sendable, Codable, Equatable {
    nonisolated public let timeZoneIdentifier: String

    nonisolated public init(timeZoneIdentifier: String) {
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    nonisolated public func makeCalendar() throws -> Calendar {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw NarrativeReportError.invalidCalendarBoundary
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

nonisolated public struct NarrativeReportSchedule: Sendable, Codable, Equatable {
    nonisolated public let monthlyEnabled: Bool
    nonisolated public let yearlyEnabled: Bool
    nonisolated public let monthlyEligibleFrom: Date?
    nonisolated public let yearlyEligibleFrom: Date?
    nonisolated public let updatedAt: Date

    nonisolated public init(
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

    nonisolated public func eligibleFrom(for type: NarrativeReportPeriodType) -> Date? {
        switch type {
        case .month: monthlyEligibleFrom
        case .year: yearlyEligibleFrom
        }
    }
}

nonisolated public struct NarrativeReportPeriod: Sendable, Codable, Equatable, Identifiable {
    nonisolated public var id: String { periodKey }
    nonisolated public let periodType: NarrativeReportPeriodType
    nonisolated public let periodKey: String
    nonisolated public let calendarIdentifier: String
    nonisolated public let timeZoneIdentifier: String
    nonisolated public let startInstant: Date
    nonisolated public let endInstant: Date
    nonisolated public let coverageStart: Date
    nonisolated public let partialBaseline: Bool
    nonisolated public let state: NarrativeReportPeriodState
    nonisolated public let revision: Int
    nonisolated public let claimedAt: Date?
    nonisolated public let taskID: String?

    nonisolated public init(
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

nonisolated public enum NarrativeReportLimits {
    nonisolated public static let version = 1
    nonisolated public static let maximumSources = 256
    nonisolated public static let maximumExcerptCharacters = 512
    nonisolated public static let maximumBatches = 16
    nonisolated public static let maximumAggregationLayers = 3
    nonisolated public static let maximumModelInputBytes = 128 * 1_024
    nonisolated public static let maximumEnvelopeBytes = 256 * 1_024
    nonisolated public static let maximumParagraphs = 64
    nonisolated public static let maximumParagraphCharacters = 8_000
    nonisolated public static let maximumReferencesPerParagraph = 16
}

nonisolated public struct NarrativeReportCoverage: Sendable, Codable, Equatable {
    nonisolated public let partialBaseline: Bool
    nonisolated public let coverageStart: Date
    nonisolated public let coverageEnd: Date
    nonisolated public let submittedSourceCount: Int
    nonisolated public let truncatedSourceCount: Int
    nonisolated public let omittedPartitions: [String]
    nonisolated public let limitsVersion: Int
    nonisolated public let aggregationLayerCount: Int

    nonisolated public init(
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

nonisolated public struct NarrativeReportParagraph: Sendable, Codable, Equatable, Identifiable {
    nonisolated public let id: UUID
    nonisolated public let text: String
    nonisolated public let sourceMemoryIDs: [UUID]
    nonisolated public let groundingStatus: GroundingStatus

    nonisolated public init(
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

nonisolated public struct NarrativeReportEnvelope: Sendable, Codable, Equatable {
    nonisolated public static let currentSchemaVersion = 1
    nonisolated public let schemaVersion: Int
    nonisolated public let title: String
    nonisolated public let periodType: NarrativeReportPeriodType
    nonisolated public let periodKey: String
    nonisolated public let paragraphs: [NarrativeReportParagraph]
    nonisolated public let contributingMemoryIDs: [UUID]?
    nonisolated public let modelCallCount: Int?
    nonisolated public let omittedParagraphCount: Int?
    nonisolated public let coverage: NarrativeReportCoverage

    nonisolated public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        title: String,
        periodType: NarrativeReportPeriodType,
        periodKey: String,
        paragraphs: [NarrativeReportParagraph],
        coverage: NarrativeReportCoverage,
        contributingMemoryIDs: [UUID]? = nil,
        modelCallCount: Int? = nil,
        omittedParagraphCount: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.periodType = periodType
        self.periodKey = periodKey
        self.paragraphs = paragraphs
        self.coverage = coverage
        self.contributingMemoryIDs = contributingMemoryIDs
        self.modelCallCount = modelCallCount
        self.omittedParagraphCount = omittedParagraphCount
    }

    nonisolated public func encoded() throws -> Data {
        guard schemaVersion == Self.currentSchemaVersion,
            paragraphs.count <= NarrativeReportLimits.maximumParagraphs,
            paragraphs.allSatisfy({
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.text.count <= NarrativeReportLimits.maximumParagraphCharacters
                    && $0.sourceMemoryIDs.count <= NarrativeReportLimits.maximumReferencesPerParagraph
            }),
            coverage.limitsVersion == NarrativeReportLimits.version,
            (1...NarrativeReportLimits.maximumAggregationLayers)
                .contains(coverage.aggregationLayerCount)
        else {
            throw NarrativeReportError.invalidReportEnvelope
        }
        if let contributors = contributingMemoryIDs {
            guard (1...24).contains(contributors.count), Set(contributors).count == contributors.count,
                coverage.submittedSourceCount == contributors.count,
                Set(paragraphs.flatMap(\.sourceMemoryIDs)).isSubset(of: Set(contributors)),
                let modelCallCount, (1...32).contains(modelCallCount),
                let omittedParagraphCount,
                (0...(NarrativeReportLimits.maximumParagraphs * 32)).contains(omittedParagraphCount),
                !paragraphs.isEmpty
            else { throw NarrativeReportError.invalidReportEnvelope }
        } else if modelCallCount != nil || omittedParagraphCount != nil {
            throw NarrativeReportError.invalidReportEnvelope
        }
        guard coverage.submittedSourceCount >= 0, coverage.truncatedSourceCount >= 0,
            coverage.coverageEnd > coverage.coverageStart
        else { throw NarrativeReportError.invalidReportEnvelope }
        let data = try JSONEncoder().encode(self)
        guard data.count <= NarrativeReportLimits.maximumEnvelopeBytes else {
            throw NarrativeReportError.invalidReportEnvelope
        }
        return data
    }

    nonisolated public static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= NarrativeReportLimits.maximumEnvelopeBytes,
            let value = try? JSONDecoder().decode(Self.self, from: data)
        else {
            throw NarrativeReportError.invalidReportEnvelope
        }
        _ = try value.encoded()
        return value
    }
}

nonisolated public struct NarrativeReportSource: Sendable, Codable, Equatable {
    nonisolated public let memoryID: UUID
    nonisolated public let sourceType: String
    nonisolated public let ordinal: Int
    nonisolated public let sourceRevision: Double?
    nonisolated public let contentDigest: String?
    nonisolated public let availability: CitationSourceAvailability

    nonisolated public init(
        memoryID: UUID,
        sourceType: String,
        ordinal: Int,
        availability: CitationSourceAvailability = .available,
        sourceRevision: Double? = nil,
        contentDigest: String? = nil
    ) {
        self.memoryID = memoryID
        self.sourceType = SearchPipeline.normalizeSourceType(sourceType)
        self.ordinal = ordinal
        self.availability = availability
        self.sourceRevision = sourceRevision
        self.contentDigest = contentDigest
    }
}

nonisolated public struct PersistedNarrativeReport: Sendable, Equatable, Identifiable {
    nonisolated public let id: UUID
    nonisolated public let periodType: NarrativeReportPeriodType
    nonisolated public let periodKey: String
    nonisolated public let envelope: NarrativeReportEnvelope
    nonisolated public let sources: [NarrativeReportSource]
    nonisolated public let createdAt: Date

    nonisolated public var sourceTypes: [String] {
        Array(Set(sources.map(\.sourceType))).sorted()
    }

    nonisolated public init(
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
nonisolated public struct NarrativeReportAuditPayload: Sendable, Equatable {
    nonisolated public let traceID: String
    nonisolated public let policyVersion: Int
    nonisolated public let periodType: NarrativeReportPeriodType
    nonisolated public let dataSourcesUsedJSON: String
    nonisolated public let periodKeyDigest: String
    nonisolated public let timestamp: Date

    nonisolated public init(
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

nonisolated public struct NarrativeReportPublication: Sendable {
    nonisolated public let reportID: UUID
    nonisolated public let period: NarrativeReportPeriod
    nonisolated public let envelope: NarrativeReportEnvelope
    nonisolated public let sources: [NarrativeReportSource]
    nonisolated public let audit: NarrativeReportAuditPayload
    nonisolated public let createdAt: Date

    nonisolated public init(
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

nonisolated public struct NarrativeReportGenerationRequest: Sendable, Equatable {
    nonisolated public let period: NarrativeReportPeriod
    nonisolated public let sourceBatches: [[CreativeSource]]
    nonisolated public let coverage: NarrativeReportCoverage

    nonisolated public init(
        period: NarrativeReportPeriod,
        sourceBatches: [[CreativeSource]],
        coverage: NarrativeReportCoverage
    ) {
        self.period = period
        self.sourceBatches = sourceBatches
        self.coverage = coverage
    }

    nonisolated public var sources: [CreativeSource] {
        sourceBatches.flatMap { $0 }
    }
}

nonisolated public struct NarrativeReportPreparedInput: Sendable, Equatable {
    nonisolated public let request: NarrativeReportGenerationRequest
    nonisolated public let sources: [NarrativeReportSource]

    nonisolated public init(
        request: NarrativeReportGenerationRequest,
        sources: [NarrativeReportSource]
    ) {
        self.request = request
        self.sources = sources
    }
}

nonisolated public struct NarrativeReportResumePayload: Sendable, Codable, Equatable {
    nonisolated public static let currentSchemaVersion = 2
    nonisolated public let schemaVersion: Int
    nonisolated public let periodType: NarrativeReportPeriodType
    nonisolated public let periodKey: String
    nonisolated public let executionIdentity: String?
    nonisolated public let aggregationCursor: Int
    nonisolated public let limitsVersion: Int

    nonisolated public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        periodType: NarrativeReportPeriodType,
        periodKey: String,
        aggregationCursor: Int = 0,
        executionIdentity: String? = nil,
        limitsVersion: Int = NarrativeReportLimits.version
    ) {
        self.schemaVersion = schemaVersion
        self.periodType = periodType
        self.periodKey = periodKey
        self.aggregationCursor = aggregationCursor
        self.executionIdentity = executionIdentity
        self.limitsVersion = limitsVersion
    }

    nonisolated public func encodedDescriptor(sourceTypes: [String]) throws -> Data {
        guard (1...Self.currentSchemaVersion).contains(schemaVersion),
            Self.validIdentity(executionIdentity),
            limitsVersion == NarrativeReportLimits.version,
            aggregationCursor >= 0,
            periodKey.hasPrefix("\(periodType.rawValue):")
        else {
            throw NarrativeReportError.invalidReportEnvelope
        }
        let payload = try JSONEncoder().encode(self)
        return try TaskResumeDescriptor(
            operation: .search,
            sourceTypes: Array(Set(sourceTypes)).sorted(),
            payload: payload
        ).encoded()
    }

    nonisolated public static func decodeDescriptor(_ data: Data) throws -> Self {
        let descriptor = try TaskResumeDescriptor.decode(data)
        guard descriptor.operation == .search,
            let payload = try? JSONDecoder().decode(Self.self, from: descriptor.payload),
            (1...Self.currentSchemaVersion).contains(payload.schemaVersion),
            Self.validIdentity(payload.executionIdentity),
            payload.limitsVersion == NarrativeReportLimits.version,
            payload.aggregationCursor >= 0,
            payload.periodKey.hasPrefix("\(payload.periodType.rawValue):")
        else {
            throw NarrativeReportError.invalidReportEnvelope
        }
        return payload
    }

    nonisolated private static func validIdentity(_ identity: String?) -> Bool {
        guard let identity else { return true }
        return identity.utf8.count == 64
            && identity.utf8.allSatisfy {
                (48...57).contains($0) || (97...102).contains($0)
            }
    }
}

nonisolated public enum NarrativeReportResourceAvailability: Sendable, Equatable {
    case available
    case lowPower
    case thermalConstrained
    case systemExpiration

    nonisolated public var canStart: Bool { self == .available }
}

nonisolated public enum NarrativeReportScanResult: Sendable, Equatable {
    case none
    case deferredForResources
    case generationUnavailable
    case noData(periodKey: String)
    case enqueued(taskID: String, periodKey: String)
    case retryRequired(periodKey: String)
}

nonisolated public enum NarrativeReportAggregator {
    nonisolated public static func prepare(
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
                let timestamp = row["memoryTimestamp"]?.doubleValue
            else { continue }
            let sourceType = SearchPipeline.normalizeSourceType(rawType)
            guard authorizedSourceTypes.contains(sourceType) else { continue }
            eligibleCount += 1
            guard accepted.count < NarrativeReportLimits.maximumSources else { continue }
            let rawText = row["canonicalText"]?.stringValue ?? ""
            let excerpt = String(rawText.prefix(NarrativeReportLimits.maximumExcerptCharacters))
            let projectedBytes = usedBytes + excerpt.utf8.count + memoryID.uuidString.utf8.count + 32
            guard projectedBytes <= NarrativeReportLimits.maximumModelInputBytes else { continue }
            usedBytes = projectedBytes
            accepted.append(
                CreativeSource(
                    memoryID: memoryID,
                    assetID: "",
                    sourceType: sourceType,
                    text: excerpt.isEmpty ? nil : excerpt,
                    timestamp: timestamp,
                    revision: row["updatedAt"]?.doubleValue
                )
            )
            sources.append(
                NarrativeReportSource(
                    memoryID: memoryID,
                    sourceType: sourceType,
                    ordinal: sources.count,
                    sourceRevision: row["updatedAt"]?.doubleValue,
                    contentDigest: AuditContentHasher.sha256Hex(rawText)
                )
            )
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
            truncatedSourceCount: max(
                0,
                max(
                    eligibleCount,
                    Int(rows.first?["eligibleSourceCount"]?.intValue ?? 0)
                ) - accepted.count
            ),
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

nonisolated public enum NarrativeReportPeriodPlanner {
    nonisolated public static func completedPeriods(
        at now: Date,
        eligibleFrom: Date,
        calendar: Calendar
    ) throws -> [NarrativeReportPeriod] {
        guard eligibleFrom < now else { return [] }
        var candidates: [NarrativeReportPeriod] = []
        candidates.append(
            contentsOf: try periods(
                type: .month,
                at: now,
                eligibleFrom: eligibleFrom,
                calendar: calendar
            )
        )
        candidates.append(
            contentsOf: try periods(
                type: .year,
                at: now,
                eligibleFrom: eligibleFrom,
                calendar: calendar
            )
        )
        return candidates.sorted {
            if $0.endInstant == $1.endInstant {
                return $0.periodType.tieBreakPriority < $1.periodType.tieBreakPriority
            }
            return $0.endInstant < $1.endInstant
        }
    }

    nonisolated private static func periods(
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
            results.append(
                makePeriod(
                    type: type,
                    interval: interval,
                    eligibleFrom: eligibleFrom,
                    calendar: calendar
                )
            )
            guard interval.end > cursor else {
                throw NarrativeReportError.invalidCalendarBoundary
            }
            cursor = interval.end
        }
        return results
    }

    nonisolated private static func makePeriod(
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

    nonisolated private static func calendarIdentifier(_ identifier: Calendar.Identifier) -> String {
        identifier == .gregorian ? "gregorian" : String(describing: identifier)
    }
}

nonisolated public enum NarrativeReportError: Error, Sendable, Equatable {
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
