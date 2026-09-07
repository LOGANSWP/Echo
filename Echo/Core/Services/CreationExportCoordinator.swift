// ==========================================
// File: CreationExportCoordinator.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md → US-SYN-002/003/004
//       docs/decisions/ADR-020-grounded-citation-share-audit.md
// Task: 4.0i - Verifiable citations, stable navigation, and system-share audit
// AC coverage: current-policy revalidation, truthful unavailable sources, controller-backed
//              share audit, exact hash-only handoff idempotency, and content-free L2 retry records
// Architecture: AGENTS.md §4.2, §4.4, §7; ADR-020 decisions 5-8
// Generated: 2026-09-07
// ==========================================

import Foundation

public protocol CreationSourceResolving: Sendable {
    func resolveSource(memoryID: UUID, traceID: String) async throws -> FocusSourceResolution
}

extension FocusSourceLifecycleActor: CreationSourceResolving {}

public nonisolated enum CreationExportFormat: String, Sendable, Codable, Equatable {
    case plainText
    case markdown
    case pdf
}

public nonisolated enum CreationExportError: Error, LocalizedError, Sendable, Equatable {
    case privacyDenied
    case sourceUnavailable
    case invalidPeriodType
    case auditPersistenceFailed

    public nonisolated var errorDescription: String? {
        switch self {
        case .privacyDenied:
            "The current privacy policy no longer permits this creation action."
        case .sourceUnavailable:
            "The source memory is currently unavailable."
        case .invalidPeriodType:
            "The report period is invalid."
        case .auditPersistenceFailed:
            "The share handoff occurred, but its audit record is pending retry."
        }
    }
}

private nonisolated struct CreationShareAuditRetry: Codable, Sendable {
    let schemaVersion: Int
    let payloadID: UUID
    let traceID: String
    let exportFormat: CreationExportFormat
    let periodType: String?
    let sharePresented: Bool
}

/// Composition-owned action boundary for citation navigation and user-mediated exports.
public actor CreationExportCoordinator {
    private static let validPeriodTypes: Set<String> = ["month", "year"]
    private let privacyActor: PrivacyActor
    private let sourceResolver: any CreationSourceResolving
    private let pendingOps: PendingOpsActor

    public init(
        privacyActor: PrivacyActor,
        sourceResolver: any CreationSourceResolving,
        pendingOps: PendingOpsActor
    ) {
        self.privacyActor = privacyActor
        self.sourceResolver = sourceResolver
        self.pendingOps = pendingOps
    }

    /// Revalidates the exact source types and refreshes availability without exposing locators.
    public func authorize(output: CreativeOutput, traceID: String) async throws -> CreativeOutput {
        let anchorSourceTypes = output.paragraphs.flatMap(\.anchors).compactMap(\.sourceType)
        let sourceTypes = Array(Set(output.sourceTypes + anchorSourceTypes)).sorted()
        guard !output.paragraphs.flatMap(\.anchors).contains(where: { $0.sourceType == nil }) else {
            throw CreationExportError.privacyDenied
        }
        let checkpoint = await privacyActor.validate(
            operation: .search,
            traceID: traceID,
            sourceTypes: sourceTypes
        )
        guard checkpoint.isAllowed else { throw CreationExportError.privacyDenied }

        var availability: [UUID: CitationSourceAvailability] = [:]
        for anchor in output.paragraphs.flatMap(\.anchors) where availability[anchor.memoryID] == nil {
            do {
                let resolution = try await sourceResolver.resolveSource(
                    memoryID: anchor.memoryID,
                    traceID: traceID
                )
                switch resolution.contentAvailability {
                case .available:
                    availability[anchor.memoryID] = .available
                case .offlineUnavailable:
                    availability[anchor.memoryID] = .offlineUnavailable
                case .missing:
                    availability[anchor.memoryID] = .missing
                case .unsupported:
                    availability[anchor.memoryID] = .unsupported
                case .authorizationDenied, .limitedScopeHidden:
                    throw CreationExportError.privacyDenied
                }
            } catch FocusSourceLifecycleError.memoryMissing {
                // The source type already passed current policy; absence is represented honestly.
                availability[anchor.memoryID] = .missing
            } catch let error as CreationExportError {
                throw error
            } catch FocusSourceLifecycleError.privacyDenied {
                throw CreationExportError.privacyDenied
            } catch {
                throw CreationExportError.sourceUnavailable
            }
        }

        return CreativeOutput(
            template: output.template,
            title: output.title,
            periodType: output.periodType,
            paragraphs: output.paragraphs.map { paragraph in
                GroundedParagraph(
                    id: paragraph.id,
                    text: paragraph.text,
                    anchors: paragraph.anchors.map { anchor in
                        SourceAnchor(
                            memoryID: anchor.memoryID,
                            sourceType: anchor.sourceType,
                            availability: availability[anchor.memoryID] ?? .missing
                        )
                    },
                    groundingStatus: paragraph.groundingStatus
                )
            },
            sourceMemoryCount: output.sourceMemoryCount,
            sourceTypes: output.sourceTypes,
            emptyReason: output.emptyReason,
            didFallback: output.didFallback
        )
    }

    public func authorizeNavigation(anchor: SourceAnchor, traceID: String) async throws -> UUID {
        let paragraph = GroundedParagraph(
            id: UUID(),
            text: "navigation-authorization",
            anchors: [anchor],
            groundingStatus: .cited
        )
        let output = CreativeOutput(
            template: .letter,
            paragraphs: [paragraph],
            sourceMemoryCount: 1
        )
        let authorized = try await authorize(output: output, traceID: traceID)
        guard authorized.paragraphs[0].anchors[0].availability == .available else {
            throw CreationExportError.sourceUnavailable
        }
        return anchor.memoryID
    }

    /// Must be called only by the system activity controller lifecycle bridge.
    public func recordSharePresentation(
        payloadID: UUID,
        format: CreationExportFormat,
        periodType: String?,
        traceID: String,
        presented: Bool
    ) async throws {
        guard periodType.map(Self.validPeriodTypes.contains) ?? true else {
            throw CreationExportError.invalidPeriodType
        }
        let handoffDigest = Self.handoffDigest(payloadID)
        let policy = await privacyActor.getPolicy()
        do {
            let alreadyRecorded = try await privacyActor.hasCreationShareAudit(
                shareHandoffIdDigest: handoffDigest
            )
            guard !alreadyRecorded else { return }
            try await privacyActor.writeAuditLog(
                eventType: .creationSharePresented,
                traceID: traceID,
                policyVersion: policy.policyVersion,
                success: presented,
                exportFormat: format.rawValue,
                sharePresented: presented,
                periodType: periodType,
                shareHandoffIdDigest: handoffDigest
            )
        } catch {
            if (try? await privacyActor.hasCreationShareAudit(
                shareHandoffIdDigest: handoffDigest
            )) == true {
                return
            }
            let retry = CreationShareAuditRetry(
                schemaVersion: 1,
                payloadID: payloadID,
                traceID: traceID,
                exportFormat: format,
                periodType: periodType,
                sharePresented: presented
            )
            let operationID = "creation-share-audit-\(payloadID.uuidString.lowercased())"
            let existingRetry = try? await pendingOps.load(operationId: operationID)
            if existingRetry == nil, let parameters = try? JSONEncoder().encode(retry) {
                try? await pendingOps.add(operation: PendingOperation(
                    operationId: operationID,
                    operationType: "creationShareAudit",
                    parameters: parameters,
                    lastError: "audit-write-failed"
                ))
            }
            throw CreationExportError.auditPersistenceFailed
        }
    }

    /// Manual L2 retry. Repeated calls are idempotent even if audit persistence succeeded
    /// before the pending-row cleanup could complete.
    @discardableResult
    public func retryPendingShareAudit(operationID: String) async throws -> Bool {
        guard let operation = try await pendingOps.load(operationId: operationID),
              operation.operationType == "creationShareAudit",
              let retry = try? JSONDecoder().decode(
                CreationShareAuditRetry.self,
                from: operation.parameters
              ) else {
            return false
        }
        guard retry.schemaVersion == 1,
              retry.periodType.map(Self.validPeriodTypes.contains) ?? true else {
            throw CreationExportError.invalidPeriodType
        }

        let handoffDigest = Self.handoffDigest(retry.payloadID)
        let existing = try await privacyActor.hasCreationShareAudit(
            shareHandoffIdDigest: handoffDigest
        )
        if !existing {
            let policy = await privacyActor.getPolicy()
            do {
                try await privacyActor.writeAuditLog(
                    eventType: .creationSharePresented,
                    traceID: retry.traceID,
                    policyVersion: policy.policyVersion,
                    success: retry.sharePresented,
                    exportFormat: retry.exportFormat.rawValue,
                    sharePresented: retry.sharePresented,
                    periodType: retry.periodType,
                    shareHandoffIdDigest: handoffDigest
                )
            } catch {
                guard (try? await privacyActor.hasCreationShareAudit(
                    shareHandoffIdDigest: handoffDigest
                )) == true else {
                    throw CreationExportError.auditPersistenceFailed
                }
            }
        }
        _ = try await pendingOps.remove(operationId: operationID)
        return !existing
    }

    private nonisolated static func handoffDigest(_ payloadID: UUID) -> String {
        AuditContentHasher.sha256Hex(payloadID.uuidString.lowercased())
    }
}
