// ==========================================
// File: 4.0k_OfflineGenerationRuntimeTests.swift
// Spec: US-SYN-001/002/004; ADR-023 sections 1-6
// Task: 4.0k - Approved offline generation runtime
// AC coverage: exact artifact identity, token bounds and structured decoding
// Architecture: AGENTS.md sections 4.2, 6.2, 9.4
// Generated: 2026-09-08
// ==========================================

import Foundation
import Testing

@testable import Echo

private actor GenerationSequenceProvider: LLMProvider {
    let outputs: [String]
    private(set) var calls = 0
    init(outputs: [String]) { self.outputs = outputs }
    func generate(prompt: String, preferredLanguage: String) async throws -> String {
        let index = min(calls, outputs.count - 1)
        calls += 1
        return outputs[index]
    }
}

private actor RecordingStructuredProvider: StructuredLLMProvider {
    private(set) var requests: [GenerationRequest] = []
    func validateAvailability(traceID: String) async throws {}
    func tokenCount(request: GenerationRequest) async throws -> Int { 300 }
    func generate(prompt: String, preferredLanguage: String) async throws -> String {
        throw GenerationRuntimeError.invalidRequest
    }
    func generate(request: GenerationRequest) async throws -> GenerationResult {
        requests.append(request)
        let ids = request.allowedMemoryIDs.map { "\"\($0.uuidString)\"" }.joined(separator: ",")
        return GenerationResult(
            envelope:
                "{\"schemaVersion\":1,\"paragraphs\":[{\"text\":\"The family walked together in the garden during the afternoon.\",\"sourceMemoryIDs\":[\(ids)]}]}",
            inputTokenCount: 300,
            outputTokenCount: 90,
            predictionCount: 389,
            elapsedSeconds: 1,
            artifactIdentity: "test-double"
        )
    }
}

@Suite("4.0k Offline Generation Runtime", .serialized)
@MainActor
struct OfflineGenerationRuntimeTests {
    @Test("AC-1: explicit model retry revalidates the approved artifact and cannot register missing resources")
    func test_AC1_modelRepairCannotGrantApproval() async throws {
        let database = DatabaseManager(
            databaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("4.0k-model-repair-\(UUID().uuidString).sqlite")
        )
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(UserPolicy(authorizedSourceTypes: ["note"]))
        let manifest = ModelManifestActor(db: database)
        let runtime = BundledGenerationActor(resourceRoot: nil, privacyActor: privacy, manifestActor: manifest)
        await #expect(throws: GenerationRuntimeError.invalidArtifact) {
            try await runtime.validateAvailability(traceID: "missing-first")
        }
        await #expect(throws: GenerationRuntimeError.invalidArtifact) {
            try await runtime.retryAvailability(traceID: "explicit-repair")
        }
        #expect(try await manifest.loadAll().isEmpty)
        #expect(try await privacy.fetchAuditLogs(eventType: .modelLoadFailed).count == 2)
        #expect(try await privacy.fetchAuditLogs(eventType: .modelLoadRetrySuccess).isEmpty)
        #expect(ApprovedGenerationArtifact.manifest.revision == "c1899de289a04d12100db370d81485cdf75e47ca")
        #expect(ApprovedGenerationArtifact.manifest.dimension == 151_936)
        #expect(ApprovedGenerationArtifact.manifest.pooling == .none)
    }

    @Test("AC-4: prompt includes relevant terms and oversized manual source selections fail before inference")
    func test_AC4_promptTermsAndSelectionBounds() async throws {
        let database = DatabaseManager(
            databaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("4.0k-terms-\(UUID().uuidString).sqlite")
        )
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["note"]))
        let provider = RecordingStructuredProvider()
        let pipeline = CreativePipeline(
            llmProvider: provider,
            aligner: LanguageAligner(llmProvider: provider),
            privacyActor: privacy,
            terminology: TerminologyTable(entries: [
                "garden": ["en-US": "Summer Garden", "zh-Hans": "夏日花园"],
                "unrelated": ["en-US": "Unused Term", "zh-Hans": "无关术语"],
            ])
        )
        let source = CreativeSource(
            memoryID: UUID(),
            assetID: "",
            sourceType: "note",
            text: "The family walked in the garden.",
            timestamp: 1
        )
        _ = try await pipeline.generate(template: .report, sources: [source], traceID: "terms")
        let request = try #require(await provider.requests.first)
        #expect(request.system.contains("Summer Garden"))
        #expect(!request.system.contains("Unused Term"))
        let oversized = (0..<25).map { _ in
            CreativeSource(
                memoryID: UUID(),
                assetID: "",
                sourceType: "note",
                text: "The family walked in the garden.",
                timestamp: 1
            )
        }
        await #expect(throws: GenerationRuntimeError.contextLimit) {
            try await pipeline.generate(template: .report, sources: oversized, traceID: "oversized")
        }
        #expect(await provider.requests.count == 1)
    }

    @Test("AC-2/7: persisted generation metadata and resume identity fail closed")
    func test_AC2_AC7_rejectUnboundedProvenanceMetadata() throws {
        let id = UUID()
        let outsider = UUID()
        let paragraph = NarrativeReportParagraph(
            id: UUID(),
            text: "A recorded walk in the garden.",
            sourceMemoryIDs: [id],
            groundingStatus: .cited
        )
        let coverage = NarrativeReportCoverage(
            partialBaseline: false,
            coverageStart: Date(timeIntervalSince1970: 0),
            coverageEnd: Date(timeIntervalSince1970: 1),
            submittedSourceCount: 1
        )
        for (ids, calls, omitted) in [([outsider], 1, 0), ([id], 33, 0), ([id], 1, -1), ([id, id], 1, 0)] {
            let envelope = NarrativeReportEnvelope(
                title: "A month",
                periodType: .month,
                periodKey: "month:2025-12",
                paragraphs: [paragraph],
                coverage: coverage,
                contributingMemoryIDs: ids,
                modelCallCount: calls,
                omittedParagraphCount: omitted
            )
            #expect(throws: NarrativeReportError.invalidReportEnvelope) { try envelope.encoded() }
        }
        for identity in ["private source text", String(repeating: "z", count: 64), ""] {
            let payload = NarrativeReportResumePayload(
                periodType: .month,
                periodKey: "month:2025-12",
                executionIdentity: identity
            )
            #expect(throws: NarrativeReportError.invalidReportEnvelope) {
                try payload.encodedDescriptor(sourceTypes: ["note"])
            }
        }
    }

    @Test(
        "AC-7: recovery preserves checkpoint and distinguishes L3 from Restart-required L2",
        arguments: [GenerationRuntimeError.modelContract, .restartRequired]
    )
    func test_AC7_blockingRecoveryDoesNotBecomeL2(failure: GenerationRuntimeError) async throws {
        let database = DatabaseManager(
            databaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("4.0k-blocking-\(UUID().uuidString).sqlite")
        )
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(UserPolicy(authorizedSourceTypes: ["note"]))
        let progress = ProgressActor(db: database)
        let queue = TaskQueueActor(progressActor: progress)
        let registry = TaskRecoveryRegistry()
        await registry.register(taskType: .narrativeReport) { _ in throw failure }
        let descriptor = try TaskResumeDescriptor(operation: .search, sourceTypes: ["note"], payload: Data()).encoded()
        let saved = TaskProgress(
            taskId: "blocked-generation",
            taskType: .narrativeReport,
            lastProcessedIndex: 2,
            totalCount: 4,
            resumeData: descriptor
        )
        try await progress.save(progress: saved)
        let coordinator = TaskRecoveryCoordinator(
            progressActor: progress,
            taskQueue: queue,
            registry: registry,
            privacyActor: privacy,
            pendingOpsActor: PendingOpsActor(db: database),
            auditWriter: privacy
        )
        for restart in [false, true] {
            let snapshot = try #require(try await progress.load(taskId: saved.taskId))
            await #expect(throws: failure) {
                if restart {
                    _ = try await coordinator.restartTask(snapshot)
                } else {
                    _ = try await coordinator.continueTask(snapshot)
                }
            }
            #expect(try await progress.load(taskId: saved.taskId)?.lastProcessedIndex == 2)
            #expect(
                try await database.executeQuery(sql: "SELECT * FROM PendingOperations", bindings: []).isEmpty
                    == (failure == .modelContract)
            )
            #expect(await queue.ownedTaskIDs().isEmpty)
        }
    }

    @Test("AC-7: Restart atomically replaces the descriptor; Continue identity excludes plaintext")
    func test_AC7_restartDescriptorAndIdentity() async throws {
        let database = DatabaseManager(
            databaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("4.0k-restart-\(UUID().uuidString).sqlite")
        )
        try await database.open()
        let progress = ProgressActor(db: database)
        let oldData = try TaskResumeDescriptor(operation: .search, sourceTypes: ["note"], payload: Data("old".utf8))
            .encoded()
        let newData = try TaskResumeDescriptor(operation: .search, sourceTypes: ["note"], payload: Data("new".utf8))
            .encoded()
        let old = TaskProgress(
            taskId: "restart",
            taskType: .narrativeReport,
            lastProcessedIndex: 2,
            totalCount: 3,
            resumeData: oldData
        )
        try await progress.save(progress: old)
        let fresh = try #require(try await progress.load(taskId: old.taskId))
        let reset = try await progress.resetForRestart(fresh, resumeData: newData, totalCount: 4)
        #expect(reset.lastProcessedIndex == 0)
        #expect(reset.resumeData == newData)
        #expect(try await progress.load(taskId: old.taskId)?.totalCount == 4)
        let id = UUID()
        let source = CreativeSource(
            memoryID: id,
            assetID: "private-locator",
            sourceType: "note",
            text: "Private source text",
            timestamp: 1
        )
        let first = try NarrativeGenerationIdentity.digest(sources: [source], language: "en-US", policyVersion: 1)
        let changed = try NarrativeGenerationIdentity.digest(sources: [source], language: "zh-Hans", policyVersion: 1)
        #expect(first.count == 64)
        #expect(first != changed)
        #expect(
            first
                != (try NarrativeGenerationIdentity.digest(
                    sources: [source],
                    language: "en-US",
                    policyVersion: 1,
                    batches: [[source]]
                ))
        )
        #expect(
            first
                != (try NarrativeGenerationIdentity.digest(
                    sources: [source],
                    language: "en-US",
                    policyVersion: 1,
                    configuration: "changed-terms"
                ))
        )
        #expect(!first.contains("Private"))
    }

    @Test("AC-6: language audit uses bounded typed columns and survives reload")
    func test_AC6_languageAuditFields() async throws {
        let database = DatabaseManager(
            databaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("4.0k-audit-\(UUID().uuidString).sqlite")
        )
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.writeAuditLog(
            eventType: .generationLanguageChecked,
            traceID: "language-audit",
            policyVersion: 1,
            outputLanguage: "en-US",
            uiLanguage: "en-US",
            languageRetryCount: 1
        )
        let entries = try await privacy.fetchAuditLogs(eventType: .generationLanguageChecked)
        #expect(entries.first?.outputLanguage == "en-US")
        #expect(entries.first?.uiLanguage == "en-US")
        #expect(entries.first?.languageRetryCount == 1)
        await #expect(throws: AuditValidationError.self) {
            try await privacy.writeAuditLog(
                eventType: .generationLanguageChecked,
                traceID: "invalid",
                policyVersion: 1,
                outputLanguage: "fr-FR",
                uiLanguage: "en-US",
                languageRetryCount: 2
            )
        }
    }

    @Test("AC-4: consume real batches, then reduce only their actual leaf identities")
    func test_AC4_batchesAreExecutedBeforeReduction() async throws {
        let database = DatabaseManager(
            databaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("4.0k-hierarchy-\(UUID().uuidString).sqlite")
        )
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(
            UserPolicy(preferredLanguage: "en-US", authorizedSourceTypes: ["note"], policyVersion: 1)
        )
        let provider = RecordingStructuredProvider()
        let pipeline = CreativePipeline(
            llmProvider: provider,
            aligner: LanguageAligner(llmProvider: provider),
            privacyActor: privacy
        )
        let generator = CreativeNarrativeReportGenerator(pipeline: pipeline)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let period = try #require(
            NarrativeReportPeriodPlanner.completedPeriods(
                at: Date(timeIntervalSince1970: 1_767_744_000),
                eligibleFrom: Date(timeIntervalSince1970: 1_735_689_600),
                calendar: calendar
            ).first
        )
        let sources = (0..<2).map { index in
            CreativeSource(
                memoryID: UUID(),
                assetID: "",
                sourceType: "note",
                text: "The family walked in the garden.",
                timestamp: Double(index)
            )
        }
        let coverage = NarrativeReportCoverage(
            partialBaseline: false,
            coverageStart: period.coverageStart,
            coverageEnd: period.endInstant,
            submittedSourceCount: 2
        )
        let report = try await generator.generate(
            request: NarrativeReportGenerationRequest(
                period: period,
                sourceBatches: sources.map { [$0] },
                coverage: coverage
            ),
            traceID: "hierarchy"
        )
        let calls = await provider.requests
        #expect(calls.count == 3)
        #expect(calls.prefix(2).map(\.allowedMemoryIDs) == sources.map { [$0.memoryID] })
        #expect(Set(calls.last?.allowedMemoryIDs ?? []) == Set(sources.map(\.memoryID)))
        #expect(report.coverage.aggregationLayerCount == 2)
        #expect(report.coverage.submittedSourceCount == 2)
    }

    @Test("AC-4/5: language checks body after schema and allows exactly one retry")
    func test_AC4_AC5_structuredLanguageAlignment() async throws {
        let id = UUID()
        func envelope(_ text: String) -> String {
            "{\"schemaVersion\":1,\"paragraphs\":[{\"text\":\"\(text)\",\"sourceMemoryIDs\":[\"\(id)\"]}]}"
        }
        let request = GenerationRequest(
            system: "Summarize.",
            user: "Records.",
            allowedMemoryIDs: [id],
            sourceTypes: ["note"],
            preferredLanguage: "en-US",
            traceID: "language",
            executionDeadline: ProcessInfo.processInfo.systemUptime + 60
        )
        let provider = GenerationSequenceProvider(outputs: [
            envelope("这是一段完整的中文内容，描述我们一起散步的愉快回忆。"),
            envelope("The family walked together in the garden and enjoyed a peaceful afternoon."),
        ])
        let aligner = LanguageAligner(llmProvider: provider)
        let aligned = try await aligner.alignEnvelope(request: request)
        #expect(aligned.languageRetryCount == 1)
        #expect(await provider.calls == 2)
        let malformed = GenerationSequenceProvider(outputs: ["not JSON"])
        let invalidAligner = LanguageAligner(llmProvider: malformed)
        await #expect(throws: CreativeError.self) { try await invalidAligner.alignEnvelope(request: request) }
        #expect(await malformed.calls == 1)
        let wrong = GenerationSequenceProvider(outputs: [envelope("這是一段完整的繁體中文內容，描述我們共同創造的難忘經歷。")])
        let wrongAligner = LanguageAligner(llmProvider: wrong)
        await #expect(throws: GenerationRuntimeError.languageFallback) {
            try await wrongAligner.alignEnvelope(request: request)
        }
        #expect(await wrong.calls == 2)
    }

    @Test("AC-1: configured missing runtime is L3 before any generation")
    func test_AC1_configuredMissingRuntimeIsBlocking() async throws {
        let database = DatabaseManager(
            databaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("4.0k-\(UUID().uuidString).sqlite")
        )
        try await database.open()
        let privacy = PrivacyActor(db: database)
        try await privacy.updatePolicy(
            UserPolicy(
                preferredLanguage: "en-US",
                authorizedSourceTypes: ["note"],
                policyVersion: 1
            )
        )
        let runtime = BundledGenerationActor(resourceRoot: nil, privacyActor: privacy)
        await #expect(throws: GenerationRuntimeError.invalidArtifact) {
            try await runtime.validateAvailability(traceID: "missing-runtime")
        }
        #expect(ErrorClassifier.classify(GenerationRuntimeError.invalidArtifact) == .l3Blocking)
    }

    @Test("AC-1: approved files require exact bytes, regular files and a closed inventory")
    func test_AC1_artifactVerificationFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = GenerationArtifactFile(
            path: "weight.bin",
            sizeBytes: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        #expect(throws: GenerationRuntimeError.self) {
            try GenerationArtifactVerifier.verify(root: root, files: [file])
        }
        try Data("abc".utf8).write(to: root.appendingPathComponent("weight.bin"))
        try GenerationArtifactVerifier.verify(root: root, files: [file])
        try Data("abd".utf8).write(to: root.appendingPathComponent("weight.bin"))
        #expect(throws: GenerationRuntimeError.self) {
            try GenerationArtifactVerifier.verify(root: root, files: [file])
        }
        try Data("abc".utf8).write(to: root.appendingPathComponent("weight.bin"))
        try Data().write(to: root.appendingPathComponent("extra"))
        #expect(throws: GenerationRuntimeError.self) {
            try GenerationArtifactVerifier.verify(root: root, files: [file])
        }
    }

    @Test("AC-4: reserve output before the first prediction")
    func test_AC4_budgetRejectsOverflowAndOutOfOrderPredictions() throws {
        #expect(throws: GenerationBudgetError.self) {
            try GenerationBudget(inputCount: 769, outputLimit: 256, context: 1024, startedAt: 10, seconds: 60)
        }
        var budget = try GenerationBudget(inputCount: 2, outputLimit: 2, context: 1024, startedAt: 10, seconds: 60)
        #expect(throws: GenerationBudgetError.self) { try budget.beforePrediction(position: 1, now: 11) }
        try budget.beforePrediction(position: 0, now: 11)
        #expect(throws: GenerationBudgetError.self) { try budget.recordOutput(now: 11) }
        try budget.beforePrediction(position: 1, now: 11)
        try budget.recordOutput(now: 11)
        try budget.beforePrediction(position: 2, now: 11)
        try budget.recordOutput(now: 11)
        #expect(throws: GenerationBudgetError.self) { try budget.beforePrediction(position: 3, now: 11) }
        #expect(throws: GenerationBudgetError.self) { try budget.afterPrediction(now: 70) }
    }

    @Test("AC-2: grammar permits only submitted leaf identities and complete EOS")
    func test_AC2_grammarSourceBoundaryAndEOS() throws {
        let known = "00000000-0000-0000-0000-000000000001"
        let unknown = "00000000-0000-0000-0000-000000000002"
        let grammar = try GenerationEnvelopeGrammar(allowedIDs: [known])
        let envelope =
            "{\"schemaVersion\":1,\"paragraphs\":[{\"text\":\"A boat.\",\"sourceMemoryIDs\":[\"\(known)\"]}]}"
        #expect(grammar.status(Array(envelope.utf8)) == .complete)
        #expect(grammar.status(Array(envelope.replacingOccurrences(of: known, with: unknown).utf8)) == .invalid)
        var decoder = GenerationGrammarDecoder(grammar: grammar, tokenBytes: [1: Array(envelope.utf8)], eosIDs: [2])
        #expect(!decoder.allows(2))
        try decoder.accept(1)
        #expect(decoder.allows(2))
        try decoder.accept(2)
        #expect(!decoder.allows(1))
    }
}
