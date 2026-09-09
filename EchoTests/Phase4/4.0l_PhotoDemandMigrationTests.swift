// Task 4.0l; ADR-025: retire automatic backlog, preserve requested work and ready material.
import Foundation
import Testing

@testable import Echo

@Suite("4.0l Photo Demand Migration", .serialized)
struct PhotoDemandMigrationTests {
    @Test("AC-6: reopening clears only legacy automatic queued photo work")
    func test_AC6_legacyBacklog() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("photo-demand-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path.path + suffix) }
        }
        let db = DatabaseManager(databaseURL: path)
        try await db.open()
        if try await !db.executeQuery(sql: "PRAGMA table_info(PhotoUnderstandingJob)", bindings: []).contains(where: {
            $0["name"]?.stringValue == "requestOrigin"
        }) {
            try await db.executeWrite(
                sql: "ALTER TABLE PhotoUnderstandingJob ADD COLUMN requestOrigin TEXT NOT NULL DEFAULT 'automatic'",
                bindings: []
            )
        }
        for (id, origin, state) in [
            ("old", "automatic", "queued"), ("requested", "onDemand", "queued"), ("ready", "automatic", "ready"),
        ] {
            try await db.executeWrite(
                sql:
                    "INSERT INTO Memory (memoryId, sourceLocator, sourceType, createdAt, updatedAt) VALUES (?, ?, 'photo', 1, 1)",
                bindings: [.text(id), .text(id)]
            )
            try await db.executeWrite(
                sql:
                    "INSERT INTO PhotoUnderstandingJob (memoryId, taskId, sourceVersion, assetRevision, modelVersion, processingVersion, state, updatedAt, requestOrigin) VALUES (?, ?, 's', 'a', 'm', 'p', ?, 1, ?)",
                bindings: [.text(id), .text(id), .text(state), .text(origin)]
            )
        }
        await db.close()
        try await db.open()
        let rows = try await db.executeQuery(
            sql: "SELECT memoryId FROM PhotoUnderstandingJob ORDER BY memoryId",
            bindings: []
        )
        #expect(rows.compactMap { $0["memoryId"]?.stringValue } == ["ready", "requested"])
        #expect(try await db.executeQuery(sql: "SELECT memoryId FROM Memory", bindings: []).count == 3)
        await db.close()
    }
}
