import Foundation
import SQLite3
import SwiftData
import OSLog

// MARK: - Store 路径与快照管理
//
// 这是「升级不丢数据」的最后一道物理防线。
//
// 原理：SwiftData 的库是一个 SQLite 文件。整个文件拷贝一份就是完整备份。
// 我们的库只存元数据 + 相对路径，照片单独存磁盘，所以：
//   - 库很小（150 件衣服约几百 KB），每次启动拷一份不心疼
//   - 快照是原子的，不存在「拷到一半」的中间态
//
// 保留最近 5 份，其余自动清理。

enum StoreBackup {
    private static let logger = Logger(subsystem: "com.familywardrobe.app", category: "backup")

    /// 保留的快照数量
    static let maxSnapshots = 5

    // MARK: 路径

    /// 库文件所在目录
    static var storeDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appending(path: "FamilyWardrobe", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 主库文件
    static var storeURL: URL {
        storeDirectory.appending(path: "FamilyWardrobe.store")
    }

    /// 快照目录
    static var snapshotDirectory: URL {
        let dir = storeDirectory.appending(path: "Snapshots", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 照片目录 —— 与库分离，迁移完全不碰
    static var assetsDirectory: URL {
        let dir = storeDirectory.appending(path: "Assets", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 备份包目录（导出 zip 用）
    static var exportDirectory: URL {
        let dir = storeDirectory.appending(path: "Exports", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: 快照

    /// 给快照编号。存库文件旁边，迁移时可以读到「迁移前是第几版」。
    static var versionMarkerURL: URL {
        storeDirectory.appending(path: "schema-version.txt")
    }

    static func readSchemaMarker() -> String? {
        try? String(contentsOf: versionMarkerURL, encoding: .utf8)
    }

    static func writeSchemaMarker(_ value: String) {
        try? value.write(to: versionMarkerURL, atomically: true, encoding: .utf8)
    }

    /// 迁移前快照。返回一个可回滚的句柄。
    @discardableResult
    static func snapshot(reason: String) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return nil }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let target = snapshotDirectory.appending(path: "snapshot-\(stamp).store")

        do {
            // 数据库开着 WAL 模式，光拷 .store 会漏掉 WAL 里的数据。
            // 正确做法是让 SQLite 做一次 checkpoint，把 WAL 合并进主库。
            // 这里用 SQLite3 直接做，不依赖 App 生命周期。
            try checkpointWAL()
            try fm.copyItem(at: storeURL, to: target)
            logger.info("snapshot saved: \(target.lastPathComponent, privacy: .public) reason=\(reason, privacy: .public)")
            pruneSnapshots()
            return target
        } catch {
            logger.error("snapshot failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 把 WAL 内容合并进主库文件。拷贝备份前必须做，否则备份不完整。
    private static func checkpointWAL() throws {
        // SQLite3 的 wal_checkpoint 把 WAL 内容写回主库
        var db: OpaquePointer?
        guard sqlite3_open_v2(
            storeURL.path,
            &db,
            SQLITE_OPEN_READWRITE,
            nil
        ) == SQLITE_OK, let db else {
            throw BackupError.openFailed
        }
        defer { sqlite3_close(db) }
        // SQLITE_CHECKPOINT_TRUNCATE = 3；最后两个是出参（日志帧数 / 已 checkpoint 帧数）
        var logFrames: Int32 = 0
        var checkpointedFrames: Int32 = 0
        let rc = sqlite3_wal_checkpoint_v2(db, nil, 3, &logFrames, &checkpointedFrames)
        guard rc == SQLITE_OK else { throw BackupError.checkpointFailed }
    }

    /// 清理旧快照，只留最近 N 份。
    static func pruneSnapshots() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: snapshotDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let snapshots = files
            .filter { $0.pathExtension == "store" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return da > db
            }

        guard snapshots.count > maxSnapshots else { return }
        for old in snapshots.dropFirst(maxSnapshots) {
            try? fm.removeItem(at: old)
            logger.info("pruned snapshot: \(old.lastPathComponent, privacy: .public)")
        }
    }

    /// 回滚到最近一份快照。
    /// 返回 true = 回滚成功，false = 没有可用快照。
    @discardableResult
    static func rollbackToLatestSnapshot() -> Bool {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: snapshotDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        let snapshots = files
            .filter { $0.pathExtension == "store" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return da > db
            }

        guard let latest = snapshots.first else { return false }

        do {
            // 保留坏库，不删 —— 万一快照本身有问题，还有余地人工救
            let quarantine = storeDirectory.appending(path: "broken-\(Int(Date().timeIntervalSince1970)).store")
            if fm.fileExists(atPath: storeURL.path) {
                try? fm.moveItem(at: storeURL, to: quarantine)
            }
            try fm.copyItem(at: latest, to: storeURL)
            logger.notice("rolled back to snapshot \(latest.lastPathComponent, privacy: .public)")
            return true
        } catch {
            logger.error("rollback failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 列出可用快照（设置页展示用）
    static func listSnapshots() -> [(url: URL, date: Date)] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: snapshotDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "store" }
            .compactMap { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return date.map { (url, $0) }
            }
            .sorted { $0.date > $1.date }
    }
}

// MARK: - 错误

enum BackupError: LocalizedError {
    case openFailed
    case checkpointFailed

    var errorDescription: String? {
        switch self {
        case .openFailed: "无法打开数据库文件"
        case .checkpointFailed: "无法合并 WAL 日志"
        }
    }
}
