// File: 4.0m_CreationDeletionTests.swift
// Spec: US-SYN-003 AC-9/10; US-SYN-004 AC-7; ADR-026
// Task: 4.0m - Explicit library deletion preserves source memories
import Foundation
import Testing
@testable import Echo

@Suite("4.0m Creation Deletion", .serialized)
@MainActor
struct CreationDeletionTests {
    @Test("AC-9/10: deleting either library kind preserves sources and survives reopening", arguments: [false, true], [false, true])
    func test_AC9_deleteLibraryEntry(report: Bool, failDeletion: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("creation-delete-\(UUID()).sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let db = DatabaseManager(databaseURL: url)
        try await db.open()
        let privacy = PrivacyActor(db: db)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["note"]))
        let sourceID = UUID()
        let id = UUID()
        try await db.executeWrite(sql: "INSERT INTO Memory(memoryId,sourceLocator,sourceType,canonicalText,createdAt,updatedAt) VALUES (?,'deletion-test','note','A garden grows.',1,1)", bindings: [.text(sourceID.uuidString)])
        if report {
            try await insertReport(id: id, sourceID: sourceID, database: db)
        } else {
            let checkpoint = await privacy.validate(operation: .search, traceID: "delete-fixture")
            let request = CreationLibraryRequest(id: id, template: .letter, sourceIDs: [sourceID], language: "en-US")
            try await db.insertCreationRequest(request, checkpoint: checkpoint, requiresConsent: false)
            try await db.updateCreationState(id: id, state: .running)
            let output = CreativeOutput(template: .letter, title: "Garden", paragraphs: [GroundedParagraph(id: UUID(), text: "A garden grows.", anchors: [SourceAnchor(memoryID: sourceID, sourceType: "note")], groundingStatus: .cited)], sourceMemoryCount: 1, sourceTypes: ["note"])
            try await db.publishCreation(output, request: request, checkpoint: checkpoint, requiresConsent: false)
        }
        let repository = CanonicalMemoryRepositoryActor(db: db, privacyActor: privacy)
        let pipeline = CreativePipeline(llmProvider: nil, aligner: LanguageAligner(llmProvider: nil, preferredLanguage: "en-US"), privacyActor: privacy)
        let library = CreationLibraryActor(database: db, privacy: privacy, queue: TaskQueueActor(progressActor: ProgressActor(db: db)), repository: repository, pipeline: pipeline)
        let model = CreationLibraryViewModel(library: library, reportActor: NarrativeReportActor(database: db, privacyActor: privacy))
        await model.refresh()
        #expect(model.entries.map(\.id) == [id])
        if failDeletion {
            let table = report ? "NarrativeReport" : "CreationLibrary"
            try await db.executeWrite(sql: "CREATE TRIGGER reject_library_delete BEFORE DELETE ON \(table) BEGIN SELECT RAISE(ABORT,'injected deletion failure'); END", bindings: [])
            await model.delete(id)
            #expect(model.entries.map(\.id) == [id])
            #expect(model.deletionError)
            await model.refresh()
            #expect(model.deletionError)
            try await db.executeWrite(sql: "DROP TRIGGER reject_library_delete", bindings: [])
        }
        await model.delete(id)
        #expect(!model.deletionError)
        #expect(!model.error)
        #expect(model.entries.isEmpty)
        #expect(try await db.executeQuery(sql: "SELECT memoryId FROM Memory WHERE memoryId=?", bindings: [.text(sourceID.uuidString)]).count == 1)
        #expect(try await db.executeQuery(sql: "SELECT * FROM ExcludedAssets", bindings: []).isEmpty)
        if report {
            #expect(try await db.executeQuery(sql: "SELECT state FROM NarrativeReportPeriod", bindings: []).first?["state"]?.stringValue == "invalidated")
            #expect(try await db.executeQuery(sql: "SELECT * FROM NarrativeReportSource", bindings: []).isEmpty)
        } else {
            #expect(try await db.executeQuery(sql: "SELECT * FROM CreationLibrarySource", bindings: []).isEmpty)
        }
        await db.close()
        try await db.open()
        await model.refresh()
        #expect(model.entries.isEmpty)
        await db.close()
    }

    private func insertReport(id: UUID, sourceID: UUID, database: DatabaseManager) async throws {
        let key = "month:2025-12"
        let coverage = NarrativeReportCoverage(partialBaseline: false, coverageStart: Date(timeIntervalSince1970: 1), coverageEnd: Date(timeIntervalSince1970: 2), submittedSourceCount: 1)
        let envelope = NarrativeReportEnvelope(title: "Garden report", periodType: .month, periodKey: key, paragraphs: [NarrativeReportParagraph(id: UUID(), text: "A garden grows.", sourceMemoryIDs: [sourceID], groundingStatus: .cited)], coverage: coverage)
        try await database.executeWrite(sql: "INSERT INTO NarrativeReportPeriod(periodType,periodKey,calendarIdentifier,timeZoneIdentifier,startInstant,endInstant,coverageStart,partialBaseline,state,updatedAt) VALUES ('month',?,'gregorian','UTC',1,2,1,0,'completed',2)", bindings: [.text(key)])
        try await database.executeWrite(sql: "INSERT INTO NarrativeReport VALUES (?,'month',?,1,'Garden report',?,?,2)", bindings: [.text(id.uuidString), .text(key), .blob(try JSONEncoder().encode(envelope)), .text(try #require(String(data: JSONEncoder().encode(coverage), encoding: .utf8)))])
        try await database.executeWrite(sql: "INSERT INTO NarrativeReportSource(reportId,memoryId,sourceType,ordinal) VALUES (?,?,'note',0)", bindings: [.text(id.uuidString), .text(sourceID.uuidString)])
    }
}
