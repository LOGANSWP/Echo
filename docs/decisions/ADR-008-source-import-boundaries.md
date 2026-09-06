# ADR-008: 来源导入边界（PhotoKit/Share Extension/App Group 与迁移包）

**状态**: 已接受
**日期**: 2026-08-04
**决策人**: Privacy Engineering Lead（审批）+ iOS Sources Lead（实现）；US-SRC-007 迁移安全部分由 Security Engineering Lead、Privacy Engineering Lead、Architecture Lead 三方强制批准

> **2026-09-05 规格修订（ADR-019）**：Share Extension 不公开可靠的宿主 App 身份。下文“来源身份”仅指 Echo 可验证的 `importOrigin=shareExtension`、实际 `contentType` 与稳定 dedupe identity；不得把扩展自身 bundle ID 当作 Notes/Voice Memos/第三方宿主身份。实现证据中的 `appBundleId` 是历史字段，不构成可信宿主归因。

## 背景

基线中无 Share Extension target、无 PhotoKit 采集、无来源协调器；SRC-012 的 SyncPipeline 无注册观察者/BG task/默认 composition，Notes 路径与 share-only 规则冲突；SRC-007 迁移只有 UI/fixtures，无本地传输、恢复、冲突或完整性实现。

## 决策

3F.2/3F.7 落地以下来源导入边界：

1. **PhotoKit 授权与变更观察**：limited/full/denied/revoked 全状态处理；`PhotoKitChangeObserver` 变更去重；授权撤回立即停止读取。
2. **Share Extension 仅用户中介**：Notes/Voice 只通过 `EchoShareExtension` 显式分享摄入（share-only AC）；拒绝不支持类型与明文审计内容。iMessage 自动历史移出 v1（ADR-006）。
3. **App Group 信封**：分享文本/音频通过 App Group 队列（`SharedImportEnvelope` + `SharedImportQueueActor`）原子入队，重复投递去重，共享导入在 App 重启后恰好处理一次。
4. **去重键与来源身份**：稳定 dedupe identity 由 `importOrigin + contentType + payload digest` 构成；仅在公开系统 API 提供可验证值时附加 hash-only `sourceAppDigest`。来源 App 未知时保持 unknown；`ExcludedAssets` 过滤与审计（`.excluded` 事件）。
5. **权限撤回**：撤回数据源权限后停止读取并保留审计。
6. **US-SRC-007 加密用户中介迁移包边界**（与 ADR-010 共同管辖）：AirDrop/系统分享的导入使用版本化固定格式包 `ECHOMIG1`，算法标识精确为 `AES-GCM-256+HKDF-SHA256`，其他标识一律 fail-closed；每次归档生成一个全新随机 256-bit `K_transfer` 并作为一次性 base64url/QR 传输密钥单独展示，绝不嵌入包内、不记录、不入剪贴板、不备份、会话结束即销毁；无包裹密钥、无云服务、无密钥服务器、无远程恢复。Finder/iTunes 加密本地备份恢复由 OS 管理备份加密与密钥，Echo 不接触备份密钥，仅做恢复后 schema/完整性/active-route 校验。
7. **最小数据边界**：App Group 仅承载分享信封最小字段；不存储原文件全文于队列。

## 备选方案

| 方案 | 描述 | 结论 |
|------|------|------|
| **A（采纳）** | Share-only 用户中介 + App Group 原子队列 + 固定格式加密迁移包 | ✅ 满足 R-002/R-003/D-002/D-003，公开 API 内可落地 |
| B | 自动读取系统 Notes/Voice Memos | ❌ 私有/不存在 API，违反 share-only 红线 |
| C | 明文或自研加密迁移格式 | ❌ 违背固定格式 fail-closed 与保密性/真实性要求 |

## 后果

### 正面

- 来源摄入、去重、权限撤回、迁移包保密性/真实性全部在公开 API 能力内可测。
- 迁移包协议精确（JCS manifest、NFC 排序、逐块哈希、AAD、资源边界、staging 原子发布），任何篡改/截断/重放均 fail-closed。
- 关闭 DEF-34-001/002（search 侧）与 SRC-007 相关证据路径确定。

### 负面

- 用户必须主动分享才能摄入 Notes/Voice（产品交互成本）。
- 迁移包格式固定后无法向后不兼容演进（需 schemaVersion 升级路径）。
- App Group 队列需处理 App 未运行时的投递窗口。

## 参考

- `docs/01-spec/用户故事与验收标准规格书.md` US-SRC-001/003/004/005/007/008/012/013、US-PRV-001
- `docs/05-planning/phase3f-execution-plan.md` §4.6.2（3F.2 文档合同）、§4.6.7（3F.7 迁移安全子契约）
- AGENTS.md R-002/R-003、D-002/D-003
- ADR-010（canonical generation 生命周期与迁移发布）
- ADR-019（Share provenance、来源能力与 PhotoKit 删除恢复）

## 实现证据（3F.2，2026-08-05）

- **决策-1 PhotoKit 授权与变更观察**：`Echo/Core/Sources/PhotoKitSourceAdapter.swift`（全授权状态处理 + 每次读取实时校验授权，撤回立即停止）+ `Echo/Core/Sources/PhotoKitChangeObserver.swift`（`PHPhotoLibraryChangeObserver` 批内去重，跨投递窗口去重于 `SyncPipeline.processPhotoChanges`，ADR-008 决策-1 变更去重）。
- **决策-2 Share-only 用户中介**：`EchoShareExtension/ShareViewController.swift`（`ShareContentExtractor` 拒绝不支持类型；`NSExtensionPointIdentifier=com.apple.share-services` 预览确认后入队）。
- **决策-3 App Group 信封与原子队列**：`Echo/Core/Models/SharedImportEnvelope.swift` + `Echo/Core/Actors/SharedImportQueueActor.swift`（文件原子入队、`dedupeKey` 重复拒绝、`begin/finish/rollback` + `recoverInterrupted` 恰好一次）；App/Extension 共享 `group.com.echo.Echo`（`Echo/Config/Echo.entitlements`、`EchoShareExtension/EchoShareExtension.entitlements`）。
- **决策-4 去重键与来源身份（历史实现）**：`SharedImportEnvelope.dedupeKey = SHA-256(sourceType|contentKind|payload)` 在 3F.2 提供跨投递稳定性；其中 `sourceType` 来自扩展进程，不能证明宿主 App。ADR-019 要求生产合同改用可验证的 `importOrigin + contentType + payload digest`，未知宿主保持 unknown。
- **决策-5 权限撤回**：`PhotoKitSourceAdapter.canReadAssets()` 每次读取前实时校验（测试 `test_photoKit_revocationStopsReads`）。
- **决策-7 最小数据边界**：信封仅最小字段（不存原文件全文）；`Echo-Info.plist` 含 `NSPhotoLibraryUsageDescription`。
- **审计（历史实现）**：`.shareExtensionImported`（US-SRC-003 AC-4）在 3F.2 将 `appBundleId|contentType` 以 hash-only 写入；ADR-019 明确该 bundle 值不得作为宿主 App 证据，当前合同记录 `importOrigin + contentType`，只有可信公开值存在时才附 `sourceAppDigest`。
- 测试：`EchoTests/Phase3F/3F.2_RealDataSourcesTests.swift` 29 项；全量回归 785 tests / 86 suites 0 失败。
