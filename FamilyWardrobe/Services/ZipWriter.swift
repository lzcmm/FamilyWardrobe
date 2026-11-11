import Foundation

// MARK: - 最小 ZIP 打包器（store 模式，无压缩）
//
// iOS 上没有 `Process`，也不能调用 macOS 的 /usr/bin/ditto。
// 备份包必须自己写。这里只实现 ZIP 的 store（不压缩）模式：
// 照片本身就是 JPEG/PNG，再压缩没有收益，反而耗电发热。
//
// 结构：local file header + 数据 → central directory → EOCD。
// 用 UTF-8 文件名标志位（0x0800），中文路径不会乱码。

enum ZipWriter {

    struct Entry {
        let relativePath: String
        let data: Data
    }

    static func create(at target: URL, entries: [Entry]) throws {
        var localSection = Data()
        var centralSection = Data()
        var localOffset: UInt32 = 0

        for entry in entries {
            let name = entry.relativePath.data(using: .utf8) ?? Data()
            let payload = entry.data
            let crc = crc32(payload)
            let size = UInt32(truncatingIfNeeded: payload.count)
            let nameLength = UInt16(truncatingIfNeeded: name.count)

            // ---- Local file header ----
            var local = Data()
            local.append(le32(0x0403_4B50))   // signature
            local.append(le16(20))             // version needed
            local.append(le16(0x0800))         // flags: UTF-8 names
            local.append(le16(0))              // method: store
            local.append(le16(0))              // mod time
            local.append(le16(0))              // mod date
            local.append(le32(crc))
            local.append(le32(size))
            local.append(le32(size))
            local.append(le16(nameLength))
            local.append(le16(0))              // extra length
            local.append(name)
            local.append(payload)

            // ---- Central directory record ----
            var record = Data()
            record.append(le32(0x0201_4B50))  // signature
            record.append(le16(20))            // version made by
            record.append(le16(20))            // version needed
            record.append(le16(0x0800))
            record.append(le16(0))
            record.append(le16(0))
            record.append(le16(0))
            record.append(le32(crc))
            record.append(le32(size))
            record.append(le32(size))
            record.append(le16(nameLength))
            record.append(le16(0))             // extra length
            record.append(le16(0))             // comment length
            record.append(le16(0))             // disk number
            record.append(le16(0))             // internal attributes
            record.append(le32(0))             // external attributes
            record.append(le32(localOffset))
            record.append(name)

            localSection.append(local)
            centralSection.append(record)
            localOffset = localOffset + UInt32(truncatingIfNeeded: local.count)
        }

        let centralOffset = UInt32(truncatingIfNeeded: localSection.count)
        let centralSize = UInt32(truncatingIfNeeded: centralSection.count)
        let count = UInt16(truncatingIfNeeded: entries.count)

        // ---- End of central directory ----
        var end = Data()
        end.append(le32(0x0605_4B50))
        end.append(le16(0))
        end.append(le16(0))
        end.append(le16(count))
        end.append(le16(count))
        end.append(le32(centralSize))
        end.append(le32(centralOffset))
        end.append(le16(0))

        var output = Data()
        output.append(localSection)
        output.append(centralSection)
        output.append(end)

        let directory = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try output.write(to: target)
    }

    // MARK: 小端字节序

    private static func le16(_ value: UInt16) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
        ])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24),
        ])
    }

    // MARK: CRC-32 (IEEE)

    private static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            table[index] = value
        }

        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
