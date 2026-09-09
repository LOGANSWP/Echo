// ==========================================
// 文件: ErrorEnums.swift
// 对应规格: docs/02-architecture/架构设计文档.md §5 (统一错误处理矩阵)
//            docs/01-spec/用户故事与验收标准规格书.md §US-FBK-001~003, US-DIS-003 (错误文案本地化)
// 任务: 1.4 - 集成 SQLite，创建 ExcludedAssets, Feedback, TaskProgress, PendingOperations 表
//       3F.10 - L1~L4 错误分级映射 + 本地化用户文案 (US-DIS-003 AC-2/AC-4, DEF-39-1)
// 架构约束: 遵循 AGENTS.md §4.4 (L1~L4 错误分级), R-007 (compiler-checked Sendable only)
// 重要: 所有 struct stored/computed properties 必须 nonisolated（项目 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor）
// 生成时间: 2026-07-04 | 更新: 2026-08-12 (3F.10 ErrorSeverity/ErrorClassifier/localized messages)
// Task 4.0k (2026-09-08): typed generation failure severity without fallback masking.
// Traceability: US-SYN-001/004 and ADR-023; device/quality qualification remains pending.
// ==========================================

import Foundation

// MARK: - Database Error

public enum DatabaseError: Error, LocalizedError, Sendable {
    case connectionFailed(underlying: Error)
    case tableCreationFailed(table: String, underlying: Error)
    case writeFailed(operation: String, underlying: Error)
    case readFailed(operation: String, underlying: Error)
    case notFound(id: String)
    case rowMappingFailed

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let error):
            return "Database connection failed: \(error.localizedDescription)"

        case .tableCreationFailed(let table, let error):
            return "Failed to create table '\(table)': \(error.localizedDescription)"

        case .writeFailed(let op, let error):
            return "Write operation '\(op)' failed: \(error.localizedDescription)"

        case .readFailed(let op, let error):
            return "Read operation '\(op)' failed: \(error.localizedDescription)"

        case .notFound(let id):
            return "Record not found: \(id)"

        case .rowMappingFailed:
            return "Failed to map SQLite row to domain model"
        }
    }
}

// MARK: - Localization Lookup (3F.10)

/// Locale-explicit catalog lookup. String(localized:locale:) only affects formatting,
/// not localization choice, so the locale-specific .lproj sub-bundle is loaded directly.
public enum EchoLocalization {
    nonisolated public static func localized(_ key: String, locale: Locale) -> String {
        guard let bundle = localizationBundle(for: locale) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    nonisolated private static func localizationBundle(for locale: Locale) -> Bundle? {
        let main = Bundle.main
        var candidates = [locale.identifier]
        if let code = locale.language.languageCode?.identifier {
            if let script = locale.language.script?.identifier {
                candidates.append("\(code)-\(script)")
            }
            candidates.append(code)
        }
        for candidate in candidates {
            if let path = main.path(forResource: candidate, ofType: "lproj"),
                let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return nil
    }
}

// MARK: - Error Severity (AGENTS.md §4.4 L1~L4, US-DIS-003 AC-2/AC-4)

public enum ErrorSeverity: String, Sendable, CaseIterable, Equatable {
    case l1Transient
    case l2Recoverable
    case l3Blocking
    case l4Conflict

    nonisolated public var userFacingMessageKey: String {
        switch self {
        case .l1Transient:
            return "Something went wrong briefly. Echo is retrying automatically."

        case .l2Recoverable:
            return "This action could not be completed. You can retry it when ready."

        case .l3Blocking:
            return "This feature is unavailable until the issue is fixed. Open Settings for repair options."

        case .l4Conflict:
            return "Two versions of this memory conflict. Choose which one to keep."
        }
    }

    nonisolated public func userFacingMessage(locale: Locale) -> String {
        EchoLocalization.localized(userFacingMessageKey, locale: locale)
    }
}

// MARK: - Sync Conflict Error (L4, AGENTS.md §4.4)

public enum SyncConflictError: Error, LocalizedError, Sendable, Equatable {
    case conflict(memoryId: UUID)

    nonisolated public var errorDescription: String? {
        switch self {
        case .conflict(let id):
            return "Sync conflict for memory \(id.uuidString)"
        }
    }
}

// MARK: - Error Classifier (DEF-39-1: L1/L2/L3/L4 production mapping)

public enum ErrorClassifier {
    nonisolated public static func classify(_ error: Error) -> ErrorSeverity {
        if let generationError = error as? GenerationRuntimeError {
            return generationError.severity
        }
        if error is SyncConflictError {
            return .l4Conflict
        }
        if error is ModelLoaderActor.ModelLoadError {
            return .l3Blocking
        }
        if let dbError = error as? DatabaseError {
            switch dbError {
            case .connectionFailed:
                return .l1Transient

            case .tableCreationFailed:
                return .l3Blocking

            case .writeFailed, .readFailed, .rowMappingFailed:
                return .l2Recoverable

            case .notFound:
                return .l2Recoverable
            }
        }
        if error is CancellationError {
            return .l1Transient
        }
        return .l2Recoverable
    }
}

// MARK: - User-Facing Error Message (US-DIS-003 AC-2)

public protocol UserFacingError {
    func userFacingMessage(locale: Locale) -> String
}

extension DatabaseError: UserFacingError {
    nonisolated public func userFacingMessage(locale: Locale) -> String {
        ErrorClassifier.classify(self).userFacingMessage(locale: locale)
    }
}

// MARK: - Task Type

public enum TaskType: String, Sendable, Codable {
    case fullIndex
    case dataSourceSync
    case modelLoad
    case narrativeReport
    /// Task 4.0l / US-ING-004: bounded, reconstructible photo material preparation.
    case photoUnderstanding
    /// Persisted raw value is unknown to this app version. `TaskProgress.rawTaskType`
    /// retains the original identity for diagnostics and fail-closed recovery.
    case unknown
}

// MARK: - Feedback Models

public enum FeedbackSentiment: String, Sendable, Codable {
    case like
    case dislike
}

public struct FeedbackEntry: Sendable, Codable {
    nonisolated public let id: UUID
    nonisolated public let memoryId: UUID
    nonisolated public let queryText: String
    nonisolated public let sentiment: FeedbackSentiment
    nonisolated public let cosineSimilarity: Double
    nonisolated public let createdAt: Date
    nonisolated public let isBadCase: Bool
    nonisolated public let badCaseReason: String?

    nonisolated public init(
        id: UUID = UUID(),
        memoryId: UUID,
        queryText: String,
        sentiment: FeedbackSentiment,
        cosineSimilarity: Double,
        createdAt: Date = Date(),
        isBadCase: Bool = false,
        badCaseReason: String? = nil
    ) {
        self.id = id
        self.memoryId = memoryId
        self.queryText = queryText
        self.sentiment = sentiment
        self.cosineSimilarity = cosineSimilarity
        self.createdAt = createdAt
        self.isBadCase = isBadCase
        self.badCaseReason = badCaseReason
    }
}

public struct FeedbackAdjustment: Sendable {
    nonisolated public let adjustment: Double
    nonisolated public let feedbackCount: Int

    nonisolated public init(adjustment: Double, feedbackCount: Int) {
        self.adjustment = adjustment
        self.feedbackCount = feedbackCount
    }
}

// MARK: - Task Progress Model

public struct TaskProgress: Sendable, Codable {
    nonisolated public let taskId: String
    nonisolated public let taskType: TaskType
    nonisolated public let rawTaskType: String
    nonisolated public var lastProcessedIndex: Int
    nonisolated public var totalCount: Int
    nonisolated public var lastProcessedId: String?
    nonisolated public var resumeData: Data?
    nonisolated public var updatedAt: Date
    nonisolated public let createdAt: Date

    nonisolated public init(
        taskId: String = UUID().uuidString,
        taskType: TaskType,
        lastProcessedIndex: Int = 0,
        totalCount: Int = 0,
        lastProcessedId: String? = nil,
        resumeData: Data? = nil,
        updatedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.taskId = taskId
        self.taskType = taskType
        self.rawTaskType = taskType.rawValue
        self.lastProcessedIndex = lastProcessedIndex
        self.totalCount = totalCount
        self.lastProcessedId = lastProcessedId
        self.resumeData = resumeData
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }

    nonisolated public init(
        taskId: String,
        rawTaskType: String,
        lastProcessedIndex: Int = 0,
        totalCount: Int = 0,
        lastProcessedId: String? = nil,
        resumeData: Data? = nil,
        updatedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.taskId = taskId
        self.taskType = TaskType(rawValue: rawTaskType) ?? .unknown
        self.rawTaskType = rawTaskType
        self.lastProcessedIndex = lastProcessedIndex
        self.totalCount = totalCount
        self.lastProcessedId = lastProcessedId
        self.resumeData = resumeData
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}

// MARK: - Pending Operation Model

public struct PendingOperation: Sendable, Codable {
    nonisolated public let operationId: String
    nonisolated public let operationType: String
    nonisolated public var retryCount: Int
    nonisolated public let parameters: Data
    nonisolated public let createdAt: Date
    nonisolated public var lastError: String?

    nonisolated public init(
        operationId: String = UUID().uuidString,
        operationType: String,
        retryCount: Int = 0,
        parameters: Data,
        createdAt: Date = Date(),
        lastError: String? = nil
    ) {
        self.operationId = operationId
        self.operationType = operationType
        self.retryCount = retryCount
        self.parameters = parameters
        self.createdAt = createdAt
        self.lastError = lastError
    }
}
