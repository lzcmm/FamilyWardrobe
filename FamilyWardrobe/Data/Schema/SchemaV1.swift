import Foundation
import SwiftData

// MARK: - SchemaV1
//
// ⚠️ 本文件一经发布即永久冻结。
//
// 规则：
//   1. 不得修改任何已有属性的类型、默认值、可选性
//   2. 不得删除任何属性（哪怕已废弃 —— 删了老库读不出来）
//   3. 不得修改 rawValue（枚举尤其致命）
//   4. 结构变更 = 新建 SchemaV2.swift，在 MigrationPlan 里加一个 stage
//
// 为什么这么严：iPhone 上装的是老 App 时写下的数据。字段一改，
// 老数据可能解析失败或静默变成默认值 —— 那就是「升级后历史数据没了」。
//
// 照片一律存文件系统，库里只存相对文件名。这样：
//   - 迁移只动元数据，几毫秒完成
//   - 数据库体积小到可以每次启动整份快照
//   - 换机、重装、恢复备份都不需要重新处理二进制

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Profile.self, Garment.self, Outfit.self, WearLog.self, TryOnSession.self]
    }

    // MARK: - 档案

    @Model
    final class Profile {
        var id: UUID = UUID()
        var name: String = ""
        /// 头像首字来源
        var avatarSeed: String = ""
        /// 头像底色（十六进制）
        var accentHex: String = "#4C63E6"
        var createdAt: Date = Date()

        // 体型参数（供写实合成时做身形微调，全部可选）
        var heightCM: Double?
        var shoulderWidthCM: Double?
        var chestCM: Double?
        var waistCM: Double?
        var hipCM: Double?

        init(name: String, accentHex: String = "#4C63E6") {
            self.id = UUID()
            self.name = name
            self.avatarSeed = String(name.prefix(1))
            self.accentHex = accentHex
            self.createdAt = Date()
        }
    }

    // MARK: - 单品

    @Model
    final class Garment {
        var id: UUID = UUID()
        /// 归属档案。**所有查询强制带此条件**
        var profileID: UUID = UUID()

        var name: String = ""

        /// 穿戴层级（唯一真相源，见 Enums.swift）
        var layerRaw: Int = WearLayer.top.rawValue
        /// 覆盖的层级（仅连衣裙用，存 [WearLayer] 的 rawValue）
        var coversLayerRaws: [Int] = []

        var colorName: String = ""
        var colorHex: String = "#CCCCCC"
        var secondaryColorHex: String?
        var patternRaw: String = Pattern.solid.rawValue
        var materialRaw: String = Material.cotton.rawValue
        var thicknessRaw: Int = Thickness.medium.rawValue
        var fitRaw: String = Fit.regular.rawValue

        var occasionRaws: [String] = []
        var seasonRaws: [String] = []

        var price: Double?
        var brand: String?
        var purchaseDate: Date?

        /// 穿着次数（冗余计数，便于排序；权威来源是 WearLog）
        var wearCount: Int = 0
        var lastWornDate: Date?
        var favorite: Bool = false
        /// 归档 = 不再参与推荐，但保留历史记录与统计
        var archived: Bool = false

        /// 平铺照（抠图前的原图）—— 相对路径
        var photoPath: String?
        /// 抠图结果 —— 相对路径
        var maskPath: String?
        /// 缩略图 —— 相对路径
        var thumbPath: String?
        /// 穿着照（写实合成用）—— 相对路径
        var wearingPhotoPath: String?

        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(
            profileID: UUID,
            name: String,
            layer: WearLayer = .top,
            colorName: String = "",
            colorHex: String = "#CCCCCC"
        ) {
            self.id = UUID()
            self.profileID = profileID
            self.name = name
            self.layerRaw = layer.rawValue
            self.coversLayerRaws = layer.coversLayers.map(\.rawValue)
            self.colorName = colorName
            self.colorHex = colorHex
            self.createdAt = Date()
            self.updatedAt = Date()
        }

        var layer: WearLayer {
            get { WearLayer(rawValue: layerRaw) ?? .top }
            set {
                layerRaw = newValue.rawValue
                coversLayerRaws = newValue.coversLayers.map(\.rawValue)
            }
        }

        var coversLayers: [WearLayer] {
            coversLayerRaws.compactMap(WearLayer.init(rawValue:))
        }

        var occasions: [Occasion] {
            occasionRaws.compactMap(Occasion.init(rawValue:))
        }

        var seasons: [Season] {
            seasonRaws.compactMap(Season.init(rawValue:))
        }

        var pattern: Pattern { Pattern(rawValue: patternRaw) ?? .solid }
        var material: Material { Material(rawValue: materialRaw) ?? .cotton }
        var thickness: Thickness { Thickness(rawValue: thicknessRaw) ?? .medium }
        var fit: Fit { Fit(rawValue: fitRaw) ?? .regular }
    }

    // MARK: - 组合

    @Model
    final class Outfit {
        var id: UUID = UUID()
        var profileID: UUID = UUID()
        var name: String = ""
        var occasionRaw: String = Occasion.casual.rawValue
        var seasonRaws: [String] = []
        /// 成员单品 ID。顺序按穿戴层级正序（上衣 → 外套 → 下装 → 鞋）
        var garmentIDs: [UUID] = []
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var wearCount: Int = 0
        var lastWornDate: Date?
        var favorite: Bool = false

        init(profileID: UUID, name: String, occasion: Occasion = .casual) {
            self.id = UUID()
            self.profileID = profileID
            self.name = name
            self.occasionRaw = occasion.rawValue
            self.createdAt = Date()
            self.updatedAt = Date()
        }

        var occasion: Occasion {
            get { Occasion(rawValue: occasionRaw) ?? .casual }
            set { occasionRaw = newValue.rawValue }
        }

        var seasons: [Season] {
            seasonRaws.compactMap(Season.init(rawValue:))
        }
    }

    // MARK: - 穿着记录

    @Model
    final class WearLog {
        var id: UUID = UUID()
        var profileID: UUID = UUID()
        /// 当天（归一化到本地时区零点）
        var date: Date = Date()
        /// 穿了哪些单品
        var garmentIDs: [UUID] = []
        /// 当天场合
        var occasionRaw: String = Occasion.casual.rawValue
        /// 是否由推荐一键落地
        var fromRecommendation: Bool = false
        var note: String = ""
        var createdAt: Date = Date()

        init(profileID: UUID, date: Date, garmentIDs: [UUID], occasion: Occasion = .casual) {
            self.id = UUID()
            self.profileID = profileID
            self.date = date
            self.garmentIDs = garmentIDs
            self.occasionRaw = occasion.rawValue
            self.createdAt = Date()
        }

        var occasion: Occasion {
            get { Occasion(rawValue: occasionRaw) ?? .casual }
            set { occasionRaw = newValue.rawValue }
        }
    }

    // MARK: - 试衣会话

    @Model
    final class TryOnSession {
        var id: UUID = UUID()
        var profileID: UUID = UUID()
        var createdAt: Date = Date()
        /// 当前搭配的单品 ID
        var garmentIDs: [UUID] = []
        /// 选中的底板姿势索引
        var poseIndex: Int = 0
        /// 是否已存为搭配
        var savedAsOutfit: Bool = false

        init(profileID: UUID, garmentIDs: [UUID] = []) {
            self.id = UUID()
            self.profileID = profileID
            self.garmentIDs = garmentIDs
            self.createdAt = Date()
        }
    }
}

// MARK: - 最新 Schema 别名
//
// 业务代码一律用这些别名，不要直接引用 SchemaV1.X。
// 将来出 V2 时只改这一行。

typealias Profile = SchemaV1.Profile
typealias Garment = SchemaV1.Garment
typealias Outfit = SchemaV1.Outfit
typealias WearLog = SchemaV1.WearLog
typealias TryOnSession = SchemaV1.TryOnSession
typealias CurrentSchema = SchemaV1
