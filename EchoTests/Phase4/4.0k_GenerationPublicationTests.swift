// ==========================================
// File: 4.0k_GenerationPublicationTests.swift
// Spec: US-SYN-004; ADR-023 sections 3/5
// Task: 4.0k - Final generation publication boundary
// AC coverage: consent, current source content and complete derived dependencies
// Architecture: AGENTS.md D-005, sections 4.2/7.1
// Generated: 2026-09-08
// ==========================================

import Foundation
import Testing

@testable import Echo

private actor SourceChangingGenerationProvider: StructuredLLMProvider {
    let database: DatabaseManager
    let id: UUID
    private(set) var calls = 0
    init(database: DatabaseManager, id: UUID) {
        self.database = database
        self.id = id
    }
    func validateAvailability(traceID: String) async throws {}
    func tokenCount(request: GenerationRequest) async throws -> Int { 300 }
    func generate(prompt: String, preferredLanguage: String) async throws -> String {
        throw GenerationRuntimeError.invalidRequest
    }
    func generate(request: GenerationRequest) async throws -> GenerationResult {
        calls += 1
        try await database.executeWrite(
            sql: "UPDATE Memory SET canonicalText = 'Changed while generating' WHERE memoryId = ?",
            bindings: [.text(id.uuidString)]
        )
        return GenerationResult(
            envelope:
                "{\"schemaVersion\":1,\"paragraphs\":[{\"text\":\"The family walked together in the garden during the afternoon.\",\"sourceMemoryIDs\":[\"\(id.uuidString)\"]}]}",
            inputTokenCount: 300,
            outputTokenCount: 60,
            predictionCount: 359,
            elapsedSeconds: 1,
            artifactIdentity: "test-double"
        )
    }
}

@Suite("4.0k Generation Publication", .serialized)
struct GenerationPublicationTests {
    @Test("AC-2: source edits during manual generation invalidate the response")
    func test_AC2_manualGenerationRejectsEditedSource() async throws {
        let database = DatabaseManager(
            databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                "snapshot-\(UUID().uuidString).sqlite"
            )
        )
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["note"]))
        let id = UUID()
        try await database.executeWrite(
            sql:
                "INSERT INTO Memory (memoryId, sourceLocator, canonicalText, sourceType, createdAt, updatedAt, recoverability) VALUES (?, '', 'The family walked in the garden.', 'note', 1, 1, 'full')",
            bindings: [.text(id.uuidString)]
        )
        let provider = SourceChangingGenerationProvider(database: database, id: id)
        let repository = CanonicalMemoryRepositoryActor(db: database, privacyActor: privacy)
        let pipeline = CreativePipeline(
            llmProvider: provider,
            aligner: LanguageAligner(llmProvider: provider),
            privacyActor: privacy,
            canonicalRepository: repository
        )
        await #expect(throws: GenerationRuntimeError.privacyDenied) {
            _ = try await pipeline.generate(
                template: .report,
                sources: [.init(memoryID: id, assetID: "", sourceType: "note", text: nil, timestamp: 1)],
                traceID: "edited-during-generation"
            )
        }
        #expect(await provider.calls == 1)
        let success = try await database.executeQuery(
            sql: "SELECT COUNT(*) AS total FROM AuditLog WHERE eventType = 'creativeGeneration' AND success = 1",
            bindings: []
        )
        #expect(success.first?["total"]?.intValue == 0)
    }

    enum Mutation: CaseIterable { case none, withdrawConsent, changeSource, omitDependency }

    @Test("AC-2/7: final transaction rechecks consent and every contributing source", arguments: Mutation.allCases)
    func test_AC2_AC7_finalPublicationRevalidation(_ mutation: Mutation) async throws {
        let database = DatabaseManager(
            databaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("4.0k-publication-\(UUID().uuidString).sqlite")
        )
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(
            UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["note"], policyVersion: 3)
        )
        try await database.executeWrite(
            sql:
                "INSERT OR REPLACE INTO ConsentStore (id, hasConsented, consentVersion, policyVersion, updatedAt) VALUES (1, 1, 1, 3, 1)",
            bindings: []
        )
        let id = UUID()
        let revision = 1_764_550_800.0
        let text = "The family walked in the garden."
        try await database.executeWrite(
            sql:
                "INSERT INTO Memory (memoryId, sourceLocator, canonicalText, sourceType, createdAt, updatedAt, recoverability) VALUES (?, '', ?, 'note', ?, ?, 'full')",
            bindings: [.text(id.uuidString), .text(text), .double(revision), .double(revision)]
        )
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
            taskID: "publication"
        )
        try await database.executeWrite(
            sql:
                "INSERT INTO NarrativeReportPeriod (periodType, periodKey, calendarIdentifier, timeZoneIdentifier, startInstant, endInstant, coverageStart, partialBaseline, state, revision, claimedAt, taskId, updatedAt) VALUES ('month', 'month:2025-12', 'gregorian', 'UTC', ?, ?, ?, 0, 'claimed', 1, ?, 'publication', ?)",
            bindings: [
                .double(start.timeIntervalSince1970), .double(end.timeIntervalSince1970),
                .double(start.timeIntervalSince1970), .double(end.timeIntervalSince1970),
                .double(end.timeIntervalSince1970),
            ]
        )
        let checkpoint = await privacy.validate(operation: .search, traceID: "publication", sourceTypes: ["note"])
        let audit = try await privacy.prepareNarrativeReportAuditPayload(
            checkpoint: checkpoint,
            period: period,
            sourceTypes: ["note"]
        )
        let contributors = mutation == .omitDependency ? [id, UUID()] : [id]
        let coverage = NarrativeReportCoverage(
            partialBaseline: false,
            coverageStart: start,
            coverageEnd: end,
            submittedSourceCount: contributors.count
        )
        let envelope = NarrativeReportEnvelope(
            title: "December",
            periodType: .month,
            periodKey: period.periodKey,
            paragraphs: [.init(id: UUID(), text: text, sourceMemoryIDs: [id], groundingStatus: .cited)],
            coverage: coverage,
            contributingMemoryIDs: contributors,
            modelCallCount: 1,
            omittedParagraphCount: 0
        )
        let publication = NarrativeReportPublication(
            period: period,
            envelope: envelope,
            sources: [
                .init(
                    memoryID: id,
                    sourceType: "note",
                    ordinal: 0,
                    sourceRevision: revision,
                    contentDigest: AuditContentHasher.sha256Hex(text)
                ),
            ],
            audit: audit
        )
        switch mutation {
        case .none:
            try await database.publishNarrativeReport(publication)

        case .withdrawConsent:
            try await database.executeWrite(sql: "UPDATE ConsentStore SET hasConsented = 0 WHERE id = 1", bindings: [])
            await #expect(throws: NarrativeReportError.privacyDenied) {
                try await database.publishNarrativeReport(publication)
            }

        case .changeSource:
            try await database.executeWrite(
                sql: "UPDATE Memory SET canonicalText = 'Changed after generation' WHERE memoryId = ?",
                bindings: [.text(id.uuidString)]
            )
            await #expect(throws: NarrativeReportError.publicationConflict) {
                try await database.publishNarrativeReport(publication)
            }

        case .omitDependency:
            await #expect(throws: NarrativeReportError.invalidReportEnvelope) {
                try await database.publishNarrativeReport(publication)
            }
        }
        let reports = try await database.executeQuery(sql: "SELECT * FROM NarrativeReport", bindings: [])
        let audits = try await privacy.fetchAuditLogs(eventType: .narrativeReportGenerated)
        #expect(reports.count == (mutation == .none ? 1 : 0))
        #expect(audits.count == (mutation == .none ? 1 : 0))
    }
}
