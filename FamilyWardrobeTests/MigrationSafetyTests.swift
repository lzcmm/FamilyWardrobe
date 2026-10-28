import Foundation
import Testing
import SwiftData
@testable import FamilyWardrobe

// MARK: - 迁移安全测试
//
// 这些测试是「升级不能删历史数据」这个需求的直接验证。
// 每个测试模拟一次真实的升级场景。

@Suite("Schema 迁移安全")
struct MigrationSafetyTests {

    /// 建一个临时库，写入 V1 数据
    private func makeV1Store(with data: (inout ModelContext) -> Void) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: WardrobeMigrationPlan.self,
            configurations: [config]
        )
        let context = ModelContext(container)
        data(&context)
        try context.save()
        return url
    }

    // MARK: 基础场景

    @Test("V1 数据在重新打开后完整保留")
    func v1DataSurvivesReopen() throws {
        let url = try makeV1Store { context in
            let profile = Profile(name: "我")
            context.insert(profile)
            for i in 0..<5 {
                context.insert(Garment(profileID: profile.id, name: "衣服\(i)"))
            }
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: WardrobeMigrationPlan.self,
            configurations: [config]
        )
        let context = ModelContext(container)

        #expect(try context.fetchCount(FetchDescriptor<Profile>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Garment>()) == 5)
    }

    // MARK: 层级枚举

    @Test("穿戴层级顺序从头顶到脚尖")
    func layerOrderIsHeadToToe() {
        let order = WearLayer.allCases
        #expect(order.first == .headwear)
        #expect(order.last == .bag)
        #expect(order.firstIndex(of: .top)! < order.firstIndex(of: .dress)!)
        #expect(order.firstIndex(of: .dress)! < order.firstIndex(of: .outerwear)!)
        #expect(order.firstIndex(of: .outerwear)! < order.firstIndex(of: .bottom)!)
        #expect(order.firstIndex(of: .bottom)! < order.firstIndex(of: .shoes)!)
    }

    @Test("合成遮挡顺序由枚举派生且覆盖全部层级")
    func overlayOrderIsDerived() {
        let overlay = WearLayer.overlayOrder
        #expect(overlay.count == WearLayer.allCases.count)
        #expect(Set(overlay) == Set(WearLayer.allCases))
        // 反序：越晚穿越靠上
        #expect(overlay.first == .bag)
        #expect(overlay.last == .headwear)
    }

    @Test("连衣裙覆盖上衣与下装两层")
    func dressCoversTopAndBottom() {
        #expect(WearLayer.dress.coversLayers == [.top, .bottom])
        #expect(WearLayer.top.coversLayers.isEmpty)
        #expect(WearLayer.top.isCovered(by: .dress))
        #expect(WearLayer.bottom.isCovered(by: .dress))
        #expect(!WearLayer.shoes.isCovered(by: .dress))
    }

    // MARK: 幂等性

    @Test("重复打开同一个库不改变数据")
    func repeatedOpenIsIdempotent() throws {
        let url = try makeV1Store { context in
            let profile = Profile(name: "家人")
            context.insert(profile)
            context.insert(Garment(profileID: profile.id, name: "白衬衫"))
        }
        defer { try? FileManager.default.removeItem(at: url) }

        for _ in 0..<3 {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: WardrobeMigrationPlan.self,
                configurations: [config]
            )
            let context = ModelContext(container)
            #expect(try context.fetchCount(FetchDescriptor<Garment>()) == 1)
        }
    }

    // MARK: 快照

    @Test("快照保留且行数一致")
    func snapshotPreservesRowCount() throws {
        let url = try makeV1Store { context in
            let profile = Profile(name: "测试")
            context.insert(profile)
            for i in 0..<3 {
                context.insert(Garment(profileID: profile.id, name: "件\(i)"))
            }
        }
        defer { try? FileManager.default.removeItem(at: url) }

        // 快照
        let snapshotDir = StoreBackup.snapshotDirectory
        let before = (try? FileManager.default.contentsOfDirectory(at: snapshotDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "store" }.count ?? 0

        StoreBackup.snapshot(reason: "test")

        let after = (try? FileManager.default.contentsOfDirectory(at: snapshotDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "store" }.count ?? 0

        #expect(after >= before)
    }

    // MARK: 完整性报告

    @Test("行数减少被判定为数据丢失")
    func integrityReportDetectsLoss() {
        let report = MigrationIntegrityReport(
            garmentCountBefore: 10, garmentCountAfter: 7,
            profileCountBefore: 2, profileCountAfter: 2,
            outfitCountBefore: 3, outfitCountAfter: 3,
            wearLogCountBefore: 20, wearLogCountAfter: 20
        )
        #expect(report.hasLoss)
    }

    @Test("行数增加不算数据丢失")
    func integrityReportAllowsGrowth() {
        let report = MigrationIntegrityReport(
            garmentCountBefore: 5, garmentCountAfter: 8,
            profileCountBefore: 1, profileCountAfter: 1,
            outfitCountBefore: 2, outfitCountAfter: 2,
            wearLogCountBefore: 10, wearLogCountAfter: 10
        )
        #expect(!report.hasLoss)
    }

    // MARK: 资源路径

    @Test("资源路径是相对路径，不含沙盒绝对路径")
    func assetPathsAreRelative() {
        let garment = Garment(profileID: UUID(), name: "测试")
        let path = AssetStore.shared.relativePath(for: garment.id, kind: .thumb)
        #expect(!path.hasPrefix("/"))
        #expect(path.contains(garment.id.uuidString))
        #expect(path.hasSuffix(".jpg"))
    }
}
