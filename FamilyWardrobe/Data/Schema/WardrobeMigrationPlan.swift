import Foundation
import SwiftData

// MARK: - 迁移计划
//
// ⚠️ 这个枚举是「升级不丢数据」的中枢。
//
// 三条铁律：
//   1. schemas 数组**只增不改**。V1 永远排第一，顺序即版本顺序。
//      删掉中间某个版本 → 从那个版本装机的用户会直接打不开 App。
//   2. stages 与 schemas 一一对应，顺序不能变。
//   3. 永远不要用「重建整个库」的方式迁移。那等于清空。
//
// 将来加 V2 时的完整步骤：
//   ① 新建 Data/Schema/SchemaV2.swift，复制 V1 的全部模型，只改要改的部分
//   ② 在下面加：static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
//   ③ 加一个 stage：
//        .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
//      —— 只是加带默认值的属性时用这个，Swift 自动处理，最安全
//   ④ 需要改数据时用 .custom，并务必遵守下面注释里的三步写法
//   ⑤ 把文件顶部的 typealias 全部指向 SchemaV2
//   ⑥ 写一个迁移测试（FamilyWardrobeTests 里已有模板）
//
// .custom 迁移的安全写法（三步，顺序不能换）：
//   willMigrate:  先把全部旧数据算成新值放进内存数组，一个都不写回
//                 → 此时任何一条算错都会抛错，库还是原样
//   校验:         检查转换结果合法性（负数、空值、超范围）
//   didMigrate:   确认全部算对之后，才逐条写回并 save
//
// 为什么这么写：SwiftData 的迁移**不是全有全无的事务**。
// 实测中 V1→V2 成功、V2→V3 失败时，库停在 V2 —— 中间态是真实存在的。
// 所以真正的兜底不在迁移代码里，而在 StoreBackup 的快照回滚里。

enum WardrobeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // V1 是首个版本，没有需要迁移的来源版本
        []
    }
}

// MARK: - 迁移后的完整性校验
//
// 「迁移抛错了」和「迁移成功但数据少了」是两种不同的事故。
// 后者不会抛错，只能靠对比行数发现。所以每次启动都要跑这个。

struct MigrationIntegrityReport {
    var garmentCountBefore: Int
    var garmentCountAfter: Int
    var profileCountBefore: Int
    var profileCountAfter: Int
    var outfitCountBefore: Int
    var outfitCountAfter: Int
    var wearLogCountBefore: Int
    var wearLogCountAfter: Int

    /// 是否有记录丢失。允许变多（迁移过程可能补默认行），不允许变少。
    var hasLoss: Bool {
        garmentCountAfter < garmentCountBefore
            || profileCountAfter < profileCountBefore
            || outfitCountAfter < outfitCountBefore
            || wearLogCountAfter < wearLogCountBefore
    }

    var summary: String {
        """
        单品 \(garmentCountBefore) → \(garmentCountAfter)
        档案 \(profileCountBefore) → \(profileCountAfter)
        组合 \(outfitCountBefore) → \(outfitCountAfter)
        记录 \(wearLogCountBefore) → \(wearLogCountAfter)
        """
    }
}
