// ==========================================
// File: 4.0k_BundledGenerationIntegrationTests.swift
// Spec: US-SYN-001/003/004; ADR-023 section 6
// Task: 4.0k - Real bundled generation integration
// AC coverage: real E5 ingestion, canonical sources and approved Core ML provider
// Evidence scope: synthetic engineering integration; not device/quality qualification
// Architecture: AGENTS.md sections 4.2, 7.1, 9.4
// Generated: 2026-09-08
// ==========================================

import Foundation
import Testing

@testable import Echo

// DEF-79-002: explicitly deferred only in the CI lane until artifact distribution is authorized.
@Suite("4.0k Real Bundled Generation", .serialized,
       .disabled(if: ProcessInfo.processInfo.environment["ECHO_DEFER_GENERATION_ARTIFACT_TESTS"] == "1",
                 "DEF-79-002: CI model distribution deferred by user; real-model acceptance remains open"))
@MainActor
struct BundledGenerationIntegrationTests {
    @Test("AC-1/3: real ingestion, bilingual creation and hierarchical month/year reports", arguments: [false, true])
    func test_AC1_AC3_realIngestionAndCreation(hierarchical: Bool) async throws {
        let language = hierarchical ? "zh-Hans" : "en-US"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "generation-e2e-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = DatabaseManager(databaseURL: directory.appendingPathComponent("test.sqlite"))
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(
            UserPolicy(preferredLanguage: language, authorizedSourceTypes: ["note"], policyVersion: 1)
        )
        let consent = ConsentStoreActor(db: database, privacyActor: privacy)
        try await consent.acceptConsent(consentVersion: 1, policyVersion: 1)
        await privacy.enableConsentEnforcement(consentStore: consent)
        let registry = GenerationRegistryActor(
            db: database,
            storeDirectory: directory.appendingPathComponent("indexes")
        )
        try await registry.ensureInitialGenerations()
        let progress = ProgressActor(db: database)
        let queue = TaskQueueActor(progressActor: progress)
        let composition = AppComposition(
            databaseManager: database,
            privacyActor: privacy,
            consentStore: consent,
            generationRegistry: registry,
            taskQueue: queue,
            progressActor: progress
        )
        let route = try #require(try await registry.loadActiveRoute())
        let store = try #require(await registry.vectorStore(for: route.textGeneration))
        let ingest = IngestPipeline(
            embedder: composition.textEmbedder,
            privacyActor: privacy,
            vectorStore: store,
            excludedAssets: composition.excludedAssetsActor,
            canonicalRepository: composition.canonicalRepository,
            generationRegistry: registry,
            taskQueue: queue,
            progressActor: progress
        )
        let texts = [
            "A paper boat floated upright for ten seconds. It then tipped to the left. No other changes were recorded.",
            "Two red blocks stood side by side on a flat table. Neither block moved.",
            "A blue ball rolled down a short ramp and stopped beside a white cup.",
            "一片绿叶平放在灰色石头旁边。绿叶没有移动。",
            "玩具火车沿圆形轨道行驶了一圈，停在黄色车站前。",
        ]
        var ids: [UUID] = []
        for (index, text) in texts.prefix(hierarchical ? 5 : 1).enumerated() {
            let source = try SharedImportEnvelope.make(
                contentKind: .text,
                sourceType: .note,
                payload: text,
                sourceAppBundleId: "",
                createdAt: Date(timeIntervalSince1970: 1_764_892_800 + Double(index))
            )
            let ingested = try await ingest.ingestProductionSharedText(
                source,
                taskID: "generation-source-\(index)",
                traceID: "generation-source-\(index)"
            )
            ids.append(CanonicalMemoryRepositoryActor.deterministicID(
                sourceLocator: ingested.sourceLocator,
                sourceType: "note"
            ))
        }
        let id = try #require(ids.first)
        let memory = try #require(try await composition.canonicalRepository.loadMemory(memoryId: id))
        try await composition.generationProvider.validateAvailability(traceID: "generation-artifact")
        let output = try await composition.creativePipeline.generate(
            template: .report,
            sources: [
                CreativeSource(
                    memoryID: id,
                    assetID: "",
                    sourceType: "note",
                    text: nil,
                    timestamp: memory.createdAt.timeIntervalSince1970
                ),
            ],
            traceID: "generation-creation"
        )
        #expect(!output.didFallback)
        #expect(!output.paragraphs.isEmpty)
        #expect(output.paragraphs.allSatisfy { LanguageAligner.bodyMatches($0.text, language: language) })
        #expect(output.paragraphs.flatMap(\.anchors).allSatisfy { $0.memoryID == id })
        #expect(output.citationCount > 0)
        #expect(try await privacy.fetchAuditLogs(eventType: .generationLanguageChecked).contains { $0.success })

        // Advance the domain clock through public scheduling APIs. The source
        // remains the real E5-ingested canonical memory; no generator double is installed.
        for type in [NarrativeReportPeriodType.month, .year] {
            // Only December and the full year contain this source. Independent
            // baselines avoid claiming the intentionally empty earlier months.
            let baseline = Date(timeIntervalSince1970: type == .month ? 1_764_547_200 : 1_735_689_600)
            try await composition.narrativeReportActor.setEnabled(false, for: type, at: baseline)
            try await composition.narrativeReportActor.setEnabled(true, for: type, at: baseline)
        }
        for _ in 0..<2 {
            let result = try await composition.narrativeReportActor.scanAndEnqueue(
                at: Date(timeIntervalSince1970: 1_768_435_200),
                calendarContext: .init(timeZoneIdentifier: "UTC"),
                trigger: .userInitiated
            )
            guard case .enqueued(let taskID, _) = result else {
                Issue.record("Real generation did not enqueue the completed period: \(result)")
                return
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 180
            while await queue.activeTaskIDs().contains(taskID), ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            if await queue.activeTaskIDs().contains(taskID) {
                _ = await queue.cancelAndDiscard(taskId: taskID)
                Issue.record("Real report generation exceeded the engineering test deadline")
                return
            }
        }
        let reports = try await composition.narrativeReportActor.listReports()
        #expect(Set(reports.map(\.periodType)) == [.month, .year])
        #expect(
            reports.allSatisfy { report in
                (report.envelope.modelCallCount ?? 0) >= (hierarchical ? 3 : 1)
                    && Set(report.envelope.contributingMemoryIDs ?? []) == Set(ids)
                    && Set(report.sources.map(\.memoryID)) == Set(ids)
                    && report.envelope.coverage.submittedSourceCount == ids.count
                    && report.envelope.coverage.aggregationLayerCount >= (hierarchical ? 2 : 1)
                    && report.envelope.paragraphs.allSatisfy {
                        LanguageAligner.bodyMatches($0.text, language: language)
                    }
            }
        )
        #expect(try await privacy.fetchAuditLogs(eventType: .narrativeReportGenerated).count == 2)
    }
}
