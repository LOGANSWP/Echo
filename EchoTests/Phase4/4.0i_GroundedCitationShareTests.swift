// ==========================================
// File: 4.0i_GroundedCitationShareTests.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md → US-SYN-002/003/004
//       docs/decisions/ADR-020-grounded-citation-share-audit.md
// Task: 4.0i - Verifiable citations, stable navigation, and system-share audit
// AC coverage: bounded versioned envelope, exact allow-list citations, citation-preserving
//              exports, multipage PDF, and typed audit fields
// Architecture: AGENTS.md §4.1, §7, §9; ADR-020 decisions 1-8
// Generated: 2026-09-07
// ==========================================

import CoreGraphics
import Foundation
import Testing
@testable import Echo

@Suite("4.0i Grounded Citation and Share", .serialized)
struct GroundedCitationShareTests {
    private actor CapturingLLMProvider: LLMProvider {
        let output: String
        private(set) var prompts: [String] = []

        init(output: String) {
            self.output = output
        }

        func generate(prompt: String, preferredLanguage: String) async throws -> String {
            prompts.append(prompt)
            return output
        }

        func lastPrompt() -> String? {
            prompts.last
        }
    }

    private actor SourceResolverFake: CreationSourceResolving {
        let availability: FocusContentAvailability

        init(availability: FocusContentAvailability) {
            self.availability = availability
        }

        func resolveSource(memoryID: UUID, traceID: String) async throws -> FocusSourceResolution {
            FocusSourceResolution(
                memoryID: memoryID,
                sourceType: "note",
                contentAvailability: availability,
                presentation: availability == .available ? .canonicalText : .unavailable,
                sourceDeletionCapability: .unavailable
            )
        }
    }

    private func makeDatabase() async throws -> (DatabaseManager, PrivacyActor) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-4-0i-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let database = DatabaseManager(databaseURL: url)
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(UserPolicy(
            preferredLanguage: "en-US",
            authorizedSourceTypes: ["note"],
            policyVersion: 7
        ))
        return (database, privacy)
    }

    private func sources() -> [CreativeSource] {
        [
            CreativeSource(
                memoryID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                assetID: "private-source-locator-one",
                sourceType: "note",
                text: "A quiet walk beside the lake.",
                timestamp: 1
            ),
            CreativeSource(
                memoryID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                assetID: "private-source-locator-two",
                sourceType: "note",
                text: "The family shared breakfast together.",
                timestamp: 2
            ),
        ]
    }

    @Test("AC-1/2: versioned envelope preserves exact multi-source and partial provenance")
    func envelopeUsesOnlySubmittedMemoryIDs() async throws {
        let json = #"{"schemaVersion":1,"paragraphs":[{"text":"A grounded paragraph about the lake and breakfast.","sourceMemoryIDs":["11111111-1111-1111-1111-111111111111","22222222-2222-2222-2222-222222222222","99999999-9999-9999-9999-999999999999","11111111-1111-1111-1111-111111111111"]},{"text":"A paragraph with no submitted source.","sourceMemoryIDs":["99999999-9999-9999-9999-999999999999"]}]}"#
        let provider = CapturingLLMProvider(output: json)
        let (_, privacy) = try await makeDatabase()
        let pipeline = CreativePipeline(
            llmProvider: provider,
            aligner: LanguageAligner(llmProvider: provider, preferredLanguage: "en-US"),
            privacyActor: privacy
        )

        let output = try await pipeline.generate(
            template: .letter,
            sources: sources(),
            traceID: "4.0i-envelope"
        )

        #expect(output.paragraphs[0].anchors.map(\.memoryID) == [
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        ])
        #expect(output.paragraphs[0].groundingStatus == .partialNoSource)
        #expect(output.paragraphs[1].anchors.isEmpty)
        #expect(output.paragraphs[1].groundingStatus == .noSource)
        #expect(output.citationCount == 2)
        #expect(output.noSourceCount == 2)

        let prompt = try #require(await provider.lastPrompt())
        #expect(prompt.contains("11111111-1111-1111-1111-111111111111"))
        #expect(prompt.contains("private-source-locator-one") == false)
        #expect(prompt.contains("assetID") == false)
    }

    @Test("AC-1: unknown, malformed, and oversized envelopes fail closed")
    func invalidEnvelopesFailClosed() async throws {
        let (_, privacy) = try await makeDatabase()
        let tooManyParagraphs = (0...CreativeGenerationLimits.maximumParagraphs)
            .map { _ in #"{"text":"Grounded English text","sourceMemoryIDs":[]}"# }
            .joined(separator: ",")
        let oversizedParagraph = String(
            repeating: "a",
            count: CreativeGenerationLimits.maximumParagraphCharacters + 1
        )
        let oversizedPayload = String(
            repeating: "English payload ",
            count: CreativeGenerationLimits.maximumPayloadBytes / 8
        )
        let invalidOutputs = [
            #"{"schemaVersion":2,"paragraphs":[]}"#,
            "This is unstructured prose and must never receive a round-robin citation.",
            #"{"schemaVersion":1,"paragraphs":[{"text":"Valid text","sourceMemoryIDs":[]}]"#,
            #"{"schemaVersion":1,"paragraphs":[{"text":"Valid text","sourceMemoryIDs":["11111111-1111-1111-1111-111111111111","22222222-2222-2222-2222-222222222222","33333333-3333-3333-3333-333333333333","44444444-4444-4444-4444-444444444444","55555555-5555-5555-5555-555555555555","66666666-6666-6666-6666-666666666666","77777777-7777-7777-7777-777777777777","88888888-8888-8888-8888-888888888888","99999999-9999-9999-9999-999999999999","aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","cccccccc-cccc-cccc-cccc-cccccccccccc","dddddddd-dddd-dddd-dddd-dddddddddddd","eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee","ffffffff-ffff-ffff-ffff-ffffffffffff","00000000-0000-0000-0000-000000000000","12121212-1212-1212-1212-121212121212"]}]}"#,
            "{\"schemaVersion\":1,\"paragraphs\":[\(tooManyParagraphs)]}",
            "{\"schemaVersion\":1,\"paragraphs\":[{\"text\":\"\(oversizedParagraph)\",\"sourceMemoryIDs\":[]}]}",
            "{\"schemaVersion\":1,\"paragraphs\":[{\"text\":\"\(oversizedPayload)\",\"sourceMemoryIDs\":[]}]}",
        ]

        for (index, invalidOutput) in invalidOutputs.enumerated() {
            let provider = CapturingLLMProvider(output: invalidOutput)
            let pipeline = CreativePipeline(
                llmProvider: provider,
                aligner: LanguageAligner(llmProvider: provider, preferredLanguage: "en-US"),
                privacyActor: privacy
            )
            await #expect(throws: CreativeError.self) {
                _ = try await pipeline.generate(
                    template: .letter,
                    sources: sources(),
                    traceID: "4.0i-invalid-\(index)"
                )
            }
        }
    }

    @Test("AC-3/4: plain text, Markdown, and PDF preserve citations without source locators")
    @MainActor
    func everyExportPreservesCitationSemantics() async throws {
        let output = CreativeOutput(
            template: .report,
            title: "2026 September Report",
            periodType: "month",
            paragraphs: [
                GroundedParagraph(
                    id: UUID(),
                    text: String(repeating: "A fully grounded sentence. ", count: 1_800),
                    anchors: [
                        SourceAnchor(memoryID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!),
                        SourceAnchor(memoryID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!),
                    ],
                    groundingStatus: .cited
                ),
                GroundedParagraph(
                    id: UUID(),
                    text: "This paragraph has no validated source.",
                    anchors: [],
                    groundingStatus: .noSource
                ),
            ],
            sourceMemoryCount: 2
        )

        let plainText = CreationExportService.plainText(from: output)
        let markdown = CreationExportService.markdown(from: output)
        let pdf = try await CreationExportService.pdf(from: output)

        for export in [plainText, markdown] {
            #expect(export.contains("MemoryID:11111111"))
            #expect(export.contains("MemoryID:22222222"))
            #expect(export.contains("NoSource"))
            #expect(export.contains("private-source-locator") == false)
        }

        let document = try #require(CGDataProvider(data: pdf as CFData))
        let pdfDocument = try #require(CGPDFDocument(document))
        #expect(pdfDocument.numberOfPages > 1)
    }

    @Test("AC-5/6: generation audit uses dedicated typed columns")
    func generationAuditIsTyped() async throws {
        let json = #"{"schemaVersion":1,"paragraphs":[{"text":"A grounded paragraph from one memory.","sourceMemoryIDs":["11111111-1111-1111-1111-111111111111"]}]}"#
        let provider = CapturingLLMProvider(output: json)
        let (_, privacy) = try await makeDatabase()
        let pipeline = CreativePipeline(
            llmProvider: provider,
            aligner: LanguageAligner(llmProvider: provider, preferredLanguage: "en-US"),
            privacyActor: privacy
        )

        _ = try await pipeline.generate(
            template: .letter,
            sources: [sources()[0]],
            traceID: "4.0i-typed-audit"
        )

        let events = try await privacy.fetchAuditLogs(eventType: .creativeGeneration)
        let event = try #require(events.first)
        #expect(event.templateType == "letter")
        #expect(event.sourceMemoryCount == 1)
        #expect(event.citationCount == 1)
        #expect(event.noSourceCount == 0)
        #expect(event.sourceLanguage == nil)
    }

    @Test("AC-6: audit migration is idempotent and typed allow-lists reject invalid values")
    func auditMigrationAndAllowLists() async throws {
        let (database, privacy) = try await makeDatabase()
        await database.close()
        try await database.open()
        let rows = try await database.executeQuery(sql: "PRAGMA table_info(AuditLog)", bindings: [])
        let names = Set(rows.compactMap { $0["name"]?.stringValue })
        #expect(names.isSuperset(of: [
            "templateType",
            "sourceMemoryCount",
            "citationCount",
            "noSourceCount",
            "exportFormat",
            "sharePresented",
            "periodType",
            "shareHandoffIdDigest",
        ]))

        await #expect(throws: AuditValidationError.invalidCreationFields) {
            try await privacy.writeAuditLog(
                eventType: .creationSharePresented,
                traceID: "invalid-audit-value",
                policyVersion: 7,
                exportFormat: "webUpload",
                sharePresented: true
            )
        }
    }

    @Test("AC-2/3: action boundary revalidates policy and preserves authorized missing sources")
    func exportBoundaryRevalidatesCurrentPolicy() async throws {
        let (database, privacy) = try await makeDatabase()
        let pending = PendingOpsActor(db: database)
        let coordinator = CreationExportCoordinator(
            privacyActor: privacy,
            sourceResolver: SourceResolverFake(availability: .offlineUnavailable),
            pendingOps: pending
        )
        let memoryID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let output = CreativeOutput(
            template: .letter,
            paragraphs: [
                GroundedParagraph(
                    id: UUID(),
                    text: "Grounded body",
                    anchors: [SourceAnchor(memoryID: memoryID, sourceType: "note")],
                    groundingStatus: .cited
                ),
            ],
            sourceMemoryCount: 1
        )

        let authorized = try await coordinator.authorize(output: output, traceID: "authorized-export")
        #expect(authorized.paragraphs[0].anchors[0].availability == .offlineUnavailable)
        #expect(CreationExportService.plainText(from: authorized).contains("SourceUnavailable"))

        try await privacy.updatePolicy(UserPolicy(
            preferredLanguage: "en-US",
            authorizedSourceTypes: [],
            policyVersion: 8
        ))
        await #expect(throws: CreationExportError.privacyDenied) {
            _ = try await coordinator.authorize(output: output, traceID: "revoked-export")
        }
        let uncitedDerivedOutput = CreativeOutput(
            template: .letter,
            paragraphs: [
                GroundedParagraph(
                    id: UUID(),
                    text: "Derived body without a validated paragraph citation",
                    anchors: [],
                    groundingStatus: .noSource
                ),
            ],
            sourceMemoryCount: 1,
            sourceTypes: ["note"]
        )
        await #expect(throws: CreationExportError.privacyDenied) {
            _ = try await coordinator.authorize(
                output: uncitedDerivedOutput,
                traceID: "revoked-uncited-export"
            )
        }
    }

    @Test("AC-5: sharePresented is absent before callback and true only after callback")
    func shareAuditFollowsPresentationCallback() async throws {
        let (database, privacy) = try await makeDatabase()
        let coordinator = CreationExportCoordinator(
            privacyActor: privacy,
            sourceResolver: SourceResolverFake(availability: .available),
            pendingOps: PendingOpsActor(db: database)
        )
        let payloadID = UUID()

        #expect(try await privacy.fetchAuditLogs(eventType: .creationSharePresented).isEmpty)
        try await coordinator.recordSharePresentation(
            payloadID: payloadID,
            format: .markdown,
            periodType: "month",
            traceID: "presented-callback",
            presented: true
        )

        let event = try #require(try await privacy.fetchAuditLogs(eventType: .creationSharePresented).first)
        #expect(event.exportFormat == "markdown")
        #expect(event.sharePresented == true)
        #expect(event.periodType == "month")
        #expect(event.shareHandoffIdDigest == AuditContentHasher.sha256Hex(
            payloadID.uuidString.lowercased()
        ))
        #expect(event.sourceLanguage == nil)
    }

    @Test("AC-6: share audit idempotency uses the exact handoff digest without a scan window")
    func shareAuditUsesExactHandoffIdentity() async throws {
        let (database, privacy) = try await makeDatabase()
        let pending = PendingOpsActor(db: database)
        let coordinator = CreationExportCoordinator(
            privacyActor: privacy,
            sourceResolver: SourceResolverFake(availability: .available),
            pendingOps: pending
        )
        let firstPayloadID = UUID()
        let reusedTraceID = "reused-share-trace"

        try await coordinator.recordSharePresentation(
            payloadID: firstPayloadID,
            format: .plainText,
            periodType: nil,
            traceID: reusedTraceID,
            presented: true
        )
        try await coordinator.recordSharePresentation(
            payloadID: firstPayloadID,
            format: .plainText,
            periodType: nil,
            traceID: reusedTraceID,
            presented: true
        )

        for index in 0...CreativeGenerationLimits.maximumParagraphs {
            try await coordinator.recordSharePresentation(
                payloadID: UUID(),
                format: .plainText,
                periodType: nil,
                traceID: "newer-share-\(index)",
                presented: true
            )
        }

        let operationID = "creation-share-audit-\(firstPayloadID.uuidString.lowercased())"
        let retryData = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "payloadID": firstPayloadID.uuidString,
            "traceID": reusedTraceID,
            "exportFormat": "plainText",
            "sharePresented": true,
        ])
        try await pending.add(operation: PendingOperation(
            operationId: operationID,
            operationType: "creationShareAudit",
            parameters: retryData
        ))

        #expect(try await coordinator.retryPendingShareAudit(operationID: operationID) == false)
        let events = try await privacy.fetchAuditLogs(
            limit: CreativeGenerationLimits.maximumParagraphs + 10,
            eventType: .creationSharePresented
        )
        #expect(events.count == CreativeGenerationLimits.maximumParagraphs + 2)
        #expect(Set(events.compactMap(\.shareHandoffIdDigest)).count == events.count)
        #expect(try await pending.count() == 0)
    }

    @Test("AC-6: invalid report periods fail validation without entering persistence retry")
    func invalidPeriodDoesNotQueueAuditRetry() async throws {
        let (database, privacy) = try await makeDatabase()
        let pending = PendingOpsActor(db: database)
        let coordinator = CreationExportCoordinator(
            privacyActor: privacy,
            sourceResolver: SourceResolverFake(availability: .available),
            pendingOps: pending
        )

        await #expect(throws: CreationExportError.invalidPeriodType) {
            try await coordinator.recordSharePresentation(
                payloadID: UUID(),
                format: .pdf,
                periodType: "quarter",
                traceID: "invalid-period",
                presented: true
            )
        }
        #expect(try await pending.count() == 0)
    }

    @Test("AC-5/6: post-presentation audit failure queues one content-free retry and never writes false")
    func auditFailureQueuesIdempotentRetry() async throws {
        let (database, privacy) = try await makeDatabase()
        let pending = PendingOpsActor(db: database)
        let coordinator = CreationExportCoordinator(
            privacyActor: privacy,
            sourceResolver: SourceResolverFake(availability: .available),
            pendingOps: pending
        )
        let payloadID = UUID()
        await database.close()

        for _ in 0..<2 {
            await #expect(throws: CreationExportError.auditPersistenceFailed) {
                try await coordinator.recordSharePresentation(
                    payloadID: payloadID,
                    format: .plainText,
                    periodType: nil,
                    traceID: "post-presentation-audit-failure",
                    presented: true
                )
            }
            await database.close()
        }

        try await database.open()
        let retries = try await pending.listAll()
        #expect(retries.count == 1)
        #expect(retries[0].operationType == "creationShareAudit")
        let parameters = try #require(String(bytes: retries[0].parameters, encoding: .utf8))
        #expect(parameters.contains("Grounded body") == false)
        #expect(parameters.contains("target") == false)
        #expect(try await privacy.fetchAuditLogs(eventType: .creationSharePresented).isEmpty)

        let operationID = "creation-share-audit-\(payloadID.uuidString.lowercased())"
        #expect(try await coordinator.retryPendingShareAudit(operationID: operationID))
        #expect(try await coordinator.retryPendingShareAudit(operationID: operationID) == false)
        let audited = try await privacy.fetchAuditLogs(eventType: .creationSharePresented)
        #expect(audited.count == 1)
        #expect(audited[0].sharePresented == true)
        #expect(try await pending.count() == 0)
    }

    @Test("AC-5: ViewModel payload readiness is not presentation evidence")
    @MainActor
    func viewModelWaitsForControllerCallback() async throws {
        let (database, privacy) = try await makeDatabase()
        let coordinator = CreationExportCoordinator(
            privacyActor: privacy,
            sourceResolver: SourceResolverFake(availability: .available),
            pendingOps: PendingOpsActor(db: database)
        )
        let viewModel = CreationViewModel(exportCoordinator: coordinator)
        viewModel.loadPreloaded(CreationModel(
            selectedTemplate: .letter,
            title: "Grounded letter",
            periodType: nil,
            paragraphs: [
                CreationParagraph(
                    id: UUID(),
                    text: "Grounded body",
                    citations: [
                        CreationCitation(
                            memoryId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                            sourceType: "note"
                        ),
                    ],
                    groundingStatus: .cited
                ),
            ],
            sourceMemoryCount: 1,
            emptyReason: nil
        ))

        viewModel.presentShare()
        let payload = try #require(viewModel.sharePayload)
        #expect(try await privacy.fetchAuditLogs(eventType: .creationSharePresented).isEmpty)

        viewModel.shareControllerDidAppear(payloadID: payload.id)
        try await Task.sleep(for: .milliseconds(50))
        viewModel.shareSheetDidDismiss()
        try await Task.sleep(for: .milliseconds(20))

        let events = try await privacy.fetchAuditLogs(eventType: .creationSharePresented)
        #expect(events.count == 1)
        #expect(events[0].sharePresented == true)
        #expect(viewModel.viewState == .generated)
    }

    @Test("AC-5: dismissal before controller callback records false and exposes L2")
    @MainActor
    func viewModelRecordsPresentationFailure() async throws {
        let (database, privacy) = try await makeDatabase()
        let coordinator = CreationExportCoordinator(
            privacyActor: privacy,
            sourceResolver: SourceResolverFake(availability: .available),
            pendingOps: PendingOpsActor(db: database)
        )
        let viewModel = CreationViewModel(exportCoordinator: coordinator)
        viewModel.loadPreloaded(CreationFixtureLoader.load("creation-generated-letter")!)

        viewModel.presentShare()
        #expect(viewModel.sharePayload != nil)
        viewModel.shareSheetDidDismiss()
        try await Task.sleep(for: .milliseconds(50))

        let event = try #require(try await privacy.fetchAuditLogs(eventType: .creationSharePresented).first)
        #expect(event.sharePresented == false)
        #expect(event.success == false)
        if case .error = viewModel.viewState {
            #expect(Bool(true))
        } else {
            Issue.record("Expected an L2 error after presentation failed")
        }
    }

    @Test("AC-5: disappearing creation UI clears stale handoff ownership")
    @MainActor
    func viewModelClearsStaleHandoffOnDisappear() throws {
        let viewModel = CreationViewModel()
        viewModel.loadPreloaded(CreationFixtureLoader.load("creation-generated-letter")!)
        viewModel.presentShare()
        #expect(viewModel.sharePayload != nil)

        viewModel.onDisappear()
        viewModel.shareSheetDidDismiss()

        #expect(viewModel.sharePayload == nil)
        #expect(viewModel.viewState == .generated)
    }
}
