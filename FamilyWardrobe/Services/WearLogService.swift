import Foundation
import SwiftData
import SwiftUI
import OSLog

// MARK: - 穿着记录服务
//
// **单一写入路径**。今天页、试衣间、日历页都走这里。
//
// 为什么必须单一：之前的设计里如果试衣间自己写一遍 WearLog，
// 就会出现两套写入逻辑、字段可能不一致、统计会漏。
// 现在试衣间的「记录今天」和今天页的「记录今天」调用同一个方法，
// 写入行为完全一致。
//
// 写入时**同步回写**每件单品的 wearCount 和 lastWornDate。
// 这两个字段是冗余计数（权威来源是 WearLog），但排序需要它们
// —— 一百多件衣服每次排序都去聚合查询太慢。

@MainActor
final class WearLogService {
    static let shared = WearLogService()

    private let logger = Logger(subsystem: "com.familywardrobe.app", category: "wearlog")

    private init() {}

    /// 记录今天。
    /// - Parameters:
    ///   - garmentIDs: 穿了哪些单品
    ///   - fromRecommendation: 是否由推荐一键落地（用于后续分析推荐质量）
    func recordToday(
        profileID: UUID,
        garmentIDs: [UUID],
        occasion: Occasion,
        fromRecommendation: Bool,
        context: ModelContext
    ) {
        guard !garmentIDs.isEmpty else { return }

        let log = WearLog(
            profileID: profileID,
            date: Date(),
            garmentIDs: garmentIDs,
            occasion: occasion
        )
        log.fromRecommendation = fromRecommendation
        context.insert(log)

        // 回写单品计数
        let today = Calendar.current.startOfDay(for: Date())
        for garment in fetchGarments(ids: garmentIDs, context: context) {
            garment.wearCount += 1
            garment.lastWornDate = Date()
            garment.updatedAt = Date()
        }

        do {
            try context.save()
            logger.info("recorded wear for \(garmentIDs.count, privacy: .public) garments")
        } catch {
            logger.error("failed to save wear log: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 补记某一天
    func record(
        profileID: UUID,
        date: Date,
        garmentIDs: [UUID],
        occasion: Occasion,
        context: ModelContext
    ) {
        guard !garmentIDs.isEmpty else { return }

        let normalized = Calendar.current.startOfDay(for: date)
        let log = WearLog(
            profileID: profileID,
            date: normalized,
            garmentIDs: garmentIDs,
            occasion: occasion
        )
        context.insert(log)

        for garment in fetchGarments(ids: garmentIDs, context: context) {
            garment.wearCount += 1
            if garment.lastWornDate == nil || garment.lastWornDate! < normalized {
                garment.lastWornDate = normalized
            }
        }

        try? context.save()
    }

    /// 取消某天的记录
    func remove(log: WearLog, context: ModelContext) {
        let garmentIDs = log.garmentIDs
        context.delete(log)

        for garment in fetchGarments(ids: garmentIDs, context: context) {
            garment.wearCount = max(0, garment.wearCount - 1)
        }

        try? context.save()
    }

    /// 取指定 ID 的单品
    ///
    /// 注意：`#Predicate` 不支持捕获外部数组做 `contains`。
    /// 必须改成 fetch 全部再在内存里过滤 —— 一百多件衣服的规模下
    /// 完全不是瓶颈，而谓词里写 `ids.contains($0.id)` 编译不过。
    private func fetchGarments(ids: [UUID], context: ModelContext) -> [Garment] {
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<Garment>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { idSet.contains($0.id) }
    }
}

// MARK: - 日历颜色语义
//
// 定稿决议 #4：用「当天主色深浅」表示。
//
// 两个衍生要求（原评审没覆盖的）：
//   1. **图例必须常驻** —— 用户第一次看到一片彩色格子必然困惑，
//      不知道深浅代表什么。没有图例条就是设计缺陷。
//   2. **取色要做归一化** —— 直接用衣服主色的饱和度不可行，
//      同一件米色衬衫换个光线拍颜色就跳变。
//      规则：当天 3–4 件取 Lab 空间均值 → 映射到 5 档色阶；
//      记录不足 2 件时用中性灰填充，不参与取色。
//
// 另外区分规则：**无记录 = 浅灰底无描边，有记录（哪怕是素色）= 加极细描边**。
// 否则「穿了但很素」和「没穿」在视觉上分不开。

enum DayColorScale {
    /// 5 档色阶
    static let steps: [Color] = [
        Color(hex: 0xE8E8EC),  // 0 档：素色
        Color(hex: 0xD8DBE8),  // 1 档
        Color(hex: 0xB5BEE8),  // 2 档
        Color(hex: 0x8A8FE0),  // 3 档
        Color(hex: 0x4C63E6)   // 4 档：多彩
    ]

    /// 无记录的中性灰
    static let empty = Color(hex: 0xF1EFE8)

    /// 根据当天的单品计算色阶档位（0–4）
    static func step(for garments: [Garment]) -> Int {
        // 不足 2 件不参与取色
        guard garments.count >= 2 else { return 0 }

        var labValues: [(L: Double, a: Double, b: Double)] = []

        for garment in garments {
            var cleaned = garment.colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasPrefix("#") { cleaned.removeFirst() }
            guard let value = UInt32(cleaned, radix: 16) else { continue }
            labValues.append(toLab(
                r: Double((value >> 16) & 0xFF),
                g: Double((value >> 8) & 0xFF),
                b: Double(value & 0xFF)
            ))
        }

        guard !labValues.isEmpty else { return 0 }

        // Lab 均值 —— 感知均匀，避免 RGB 均值把明暗差算成色差
        let meanL = labValues.map(\.L).reduce(0, +) / Double(labValues.count)
        let meanA = labValues.map(\.a).reduce(0, +) / Double(labValues.count)
        let meanB = labValues.map(\.b).reduce(0, +) / Double(labValues.count)

        // 彩度：Lab 平面上的半径
        let chroma = (meanA * meanA + meanB * meanB).squareRoot()

        // 彩度 → 档位。阈值按常见衣物色彩分布标定
        switch chroma {
        case ..<8: return 0
        case ..<18: return 1
        case ..<32: return 2
        case ..<50: return 3
        default: return 4
        }
    }

    /// sRGB → CIE Lab
    static func toLab(r: Double, g: Double, b: Double) -> (L: Double, a: Double, b: Double) {
        func linearize(_ c: Double) -> Double {
            let v = c / 255.0
            return v > 0.04045 ? pow((v + 0.055) / 1.055, 2.4) : v / 12.92
        }

        let lr = linearize(r)
        let lg = linearize(g)
        let lb = linearize(b)

        // sRGB → XYZ (D65)
        let x = (lr * 0.4124 + lg * 0.3576 + lb * 0.1805) / 0.95047
        let y = (lr * 0.2126 + lg * 0.7152 + lb * 0.0722) / 1.00000
        let z = (lr * 0.0193 + lg * 0.1192 + lb * 0.9505) / 1.08883

        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t) + 16.0 / 116.0
        }

        let fx = f(x), fy = f(y), fz = f(z)

        return (
            L: (116.0 * fy) - 16.0,
            a: 500.0 * (fx - fy),
            b: 200.0 * (fy - fz)
        )
    }
}
