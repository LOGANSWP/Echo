// File: CreationLibraryActor.swift
// Spec: docs/01-spec/用户故事与验收标准规格书.md -> US-SYN-003 AC-8/9/10; ADR-026
// Task: 4.0m - Application-owned creation queue
// Architecture: PrivacyCheckpoint, typed queue jobs and durable publication
// PR #81: same-ID delete barrier, honest resource deferral (AC-8/9/10).
// Generated: 2026-09-09
import Foundation

actor CreationLibraryActor {
    private let database: DatabaseManager
    private let privacy: PrivacyActor
    private let queue: TaskQueueActor
    private let repository: CanonicalMemoryRepositoryActor
    private let pipeline: CreativePipeline
    private var reservations: Set<UUID> = []
    private var deletingIDs: Set<UUID> = []

    init(
        database: DatabaseManager,
        privacy: PrivacyActor,
        queue: TaskQueueActor,
        repository: CanonicalMemoryRepositoryActor,
        pipeline: CreativePipeline
    ) {
        self.database = database
        self.privacy = privacy
        self.queue = queue
        self.repository = repository
        self.pipeline = pipeline
    }

    func list() async throws -> [CreationLibraryRecord] {
        let checkpoint = await privacy.validate(operation: .search, traceID: UUID().uuidString)
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        let requiresConsent = await privacy.isConsentEnforcementEnabled()
        let records = try await database.creationRecords(checkpoint: checkpoint, requiresConsent: requiresConsent)
        let owned = await queue.ownedTaskIDs()
        for record in records where [.queued, .running].contains(record.state)
            && !owned.contains(Self.taskID(record.id)) && !reservations.contains(record.id) {
            try await database.executeWrite(sql: "UPDATE CreationLibrary SET state='interrupted',errorCode='interrupted' WHERE id=? AND state IN ('queued','running')", bindings: [.text(record.id.uuidString)])
        }
        return try await database.creationRecords(checkpoint: checkpoint, requiresConsent: requiresConsent)
    }

    func submit(id: UUID, template: CreativeTemplate, sourceIDs: [UUID]) async throws {
        let checkpoint = await privacy.validate(operation: .search, traceID: id.uuidString)
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard !deletingIDs.contains(id), reservations.insert(id).inserted else { return }
        defer { reservations.remove(id) }
        if try await list().contains(where: { $0.id == id }) { return }
        let policy = await privacy.getPolicy()
        let request = CreationLibraryRequest(id: id, template: template, sourceIDs: sourceIDs, language: policy.preferredLanguage)
        try await schedule(request, checkpoint: checkpoint)
    }

    func retry(id: UUID) async throws {
        let checkpoint = await privacy.validate(operation: .search, traceID: id.uuidString)
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard !deletingIDs.contains(id), reservations.insert(id).inserted else { return }
        defer { reservations.remove(id) }
        guard let record = try await list().first(where: { $0.id == id }),
            [.failed, .cancelled, .interrupted, .deferred].contains(record.state)
        else { throw GenerationRuntimeError.invalidRequest }
        if record.errorCode == "model-unavailable" { try await pipeline.retryRuntime(traceID: id.uuidString) }
        let policy = await privacy.getPolicy()
        let request = CreationLibraryRequest(id: id, template: record.request.template, sourceIDs: record.request.sourceIDs, language: policy.preferredLanguage)
        // Retry explicitly rebuilds current input; no old output or model cache is reused.
        try await database.executeWrite(sql: "UPDATE CreationLibrary SET request=? WHERE id=? AND state!='completed'", bindings: [.blob(try JSONEncoder().encode(request)), .text(id.uuidString)])
        try await schedule(request, checkpoint: checkpoint)
    }

    func cancel(id: UUID) async throws {
        let checkpoint = await privacy.validate(operation: .search, traceID: id.uuidString)
        guard checkpoint.isAllowed, try await list().contains(where: { $0.id == id }) else { throw GenerationRuntimeError.privacyDenied }
        if await queue.cancel(taskId: Self.taskID(id)) {
            try await database.updateCreationState(id: id, state: .cancelled)
        }
    }

    func delete(id: UUID) async throws {
        let checkpoint = await privacy.validate(operation: .delete, traceID: id.uuidString)
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard deletingIDs.insert(id).inserted else { throw GenerationRuntimeError.busy }
        defer { deletingIDs.remove(id) }
        // Block new submissions/retries and let an already accepted reservation finish.
        // Cancellation then sees its actual queue ownership before the row is removed.
        while reservations.contains(id) { try await Task.sleep(for: .milliseconds(10)) }
        let final = await privacy.validate(operation: .delete, traceID: id.uuidString)
        guard final.isAllowed, try await list().contains(where: { $0.id == id }) else {
            throw GenerationRuntimeError.privacyDenied
        }
        _ = await queue.cancel(taskId: Self.taskID(id))
        try await database.executeWrite(sql: "DELETE FROM CreationLibrary WHERE id=?", bindings: [.text(id.uuidString)])
    }

    func markRead(id: UUID) async throws {
        let checkpoint = await privacy.validate(operation: .search, traceID: id.uuidString)
        guard checkpoint.isAllowed, try await list().contains(where: { $0.id == id }) else { throw GenerationRuntimeError.privacyDenied }
        try await database.executeWrite(sql: "UPDATE CreationLibrary SET unread=0 WHERE id=?", bindings: [.text(id.uuidString)])
    }

    private func schedule(_ request: CreationLibraryRequest, checkpoint: PrivacyCheckpoint) async throws {
        let reservation = try await queue.reserve(taskId: Self.taskID(request.id))
        do {
            try await database.insertCreationRequest(request, checkpoint: checkpoint, requiresConsent: await privacy.isConsentEnforcementEnabled())
            try await database.updateCreationState(id: request.id, state: .submitting)
            _ = try await database.executeWrite(sql: "DELETE FROM TaskProgress WHERE taskId=?", bindings: [.text(Self.taskID(request.id))])
            _ = try await database.executeWrite(sql: "DELETE FROM PendingOperations WHERE operationId=?", bindings: [.text(Self.taskID(request.id))])
            let descriptor = try TaskResumeDescriptor(operation: .search, sourceTypes: [], payload: JSONEncoder().encode(request)).encoded()
            let job = TaskQueueActor.QueuedJob(taskId: Self.taskID(request.id), taskType: .manualCreation, totalCount: 1, resumeData: descriptor) { [self, request] context in
                try await execute(request, context: context)
            }
            try await queue.enqueue(job, progressPolicy: .createNew, reservation: reservation)
            try await database.executeWrite(sql: "UPDATE CreationLibrary SET state='queued' WHERE id=? AND state='submitting'", bindings: [.text(request.id.uuidString)])
        } catch {
            await queue.release(reservation)
            try await recordFailure(request, error: error)
            throw error
        }
    }

    private func execute(_ request: CreationLibraryRequest, context: TaskQueueActor.TaskContext) async throws {
        let checkpoint = await privacy.validate(operation: .search, traceID: request.id.uuidString)
        do {
            guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
            try await context.checkPaused()
            try context.checkCancelled()
            try request.validate(forExecution: true)
            guard await privacy.getPolicy().preferredLanguage == request.language else { throw GenerationRuntimeError.restartRequired }
            try await database.updateCreationState(id: request.id, state: .running)
            var sources: [CreativeSource] = []
            for id in request.sourceIDs {
                guard let source = try await repository.loadCreationSource(memoryID: id, maximumTextBytes: GenerationInputBudget.maximumBytes) else { throw GenerationRuntimeError.restartRequired }
                sources.append(source)
            }
            let output = try await pipeline.generate(template: request.template, sources: sources, traceID: request.id.uuidString)
            try context.checkCancelled()
            try await context.checkPaused()
            for source in sources {
                guard try await repository.loadCreationSource(memoryID: source.memoryID, maximumTextBytes: GenerationInputBudget.maximumBytes) == source else { throw GenerationRuntimeError.restartRequired }
            }
            let final = await privacy.validate(operation: .search, traceID: request.id.uuidString, sourceTypes: output.sourceTypes)
            guard await privacy.getPolicy().preferredLanguage == request.language else { throw GenerationRuntimeError.restartRequired }
            try await database.publishCreation(output, request: request, sources: sources, checkpoint: final, requiresConsent: await privacy.isConsentEnforcementEnabled())
            try await context.report(processedIndex: 1, lastProcessedId: nil)
        } catch is CancellationError {
            try await database.updateCreationState(id: request.id, state: .cancelled)
            throw CancellationError()
        } catch {
            try await recordFailure(request, error: error)
            throw error
        }
    }

    private func recordFailure(_ request: CreationLibraryRequest, error: Error) async throws {
        if error as? NarrativeReportError == .resourceDeferred {
            try await database.updateCreationState(id: request.id, state: .deferred)
            return
        }
        let code: String
        switch error {
        case GenerationRuntimeError.deadline: code = "deadline"
        case GenerationRuntimeError.outputLimit: code = "output-limit"
        case GenerationRuntimeError.languageFallback: code = "language"
        case let error as GenerationRuntimeError where error.severity == .l3Blocking: code = "model-unavailable"
        default: code = "generation-failed"
        }
        try await database.updateCreationState(id: request.id, state: .failed, errorCode: code)
        if code == "model-unavailable" { return }
        // Insert only while the durable request still exists; a source deletion cannot resurrect it.
        try await database.executeWrite(sql: "INSERT OR REPLACE INTO PendingOperations(operationId,operationType,retryCount,parameters,createdAt,lastError) SELECT ?, 'manualCreation', 0, ?, ?, ? WHERE EXISTS(SELECT 1 FROM CreationLibrary WHERE id=? AND state='failed')", bindings: [.text(Self.taskID(request.id)), .blob(try JSONEncoder().encode(request)), .double(Date().timeIntervalSince1970), .text(code), .text(request.id.uuidString)])
    }

    nonisolated private static func taskID(_ id: UUID) -> String { "creation-\(id.uuidString)" }
}
