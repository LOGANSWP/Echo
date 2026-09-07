// ==========================================
// 文件: DatabaseManager.swift
// 对应规格: docs/02-architecture/架构设计文档.md §5.1 (存储层次), §4.2 (Actor 隔离)
//            AGENTS.md §5 (数据持久化契约)
// 任务: 1.4 - 集成 SQLite，创建 ExcludedAssets, Feedback, TaskProgress, PendingOperations 表
//      4.0d - MemoryFeeling relationship and card interaction audit migration
//      4.0f - Persisted awakening preferences and HealthKit request lifecycle
//      4.0h - Source deletion saga, structured audit fields, and cleanup notices
//      4.0i - Typed grounded-generation and system-share audit fields
//      4.0j - Persisted narrative report scheduling and atomic publication
// 架构约束: 遵循 AGENTS.md §4.2 (Actor 隔离契约), R-007 (禁止 @unchecked Sendable)
// AC 覆盖: D-005 deletion journal persists phase, vector plan, and exclusion intent;
//          US-AWK-005 AC-4/5 (feeling cascade and structured interaction audit);
//          4.0f AC-3/6 (awakening preferences and honest HealthKit request state);
//          4.0h AC-2/3/5 (source deletion recovery and structured audit state);
//          4.0i AC-6 (unique exact share handoff audit identity)
//          4.0j AC-1/2/3/7 (per-type baselines, frozen periods, reports and invalidation)
// Generated: 2026-07-04; Updated: 2026-09-07 (4.0j)
// ==========================================

import Foundation
import SQLite3

internal nonisolated enum NarrativePublicationFailureStage: Sendable, Equatable, CaseIterable {
    case afterReport
    case afterSources
    case afterAudit
    case afterCompletion
}

// MARK: - Database Manager Actor

/// 共享 SQLite 数据库连接管理器 — 提供线程安全的数据库连接，负责建表与 WAL 模式配置。
///
/// ## Actor 隔离契约 (AGENTS.md §4.2)
/// - 可变状态封装: SQLite3 连接句柄指针封装在 Actor 中
/// - 串行执行: 同一 Actor 的操作串行执行，无数据竞争
/// - 所有 SQLite 写操作通过此 Actor 的串行队列执行
/// - OpaquePointer (SQL语句句柄) 不跨 Actor 传递，所有 SQL 操作内聚
///
/// ## 设计决策
/// - 使用系统 SQLite3（零外部依赖），通过 actor 保证线程安全
/// - WAL 模式：支持并发读，写入串行化
/// - 数据库文件路径：`<AppSupport>/Echo/db.sqlite`，NSFileProtectionComplete
public actor DatabaseManager {

    // MARK: - Singleton

    public static let shared = DatabaseManager()

    // MARK: - Properties

    private var db: OpaquePointer?
    private let dbURL: URL
    internal var narrativePublicationFailureStageForTesting: NarrativePublicationFailureStage?

    /// SQLite 版本号（运行时诊断用）
    public nonisolated var sqliteVersion: String {
        String(cString: sqlite3_libversion())
    }

    // MARK: - Initialization

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let echoDir = appSupport.appendingPathComponent("Echo", isDirectory: true)
        try? FileManager.default.createDirectory(at: echoDir, withIntermediateDirectories: true)
        self.dbURL = echoDir.appendingPathComponent("db.sqlite")
    }

    /// Creates an isolated database instance for deterministic tests and bounded tools.
    /// Production composition continues to use ``shared`` exclusively.
    internal init(databaseURL: URL) {
        self.dbURL = databaseURL
    }

    // MARK: - Connection Management

    /// 打开数据库连接（WAL 模式，NSFileProtectionComplete）
    public func open() async throws {
        guard sqlite3_open_v2(
            dbURL.path,
            &db,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FILEPROTECTION_COMPLETE,
            nil
        ) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw DatabaseError.connectionFailed(underlying: NSError(domain: "sqlite3", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
        }
        try execute(sql: "PRAGMA journal_mode=WAL")
        try execute(sql: "PRAGMA foreign_keys=ON")
        try createAllTables()
    }

    public func close() {
        if let db = db {
            sqlite3_close_v2(db)
            self.db = nil
        }
    }

    // MARK: - Table Creation

    private func createAllTables() throws {
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS ExcludedAssets (
                assetId TEXT PRIMARY KEY NOT NULL,
                sourceType TEXT NOT NULL,
                excludedAt INTEGER NOT NULL
            )
            """)
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS FeedbackStore (
                feedbackId TEXT PRIMARY KEY NOT NULL,
                memoryId TEXT NOT NULL,
                queryText TEXT NOT NULL,
                sentiment TEXT NOT NULL,
                cosineSimilarity REAL NOT NULL,
                createdAt REAL NOT NULL,
                isBadCase INTEGER NOT NULL DEFAULT 0,
                badCaseReason TEXT,
                generationId TEXT
            )
            """)
        // v5 migration: existing FeedbackStore gains generation identity (US-FBK-001/002/003, ADR-010 决策-4)
        let feedbackColumns = try columnNames(in: "FeedbackStore")
        if !feedbackColumns.contains("generationId") {
            try execute(sql: "ALTER TABLE FeedbackStore ADD COLUMN generationId TEXT")
        }
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS TaskProgress (
                taskId TEXT PRIMARY KEY NOT NULL,
                taskType TEXT NOT NULL,
                lastProcessedId TEXT,
                lastProcessedIndex INTEGER NOT NULL DEFAULT 0,
                totalCount INTEGER NOT NULL DEFAULT 0,
                resumeData BLOB,
                createdAt REAL NOT NULL,
                updatedAt REAL NOT NULL
            )
            """)
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS PendingOperations (
                operationId TEXT PRIMARY KEY NOT NULL,
                operationType TEXT NOT NULL,
                retryCount INTEGER NOT NULL DEFAULT 0,
                parameters BLOB NOT NULL,
                createdAt REAL NOT NULL,
                lastError TEXT
            )
            """)
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS AuditLog (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                eventType TEXT NOT NULL,
                timestamp REAL NOT NULL,
                traceID TEXT NOT NULL,
                policyVersion INTEGER NOT NULL DEFAULT 1,
                success INTEGER NOT NULL DEFAULT 1,
                sourceType TEXT,
                affectedCount INTEGER,
                excludedWritten INTEGER,
                sourceLanguage TEXT,
                elapsedMs INTEGER,
                action TEXT,
                resumePoint INTEGER,
                userChoiceOnRestart TEXT,
                outcome TEXT,
                cardIdDigest TEXT,
                memoryIdDigest TEXT,
                feelingAssociatedToSource INTEGER
            )
            """)
        try execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_auditlog_timestamp ON AuditLog(timestamp)
            """)
        // v2 schema migration: add video-specific audit fields (US-ING-005 AC-5, Task 2.4)
        // Idempotent via PRAGMA table_info guard; migration errors propagate instead of
        // being silently swallowed (a failed ALTER leaves the schema inconsistent).
        let auditColumns = try columnNames(in: "AuditLog")
        if !auditColumns.contains("frameCount") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN frameCount INTEGER")
        }
        if !auditColumns.contains("audioTranscriptLength") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN audioTranscriptLength INTEGER")
        }
        if !auditColumns.contains("hasAudio") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN hasAudio INTEGER")
        }
        // v4 schema migration (3F.1): add hash-only content column (AGENTS.md §5.4)
        // 修复：v4 迁移仅有注释无 ALTER——干净容器下 AuditLog 缺 contentHash 列，
        // 使 writeAuditLog 的 INSERT 静默失败（调用方 try? 吞错）
        if !auditColumns.contains("contentHash") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN contentHash TEXT")
        }

        // WP3 steps 3c-3c5 (photo-text-search): audit subject identity columns + index
        if !auditColumns.contains("subjectKind") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN subjectKind TEXT")
        }
        if !auditColumns.contains("subjectHash") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN subjectHash TEXT")
        }
        if !auditColumns.contains("action") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN action TEXT")
        }
        if !auditColumns.contains("resumePoint") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN resumePoint INTEGER")
        }
        if !auditColumns.contains("userChoiceOnRestart") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN userChoiceOnRestart TEXT")
        }
        if !auditColumns.contains("outcome") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN outcome TEXT")
        }
        if !auditColumns.contains("cardIdDigest") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN cardIdDigest TEXT")
        }
        if !auditColumns.contains("memoryIdDigest") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN memoryIdDigest TEXT")
        }
        if !auditColumns.contains("feelingAssociatedToSource") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN feelingAssociatedToSource INTEGER")
        }
        if !auditColumns.contains("editedFields") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN editedFields TEXT")
        }
        if !auditColumns.contains("reindexed") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN reindexed INTEGER")
        }
        if !auditColumns.contains("conflictResolvedWith") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN conflictResolvedWith TEXT")
        }
        // 4.0h / ADR-019: external source deletion and notice state stay structured.
        if !auditColumns.contains("preservedOriginal") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN preservedOriginal INTEGER")
        }
        if !auditColumns.contains("sourceDeletionRequested") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN sourceDeletionRequested INTEGER")
        }
        if !auditColumns.contains("sourceDeletionCompleted") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN sourceDeletionCompleted INTEGER")
        }
        if !auditColumns.contains("sourceDeletionOutcome") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN sourceDeletionOutcome TEXT")
        }
        if !auditColumns.contains("excludedAutoCleaned") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN excludedAutoCleaned INTEGER")
        }
        if !auditColumns.contains("userNotified") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN userNotified INTEGER")
        }
        // 4.0i / ADR-020: creation/share semantics use typed columns, never sourceLanguage JSON.
        if !auditColumns.contains("templateType") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN templateType TEXT")
        }
        if !auditColumns.contains("sourceMemoryCount") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN sourceMemoryCount INTEGER")
        }
        if !auditColumns.contains("citationCount") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN citationCount INTEGER")
        }
        if !auditColumns.contains("noSourceCount") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN noSourceCount INTEGER")
        }
        if !auditColumns.contains("exportFormat") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN exportFormat TEXT")
        }
        if !auditColumns.contains("sharePresented") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN sharePresented INTEGER")
        }
        if !auditColumns.contains("periodType") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN periodType TEXT")
        }
        if !auditColumns.contains("shareHandoffIdDigest") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN shareHandoffIdDigest TEXT")
        }
        if !auditColumns.contains("dataSourcesUsed") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN dataSourcesUsed TEXT")
        }
        if !auditColumns.contains("periodKeyDigest") {
            try execute(sql: "ALTER TABLE AuditLog ADD COLUMN periodKeyDigest TEXT")
        }
        try execute(sql: """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_auditlog_share_handoff
            ON AuditLog(shareHandoffIdDigest)
            WHERE eventType = 'creationSharePresented' AND shareHandoffIdDigest IS NOT NULL
            """)
        try execute(sql: """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_auditlog_narrative_period
            ON AuditLog(periodKeyDigest)
            WHERE eventType = 'narrativeReportGenerated' AND periodKeyDigest IS NOT NULL
            """)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_auditlog_subject_hash ON AuditLog(subjectHash)")
        // WP3 steps 3i-3t2 (photo-text-search): D-005 resumable deletion journal
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS MemoryDeletionJournal (
                operationID TEXT PRIMARY KEY NOT NULL,
                memoryId TEXT NOT NULL,
                auditSubjectHash TEXT NOT NULL,
                traceID TEXT NOT NULL,
                phase TEXT NOT NULL,
                vectorIDsByGenerationJSON TEXT NOT NULL DEFAULT '[]',
                sourceLocator TEXT,
                sourceType TEXT,
                writeExcluded INTEGER,
                updatedAt REAL NOT NULL
            )
            """)
        let deletionJournalColumns = try columnNames(in: "MemoryDeletionJournal")
        if !deletionJournalColumns.contains("sourceLocator") {
            try execute(sql: "ALTER TABLE MemoryDeletionJournal ADD COLUMN sourceLocator TEXT")
        }
        if !deletionJournalColumns.contains("sourceType") {
            try execute(sql: "ALTER TABLE MemoryDeletionJournal ADD COLUMN sourceType TEXT")
        }
        if !deletionJournalColumns.contains("writeExcluded") {
            try execute(sql: "ALTER TABLE MemoryDeletionJournal ADD COLUMN writeExcluded INTEGER")
        }
        if !deletionJournalColumns.contains("intentKind") {
            try execute(sql: "ALTER TABLE MemoryDeletionJournal ADD COLUMN intentKind TEXT")
        }
        if !deletionJournalColumns.contains("sourceDeletionState") {
            try execute(sql: "ALTER TABLE MemoryDeletionJournal ADD COLUMN sourceDeletionState TEXT")
        }
        if !deletionJournalColumns.contains("sourceDeletionOutcome") {
            try execute(sql: "ALTER TABLE MemoryDeletionJournal ADD COLUMN sourceDeletionOutcome TEXT")
        }
        // Existing databases may contain duplicate legacy operations. Keep the newest before
        // installing the one-active-intent invariant.
        try execute(sql: """
            DELETE FROM MemoryDeletionJournal
            WHERE rowid NOT IN (
                SELECT MAX(rowid) FROM MemoryDeletionJournal GROUP BY memoryId
            )
            """)
        try execute(sql: "CREATE UNIQUE INDEX IF NOT EXISTS idx_deletion_journal_memory ON MemoryDeletionJournal(memoryId)")
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS ExcludedCleanupNotice (
                assetIdDigest TEXT PRIMARY KEY NOT NULL,
                sourceType TEXT NOT NULL,
                createdAt REAL NOT NULL,
                presentedAt REAL
            )
            """)
        // UserPolicy persistence table
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS UserPolicyStore (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                preferredLanguage TEXT NOT NULL DEFAULT 'zh-Hans',
                authorizedSourceTypes TEXT NOT NULL DEFAULT '["photo","note","voice"]',
                policyVersion INTEGER NOT NULL DEFAULT 1,
                updatedAt REAL NOT NULL
            )
            """)
        // ── v3 schema migration: ModelManifest / IndexGeneration / ActiveRouteSet (R-A) ──
        // 规范 Memory 表 (R-A.1): canonical facts source
        // v5 (3F.4): originalTimestamp/userEdited/userLocked (US-AWK-007, DEF-38-001/002)
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS Memory (
                memoryId TEXT PRIMARY KEY NOT NULL,
                sourceLocator TEXT NOT NULL,
                canonicalText TEXT,
                sourceType TEXT NOT NULL,
                createdAt REAL NOT NULL,
                updatedAt REAL NOT NULL,
                recoverability TEXT NOT NULL DEFAULT 'full',
                originalTimestamp REAL,
                userEdited INTEGER NOT NULL DEFAULT 0,
                userLocked INTEGER NOT NULL DEFAULT 0
            )
            """)
        // v5 migration: existing Memory tables gain edit fields (idempotent)
        let memoryColumns = try columnNames(in: "Memory")
        if !memoryColumns.contains("originalTimestamp") {
            try execute(sql: "ALTER TABLE Memory ADD COLUMN originalTimestamp REAL")
        }
        if !memoryColumns.contains("userEdited") {
            try execute(sql: "ALTER TABLE Memory ADD COLUMN userEdited INTEGER NOT NULL DEFAULT 0")
        }
        if !memoryColumns.contains("userLocked") {
            try execute(sql: "ALTER TABLE Memory ADD COLUMN userLocked INTEGER NOT NULL DEFAULT 0")
        }
        // 4.0e: user-authored fields remain separate from immutable source text.
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS MemoryUserEdit (
                memoryId TEXT PRIMARY KEY NOT NULL REFERENCES Memory(memoryId) ON DELETE CASCADE,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                tagsJSON TEXT NOT NULL,
                updatedAt REAL NOT NULL
            )
            """)
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS MemoryEditConflict (
                memoryId TEXT PRIMARY KEY NOT NULL REFERENCES Memory(memoryId) ON DELETE CASCADE,
                externalVersionSummary TEXT NOT NULL,
                detectedAt REAL NOT NULL,
                pendingAssetId TEXT,
                pendingSource TEXT,
                pendingChangeType TEXT,
                pendingContentHash TEXT,
                pendingHashSkipped INTEGER NOT NULL DEFAULT 0
            )
            """)
        let conflictColumns = try columnNames(in: "MemoryEditConflict")
        if !conflictColumns.contains("pendingAssetId") {
            try execute(sql: "ALTER TABLE MemoryEditConflict ADD COLUMN pendingAssetId TEXT")
        }
        if !conflictColumns.contains("pendingSource") {
            try execute(sql: "ALTER TABLE MemoryEditConflict ADD COLUMN pendingSource TEXT")
        }
        if !conflictColumns.contains("pendingChangeType") {
            try execute(sql: "ALTER TABLE MemoryEditConflict ADD COLUMN pendingChangeType TEXT")
        }
        if !conflictColumns.contains("pendingContentHash") {
            try execute(sql: "ALTER TABLE MemoryEditConflict ADD COLUMN pendingContentHash TEXT")
        }
        if !conflictColumns.contains("pendingHashSkipped") {
            try execute(sql: "ALTER TABLE MemoryEditConflict ADD COLUMN pendingHashSkipped INTEGER NOT NULL DEFAULT 0")
        }
        // 4.0d: editable feelings are relational children, never canonical/search payloads.
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS MemoryFeeling (
                feelingId TEXT PRIMARY KEY NOT NULL,
                memoryId TEXT NOT NULL REFERENCES Memory(memoryId) ON DELETE CASCADE,
                text TEXT NOT NULL,
                createdAt REAL NOT NULL,
                updatedAt REAL NOT NULL
            )
            """)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_memoryfeeling_memory ON MemoryFeeling(memoryId)")
        // CR-18 (PR#57): memoryIDs(forSourceLocator:) 按 sourceLocator 全表扫查询索引（idempotent）
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_memory_sourcelocator ON Memory(sourceLocator)")
        // 一个记忆的多种表示 (R-A.1): modality-specific representations
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS Representation (
                representationId TEXT PRIMARY KEY NOT NULL,
                memoryId TEXT NOT NULL REFERENCES Memory(memoryId) ON DELETE CASCADE,
                modality TEXT NOT NULL,
                preprocessVersion TEXT NOT NULL,
                contentHash TEXT NOT NULL
            )
            """)
        // v5 (3F.4, US-ING-006 AC-3): FTS5 canonical text index, 与主事务同步提交
        try execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS MemoryFTS USING fts5(
                memoryId UNINDEXED,
                canonicalText,
                sourceType
            )
            """)
        // v5 (3F.4, D-005): translationCache 持久化（全删除边界覆盖）
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS translationCache (
                memoryId TEXT PRIMARY KEY NOT NULL,
                languagePair TEXT NOT NULL,
                translatedText TEXT NOT NULL,
                createdAt REAL NOT NULL
            )
            """)
        // 模型身份与许可登记 (R-A.2)
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS ModelManifest (
                modelId TEXT PRIMARY KEY NOT NULL,
                revision TEXT NOT NULL,
                artifactHash TEXT NOT NULL,
                licenseId TEXT NOT NULL,
                runtime TEXT NOT NULL,
                tokenizer TEXT,
                promptTemplate TEXT,
                pooling TEXT NOT NULL DEFAULT 'none',
                normalization TEXT NOT NULL DEFAULT 'none',
                dimension INTEGER NOT NULL,
                quantization TEXT
            )
            """)
        // 分代索引管理 (R-A.3): single model space per generation
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS IndexGeneration (
                generationId TEXT PRIMARY KEY NOT NULL,
                indexType TEXT NOT NULL,
                manifestId TEXT,
                dimension INTEGER NOT NULL DEFAULT 512,
                state TEXT NOT NULL DEFAULT 'building',
                counts INTEGER NOT NULL DEFAULT 0,
                validationDigest TEXT
            )
            """)
        // v3.1 schema migration: add dimension column to IndexGeneration
        // (existing DBs from initial R-A delivery lack this column)
        // WP1 步骤 6b：PRAGMA 守卫替代 try?-吞错——迁移错误必须传播（对齐 AuditLog 模式）
        let indexGenerationColumns = try columnNames(in: "IndexGeneration")
        if !indexGenerationColumns.contains("dimension") {
            try execute(sql: "ALTER TABLE IndexGeneration ADD COLUMN dimension INTEGER NOT NULL DEFAULT 512")
        }
        // 逐项构建与恢复 (R-A.3)
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS IndexBuildItem (
                generationId TEXT NOT NULL REFERENCES IndexGeneration(generationId) ON DELETE CASCADE,
                representationId TEXT NOT NULL,
                state TEXT NOT NULL DEFAULT 'pending',
                error TEXT,
                retryCount INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (generationId, representationId)
            )
            """)
        // 原子服务路由 (R-A.4): single active route row
        // v5 (3F.4, ADR-010 决策-3): previousTextGeneration 支持旧代回滚
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS ActiveRouteSet (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                textGeneration TEXT NOT NULL,
                ocrGeneration TEXT,
                visionGeneration TEXT,
                lexicalGeneration TEXT,
                version INTEGER NOT NULL DEFAULT 1,
                updatedAt REAL NOT NULL,
                previousTextGeneration TEXT
            )
            """)
        // v5 migration: existing ActiveRouteSet gains previousTextGeneration
        let routeColumns = try columnNames(in: "ActiveRouteSet")
        if !routeColumns.contains("previousTextGeneration") {
            try execute(sql: "ALTER TABLE ActiveRouteSet ADD COLUMN previousTextGeneration TEXT")
        }
        // 同意状态表 (3F.1, ADR-007 §决策-2): deny-by-default 同意版本与时间戳持久化
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS ConsentStore (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                hasConsented INTEGER NOT NULL DEFAULT 0,
                consentVersion INTEGER NOT NULL DEFAULT 1,
                consentedAt REAL,
                policyVersion INTEGER NOT NULL DEFAULT 1,
                updatedAt REAL NOT NULL
            )
            """)
        // 4.0f: App-owned preferences only. System authorization snapshots are always read live.
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS AwakeningPreference (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                geofenceEnabled INTEGER NOT NULL DEFAULT 0,
                emotionEnabled INTEGER NOT NULL DEFAULT 0,
                anniversaryEnabled INTEGER NOT NULL DEFAULT 0,
                notificationDeliveryEnabled INTEGER NOT NULL DEFAULT 0,
                healthRequestState TEXT NOT NULL DEFAULT 'notRequested',
                updatedAt REAL NOT NULL
            )
            """)
        // 4.0j / ADR-021: monthly and yearly automation are independent persisted controls.
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS NarrativeReportSchedule (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                monthlyEnabled INTEGER NOT NULL DEFAULT 1,
                yearlyEnabled INTEGER NOT NULL DEFAULT 1,
                monthlyEligibleFrom REAL,
                yearlyEligibleFrom REAL,
                revision INTEGER NOT NULL DEFAULT 0,
                updatedAt REAL NOT NULL
            )
            """)
        try execute(sql: """
            INSERT OR IGNORE INTO NarrativeReportSchedule
              (id, monthlyEnabled, yearlyEnabled, monthlyEligibleFrom, yearlyEligibleFrom, revision, updatedAt)
            VALUES (1, 1, 1, NULL, NULL, 0, CAST(strftime('%s','now') AS REAL))
            """)
        // Existing-data migration establishes both baselines once, at successful migration.
        try execute(sql: """
            UPDATE NarrativeReportSchedule
            SET monthlyEligibleFrom = COALESCE(monthlyEligibleFrom, CAST(strftime('%s','now') AS REAL)),
                yearlyEligibleFrom = COALESCE(yearlyEligibleFrom, CAST(strftime('%s','now') AS REAL)),
                revision = revision + 1,
                updatedAt = CAST(strftime('%s','now') AS REAL)
            WHERE (monthlyEligibleFrom IS NULL OR yearlyEligibleFrom IS NULL)
              AND EXISTS (SELECT 1 FROM Memory LIMIT 1)
              AND EXISTS (SELECT 1 FROM ConsentStore WHERE id = 1 AND hasConsented = 1)
            """)
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS NarrativeReportPeriod (
                periodType TEXT NOT NULL,
                periodKey TEXT NOT NULL,
                calendarIdentifier TEXT NOT NULL,
                timeZoneIdentifier TEXT NOT NULL,
                startInstant REAL NOT NULL,
                endInstant REAL NOT NULL,
                coverageStart REAL NOT NULL,
                partialBaseline INTEGER NOT NULL,
                state TEXT NOT NULL,
                revision INTEGER NOT NULL DEFAULT 0,
                claimedAt REAL,
                taskId TEXT,
                updatedAt REAL NOT NULL,
                PRIMARY KEY (periodType, periodKey)
            )
            """)
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS NarrativeReport (
                reportId TEXT PRIMARY KEY NOT NULL,
                periodType TEXT NOT NULL,
                periodKey TEXT NOT NULL,
                schemaVersion INTEGER NOT NULL,
                title TEXT NOT NULL,
                envelope BLOB NOT NULL,
                coverageJSON TEXT NOT NULL,
                createdAt REAL NOT NULL,
                UNIQUE (periodType, periodKey),
                FOREIGN KEY (periodType, periodKey)
                    REFERENCES NarrativeReportPeriod(periodType, periodKey) ON DELETE CASCADE
            )
            """)
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS NarrativeReportSource (
                reportId TEXT NOT NULL REFERENCES NarrativeReport(reportId) ON DELETE CASCADE,
                memoryId TEXT NOT NULL REFERENCES Memory(memoryId) ON DELETE CASCADE,
                sourceType TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                PRIMARY KEY (reportId, memoryId)
            )
            """)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_narrative_period_state ON NarrativeReportPeriod(state, endInstant, periodType)")
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_narrative_source_memory ON NarrativeReportSource(memoryId)")
        // A source deletion invalidates the v1 period before cascades remove the report relations.
        try execute(sql: """
            CREATE TRIGGER IF NOT EXISTS trg_narrative_source_memory_delete
            BEFORE DELETE ON Memory
            BEGIN
                UPDATE NarrativeReportPeriod
                SET state = 'invalidated', revision = revision + 1,
                    taskId = NULL, claimedAt = NULL,
                    updatedAt = CAST(strftime('%s','now') AS REAL)
                WHERE EXISTS (
                    SELECT 1 FROM NarrativeReport r
                    JOIN NarrativeReportSource s ON s.reportId = r.reportId
                    WHERE s.memoryId = OLD.memoryId
                      AND r.periodType = NarrativeReportPeriod.periodType
                      AND r.periodKey = NarrativeReportPeriod.periodKey
                );
                DELETE FROM NarrativeReport
                WHERE reportId IN (
                    SELECT reportId FROM NarrativeReportSource WHERE memoryId = OLD.memoryId
                );
            END
            """)
        // WP6 (4b): 完整路由快照 canonical bytes 持久化——原子发布校验基础
        try execute(sql: """
            CREATE TABLE IF NOT EXISTS RouteSnapshot (
                snapshotID TEXT PRIMARY KEY NOT NULL,
                canonicalBytes BLOB NOT NULL,
                canonicalDigest TEXT NOT NULL,
                publishedAt REAL NOT NULL
            )
            """)
    }

    // MARK: - Transaction Support (3F.1, ADR-007 §决策-3)

    /// 开启事务（用于事务性撤回/清除）
    public func beginTransaction() throws {
        try execute(sql: "BEGIN TRANSACTION")
    }

    /// 提交事务
    public func commitTransaction() throws {
        try execute(sql: "COMMIT")
    }

    /// 回滚事务
    public func rollbackTransaction() throws {
        try execute(sql: "ROLLBACK")
    }

    // MARK: - Atomic Transaction (3F.4, US-ING-006 AC-1/2)

    /// 单条 SQL 写操作（事务批次元素，Sendable 值类型）。
    public struct DBWrite: Sendable {
        public let sql: String
        public let bindings: [DBBinding]

        public init(sql: String, bindings: [DBBinding] = []) {
            self.sql = sql
            self.bindings = bindings
        }
    }

    /// 在一个 BEGIN/COMMIT 事务内执行一批写操作，无挂起点（同步执行）。
    ///
    /// 相比 `beginTransaction`/`commitTransaction` 分开调用（跨挂起点，
    /// DEF-50-001 曾指出会允许其他调用方插入未提交事务），此方法整个事务体在
    /// 同一次 actor 执行中同步完成，杜绝插入写。任一步失败自动 ROLLBACK。
    ///
    /// - Returns: 成功执行的写操作数
    @discardableResult
    public func executeTransaction(_ writes: [DBWrite]) throws -> Int32 {
        guard !writes.isEmpty else { return 0 }
        try execute(sql: "BEGIN TRANSACTION")
        do {
            for write in writes {
                _ = try executeWrite(sql: write.sql, bindings: write.bindings)
            }
            try execute(sql: "COMMIT")
            return Int32(writes.count)
        } catch {
            try? execute(sql: "ROLLBACK")
            throw error
        }
    }

    /// Executes writes only when the row-existence precondition still matches inside the same
    /// SQLite write transaction. This closes actor-reentrancy gaps between a prior read and commit.
    public func executeConditionalTransaction(
        _ writes: [DBWrite],
        conditionSQL: String,
        conditionBindings: [DBBinding],
        expectedRowExists: Bool
    ) throws -> Bool {
        guard !writes.isEmpty else { return true }
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION")
        do {
            let rowExists = try !executeQuery(
                sql: conditionSQL,
                bindings: conditionBindings
            ).isEmpty
            guard rowExists == expectedRowExists else {
                try execute(sql: "ROLLBACK")
                return false
            }
            for write in writes {
                _ = try executeWrite(sql: write.sql, bindings: write.bindings)
            }
            try execute(sql: "COMMIT")
            return true
        } catch {
            try? execute(sql: "ROLLBACK")
            throw error
        }
    }

    /// Claims exactly one earliest eligible narrative period inside one SQLite transaction.
    func claimEarliestNarrativeReportPeriod(taskID: String, claimedAt: Date) throws -> [String: DBValue]? {
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION")
        do {
            let rows = try executeQuery(
                sql: """
                    SELECT * FROM NarrativeReportPeriod
                    WHERE state = 'eligible'
                    ORDER BY endInstant ASC,
                             CASE periodType WHEN 'month' THEN 0 ELSE 1 END ASC,
                             periodKey ASC
                    LIMIT 1
                    """,
                bindings: []
            )
            guard let candidate = rows.first,
                  let periodType = candidate["periodType"]?.stringValue,
                  let periodKey = candidate["periodKey"]?.stringValue,
                  let revision = candidate["revision"]?.intValue else {
                try execute(sql: "COMMIT")
                return nil
            }
            let changes = try executeWrite(
                sql: """
                    UPDATE NarrativeReportPeriod
                    SET state = 'claimed', revision = revision + 1,
                        claimedAt = ?, taskId = ?, updatedAt = ?
                    WHERE periodType = ? AND periodKey = ?
                      AND state = 'eligible' AND revision = ?
                    """,
                bindings: [
                    .double(claimedAt.timeIntervalSince1970),
                    .text(taskID),
                    .double(claimedAt.timeIntervalSince1970),
                    .text(periodType),
                    .text(periodKey),
                    .int(revision),
                ]
            )
            guard changes == 1 else {
                try execute(sql: "ROLLBACK")
                return nil
            }
            let claimed = try executeQuery(
                sql: "SELECT * FROM NarrativeReportPeriod WHERE periodType = ? AND periodKey = ?",
                bindings: [.text(periodType), .text(periodKey)]
            ).first
            try execute(sql: "COMMIT")
            return claimed
        } catch {
            try? execute(sql: "ROLLBACK")
            throw error
        }
    }

    /// Publishes the report, source relations, terminal period state and typed audit record
    /// in one non-suspending SQLite transaction.
    public func publishNarrativeReport(_ publication: NarrativeReportPublication) throws {
        let envelopeData = try publication.envelope.encoded()
        let coverageData = try JSONEncoder().encode(publication.envelope.coverage)
        let sourceIDs = publication.sources.map(\.memoryID)
        let sourceTypes = Array(Set(publication.sources.map(\.sourceType))).sorted()
        let referencedIDs = Set(publication.envelope.paragraphs.flatMap(\.sourceMemoryIDs))
        let auditTypes = (try? JSONDecoder().decode(
            [String].self,
            from: Data(publication.audit.dataSourcesUsedJSON.utf8)
        )) ?? []
        guard let coverageJSON = String(data: coverageData, encoding: .utf8),
              publication.envelope.periodType == publication.period.periodType,
              publication.envelope.periodKey == publication.period.periodKey,
              publication.audit.periodType == publication.period.periodType,
              publication.audit.periodKeyDigest.count == 64,
              publication.audit.periodKeyDigest.allSatisfy(\.isHexDigit),
              publication.period.state == .claimed,
              publication.period.taskID != nil,
              Set(sourceIDs).count == sourceIDs.count,
              publication.sources.map(\.ordinal) == Array(publication.sources.indices),
              referencedIDs.isSubset(of: Set(sourceIDs)),
              auditTypes == sourceTypes else {
            throw NarrativeReportError.invalidReportEnvelope
        }

        try execute(sql: "BEGIN IMMEDIATE TRANSACTION")
        do {
            let ownsClaim = try !executeQuery(
                sql: """
                    SELECT 1 AS present FROM NarrativeReportPeriod
                    WHERE periodType = ? AND periodKey = ? AND state = 'claimed'
                      AND revision = ? AND taskId = ? LIMIT 1
                    """,
                bindings: [
                    .text(publication.period.periodType.rawValue),
                    .text(publication.period.periodKey),
                    .int(Int64(publication.period.revision)),
                    .text(publication.period.taskID ?? ""),
                ]
            ).isEmpty
            guard ownsClaim else { throw NarrativeReportError.publicationConflict }

            try executeWrite(
                sql: """
                    INSERT INTO NarrativeReport
                      (reportId, periodType, periodKey, schemaVersion, title, envelope, coverageJSON, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                bindings: [
                    .text(publication.reportID.uuidString),
                    .text(publication.period.periodType.rawValue),
                    .text(publication.period.periodKey),
                    .int(Int64(publication.envelope.schemaVersion)),
                    .text(publication.envelope.title),
                    .blob(envelopeData),
                    .text(coverageJSON),
                    .double(publication.createdAt.timeIntervalSince1970),
                ]
            )
            try failNarrativePublicationIfRequested(.afterReport)

            for source in publication.sources {
                try executeWrite(
                    sql: """
                        INSERT INTO NarrativeReportSource (reportId, memoryId, sourceType, ordinal)
                        VALUES (?, ?, ?, ?)
                        """,
                    bindings: [
                        .text(publication.reportID.uuidString),
                        .text(source.memoryID.uuidString),
                        .text(source.sourceType),
                        .int(Int64(source.ordinal)),
                    ]
                )
            }
            try failNarrativePublicationIfRequested(.afterSources)

            try executeWrite(
                sql: """
                    INSERT INTO AuditLog
                      (eventType, timestamp, traceID, policyVersion, success,
                       periodType, dataSourcesUsed, periodKeyDigest)
                    VALUES ('narrativeReportGenerated', ?, ?, ?, 1, ?, ?, ?)
                    """,
                bindings: [
                    .double(publication.audit.timestamp.timeIntervalSince1970),
                    .text(publication.audit.traceID),
                    .int(Int64(publication.audit.policyVersion)),
                    .text(publication.audit.periodType.rawValue),
                    .text(publication.audit.dataSourcesUsedJSON),
                    .text(publication.audit.periodKeyDigest),
                ]
            )
            try failNarrativePublicationIfRequested(.afterAudit)

            let completed = try executeWrite(
                sql: """
                    UPDATE NarrativeReportPeriod
                    SET state = 'completed', revision = revision + 1,
                        claimedAt = NULL, taskId = NULL, updatedAt = ?
                    WHERE periodType = ? AND periodKey = ? AND state = 'claimed'
                      AND revision = ? AND taskId = ?
                    """,
                bindings: [
                    .double(publication.createdAt.timeIntervalSince1970),
                    .text(publication.period.periodType.rawValue),
                    .text(publication.period.periodKey),
                    .int(Int64(publication.period.revision)),
                    .text(publication.period.taskID ?? ""),
                ]
            )
            guard completed == 1 else { throw NarrativeReportError.publicationConflict }
            try failNarrativePublicationIfRequested(.afterCompletion)
            try execute(sql: "COMMIT")
        } catch {
            try? execute(sql: "ROLLBACK")
            throw error
        }
    }

    internal func setNarrativePublicationFailureStageForTesting(
        _ stage: NarrativePublicationFailureStage?
    ) {
        narrativePublicationFailureStageForTesting = stage
    }

    private func failNarrativePublicationIfRequested(
        _ stage: NarrativePublicationFailureStage
    ) throws {
        guard narrativePublicationFailureStageForTesting == stage else { return }
        throw NarrativeReportError.injectedPublicationFailure
    }

    // MARK: - Database URL

    /// SQLite 数据库文件 URL（测试/审计用，NSFileProtectionComplete 校验）
    public nonisolated var databaseURL: URL { dbURL }

    // MARK: - Generic SQL Execution

    func execute(sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK else {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw DatabaseError.tableCreationFailed(table: "<sql>", underlying: NSError(domain: "sqlite3", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
        }
    }

    @discardableResult
    func executeWrite(sql: String, bindings: [DBBinding]) throws -> Int32 {
        guard let db = db else {
            throw DatabaseError.connectionFailed(underlying: NSError(domain: "sqlite3", code: -1, userInfo: [NSLocalizedDescriptionKey: "Database not open"]))
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let prepared = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.writeFailed(operation: "prepare", underlying: NSError(domain: "sqlite3", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
        }
        defer { sqlite3_finalize(prepared) }
        for (i, binding) in bindings.enumerated() {
            let idx = Int32(i + 1)
            switch binding {
            case .text(let value): sqlite3_bind_text(prepared, idx, (value as NSString).utf8String, -1, nil)
            case .int(let value): sqlite3_bind_int64(prepared, idx, value)
            case .double(let value): sqlite3_bind_double(prepared, idx, value)
            case .blob(let data):
                data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(prepared, idx, bytes.baseAddress, Int32(data.count), nil)
                }
            case .null: sqlite3_bind_null(prepared, idx)
            }
        }
        guard sqlite3_step(prepared) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.writeFailed(operation: "step", underlying: NSError(domain: "sqlite3", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
        }
        return sqlite3_changes(db)
    }

    // MARK: - MemoryDeletionJournal CRUD (WP3 steps 3i-3t2, D-005)

    func upsertDeletionJournal(_ journal: MemoryDeletionJournal) async throws {
        let vecJSONData = try JSONEncoder().encode(journal.vectorIDsByGeneration)
        let vecJSON = String(data: vecJSONData, encoding: .utf8) ?? "[]"
        try executeWrite(
            sql: "INSERT OR REPLACE INTO MemoryDeletionJournal (operationID, memoryId, auditSubjectHash, traceID, phase, vectorIDsByGenerationJSON, sourceLocator, sourceType, writeExcluded, intentKind, sourceDeletionState, sourceDeletionOutcome, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(journal.operationID),
                .text(journal.memoryID.uuidString),
                .text(journal.auditSubjectHash),
                .text(journal.traceID),
                .text(journal.phase.rawValue),
                .text(vecJSON),
                journal.sourceLocator.map(DBBinding.text) ?? .null,
                journal.sourceType.map(DBBinding.text) ?? .null,
                journal.writeExcluded.map { .int($0 ? 1 : 0) } ?? .null,
                .text(journal.intentKind.rawValue),
                .text(journal.sourceDeletionState.rawValue),
                .text(journal.sourceDeletionOutcome.rawValue),
                .double(Date().timeIntervalSince1970),
            ]
        )
    }

    func loadDeletionJournals(memoryId: UUID) async throws -> [MemoryDeletionJournal] {
        let rows = try executeQuery(
            sql: "SELECT * FROM MemoryDeletionJournal WHERE memoryId = ? ORDER BY updatedAt",
            bindings: [.text(memoryId.uuidString)]
        )
        return rows.compactMap { Self.rowToDeletionJournal($0) }
    }

    func loadAllDeletionJournals() async throws -> [MemoryDeletionJournal] {
        let rows = try executeQuery(
            sql: "SELECT * FROM MemoryDeletionJournal ORDER BY updatedAt, operationID",
            bindings: []
        )
        return rows.compactMap { Self.rowToDeletionJournal($0) }
    }

    func deleteDeletionJournal(operationID: String) async throws {
        try executeWrite(
            sql: "DELETE FROM MemoryDeletionJournal WHERE operationID = ?",
            bindings: [.text(operationID)]
        )
    }

    func deleteAllDeletionJournals() async throws -> Int {
        let before = try Int(executeQuery(sql: "SELECT COUNT(*) AS c FROM MemoryDeletionJournal", bindings: []).first?["c"]?.intValue ?? 0)
        try execute(sql: "DELETE FROM MemoryDeletionJournal")
        return before
    }

    private static func rowToDeletionJournal(_ row: [String: DBValue]) -> MemoryDeletionJournal? {
        guard let opID = row["operationID"]?.stringValue,
              let memStr = row["memoryId"]?.stringValue,
              let memoryId = UUID(uuidString: memStr),
              let subjHash = row["auditSubjectHash"]?.stringValue,
              let traceID = row["traceID"]?.stringValue,
              let phaseRaw = row["phase"]?.stringValue,
              let phase = MemoryDeletionPhase(rawValue: phaseRaw),
              let vecJSONStr = row["vectorIDsByGenerationJSON"]?.stringValue,
              let vecData = vecJSONStr.data(using: .utf8) else {
            return nil
        }
        let vectors = (try? JSONDecoder().decode([GenerationVectorIDs].self, from: vecData)) ?? []
        let writeExcluded = row["writeExcluded"]?.intValue.map { $0 != 0 }
        let inferredIntent: MemoryDeletionIntentKind = writeExcluded == true ? .echoOnly : .externalCascade
        let intent = row["intentKind"]?.stringValue.flatMap(MemoryDeletionIntentKind.init(rawValue:))
            ?? inferredIntent
        let defaultState: SourceDeletionState = intent == .echoOnly ? .notApplicable : .confirmedDeleted
        let defaultOutcome: SourceDeletionOutcome = intent == .echoOnly ? .notRequested : .confirmedDeleted
        return MemoryDeletionJournal(
            operationID: opID,
            memoryID: memoryId,
            auditSubjectHash: subjHash,
            traceID: traceID,
            phase: phase,
            vectorIDsByGeneration: vectors,
            sourceLocator: row["sourceLocator"]?.stringValue,
            sourceType: row["sourceType"]?.stringValue,
            writeExcluded: writeExcluded,
            intentKind: intent,
            sourceDeletionState: row["sourceDeletionState"]?.stringValue.flatMap(SourceDeletionState.init(rawValue:))
                ?? defaultState,
            sourceDeletionOutcome: row["sourceDeletionOutcome"]?.stringValue.flatMap(SourceDeletionOutcome.init(rawValue:))
                ?? defaultOutcome
        )
    }

    /// Return the current column names of a table (used for idempotent ALTER migrations).
    func columnNames(in table: String) throws -> [String] {
        let rows = try executeQuery(sql: "PRAGMA table_info(\(table))", bindings: [])
        return rows.compactMap { $0["name"]?.stringValue }
    }

    func executeQuery(sql: String, bindings: [DBBinding]) throws -> [[String: DBValue]] {
        guard let db = db else {
            throw DatabaseError.connectionFailed(underlying: NSError(domain: "sqlite3", code: -1, userInfo: [NSLocalizedDescriptionKey: "Database not open"]))
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let prepared = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.readFailed(operation: "prepare", underlying: NSError(domain: "sqlite3", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
        }
        defer { sqlite3_finalize(prepared) }
        for (i, binding) in bindings.enumerated() {
            let idx = Int32(i + 1)
            switch binding {
            case .text(let value): sqlite3_bind_text(prepared, idx, (value as NSString).utf8String, -1, nil)
            case .int(let value): sqlite3_bind_int64(prepared, idx, value)
            case .double(let value): sqlite3_bind_double(prepared, idx, value)
            case .blob(let data):
                data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(prepared, idx, bytes.baseAddress, Int32(data.count), nil)
                }
            case .null: sqlite3_bind_null(prepared, idx)
            }
        }
        var rows: [[String: DBValue]] = []
        let columnCount = sqlite3_column_count(prepared)
        while true {
            let stepResult = sqlite3_step(prepared)
            if stepResult == SQLITE_ROW {
                var row: [String: DBValue] = [:]
                for i in 0..<columnCount {
                    let name = String(cString: sqlite3_column_name(prepared, i))
                    switch sqlite3_column_type(prepared, i) {
                    case SQLITE_INTEGER: row[name] = .int(sqlite3_column_int64(prepared, i))
                    case SQLITE_FLOAT: row[name] = .double(sqlite3_column_double(prepared, i))
                    case SQLITE_TEXT: row[name] = .text(String(cString: sqlite3_column_text(prepared, i)))
                    case SQLITE_BLOB:
                        if let bytes = sqlite3_column_blob(prepared, i) {
                            row[name] = .blob(Data(bytes: bytes, count: Int(sqlite3_column_bytes(prepared, i))))
                        } else { row[name] = .null }
                    default: row[name] = .null
                    }
                }
                rows.append(row)
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                // R-1.4: 查询循环中遇到错误码（非 ROW 非 DONE）→ 抛出而非静默返回部分结果
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.readFailed(
                    operation: "step",
                    underlying: NSError(domain: "sqlite3", code: Int(stepResult), userInfo: [NSLocalizedDescriptionKey: msg])
                )
            }
        }
        return rows
    }

    public func databaseSize() -> Int64 {
        Int64((try? Data(contentsOf: dbURL).count) ?? 0)
    }

    // MARK: - Route Snapshot (WP6 4b: canonical route bytes 持久化)

    /// 持久化完整路由快照 canonical bytes（原子发布校验基础）。
    public func saveRouteSnapshot(snapshotID: String, canonicalBytes: Data, canonicalDigest: String) throws {
        try executeWrite(
            sql: "INSERT OR REPLACE INTO RouteSnapshot (snapshotID, canonicalBytes, canonicalDigest, publishedAt) VALUES (?, ?, ?, ?)",
            bindings: [
                .text(snapshotID),
                .blob(canonicalBytes),
                .text(canonicalDigest),
                .double(Date().timeIntervalSince1970),
            ]
        )
    }

    /// 读取已持久化的路由快照 bytes 与 digest。
    public func loadRouteSnapshot(snapshotID: String) throws -> (bytes: Data, digest: String)? {
        let rows = try executeQuery(
            sql: "SELECT canonicalBytes, canonicalDigest FROM RouteSnapshot WHERE snapshotID = ?",
            bindings: [.text(snapshotID)]
        )
        guard let row = rows.first,
              let bytes = row["canonicalBytes"]?.blobValue,
              let digest = row["canonicalDigest"]?.stringValue else { return nil }
        return (bytes, digest)
    }

    /// 读取最近发布的路由快照记录（按 publishedAt 降序；WP6 5c-5d 回滚用前序）。
    public func loadRecentRouteSnapshots(limit: Int) throws -> [(snapshotID: String, bytes: Data, digest: String)] {
        let rows = try executeQuery(
            sql: "SELECT snapshotID, canonicalBytes, canonicalDigest FROM RouteSnapshot ORDER BY publishedAt DESC LIMIT ?",
            bindings: [.int(Int64(limit))]
        )
        return rows.compactMap { row in
            guard let id = row["snapshotID"]?.stringValue,
                  let bytes = row["canonicalBytes"]?.blobValue,
                  let digest = row["canonicalDigest"]?.stringValue else { return nil }
            return (id, bytes, digest)
        }
    }
}

// MARK: - Database Binding & Value Types

public enum DBBinding: Sendable {
    case text(String)
    case int(Int64)
    case double(Double)
    case blob(Data)
    case null
}

public enum DBValue: Sendable {
    case text(String)
    case int(Int64)
    case double(Double)
    case blob(Data)
    case null

    public nonisolated var stringValue: String? { if case .text(let s) = self { return s }; return nil }
    public nonisolated var intValue: Int64? { if case .int(let i) = self { return i }; return nil }
    public nonisolated var doubleValue: Double? { if case .double(let d) = self { return d }; return nil }
    public nonisolated var blobValue: Data? { if case .blob(let d) = self { return d }; return nil }
    public nonisolated var isNull: Bool { if case .null = self { return true }; return false }
}
