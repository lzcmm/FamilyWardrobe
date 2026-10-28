import Foundation
import UIKit
import OSLog

// MARK: - 资源文件管理
//
// 照片一律存磁盘，库里只存相对文件名。三条理由：
//   1. 数据库体积小到可以每次启动整份快照
//   2. 迁移只动元数据，几毫秒完成
//   3. 换机、恢复备份、重新安装都不需要处理二进制
//
// 相对路径形如 "garments/<uuid>/thumb.jpg"。绝不用绝对路径 ——
// 绝对路径在 App 沙盒路径变化后（比如恢复备份）会全部失效。

final class AssetStore {
    static let shared = AssetStore()

    private let logger = Logger(subsystem: "com.familywardrobe.app", category: "assets")
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
    }

    // MARK: 路径

    /// 某个单品的资源目录
    func directory(for garmentID: UUID) -> URL {
        StoreBackup.assetsDirectory
            .appending(path: "garments", directoryHint: .isDirectory)
            .appending(path: garmentID.uuidString, directoryHint: .isDirectory)
    }

    /// 相对路径（存库用）
    func relativePath(for garmentID: UUID, kind: Kind) -> String {
        "garments/\(garmentID.uuidString)/\(kind.fileName)"
    }

    /// 绝对 URL（读文件用）
    func absoluteURL(for relativePath: String) -> URL {
        StoreBackup.assetsDirectory.appending(path: relativePath)
    }

    // MARK: 写入

    /// 保存一张图。返回写入的相对路径。
    @discardableResult
    func save(image: UIImage, for garmentID: UUID, kind: Kind, compress: CGFloat = 0.85) -> String? {
        let dir = directory(for: garmentID)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appending(path: kind.fileName)
            guard let data = image.jpegData(compressionQuality: compress) else { return nil }
            try data.write(to: url, options: .atomic)
            cache.removeObject(forKey: (relativePath(for: garmentID, kind: kind) as NSString))
            return relativePath(for: garmentID, kind: kind)
        } catch {
            logger.error("save \(kind.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: 读取

    /// 读缩略图。带内存缓存。
    func thumbnail(for garment: Garment) -> UIImage? {
        guard let path = garment.thumbPath ?? garment.photoPath else { return nil }
        return image(atRelativePath: path)
    }

    func image(atRelativePath path: String) -> UIImage? {
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }
        let url = absoluteURL(for: path)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    // MARK: 删除

    /// 删除某单品的全部资源文件。
    /// 注意：这是**物理删除**。调用方应确保库里已经不再引用它，
    /// 或该单品已归档超过保留期。删除记录本身不删 —— 历史统计要留着。
    func deleteAll(for garmentID: UUID) {
        let dir = directory(for: garmentID)
        try? FileManager.default.removeItem(at: dir)
        logger.info("deleted assets for \(garmentID.uuidString, privacy: .public)")
    }

    /// 清理没有任何单品引用的孤儿目录。
    /// 每次启动时跑一次，防止长期积累垃圾文件。
    func pruneOrphans(referencedPaths: Set<String>) {
        let fm = FileManager.default
        let garmentsRoot = StoreBackup.assetsDirectory.appending(path: "garments", directoryHint: .isDirectory)
        guard let dirs = try? fm.contentsOfDirectory(
            at: garmentsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for dir in dirs {
            let uuid = dir.lastPathComponent
            let referenced = referencedPaths.contains { $0.contains(uuid) }
            if !referenced {
                try? fm.removeItem(at: dir)
            }
        }
    }

    // MARK: 资源类型

    enum Kind: String {
        case original = "原图"
        case mask = "抠图"
        case thumb = "缩略图"
        case wearing = "穿着照"

        var fileName: String {
            switch self {
            case .original: "original.jpg"
            case .mask: "mask.png"
            case .thumb: "thumb.jpg"
            case .wearing: "wearing.jpg"
            }
        }
    }
}
