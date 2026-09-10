// ==========================================
// File: PhotoUnderstandingStorage.swift
// Spec: US-ING-004 AC-7/8; D-005; ADR-025
// Task: 4.0l - Atomic photo intent and material publication
// Architecture: SQLite actor transactions, current persisted policy and exact source identity
// Generated: 2026-09-09
// ==========================================

import Foundation

extension DatabaseManager {
    func readPhotoMaterial(_ item: PhotoUnderstandingWorkItem) throws -> PhotoUnderstandingMaterial? {
        guard try photoMaterialIsReady(item) else { return nil }
        let rows = try executeQuery(
            sql: """
                SELECT kind, language,
                    CASE WHEN length(CAST(body AS BLOB)) <= CASE kind WHEN 'caption' THEN 4096 ELSE 16384 END
                        THEN body END AS body,
                    EXISTS (SELECT 1 FROM MemoryUserEdit e WHERE e.memoryId = c.memoryId
                        AND length(trim(COALESCE(e.description, ''))) > 0) AS corrected
                FROM PhotoDerivedContent c
                WHERE memoryId = ? AND sourceVersion = ? AND assetRevision = ?
                    AND modelVersion = ? AND processingVersion = ? AND state = 'ready' AND bodyVersion = 1
                """,
            bindings: [
                .text(item.memoryID.uuidString), .text(item.sourceVersion), .text(item.assetRevision),
                .text(item.modelVersion), .text(item.processingVersion),
            ]
        )
        guard let caption = rows.first(where: { $0["kind"]?.stringValue == "caption" }),
            let text = caption["body"]?.stringValue, !text.isEmpty,
            let language = caption["language"]?.stringValue, language == "en-US"
        else { throw GenerationRuntimeError.modelContract }
        let ocr = rows.first { $0["kind"]?.stringValue == "ocr" }
        if let ocr {
            guard ocr["body"]?.stringValue != nil,
                ["en-US", "zh-Hans"].contains(ocr["language"]?.stringValue ?? "")
            else { throw GenerationRuntimeError.modelContract }
        }
        return PhotoUnderstandingMaterial(
            caption: text,
            captionLanguage: language,
            ocrText: ocr?["body"]?.stringValue,
            ocrLanguage: ocr?["language"]?.stringValue,
            usesUserCorrection: caption["corrected"]?.intValue == 1
        )
    }

    func photoSourceRow(memoryID: UUID) throws -> [String: DBValue]? {
        try executeQuery(
            sql: """
                SELECT m.sourceLocator, r.contentHash AS sourceVersion
                FROM Memory m JOIN Representation r ON r.memoryId = m.memoryId AND r.modality = 'visionDense'
                WHERE m.memoryId = ? AND m.sourceType = 'photo'
                  AND NOT EXISTS (SELECT 1 FROM ExcludedAssets e WHERE e.assetId = m.sourceLocator)
                ORDER BY r.representationId LIMIT 1
                """,
            bindings: [.text(memoryID.uuidString)]
        ).first
    }

    func photoJobRow(memoryID: UUID) throws -> [String: DBValue]? {
        try executeQuery(
            sql: "SELECT * FROM PhotoUnderstandingJob WHERE memoryId = ?",
            bindings: [.text(memoryID.uuidString)]
        ).first
    }

    func photoMaterialIsReady(_ item: PhotoUnderstandingWorkItem) throws -> Bool {
        try !executeQuery(
            sql: """
                SELECT 1 FROM PhotoUnderstandingJob j JOIN PhotoDerivedContent c ON c.memoryId = j.memoryId
                WHERE j.memoryId = ? AND j.state = 'ready' AND c.kind = 'caption' AND c.state = 'ready'
                  AND j.sourceVersion = ? AND j.assetRevision = ? AND j.modelVersion = ? AND j.processingVersion = ?
                  AND c.sourceVersion = j.sourceVersion AND c.assetRevision = j.assetRevision
                  AND c.modelVersion = j.modelVersion AND c.processingVersion = j.processingVersion
                """,
            bindings: [
                .text(item.memoryID.uuidString), .text(item.sourceVersion), .text(item.assetRevision),
                .text(item.modelVersion), .text(item.processingVersion),
            ]
        ).isEmpty
    }

    func savePhotoIntent(
        _ item: PhotoUnderstandingWorkItem,
        taskID: String,
        checkpoint: PrivacyCheckpoint,
        requiresConsent: Bool
    ) throws {
        try execute(sql: "BEGIN IMMEDIATE")
        do {
            try validatePhotoWrite(item, checkpoint: checkpoint, requiresConsent: requiresConsent)
            // Publication is the durable completion fact, even if progress cleanup was interrupted.
            if try photoMaterialIsReady(item) {
                try execute(sql: "COMMIT")
                return
            }
            try executeWrite(
                sql: """
                    INSERT INTO PhotoUnderstandingJob
                    (memoryId, taskId, sourceVersion, assetRevision, modelVersion, processingVersion, state, updatedAt, requestOrigin)
                    VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, 'onDemand')
                    ON CONFLICT(memoryId) DO UPDATE SET taskId = excluded.taskId,
                        sourceVersion = excluded.sourceVersion, assetRevision = excluded.assetRevision,
                        modelVersion = excluded.modelVersion, processingVersion = excluded.processingVersion,
                        state = 'queued', updatedAt = excluded.updatedAt, requestOrigin = 'onDemand'
                    """,
                bindings: [
                    .text(item.memoryID.uuidString), .text(taskID), .text(item.sourceVersion),
                    .text(item.assetRevision), .text(item.modelVersion), .text(item.processingVersion),
                    .double(Date().timeIntervalSince1970),
                ]
            )
            // Invalidated material is removed; user corrections are in a separate table.
            try executeWrite(
                sql: """
                    DELETE FROM PhotoDerivedContent WHERE memoryId = ? AND
                        (sourceVersion != ? OR COALESCE(assetRevision, '') != ? OR modelVersion != ? OR processingVersion != ?)
                    """,
                bindings: [
                    .text(item.memoryID.uuidString), .text(item.sourceVersion),
                    .text(item.assetRevision), .text(item.modelVersion), .text(item.processingVersion),
                ]
            )
            try execute(sql: "COMMIT")
        } catch {
            try? execute(sql: "ROLLBACK")
            throw error
        }
    }

    func publishPhotoMaterial(
        _ item: PhotoUnderstandingWorkItem,
        taskID: String,
        material: (caption: PhotoCaptionOutput, ocr: OCRDocument?),
        checkpoint: PrivacyCheckpoint,
        requiresConsent: Bool
    ) throws {
        let (caption, ocr) = material
        guard !caption.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            caption.text.utf8.count <= 4096, caption.language == "en-US",
            (1...128).contains(caption.outputTokenCount),
            ocr.map({ $0.normalizedText.utf8.count <= 16384 && ["en-US", "zh-Hans"].contains($0.locale) }) ?? true
        else { throw GenerationRuntimeError.outputLimit }
        try execute(sql: "BEGIN IMMEDIATE")
        do {
            try validatePhotoWrite(item, checkpoint: checkpoint, requiresConsent: requiresConsent)
            guard let job = try photoJobRow(memoryID: item.memoryID),
                job["taskId"]?.stringValue == taskID, job["state"]?.stringValue == "queued",
                job["sourceVersion"]?.stringValue == item.sourceVersion,
                job["assetRevision"]?.stringValue == item.assetRevision,
                job["modelVersion"]?.stringValue == item.modelVersion,
                job["processingVersion"]?.stringValue == item.processingVersion
            else { throw GenerationRuntimeError.restartRequired }
            try executeWrite(
                sql: "DELETE FROM PhotoDerivedContent WHERE memoryId = ?",
                bindings: [.text(item.memoryID.uuidString)]
            )
            var bodies = [(kind: "caption", text: caption.text, language: caption.language)]
            if let ocr, !ocr.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                bodies.append(("ocr", ocr.normalizedText, ocr.locale))
            }
            for body in bodies {
                try executeWrite(
                    sql: """
                        INSERT INTO PhotoDerivedContent
                        (memoryId, kind, sourceVersion, modelVersion, processingVersion, language, state, body, assetRevision, updatedAt)
                        VALUES (?, ?, ?, ?, ?, ?, 'ready', ?, ?, ?)
                        """,
                    bindings: [
                        .text(item.memoryID.uuidString), .text(body.kind), .text(item.sourceVersion),
                        .text(item.modelVersion), .text(item.processingVersion), .text(body.language),
                        .text(body.text), .text(item.assetRevision), .double(Date().timeIntervalSince1970),
                    ]
                )
            }
            try executeWrite(
                sql: "UPDATE PhotoUnderstandingJob SET state = 'ready', updatedAt = ? WHERE taskId = ?",
                bindings: [.double(Date().timeIntervalSince1970), .text(taskID)]
            )
            try executeWrite(sql: "DELETE FROM PendingOperations WHERE operationId = ?", bindings: [.text(taskID)])
            try execute(sql: "COMMIT")
        } catch {
            try? execute(sql: "ROLLBACK")
            throw error
        }
    }

    func failPhotoJob(
        _ item: PhotoUnderstandingWorkItem,
        taskID: String,
        state: String,
        resumeData: Data,
        errorCode: String
    ) throws {
        try execute(sql: "BEGIN IMMEDIATE")
        do {
            let changed = try executeWrite(
                sql: """
                    UPDATE PhotoUnderstandingJob SET state = ?, updatedAt = ?
                    WHERE taskId = ? AND sourceVersion = ? AND assetRevision = ? AND modelVersion = ?
                      AND processingVersion = ? AND state = 'queued'
                    """,
                bindings: [
                    .text(state), .double(Date().timeIntervalSince1970), .text(taskID),
                    .text(item.sourceVersion), .text(item.assetRevision), .text(item.modelVersion),
                    .text(item.processingVersion),
                ]
            )
            if changed == 1, state == "failed" {
                try executeWrite(
                    sql: """
                        INSERT INTO PendingOperations (operationId, operationType, retryCount, parameters, createdAt, lastError)
                        VALUES (?, 'photoUnderstanding', 0, ?, ?, ?)
                        ON CONFLICT(operationId) DO UPDATE SET lastError = excluded.lastError, parameters = excluded.parameters
                        """,
                    bindings: [
                        .text(taskID), .blob(resumeData), .double(Date().timeIntervalSince1970), .text(errorCode),
                    ]
                )
            }
            try execute(sql: "COMMIT")
        } catch {
            try? execute(sql: "ROLLBACK")
            throw error
        }
    }

    private func validatePhotoWrite(
        _ item: PhotoUnderstandingWorkItem,
        checkpoint: PrivacyCheckpoint,
        requiresConsent: Bool
    ) throws {
        guard checkpoint.isAllowed, item.modelVersion == ApprovedPhotoUnderstandingArtifact.identity,
            item.processingVersion == ApprovedPhotoUnderstandingArtifact.processingVersion,
            try photoSourceRow(memoryID: item.memoryID)?["sourceVersion"]?.stringValue == item.sourceVersion
        else { throw GenerationRuntimeError.restartRequired }
        let policy = try executeQuery(
            sql: "SELECT policyVersion, authorizedSourceTypes FROM UserPolicyStore WHERE id = 1",
            bindings: []
        ).first
        guard policy?["policyVersion"]?.intValue == Int64(checkpoint.policyVersion),
            let raw = policy?["authorizedSourceTypes"]?.stringValue,
            let allowed = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)), allowed.contains("photo")
        else { throw GenerationRuntimeError.privacyDenied }
        if requiresConsent {
            let consent = try executeQuery(sql: "SELECT hasConsented FROM ConsentStore WHERE id = 1", bindings: [])
                .first
            guard consent?["hasConsented"]?.intValue == 1 else { throw GenerationRuntimeError.privacyDenied }
        }
    }
}
