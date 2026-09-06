// ==========================================
// 文件: PhotoKitSourceAdapter.swift
// 对应规格: docs/01-spec/用户故事与验收标准规格书.md → US-SRC-001 (PhotoKit 全量读取),
//            US-SRC-004/005 (排除项过滤), US-SRC-008 (排除项不重新导入),
//            US-PRV-001 (动态授权即时生效)
//            docs/decisions/ADR-008-source-import-boundaries.md §决策-1 (PhotoKit 授权与变更观察),
//            §决策-5 (权限撤回停止读取)
//            docs/decisions/ADR-019-photokit-source-deletion-recovery.md
// Task: 3F.2 - PhotoKit, Share Extension, and live sources; 4.0h - source deletion boundary
// AC 覆盖: US-SRC-001 AC-1 (PHAsset 读取图片/视频), AC-5 (.dataSourceConnected 审计 sourceType+itemCount),
//          AC-6 (仅处理已下载本地资源 — isNetworkAccessAllowed=false), AC-3 (支持"仅授权部分相册"),
//          US-SRC-008 AC-4 (排除项不重新导入), ADR-008 §决策-1/5 (全授权状态 + 撤回立即停止),
//          iOS 26 fix (limited 选择器主动弹出 — shouldPresentLimitedLibraryPicker, 3F.2 review)
// 架构约束: AGENTS.md §4.2 (Actor 隔离), §7.3 (审计事件), R-001/R-005 (零网络),
//            R-007 (禁止 unchecked Sendable)
// 重要: 项目 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
//       PhotoKit SDK 将 PHPhotoLibrary/PHImageManager 标注 @MainActor，真实实现通过
//       MainActor.run 跳转访问；协议方法均为 async，可被 Fake 注入测试
// Generated: 2026-08-05 | Updated: 2026-09-05 (4.0h)
// ==========================================

import Foundation
@preconcurrency import Photos

// MARK: - Photo Access

/// 相册授权状态（覆盖 PhotoKit 全状态，ADR-008 §决策-1）
public enum PhotoAccess: String, Sendable, Equatable {
    case notDetermined
    case restricted
    case denied
    case limited
    case authorized
}

/// 授权状态映射（测试可注入，纯函数）
public enum PhotoAccessMapper {
    public nonisolated static func map(_ status: PHAuthorizationStatus) -> PhotoAccess {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .limited:       return .limited
        case .authorized:    return .authorized
        @unknown default:    return .denied
        }
    }
}

// MARK: - Photo Fetch Configuration

/// 相册资源获取配置（US-SRC-001 AC-6：仅处理已下载到本地的资源）
public struct PhotoFetchConfiguration: Sendable, Equatable {
    /// 是否允许网络下载（AC-6 要求 false；iCloud 已优化照片不强制下载）
    public nonisolated let isNetworkAccessAllowed: Bool

    public nonisolated init(isNetworkAccessAllowed: Bool = false) {
        self.isNetworkAccessAllowed = isNetworkAccessAllowed
    }

    /// 生产配置：禁止网络访问（AC-6 红线，R-005 零网络）
    public nonisolated static let production = PhotoFetchConfiguration(isNetworkAccessAllowed: false)
}

// MARK: - Photo Asset Reference

/// 相册资产最小引用（仅本地标识符 + 媒体类型 + 时间戳，不含原始文件/图像数据）
public struct PhotoAssetReference: Sendable, Equatable {
    public nonisolated let assetId: String
    /// "image" 或 "video"
    public nonisolated let mediaType: String
    public nonisolated let creationDate: Date?
    public nonisolated let modificationDate: Date?

    public nonisolated init(
        assetId: String,
        mediaType: String,
        creationDate: Date?,
        modificationDate: Date?
    ) {
        self.assetId = assetId
        self.mediaType = mediaType
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }
}

// MARK: - Photo Library Serving

/// 照片库服务协议 — 抽象 PhotoKit 边界，支持测试注入 Fake。
///
/// 仅返回值类型（PhotoAssetReference / PhotoAccess），PHAsset 不跨边界传递。
/// 方法均为 async（真实实现经 MainActor.run 访问 @MainActor 的 PHPhotoLibrary）。
public protocol PhotoLibraryServing: Sendable {
    func currentAccess() async -> PhotoAccess
    func requestAccess() async -> PhotoAccess
    func allAssetReferences() async -> [PhotoAssetReference]
    func isAssetDownloaded(_ assetId: String) async -> Bool
}

// MARK: - Photo Source Lifecycle

public nonisolated enum PhotoSourceMediaType: String, Sendable, Codable, Equatable {
    case photo
    case video
}

/// Minimal PHAsset lifecycle snapshot. PHAsset itself never crosses an actor boundary.
public nonisolated struct PhotoSourceSnapshot: Sendable, Equatable {
    public nonisolated let assetID: String
    public nonisolated let mediaType: PhotoSourceMediaType
    public nonisolated let isLocallyAvailable: Bool
    public nonisolated let canDelete: Bool

    public nonisolated init(
        assetID: String,
        mediaType: PhotoSourceMediaType,
        isLocallyAvailable: Bool,
        canDelete: Bool
    ) {
        self.assetID = assetID
        self.mediaType = mediaType
        self.isLocallyAvailable = isLocallyAvailable
        self.canDelete = canDelete
    }
}

/// Structured PhotoKit completion result. `indeterminate` requires launch or foreground recovery.
public nonisolated enum PhotoLibraryDeletionResult: Sendable, Equatable {
    case confirmedDeleted
    case notDeleted(SourceDeletionOutcome)
    case indeterminate(SourceDeletionOutcome)
}

public protocol PhotoSourceLifecycleServing: Sendable {
    func currentAccess() async -> PhotoAccess
    func assetSnapshot(assetID: String) async -> PhotoSourceSnapshot?
    func deleteAsset(assetID: String) async -> PhotoLibraryDeletionResult
}

// MARK: - Real Photo Library

/// 真实 PhotoKit 实现（@preconcurrency import Photos，经 MainActor.run 访问 SDK）。
///
/// - 下载检测：`requestImageDataAndOrientation` + `isNetworkAccessAllowed=false`
///   （US-SRC-001 AC-6：返回 nil 表示未下载；家庭共享相册同理，不区分来源）
public struct RealPhotoLibrary: PhotoLibraryServing, PhotoSourceLifecycleServing {

    public nonisolated init() {}

    public nonisolated func currentAccess() async -> PhotoAccess {
        let status = await MainActor.run {
            PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
        return PhotoAccessMapper.map(status)
    }

    public nonisolated func requestAccess() async -> PhotoAccess {
        let status = await Self.requestAuthorization()
        return PhotoAccessMapper.map(status)
    }

    public nonisolated func allAssetReferences() async -> [PhotoAssetReference] {
        await MainActor.run {
            let access = PhotoAccessMapper.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
            guard access == .authorized || access == .limited else { return [] }
            let options = PHFetchOptions()
            options.includeAssetSourceTypes = [.typeUserLibrary]
            let fetch = PHAsset.fetchAssets(with: options)
            var refs: [PhotoAssetReference] = []
            fetch.enumerateObjects { asset, _, _ in
                let mediaType: String = asset.mediaType == .video ? "video" : "image"
                refs.append(PhotoAssetReference(
                    assetId: asset.localIdentifier,
                    mediaType: mediaType,
                    creationDate: asset.creationDate,
                    modificationDate: asset.modificationDate
                ))
            }
            return refs
        }
    }

    public nonisolated func isAssetDownloaded(_ assetId: String) async -> Bool {
        await Self.assetDownloaded(assetId)
    }

    public nonisolated func assetSnapshot(assetID: String) async -> PhotoSourceSnapshot? {
        await Self.lifecycleSnapshot(assetID)
    }

    public nonisolated func deleteAsset(assetID: String) async -> PhotoLibraryDeletionResult {
        await Self.performDeletion(assetID)
    }

    // MARK: - @MainActor SDK Helpers

    @MainActor
    private static func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    @MainActor
    private static func assetDownloaded(_ assetId: String) async -> Bool {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return false
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .fastFormat
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data != nil)
            }
        }
    }

    @MainActor
    private static func lifecycleSnapshot(_ assetID: String) async -> PhotoSourceSnapshot? {
        let access = PhotoAccessMapper.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        guard access == .authorized || access == .limited else { return nil }
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetID], options: nil
        ).firstObject else { return nil }
        let mediaType: PhotoSourceMediaType = asset.mediaType == .video ? .video : .photo
        return PhotoSourceSnapshot(
            assetID: assetID,
            mediaType: mediaType,
            isLocallyAvailable: await assetDownloaded(assetID),
            canDelete: asset.canPerform(.delete)
        )
    }

    @MainActor
    private static func performDeletion(_ assetID: String) async -> PhotoLibraryDeletionResult {
        let access = PhotoAccessMapper.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        switch access {
        case .authorized, .limited:
            break
        case .restricted:
            return .notDeleted(.accessRestricted)
        case .denied, .notDetermined:
            return .notDeleted(.authorizationDenied)
        }
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetID], options: nil
        ).firstObject else {
            // Missing is not proof of deletion under limited scope; the coordinator reconciles it.
            return .indeterminate(access == .limited ? .limitedScopeHidden : .sourceUnavailable)
        }
        guard asset.canPerform(.delete) else {
            return .notDeleted(.assetNotDeletable)
        }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            } completionHandler: { success, error in
                if success {
                    continuation.resume(returning: .confirmedDeleted)
                    return
                }
                let code = (error as NSError?)?.code
                // PHError.h in the active SDK: userCancelled=3072,
                // accessRestricted=3310, accessUserDenied=3311.
                switch code {
                case 3072:
                    continuation.resume(returning: .notDeleted(.userCancelled))
                case 3310:
                    continuation.resume(returning: .notDeleted(.accessRestricted))
                case 3311:
                    continuation.resume(returning: .notDeleted(.authorizationDenied))
                default:
                    continuation.resume(returning: .indeterminate(.systemResultUnknown))
                }
            }
        }
    }
}

// MARK: - PhotoKit Source Adapter

/// PhotoKit 来源适配器（ADR-008 §决策-1/§决策-5）。
///
/// ## 职责
/// - 全授权状态处理：notDetermined / restricted / denied / limited / authorized
/// - 授权撤回立即停止读取（每次读取前校验当前授权，ADR-008 §决策-5）
/// - 排除项过滤（US-SRC-008 AC-4）
/// - 本地已下载资源检测（US-SRC-001 AC-6）
/// - `.dataSourceConnected` 审计（US-SRC-001 AC-5）
/// - iOS 26 limited 适配：系统不再自动弹出照片选择器，App 需主动
///   `presentLimitedLibraryPicker`（ADR-008 §决策-1 补充，3F.2 review 发现）
public actor PhotoKitSourceAdapter {

    /// limited 选择器已弹出标记 key（iOS 26 适配；避免每次回前台重复弹出）
    internal nonisolated static let limitedPickerPresentedKey = "photoKit.limitedPickerPresented"

    private let library: any PhotoLibraryServing
    private let privacyActor: PrivacyActor

    /// 只读获取配置（AC-6 断言用）
    public nonisolated let fetchConfiguration: PhotoFetchConfiguration

    public init(
        library: any PhotoLibraryServing = RealPhotoLibrary(),
        privacyActor: PrivacyActor = .shared,
        configuration: PhotoFetchConfiguration = .production
    ) {
        self.library = library
        self.privacyActor = privacyActor
        self.fetchConfiguration = configuration
    }

    // MARK: - Authorization (ADR-008 §决策-1)

    /// 当前授权状态
    public func currentAccess() async -> PhotoAccess {
        await library.currentAccess()
    }

    /// 请求授权（支持"仅授权部分相册" limited，US-SRC-001 AC-3）
    public func requestAccess() async -> PhotoAccess {
        await library.requestAccess()
    }

    /// 是否可读取相册（authorized / limited）
    public func canReadAssets() async -> Bool {
        let access = await library.currentAccess()
        return access == .authorized || access == .limited
    }

    // MARK: - Read (ADR-008 §决策-5: 撤回立即停止)

    /// 读取全部资产引用；未授权/已撤回时返回空（每次调用实时校验授权状态）
    public func fetchAllAssets() async -> [PhotoAssetReference] {
        guard await canReadAssets() else { return [] }
        return await library.allAssetReferences()
    }

    /// 可导入资产（排除用户已排除项，US-SRC-008 AC-4）
    public func importableReferences(excluding excludedIds: Set<String>) async -> [PhotoAssetReference] {
        let all = await fetchAllAssets()
        return all.filter { !excludedIds.contains($0.assetId) }
    }

    /// 资源是否已下载到本地（US-SRC-001 AC-6：isNetworkAccessAllowed=false，nil 表示未下载）
    public func isLocallyAvailable(assetId: String) async -> Bool {
        guard await canReadAssets() else { return false }
        return await library.isAssetDownloaded(assetId)
    }

    // MARK: - iOS 26 Limited Library Picker (3F.2 review fix)

    /// iOS 26 起系统在 limited 授权后不再自动弹出照片选择器，App 需主动调用
    /// `PHPhotoLibrary.presentLimitedLibraryPicker(from:)` 让用户选择可访问照片。
    ///
    /// - Returns: `true` 当授权为 limited、当前无任何已选照片、且此前未主动弹出过选择器。
    ///   三者同时满足才需要 App 呈现选择器（iOS 18 及以下系统自动弹，此判定保持 false）。
    public func shouldPresentLimitedLibraryPicker() async -> Bool {
        let access = await library.currentAccess()
        guard access == .limited else { return false }
        guard await library.allAssetReferences().isEmpty else { return false }
        return !UserDefaults.standard.bool(forKey: Self.limitedPickerPresentedKey)
    }

    /// 标记 limited 选择器已主动弹出（避免每次回前台重复弹出）。
    public func markLimitedLibraryPickerPresented() {
        UserDefaults.standard.set(true, forKey: Self.limitedPickerPresentedKey)
    }

    /// 重置 limited 选择器弹出标记（测试用）。
    internal func resetLimitedLibraryPickerFlag() {
        UserDefaults.standard.removeObject(forKey: Self.limitedPickerPresentedKey)
    }

    // MARK: - Audit (US-SRC-001 AC-5)

    /// 记录数据源接入审计 `.dataSourceConnected`（sourceType + itemCount）。
    ///
    /// 首次授权相册后触发全量后台索引时由调用方调用（US-SRC-001 AC-4）。
    public func recordDataSourceConnected(traceID: String = UUID().uuidString) async {
        let itemCount = await fetchAllAssets().count
        let policy = await privacyActor.getPolicy()
        try? await privacyActor.writeAuditLog(
            eventType: .dataSourceConnected,
            traceID: traceID,
            policyVersion: policy.policyVersion,
            success: true,
            sourceType: "photo",
            affectedCount: itemCount
        )
    }
}
