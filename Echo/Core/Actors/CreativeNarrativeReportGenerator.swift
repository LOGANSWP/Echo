// ==========================================
// File: CreativeNarrativeReportGenerator.swift
// Spec: US-SYN-004 AC-3/5/6; ADR-023 sections 2-5
// Task: 4.0k - Actual bounded leaf and reduce inference
// AC coverage: real batches, layer provenance, call/time limits and coverage
// Architecture: AGENTS.md sections 4.2/4.3
// Generated: 2026-09-08
// ==========================================

import Foundation

public actor CreativeNarrativeReportGenerator: NarrativeReportGenerating {
    nonisolated public var maximumSourceCount: Int { 24 }
    private let pipeline: CreativePipeline

    public init(pipeline: CreativePipeline) { self.pipeline = pipeline }

    public func configurationIdentity(traceID: String) async throws -> String {
        try await pipeline.configurationIdentity(traceID: traceID)
    }

    public func validateAvailability(traceID: String) async throws {
        try await pipeline.validateAvailability(traceID: traceID)
    }

    public func generate(request: NarrativeReportGenerationRequest, traceID: String) async throws
        -> NarrativeReportEnvelope {
        try await generate(request: request, context: nil, traceID: traceID)
    }

    public func generate(
        request: NarrativeReportGenerationRequest,
        context: TaskQueueActor.TaskContext?,
        traceID: String
    ) async throws -> NarrativeReportEnvelope {
        try await pipeline.validateAvailability(traceID: traceID)
        let deadline = ProcessInfo.processInfo.systemUptime + 600
        let savedIndex: Int
        if let context {
            savedIndex = try await context.progressActor.load(taskId: context.taskId)?.lastProcessedIndex ?? 0
        } else {
            savedIndex = 0
        }
        var calls = 0
        var contributors: Set<UUID> = []
        var sourceTypes: [UUID: String] = [:]
        var outputs: [[GroundedParagraph]] = []
        var omittedParagraphs = 0
        var seen: Set<UUID> = []
        let batches = request.sourceBatches.map { batch in
            batch.filter { source in
                guard seen.count < maximumSourceCount, seen.insert(source.memoryID).inserted else { return false }
                sourceTypes[source.memoryID] = SearchPipeline.normalizeSourceType(source.sourceType)
                return true
            }
        }.filter { !$0.isEmpty }
        for batch in batches {
            var cursor = 0
            while cursor < batch.count {
                try Task.checkCancellation()
                try await context?.checkPaused()
                try GenerationResourcePolicy.check()
                var end = min(cursor + 4, batch.count)
                var passages: [GenerationPassage] = []
                var types: [UUID: String] = [:]
                while true {
                    passages = batch[cursor..<end].map {
                        GenerationPassage(text: $0.text ?? "", sourceMemoryIDs: [$0.memoryID])
                    }
                    let ids = Set(passages.flatMap(\.sourceMemoryIDs))
                    types = sourceTypes.filter { ids.contains($0.key) }
                    if try await pipeline.passagesFit(
                        template: .report,
                        passages: passages,
                        sourceTypes: types,
                        traceID: traceID,
                        deadline: deadline
                    ) {
                        break
                    }
                    guard end - cursor > 1 else { throw GenerationRuntimeError.contextLimit }
                    end -= 1
                }
                guard calls + 2 <= 32 else { throw GenerationRuntimeError.outputLimit }
                let output = try await pipeline.generatePassages(
                    template: .report,
                    passages: passages,
                    sourceTypes: types,
                    traceID: traceID,
                    deadline: deadline,
                    sourceSnapshots: request.sources.filter { types[$0.memoryID] != nil },
                    excerptScalarLimit: 512
                )
                calls += output.modelCallCount
                contributors.formUnion(passages.flatMap(\.sourceMemoryIDs))
                outputs.append(output.paragraphs)
                try checkIntermediateBudget(outputs, deadline: deadline)
                if contributors.count > savedIndex {
                    try await context?.report(
                        processedIndex: contributors.count,
                        lastProcessedId: request.period.periodKey
                    )
                }
                cursor = end
            }
        }
        guard !outputs.isEmpty else { throw GenerationRuntimeError.invalidRequest }
        var layers = 1
        while outputs.count > 1 {
            try Task.checkCancellation()
            try await context?.checkPaused()
            guard layers < 3 else { throw GenerationRuntimeError.outputLimit }
            let all = outputs.flatMap { $0 }
            var cited = all.filter { $0.groundingStatus == .cited && !$0.anchors.isEmpty }
            omittedParagraphs += all.count - cited.count
            // The last layer must converge. Omitted prose is counted, while all
            // contributing leaf dependencies remain attached for privacy and deletion.
            if layers == 2, cited.count > 4 {
                omittedParagraphs += cited.count - 4
                cited = Array(cited.prefix(4))
            }
            guard !cited.isEmpty else { throw GenerationRuntimeError.invalidRequest }
            guard cited.reduce(0, { $0 + $1.text.utf8.count }) <= 524_288 else {
                throw GenerationRuntimeError.outputLimit
            }
            var next: [[GroundedParagraph]] = []
            var cursor = 0
            while cursor < cited.count {
                try await context?.checkPaused()
                try GenerationResourcePolicy.check()
                var end = min(cursor + 4, cited.count)
                var passages: [GenerationPassage] = []
                var types: [UUID: String] = [:]
                while true {
                    passages = cited[cursor..<end].map {
                        GenerationPassage(text: $0.text, sourceMemoryIDs: $0.anchors.map(\.memoryID))
                    }
                    let ids = Set(passages.flatMap(\.sourceMemoryIDs))
                    types = sourceTypes.filter { ids.contains($0.key) }
                    if try await pipeline.passagesFit(
                        template: .report,
                        passages: passages,
                        sourceTypes: types,
                        traceID: traceID,
                        deadline: deadline,
                        isReduction: true
                    ) {
                        break
                    }
                    guard end - cursor > 1 else { throw GenerationRuntimeError.contextLimit }
                    end -= 1
                }
                guard calls + 2 <= 32 else { throw GenerationRuntimeError.outputLimit }
                let output = try await pipeline.generatePassages(
                    template: .report,
                    passages: passages,
                    sourceTypes: types,
                    traceID: traceID,
                    deadline: deadline,
                    isReduction: true,
                    sourceSnapshots: request.sources.filter { types[$0.memoryID] != nil },
                    excerptScalarLimit: 512
                )
                calls += output.modelCallCount
                next.append(output.paragraphs)
                try checkIntermediateBudget(next, deadline: deadline)
                cursor = end
                if layers == 2 {
                    omittedParagraphs += cited.count - cursor
                    break
                }
            }
            outputs = next
            layers += 1
        }
        guard ProcessInfo.processInfo.systemUptime < deadline, let final = outputs.first, !final.isEmpty else {
            throw GenerationRuntimeError.deadline
        }
        try GenerationResourcePolicy.check()
        let coverage = NarrativeReportCoverage(
            partialBaseline: request.coverage.partialBaseline,
            coverageStart: request.coverage.coverageStart,
            coverageEnd: request.coverage.coverageEnd,
            submittedSourceCount: contributors.count,
            truncatedSourceCount: request.coverage.truncatedSourceCount
                + max(0, request.sources.count - contributors.count),
            omittedPartitions: request.coverage.omittedPartitions,
            aggregationLayerCount: layers
        )
        let envelope = NarrativeReportEnvelope(
            title: request.period.periodKey,
            periodType: request.period.periodType,
            periodKey: request.period.periodKey,
            paragraphs: final.map {
                NarrativeReportParagraph(
                    id: $0.id,
                    text: $0.text,
                    sourceMemoryIDs: $0.anchors.map(\.memoryID),
                    groundingStatus: $0.groundingStatus
                )
            },
            coverage: coverage,
            contributingMemoryIDs: contributors.sorted { $0.uuidString < $1.uuidString },
            modelCallCount: calls,
            omittedParagraphCount: omittedParagraphs
        )
        _ = try envelope.encoded()
        return envelope
    }

    private func checkIntermediateBudget(_ batches: [[GroundedParagraph]], deadline: Double) throws {
        try Task.checkCancellation()
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw GenerationRuntimeError.deadline }
        guard
            batches.reduce(
                0,
                { size, paragraphs in
                    size + paragraphs.reduce(0) { $0 + $1.text.utf8.count }
                }
            ) <= 524_288
        else { throw GenerationRuntimeError.outputLimit }
    }
}
