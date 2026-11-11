import Foundation
import SQLite3
import SwiftData
import OSLog

// MARK: - 容器工厂
//
// 打开数据库的完整流程（顺序不可调换）：
//
//   ① 读 schema 标记 → 知道盘上是第几版
//   ② 盘上版本 < 当前版本 → 先快照（迁移前备份）
//   ③ 打开容器（SwiftData 在这一步执行迁移）
//   ④ 对比迁移前后的行数 → 少了就回滚并重开
//   ⑤ 写 schema 标记
//
// 「迁移前快照」为什么必要：SwiftData 的迁移不是全有全无的事务。
// 实测中 V1→V2 成功、V2→V3 失败时，库会停在 V2 这个中间态。
// 这时候光靠迁移代码里的 try/catch 救不回来 —— 只有物理快照能救。
//
// 「行数校验」为什么必要：「迁移成功但数据少了」不会抛错，
// 只有对比行数才能发现。
//
// 回滚时必须先让容器完全释放，才能替换文件。所以这里用
// 「开 → 验 → 必要时回滚 → 再开」的两段式，而不是在同一个容器上操作。

@MainActor
enum WardrobeContainer {

    private static let logger = Logger(subsystem: "com.familywardrobe.app", category: "container")

    /// 启动结果，供 UI 决定是否显示恢复提示
    enum OpenOutcome {
        case success(container: ModelContainer)
        /// 迁移异常，已回滚到升级前状态
        case rolledBack(container: ModelContainer, message: String)
        /// 打开失败且无法恢复 —— App 进入恢复界面
        case failed(error: Error)
    }

    /// 当前 schema 版本字符串
    nonisolated static var currentSchemaVersion: String {
        let v = CurrentSchema.versionIdentifier
        return "\(v.major).\(v.minor).\(v.patch)"
    }

    /// 打开容器。App 启动时调用一次。
    static func open() -> OpenOutcome {

        let diskVersion = StoreBackup.readSchemaMarker()
        let needsMigration = diskVersion != nil && diskVersion != currentSchemaVersion

        // ① 迁移前快照
        if needsMigration {
            logger.notice("schema \(diskVersion ?? "?", privacy: .public) → \(currentSchemaVersion, privacy: .public); snapshot before migrating")
            StoreBackup.snapshot(reason: "pre-migration")
        } else if diskVersion == nil {
            logger.info("fresh install; no snapshot needed")
        } else {
            // 版本一致也留一份。库很小，代价可忽略，但能救「上次用着 App 直接崩了」
            StoreBackup.snapshot(reason: "routine")
        }

        // ② 迁移前行数（用 SQLite 直查，容器还没开）
        let before = needsMigration ? countRowsDirectly() : nil

        // ③ 打开容器（此处执行迁移）
        let firstAttempt = openContainer()

        switch firstAttempt {
        case .failure(let error):
            // 打开就失败 → 回滚后重试
            logger.error("container open failed: \(error.localizedDescription, privacy: .public)")
            guard StoreBackup.rollbackToLatestSnapshot() else {
                return .failed(error: error)
            }
            logger.notice("rolled back after open failure; retrying")
            switch openContainer() {
            case .success(let container):
                StoreBackup.writeSchemaMarker(currentSchemaVersion)
                return .rolledBack(container: container, message: "升级未能完成，已恢复到升级前的数据。")
            case .failure(let retryError):
                return .failed(error: retryError)
            }

        case .success(let container):
            // ④ 行数校验
            if let before {
                let after = countRows(in: container)
                let report = MigrationIntegrityReport(
                    garmentCountBefore: before.garments,
                    garmentCountAfter: after.garments,
                    profileCountBefore: before.profiles,
                    profileCountAfter: after.profiles,
                    outfitCountBefore: before.outfits,
                    outfitCountAfter: after.outfits,
                    wearLogCountBefore: before.wearLogs,
                    wearLogCountAfter: after.wearLogs
                )

                if report.hasLoss {
                    logger.fault("integrity check failed after migration: \(report.summary, privacy: .public)")
                    // 有丢失。容器必须先释放才能替换文件，
                    // 所以这里返回信号，由外层在容器离开作用域后再回滚。
                    return .rolledBack(container: container, message: "检测到数据异常，已恢复到升级前状态。")
                }
                logger.info("migration verified: \(report.summary, privacy: .public)")
            }

            // ⑤ 写标记
            StoreBackup.writeSchemaMarker(currentSchemaVersion)
            return .success(container: container)
        }
    }

    /// 打开容器的一次尝试
    private static func openContainer() -> Result<ModelContainer, Error> {
        do {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            let configuration = ModelConfiguration(
                "FamilyWardrobe",
                schema: schema,
                url: StoreBackup.storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                migrationPlan: WardrobeMigrationPlan.self,
                configurations: [configuration]
            )
            return .success(container)
        } catch {
            return .failure(error)
        }
    }

    /// 完整性校验失败后的回滚 + 重开。
    /// 由 App 启动流程在容器离开作用域后调用。
    static func recoverAfterIntegrityFailure() -> OpenOutcome {
        logger.notice("recovering from integrity failure")
        guard StoreBackup.rollbackToLatestSnapshot() else {
            return .failed(error: RecoveryError.noSnapshotAvailable)
        }
        switch openContainer() {
        case .success(let container):
            StoreBackup.writeSchemaMarker(currentSchemaVersion)
            return .rolledBack(container: container, message: "检测到数据异常，已恢复到升级前状态。")
        case .failure(let error):
            return .failed(error: error)
        }
    }

    // MARK: 行数统计

    struct RowCounts {
        var garments = 0
        var profiles = 0
        var outfits = 0
        var wearLogs = 0
    }

    /// 从已打开的容器统计
    static func countRows(in container: ModelContainer) -> RowCounts {
        let context = ModelContext(container)
        var counts = RowCounts()
        counts.garments = (try? context.fetchCount(FetchDescriptor<Garment>())) ?? 0
        counts.profiles = (try? context.fetchCount(FetchDescriptor<Profile>())) ?? 0
        counts.outfits = (try? context.fetchCount(FetchDescriptor<Outfit>())) ?? 0
        counts.wearLogs = (try? context.fetchCount(FetchDescriptor<WearLog>())) ?? 0
        return counts
    }

    /// 直接用 SQLite 统计（迁移前，容器还没开的时候）
    private static func countRowsDirectly() -> RowCounts? {
        guard FileManager.default.fileExists(atPath: StoreBackup.storeURL.path) else { return nil }
        var counts = RowCounts()
        counts.garments = sqliteCount(table: "ZGARMENT") ?? 0
        counts.profiles = sqliteCount(table: "ZPROFILE") ?? 0
        counts.outfits = sqliteCount(table: "ZOUTFIT") ?? 0
        counts.wearLogs = sqliteCount(table: "ZWEARLOG") ?? 0
        return counts
    }

    private static func sqliteCount(table: String) -> Int? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(StoreBackup.storeURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else { return nil }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table);", -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int(stmt, 0))
    }
}

// MARK: - 恢复错误

enum RecoveryError: LocalizedError {
    case noSnapshotAvailable

    var errorDescription: String? {
        switch self {
        case .noSnapshotAvailable:
            "没有可用的历史快照，数据无法自动恢复。请从「设置 → 备份」检查导出包。"
        }
    }
}
