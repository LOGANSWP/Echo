// ==========================================
// File: PhotoUnderstandingActor.swift
// Spec: US-ING-004 AC-6/7/8; US-SYN-003 AC-7; ADR-025
// Task: 4.0l - Durable bounded photo preparation
// Architecture: PrivacyCheckpoint, TaskQueue, versioned values and SQLite publication
// Generated: 2026-09-09
// ==========================================

import Foundation

public actor PhotoUnderstandingActor {
    private let database: DatabaseManager
    private let privacy: PrivacyActor
    private let queue: TaskQueueActor
    private let progress: ProgressActor
    private let pixelSource: any PhotoPixelSourceReading
    private let provider: any PhotoCaptionGenerating
    private let ocr: any PhotoOCRService
    private var scheduling: Set<UUID> = []

    public init(
        database: DatabaseManager,
        privacy: PrivacyActor,
        queue: TaskQueueActor,
        progress: ProgressActor,
        pixelSource: any PhotoPixelSourceReading,
        provider: any PhotoCaptionGenerating,
        ocr: any PhotoOCRService
    ) {
        self.database = database
        self.privacy = privacy
        self.queue = queue
        self.progress = progress
        self.pixelSource = pixelSource
        self.provider = provider
        self.ocr = ocr
    }

    /// Read the same current material eligibility used by the generation boundary.
    public func canCreate(memoryID: UUID, traceID: String) async throws -> Bool {
        let checkpoint = await privacy.validate(operation: .search, traceID: traceID, sourceTypes: ["photo"])
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        let item = try await currentItem(memoryID)
        let source = try await database.readCreationSource(
            memoryID: memoryID, maximumTextBytes: GenerationInputBudget.maximumBytes, assetRevision: item.assetRevision
        )
        let final = await privacy.validate(operation: .search, traceID: traceID, sourceTypes: ["photo"])
        guard final.isAllowed, try await currentItem(memoryID) == item else {
            throw GenerationRuntimeError.privacyDenied
        }
        return source?.photoCreationReady == true
    }

    public func readMaterial(memoryID: UUID, traceID: String) async throws -> PhotoUnderstandingMaterial? {
        let checkpoint = await privacy.validate(operation: .search, traceID: traceID, sourceTypes: ["photo"])
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        let item = try await currentItem(memoryID)
        let material = try await database.readPhotoMaterial(item)
        let final = await privacy.validate(operation: .search, traceID: traceID, sourceTypes: ["photo"])
        guard final.isAllowed, try await currentItem(memoryID) == item else {
            throw GenerationRuntimeError.privacyDenied
        }
        return material
    }

    public func schedule(memoryID: UUID, traceID: String, retry: Bool = false) async throws -> Bool {
        let checkpoint = await privacy.validate(operation: .ingest, traceID: traceID, sourceTypes: ["photo"])
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard scheduling.insert(memoryID).inserted else { return false }
        defer { scheduling.remove(memoryID) }
        let taskID = Self.taskID(memoryID)
        guard !(await queue.ownedTaskIDs()).contains(taskID) else { return false }
        let item: PhotoUnderstandingWorkItem
        do { item = try await currentItem(memoryID) } catch {
            if let row = try await database.photoSourceRow(memoryID: memoryID),
                let version = row["sourceVersion"]?.stringValue {
                let unavailable = PhotoUnderstandingWorkItem(
                    memoryID: memoryID,
                    sourceVersion: version,
                    assetRevision: "unavailable",
                    modelVersion: ApprovedPhotoUnderstandingArtifact.identity,
                    processingVersion: ApprovedPhotoUnderstandingArtifact.processingVersion
                )
                try await database.savePhotoIntent(
                    unavailable,
                    taskID: taskID,
                    checkpoint: checkpoint,
                    requiresConsent: await privacy.isConsentEnforcementEnabled()
                )
                try await recordFailure(unavailable, error: error)
            }
            throw error
        }
        if let row = try await database.photoJobRow(memoryID: memoryID) {
            if Self.matches(row, item), row["state"]?.stringValue == "ready" { return false }
            if ["failed", "unavailable"].contains(row["state"]?.stringValue ?? ""), !retry { return false }
            // An orphan checkpoint belongs to explicit Continue/Restart, never a lifecycle scan.
            if try await progress.load(taskId: taskID) != nil { return false }
        }
        let reservation = try await queue.reserve(taskId: taskID)
        do {
            try await database.savePhotoIntent(
                item,
                taskID: taskID,
                checkpoint: checkpoint,
                requiresConsent: await privacy.isConsentEnforcementEnabled()
            )
            let job = try makeJob(item, traceID: traceID)
            try await queue.enqueue(job, progressPolicy: .createNew, reservation: reservation)
            return true
        } catch {
            await queue.release(reservation)
            try await recordFailure(item, error: error)
            throw error
        }
    }

    public func status(memoryID: UUID, traceID: String) async throws -> PhotoUnderstandingStatus {
        let checkpoint = await privacy.validate(operation: .search, traceID: traceID, sourceTypes: ["photo"])
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard let row = try await database.photoJobRow(memoryID: memoryID) else { return .unprepared }
        let item = try await currentItem(memoryID)
        guard Self.matches(row, item) else { return .unprepared }
        return PhotoUnderstandingStatus(rawValue: row["state"]?.stringValue ?? "") ?? .unavailable
    }

    public func makeRecoveryJob(for request: TaskRecoveryRequest) async throws -> TaskQueueActor.QueuedJob {
        let checkpoint = await privacy.validate(
            operation: .ingest,
            traceID: request.progress.taskId,
            sourceTypes: ["photo"]
        )
        guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
        guard request.progress.taskType == .photoUnderstanding, request.progress.totalCount == 1,
            request.descriptor.operation == .ingest, request.descriptor.sourceTypes == ["photo"]
        else { throw TaskRecoveryError.launcherMismatch }
        let previous = try JSONDecoder().decode(PhotoUnderstandingWorkItem.self, from: request.descriptor.payload)
        guard Self.taskID(previous.memoryID) == request.progress.taskId else {
            throw TaskRecoveryError.launcherMismatch
        }
        let current = try await currentItem(previous.memoryID)
        guard request.choice == .restart || current == previous else { throw GenerationRuntimeError.restartRequired }
        if try await !database.photoMaterialIsReady(current), let runtime = provider as? BundledPhotoUnderstandingActor {
            try await runtime.validateAvailability(traceID: request.progress.taskId)
        }
        try await database.savePhotoIntent(
            current,
            taskID: request.progress.taskId,
            checkpoint: checkpoint,
            requiresConsent: await privacy.isConsentEnforcementEnabled()
        )
        return try makeJob(current, traceID: request.progress.taskId)
    }

    private func currentItem(_ memoryID: UUID) async throws -> PhotoUnderstandingWorkItem {
        guard let row = try await database.photoSourceRow(memoryID: memoryID),
            let locator = row["sourceLocator"]?.stringValue,
            let version = row["sourceVersion"]?.stringValue, !version.isEmpty, version.utf8.count <= 128
        else { throw GenerationRuntimeError.restartRequired }
        let revision = try await pixelSource.currentRevision(assetID: locator)
        guard !revision.isEmpty, revision.utf8.count <= 128 else { throw GenerationRuntimeError.invalidRequest }
        return PhotoUnderstandingWorkItem(
            memoryID: memoryID,
            sourceVersion: version,
            assetRevision: revision,
            modelVersion: ApprovedPhotoUnderstandingArtifact.identity,
            processingVersion: ApprovedPhotoUnderstandingArtifact.processingVersion
        )
    }

    private func makeJob(_ item: PhotoUnderstandingWorkItem, traceID: String) throws -> TaskQueueActor.QueuedJob {
        TaskQueueActor.QueuedJob(
            taskId: Self.taskID(item.memoryID),
            taskType: .photoUnderstanding,
            totalCount: 1,
            resumeData: try Self.resumeData(item)
        ) { [self, item, traceID] context in
            try await execute(item, context: context, traceID: traceID)
        }
    }

    private func execute(_ item: PhotoUnderstandingWorkItem, context: TaskQueueActor.TaskContext, traceID: String)
        async throws {
        let checkpoint = await privacy.validate(operation: .ingest, traceID: traceID, sourceTypes: ["photo"])
        do {
            guard checkpoint.isAllowed else { throw GenerationRuntimeError.privacyDenied }
            try await context.checkPaused()
            try GenerationResourcePolicy.check()
            guard try await currentItem(item.memoryID) == item,
                let row = try await database.photoSourceRow(memoryID: item.memoryID),
                let locator = row["sourceLocator"]?.stringValue
            else { throw GenerationRuntimeError.restartRequired }
            if try await database.photoMaterialIsReady(item) {
                try await context.report(processedIndex: 1, lastProcessedId: item.memoryID.uuidString)
                return
            }
            let image = try await pixelSource.read(assetID: locator, expectedRevision: item.assetRevision)
            guard !image.isEmpty, image.count <= 32_000_000 else { throw GenerationRuntimeError.contextLimit }
            let beforeModel = await privacy.validate(operation: .ingest, traceID: traceID, sourceTypes: ["photo"])
            guard beforeModel.isAllowed, try await currentItem(item.memoryID) == item else {
                throw GenerationRuntimeError.privacyDenied
            }
            let caption = try await provider.describe(imageData: image, traceID: traceID)
            try context.checkCancelled()
            let text = try await ocr.recognizeText(
                imageData: image,
                preferredLanguages: ["zh-Hans", "en-US"],
                traceID: traceID
            )
            try context.checkCancelled()
            let final = await privacy.validate(operation: .ingest, traceID: traceID, sourceTypes: ["photo"])
            guard final.isAllowed, try await currentItem(item.memoryID) == item else {
                throw GenerationRuntimeError.privacyDenied
            }
            try await database.publishPhotoMaterial(
                item,
                taskID: context.taskId,
                material: (caption, text),
                checkpoint: final,
                requiresConsent: await privacy.isConsentEnforcementEnabled()
            )
            try await context.report(processedIndex: 1, lastProcessedId: item.memoryID.uuidString)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await recordFailure(item, error: error)
            throw error
        }
    }

    private func recordFailure(_ item: PhotoUnderstandingWorkItem, error: Error) async throws {
        let state: String
        if error as? NarrativeReportError == .resourceDeferred {
            state = "queued"
        } else if (error as? GenerationRuntimeError)?.severity == .l3Blocking
            || (error as? PhotoRuntimeContractFailure)?.severity == .l3Blocking {
            state = "unavailable"
        } else {
            state = "failed"
        }
        try await database.failPhotoJob(
            item,
            taskID: Self.taskID(item.memoryID),
            state: state,
            resumeData: Self.resumeData(item),
            errorCode: "photo-preparation-\(state)"
        )
    }

    nonisolated private static func taskID(_ id: UUID) -> String { "photo-understanding-\(id.uuidString.lowercased())" }

    nonisolated private static func matches(_ row: [String: DBValue], _ item: PhotoUnderstandingWorkItem) -> Bool {
        row["sourceVersion"]?.stringValue == item.sourceVersion
            && row["assetRevision"]?.stringValue == item.assetRevision
            && row["modelVersion"]?.stringValue == item.modelVersion
            && row["processingVersion"]?.stringValue == item.processingVersion
    }

    nonisolated private static func resumeData(_ item: PhotoUnderstandingWorkItem) throws -> Data {
        try TaskResumeDescriptor(operation: .ingest, sourceTypes: ["photo"], payload: JSONEncoder().encode(item))
            .encoded()
    }
}
