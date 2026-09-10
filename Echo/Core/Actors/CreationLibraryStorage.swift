// File: CreationLibraryStorage.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md -> US-SYN-003 AC-8/9/10; ADR-026
// Task: 4.0m - Atomic creation persistence and deletion
// Architecture: DatabaseManager isolation and current policy transactions
// PR #81 / AC-10: normalize supported aliases at the policy boundary.
// Generated: 2026-09-09
import Foundation

extension DatabaseManager {
    func createCreationLibrarySchema() throws {
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS CreationLibrary (
                id TEXT PRIMARY KEY, request BLOB NOT NULL, state TEXT NOT NULL,
                createdAt REAL NOT NULL, output BLOB, errorCode TEXT, unread INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS CreationLibrarySource (
                creationId TEXT NOT NULL REFERENCES CreationLibrary(id) ON DELETE CASCADE,
                memoryId TEXT NOT NULL REFERENCES Memory(memoryId) ON DELETE CASCADE,
                PRIMARY KEY(creationId, memoryId)
            );
            CREATE TRIGGER IF NOT EXISTS creation_source_delete BEFORE DELETE ON Memory BEGIN
                DELETE FROM CreationLibrary WHERE id IN
                    (SELECT creationId FROM CreationLibrarySource WHERE memoryId = OLD.memoryId);
            END;
            CREATE TRIGGER IF NOT EXISTS creation_source_exclude AFTER INSERT ON ExcludedAssets BEGIN
                DELETE FROM CreationLibrary WHERE id IN
                    (SELECT s.creationId FROM CreationLibrarySource s JOIN Memory m ON m.memoryId = s.memoryId
                     WHERE m.sourceLocator = NEW.assetId);
            END;
            CREATE TRIGGER IF NOT EXISTS creation_consent_revoked AFTER UPDATE OF hasConsented ON ConsentStore
            WHEN NEW.hasConsented = 0 BEGIN DELETE FROM CreationLibrary; END;
            CREATE TRIGGER IF NOT EXISTS creation_consent_deleted AFTER DELETE ON ConsentStore
            BEGIN DELETE FROM CreationLibrary; END;
            CREATE TRIGGER IF NOT EXISTS creation_job_delete AFTER DELETE ON CreationLibrary BEGIN
                DELETE FROM TaskProgress WHERE taskId = 'creation-' || OLD.id;
                DELETE FROM PendingOperations WHERE operationId = 'creation-' || OLD.id;
            END;
            """)
        // No queue is owned before database open; abandoned jobs need explicit user retry.
        try execute(sql: "DELETE FROM TaskProgress WHERE taskId IN (SELECT 'creation-' || id FROM CreationLibrary)")
        try execute(sql: "UPDATE CreationLibrary SET state = 'interrupted', errorCode = 'interrupted' WHERE state IN ('submitting','queued','running')")
    }

    func insertCreationRequest(_ request: CreationLibraryRequest, checkpoint: PrivacyCheckpoint, requiresConsent: Bool) throws {
        try request.validate(forExecution: true)
        let encoded = try JSONEncoder().encode(request)
        guard encoded.count <= 16384 else { throw GenerationRuntimeError.contextLimit }
        try execute(sql: "BEGIN IMMEDIATE")
        do {
            try validateCreationAccess(request, checkpoint: checkpoint, requiresConsent: requiresConsent)
            if let existing = try executeQuery(sql: "SELECT request FROM CreationLibrary WHERE id = ?", bindings: [.text(request.id.uuidString)]).first {
                guard let previous = existing["request"]?.blobValue, try JSONDecoder().decode(CreationLibraryRequest.self, from: previous) == request else { throw GenerationRuntimeError.invalidRequest }
            } else {
                try executeWrite(sql: "INSERT INTO CreationLibrary(id,request,state,createdAt) VALUES (?,?,'submitting',?)", bindings: [.text(request.id.uuidString), .blob(encoded), .double(Date().timeIntervalSince1970)])
                for id in request.sourceIDs {
                    try executeWrite(sql: "INSERT INTO CreationLibrarySource VALUES (?,?)", bindings: [.text(request.id.uuidString), .text(id.uuidString)])
                }
            }
            try execute(sql: "COMMIT")
        } catch { try? execute(sql: "ROLLBACK"); throw error }
    }

    func creationRecords(checkpoint: PrivacyCheckpoint, requiresConsent: Bool) throws -> [CreationLibraryRecord] {
        let rows = try executeQuery(sql: "SELECT id,request,state,createdAt,CASE WHEN length(output)<=262144 THEN output END AS output,errorCode,unread FROM CreationLibrary WHERE length(request)<=16384 ORDER BY createdAt DESC", bindings: [])
        return try rows.compactMap { row in
            guard let data = row["request"]?.blobValue else { throw GenerationRuntimeError.invalidRequest }
            let request = try JSONDecoder().decode(CreationLibraryRequest.self, from: data)
            try request.validate()
            do { try validateCreationAccess(request, checkpoint: checkpoint, requiresConsent: requiresConsent) } catch GenerationRuntimeError.privacyDenied { return nil }
            guard let state = CreationLibraryState(rawValue: row["state"]?.stringValue ?? "") else { throw GenerationRuntimeError.invalidRequest }
            let output = try row["output"]?.blobValue.map { try JSONDecoder().decode(CreativeOutput.self, from: $0) }
            guard state != .completed || output != nil else { throw GenerationRuntimeError.invalidRequest }
            return CreationLibraryRecord(request: request, state: state, createdAt: Date(timeIntervalSince1970: row["createdAt"]?.doubleValue ?? 0), output: output, errorCode: row["errorCode"]?.stringValue, unread: row["unread"]?.intValue == 1)
        }
    }

    func updateCreationState(id: UUID, state: CreationLibraryState, errorCode: String? = nil) throws {
        guard state != .completed else { throw GenerationRuntimeError.invalidRequest }
        try executeWrite(sql: "UPDATE CreationLibrary SET state = ?, errorCode = ? WHERE id = ? AND state != 'completed'", bindings: [.text(state.rawValue), errorCode.map(DBBinding.text) ?? .null, .text(id.uuidString)])
    }

    func publishCreation(_ output: CreativeOutput, request: CreationLibraryRequest, sources: [CreativeSource] = [], checkpoint: PrivacyCheckpoint, requiresConsent: Bool) throws {
        let body = try JSONEncoder().encode(output)
        guard !output.didFallback, !output.paragraphs.isEmpty, body.count <= 262144 else { throw GenerationRuntimeError.outputLimit }
        try execute(sql: "BEGIN IMMEDIATE")
        do {
            try validateCreationAccess(request, checkpoint: checkpoint, requiresConsent: requiresConsent)
            for source in sources {
                guard try readCreationSource(memoryID: source.memoryID, maximumTextBytes: GenerationInputBudget.maximumBytes) == source else { throw GenerationRuntimeError.restartRequired }
            }
            let changed = try executeWrite(sql: "UPDATE CreationLibrary SET output=?,state='completed',errorCode=NULL,unread=1 WHERE id=? AND state='running'", bindings: [.blob(body), .text(request.id.uuidString)])
            guard changed == 1 else { throw GenerationRuntimeError.restartRequired }
            try execute(sql: "COMMIT")
        } catch { try? execute(sql: "ROLLBACK"); throw error }
    }

    private func validateCreationAccess(_ request: CreationLibraryRequest, checkpoint: PrivacyCheckpoint, requiresConsent: Bool) throws {
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        let policy = try executeQuery(sql: "SELECT policyVersion,authorizedSourceTypes FROM UserPolicyStore WHERE id=1", bindings: []).first
        guard policy?["policyVersion"]?.intValue == Int64(checkpoint.policyVersion),
            let raw = policy?["authorizedSourceTypes"]?.stringValue,
            let allowed = try? JSONDecoder().decode([String].self, from: Data(raw.utf8))
        else { throw GenerationRuntimeError.privacyDenied }
        if requiresConsent {
            guard try executeQuery(sql: "SELECT hasConsented FROM ConsentStore WHERE id=1", bindings: []).first?["hasConsented"]?.intValue == 1 else { throw GenerationRuntimeError.privacyDenied }
        }
        for id in request.sourceIDs {
            guard let row = try executeQuery(sql: "SELECT sourceType FROM Memory m WHERE memoryId=? AND NOT EXISTS(SELECT 1 FROM ExcludedAssets e WHERE e.assetId=m.sourceLocator)", bindings: [.text(id.uuidString)]).first,
                let type = row["sourceType"]?.stringValue, allowed.contains(SearchPipeline.normalizeSourceType(type))
            else { throw GenerationRuntimeError.privacyDenied }
        }
    }
}
