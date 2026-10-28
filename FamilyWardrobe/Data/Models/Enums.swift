import Foundation
import SwiftData

// MARK: - 穿戴层级（唯一真相源）
//
// 全 App 三处共用此定义：衣橱分组顺序、试衣间槽位顺序、合成遮挡层序。
// rawValue 一经发布即冻结。调整顺序 = 破坏性变更 = 必须走 SchemaV2 + 自定义迁移。
// 新增层级只能追加到末尾。
//
// 特别说明：
//   dress = 3  排在上衣之后、外套之前（一条裙子同时覆盖上衣与下装两层）
//   bag   = 8  携带物而非穿戴物，固定排在最末

enum WearLayer: Int, CaseIterable, Codable, Identifiable, Sendable {
    case headwear = 0    // 头饰
    case neckwear = 1    // 围巾、领巾
    case top = 2         // 上衣
    case dress = 3       // 连衣裙
    case outerwear = 4   // 外套
    case bottom = 5      // 下装
    case shoes = 6       // 鞋
    case acc = 7         // 配饰：腰带、首饰
    case bag = 8         // 包袋

    var id: Int { rawValue }

    /// 展示名（组头用）
    var displayName: String {
        switch self {
        case .headwear: "头饰"
        case .neckwear: "围巾"
        case .top: "上衣"
        case .dress: "连衣裙"
        case .outerwear: "外套"
        case .bottom: "下装"
        case .shoes: "鞋履"
        case .acc: "配饰"
        case .bag: "包袋"
        }
    }

    /// 占位图资源名
    var placeholderSymbol: String {
        switch self {
        case .headwear: "hat.wide.fill"
        case .neckwear: "scarf"
        case .top: "tshirt.fill"
        case .dress: "dress"
        case .outerwear: "jacket.fill"
        case .bottom: "figure.walk"
        case .shoes: "shoe.fill"
        case .acc: "belt"
        case .bag: "bag.fill"
        }
    }

    /// 连衣裙覆盖的层级。空数组 = 只占自己这一层。
    var coversLayers: [WearLayer] {
        self == .dress ? [.top, .bottom] : []
    }

    /// 该层级是否被某个选中单品覆盖（用于置灰显示「已被连衣裙覆盖」）
    func isCovered(by layer: WearLayer) -> Bool {
        layer.coversLayers.contains(self)
    }

    /// 合成遮挡顺序（由后到前）。**必须由枚举派生，禁止手写枚举。**
    /// 手写必漏新加的层级 —— 加 bag 时就漏过一次。
    static var overlayOrder: [WearLayer] {
        allCases.reversed()
    }
}

// MARK: - 场合

enum Occasion: String, CaseIterable, Codable, Identifiable, Sendable {
    case commute = "通勤"
    case casual = "休闲"
    case formal = "正式"
    case sport = "运动"
    case date = "约会"
    case travel = "出差"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

// MARK: - 季节

enum Season: String, CaseIterable, Codable, Identifiable, Sendable {
    case spring = "春"
    case summer = "夏"
    case autumn = "秋"
    case winter = "冬"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

// MARK: - 厚薄

enum Thickness: Int, CaseIterable, Codable, Identifiable, Sendable {
    case ultraLight = 1
    case light = 2
    case medium = 3
    case heavy = 4
    case ultraHeavy = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .ultraLight: "极薄"
        case .light: "薄"
        case .medium: "适中"
        case .heavy: "厚"
        case .ultraHeavy: "极厚"
        }
    }
}

// MARK: - 版型

enum Fit: String, CaseIterable, Codable, Identifiable, Sendable {
    case slim = "修身"
    case regular = "常规"
    case loose = "宽松"
    case oversized = "Oversized"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

// MARK: - 图案

enum Pattern: String, CaseIterable, Codable, Identifiable, Sendable {
    case solid = "纯色"
    case stripe = "条纹"
    case check = "格纹"
    case floral = "碎花"
    case plaid = "格子"
    case other = "其他"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

// MARK: - 材质

enum Material: String, CaseIterable, Codable, Identifiable, Sendable {
    case cotton = "棉"
    case linen = "麻"
    case wool = "羊毛"
    case silk = "丝"
    case polyester = "涤纶"
    case denim = "牛仔"
    case leather = "皮革"
    case knit = "针织"
    case down = "羽绒"
    case other = "其他"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// 是否有光泽感 —— 推荐引擎的「材质对比」规则用
    var isGlossy: Bool {
        switch self {
        case .silk, .leather, .polyester: true
        case .cotton, .linen, .wool, .denim, .knit, .down, .other: false
        }
    }

    /// 是否粗质感 —— 与光泽面料形成对比
    var isTextured: Bool {
        switch self {
        case .knit, .wool, .denim, .down: true
        case .cotton, .linen, .silk, .polyester, .leather, .other: false
        }
    }
}
