// ==========================================
// File: CreationSourceStorage.swift
// Spec: US-ING-004 AC-7/8; US-SYN-003 AC-7; ADR-025
// Task: 4.0l - Atomic bounded creation material reads
// AC coverage: original text preserved, source identity, correction precedence
// Architecture: DatabaseManager owns SQLite; callers own operation checkpoints
// Generated: 2026-09-09
// ==========================================

import Foundation

extension DatabaseManager {
    /// Also callable inside publication transactions without an actor suspension.
    func readCreationSource(memoryID: UUID, maximumTextBytes: Int? = nil, assetRevision: String? = nil) throws
        -> CreativeSource? {
        let limit = maximumTextBytes ?? Int.max
        guard limit >= 0 else { throw GenerationRuntimeError.contextLimit }
        let rows = try executeQuery(
            sql: """
                WITH source AS (
                    SELECT m.memoryId, m.sourceType, m.canonicalText, m.createdAt, m.updatedAt,
                           m.originalTimestamp, e.title, e.description, e.tagsJSON, e.updatedAt AS editUpdatedAt,
                           c.body AS caption, o.body AS ocr,
                           MAX(COALESCE(c.updatedAt, 0), COALESCE(o.updatedAt, 0)) AS derivedUpdatedAt,
                           COALESCE(length(CAST(m.canonicalText AS BLOB)), 0)
                           + COALESCE(length(CAST(e.title AS BLOB)), 0)
                           + COALESCE(length(CAST(e.description AS BLOB)), 0)
                           + COALESCE(length(CAST(e.tagsJSON AS BLOB)), 0)
                           + COALESCE(length(CAST(c.body AS BLOB)), 0)
                           + COALESCE(length(CAST(o.body AS BLOB)), 0) AS sourceBytes
                    FROM Memory m
                    LEFT JOIN MemoryUserEdit e ON e.memoryId = m.memoryId
                    LEFT JOIN PhotoDerivedContent c ON c.memoryId = m.memoryId AND m.sourceType = 'photo'
                        AND c.kind = 'caption' AND c.state = 'ready' AND c.bodyVersion = 1
                        AND c.modelVersion = ?3 AND c.processingVersion = ?4
                        AND (?5 IS NULL OR c.assetRevision = ?5)
                        AND EXISTS (SELECT 1 FROM Representation r WHERE r.memoryId = m.memoryId
                            AND r.modality = 'visionDense' AND r.contentHash = c.sourceVersion)
                    LEFT JOIN PhotoDerivedContent o ON o.memoryId = m.memoryId AND m.sourceType = 'photo'
                        AND o.kind = 'ocr' AND o.state = 'ready' AND o.bodyVersion = 1
                        AND o.modelVersion = ?3 AND o.processingVersion = ?4
                        AND (?5 IS NULL OR o.assetRevision = ?5)
                        AND EXISTS (SELECT 1 FROM Representation r WHERE r.memoryId = m.memoryId
                            AND r.modality = 'visionDense' AND r.contentHash = o.sourceVersion)
                    WHERE m.memoryId = ?1
                )
                SELECT memoryId, sourceType, createdAt, updatedAt, originalTimestamp,
                       editUpdatedAt, derivedUpdatedAt, sourceBytes,
                       CASE WHEN sourceBytes <= ?2 THEN canonicalText END AS canonicalText,
                       CASE WHEN sourceBytes <= ?2 THEN title END AS title,
                       CASE WHEN sourceBytes <= ?2 THEN description END AS description,
                       CASE WHEN sourceBytes <= ?2 THEN tagsJSON END AS tagsJSON,
                       CASE WHEN sourceBytes <= ?2 THEN caption END AS caption,
                       CASE WHEN sourceBytes <= ?2 THEN ocr END AS ocr
                FROM source
                """,
            bindings: [
                .text(memoryID.uuidString), .int(Int64(limit)),
                .text(ApprovedPhotoUnderstandingArtifact.identity),
                .text(ApprovedPhotoUnderstandingArtifact.processingVersion), assetRevision.map(DBBinding.text) ?? .null,
            ]
        )
        guard let row = rows.first else { return nil }
        guard let bytes = row["sourceBytes"]?.intValue, bytes <= Int64(limit) else {
            throw GenerationRuntimeError.contextLimit
        }
        let tags =
            try row["tagsJSON"]?.stringValue.map {
                try JSONDecoder().decode([String].self, from: Data($0.utf8))
            } ?? []
        let description = row["description"]?.stringValue ?? ""
        let original = MemoryEditActor.effectiveText(
            title: row["title"]?.stringValue ?? "",
            description: description,
            tags: tags,
            canonicalText: row["canonicalText"]?.stringValue
        )
        let caption =
            description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? row["caption"]?.stringValue ?? "" : ""
        let text = [original, caption, row["ocr"]?.stringValue ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
        if maximumTextBytes != nil {
            var remaining = limit
            try GenerationInputBudget.consume(text, remaining: &remaining)
        }
        return CreativeSource(
            memoryID: memoryID,
            assetID: "",
            sourceType: row["sourceType"]?.stringValue ?? "",
            text: text,
            timestamp: row["originalTimestamp"]?.doubleValue ?? row["createdAt"]?.doubleValue ?? 0,
            revision: max(
                row["updatedAt"]?.doubleValue ?? 0,
                row["editUpdatedAt"]?.doubleValue ?? 0,
                row["derivedUpdatedAt"]?.doubleValue ?? 0
            ),
            photoCreationReady: !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }
}
