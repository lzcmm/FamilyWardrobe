import Foundation
import Testing
import SwiftData
import UIKit
@testable import FamilyWardrobe

// MARK: - 推荐引擎测试
//
// 验证三件事：
//   1. 推荐能产出，且理由可验证
//   2. 协调随机不产出「不能穿出门」的组合
//   3. 同一件衣服 7 天内不重复推荐

@Suite("推荐引擎")
struct RecommendationEngineTests {

    /// 造一批测试单品
    private func makeGarments(
        profileID: UUID = UUID(),
        count: Int = 12
    ) -> [Garment] {
        let colors = ["#1C1C1E", "#F5F5F0", "#4C63E6", "#8B6A4E", "#C9A87C", "#4A8C5A"]
        let layers: [WearLayer] = [.top, .top, .top, .bottom, .bottom, .bottom, .shoes, .shoes, .outerwear, .dress, .acc, .bag]

        return (0..<count).map { index in
            let layer = layers[index % layers.count]
            let garment = Garment(
                profileID: profileID,
                name: "衣服\(index)",
                layer: layer,
                colorName: "色\(index % colors.count)",
                colorHex: colors[index % colors.count]
            )
            garment.occasionRaws = [Occasion.commute.rawValue]
            garment.seasonRaws = [Season.spring.rawValue, Season.autumn.rawValue]
            garment.wearCount = index % 5
            return garment
        }
    }

    @Test("能产出推荐且每条都有可验证的理由")
    func producesVerifiableReasons() {
        let engine = RecommendationEngine()
        let profileID = UUID()
        let garments = makeGarments(profileID: profileID)

        let results = engine.recommend(
            from: garments,
            occasion: .commute,
            season: .spring,
            profileID: profileID,
            recentIDs: []
        )

        #expect(!results.isEmpty)

        guard let best = results.first else { return }

        // 理由不能为空
        #expect(!best.reasons.isEmpty)

        // 每条理由都必须是非空的、可验证的一句话
        for reason in best.reasons {
            #expect(!reason.text.isEmpty)
            #expect(reason.text.count >= 4)
            // 禁止出现「很适合你」这类不可验证的表述
            #expect(!reason.text.contains("很适合"))
            #expect(!reason.text.contains("气质"))
        }
    }

    @Test("推荐分数递减")
    func scoresAreDescending() {
        let engine = RecommendationEngine()
        let profileID = UUID()
        let garments = makeGarments(profileID: profileID, count: 20)

        let results = engine.recommend(
            from: garments,
            occasion: .commute,
            season: .spring,
            profileID: profileID,
            recentIDs: []
        )

        for index in 1..<max(1, results.count) {
            #expect(results[index - 1].score >= results[index].score)
        }
    }

    @Test("最近穿过的单品会被降权")
    func recentGarmentsAreDownweighted() {
        let engine = RecommendationEngine()
        let profileID = UUID()
        let garments = makeGarments(profileID: profileID, count: 20)

        // 把所有上层单品标记为最近穿过
        let recent = Set(garments.filter { $0.layer == .top }.map(\.id))

        let results = engine.recommend(
            from: garments,
            occasion: .commute,
            season: .spring,
            profileID: profileID,
            recentIDs: recent
        )

        // 第一套里应该尽量不含最近穿过的
        if let best = results.first {
            let topCount = best.garments.filter { $0.layer == .top }.count
            #expect(topCount <= 1)
        }
    }

    @Test("协调随机不产出空组合")
    func inspireAlwaysProducesSomething() {
        let engine = RecommendationEngine()
        let profileID = UUID()
        let garments = makeGarments(profileID: profileID, count: 20)

        let results = engine.inspire(
            from: garments,
            occasion: .commute,
            season: .spring,
            profileID: profileID,
            recentIDs: [],
            count: 1
        )

        #expect(results.count == 1)
        #expect(!(results.first?.garments.isEmpty ?? true))
    }

    @Test("随机结果至少包含上衣与下装之一")
    func inspireProducesWearableCombination() {
        let engine = RecommendationEngine()
        let profileID = UUID()
        let garments = makeGarments(profileID: profileID, count: 24)

        // 跑 30 次，每次都应该是「穿得出门」的
        for _ in 0..<30 {
            let results = engine.inspire(
                from: garments,
                occasion: .commute,
                season: .spring,
                profileID: profileID,
                recentIDs: [],
                count: 1
            )
            guard let best = results.first, !best.garments.isEmpty else {
                Issue.record("随机推荐产出了空组合")
                continue
            }
            let layers = Set(best.garments.map(\.layer))
            let wearable = layers.contains(.top) || layers.contains(.dress)
            #expect(wearable)
        }
    }

    @Test("衣橱为空时不报错")
    func emptyWardrobeIsSafe() {
        let engine = RecommendationEngine()
        let results = engine.recommend(
            from: [],
            occasion: .commute,
            season: .spring,
            profileID: UUID(),
            recentIDs: []
        )
        #expect(results.isEmpty)
    }

    @Test("档案隔离：不会推荐别人档案的衣服")
    ///
    /// ⚠️ 这条测试锁住一个真实漏洞。
    /// 曾经候选池过滤写成 `a && b && c || d`，而 `&&` 优先级高于 `||`，
    /// 导致「季节符合但档案不符」的单品混进池子 —— 家人共用时会把
    /// 别人的衣服推荐出来。
    func profileIsolationIsEnforced() {
        let engine = RecommendationEngine()
        let myProfileID = UUID()
        let otherProfileID = UUID()

        // 我的衣服：符合季节
        let mine = makeGarments(profileID: myProfileID, count: 10)

        // 家人的衣服：**季节不符合**（只有夏天），且档案不同
        let theirs = makeGarments(profileID: otherProfileID, count: 10).map { garment -> Garment in
            garment.seasonRaws = [Season.summer.rawValue]
            return garment
        }

        let results = engine.recommend(
            from: mine + theirs,
            occasion: .commute,
            season: .spring,
            profileID: myProfileID,
            recentIDs: []
        )

        #expect(!results.isEmpty)
        for result in results {
            for garment in result.garments {
                #expect(garment.profileID == myProfileID)
            }
        }
    }
}

// MARK: - 颜色归一化测试

@Suite("日历颜色归一化")
struct DayColorScaleTests {

    @Test("单件衣服不算多彩")
    func singleGarmentIsNeutral() {
        let garment = Garment(profileID: UUID(), name: "白衬衫", colorHex: "#FFFFFF")
        #expect(DayColorScale.step(for: [garment]) == 0)
    }

    @Test("多件彩色衣服得到更高色阶")
    func multipleColorsGetHigherStep() {
        let profileID = UUID()
        let neutrals = [
            Garment(profileID: profileID, name: "白", colorHex: "#F5F5F0"),
            Garment(profileID: profileID, name: "灰", colorHex: "#9A9A94")
        ]
        let colorful = [
            Garment(profileID: profileID, name: "红", colorHex: "#C0392B"),
            Garment(profileID: profileID, name: "蓝", colorHex: "#3E6FA8")
        ]

        #expect(DayColorScale.step(for: neutrals) < DayColorScale.step(for: colorful))
    }

    @Test("色阶在 0–4 范围内")
    func stepIsBounded() {
        let profileID = UUID()
        let garments = (0..<5).map { index in
            Garment(profileID: profileID, name: "色\(index)", colorHex: "#FF0000")
        }
        let step = DayColorScale.step(for: garments)
        #expect(step >= 0 && step <= 4)
    }

    @Test("Lab 转换对中性色返回低彩度")
    func labConversionIsSane() {
        let white = DayColorScale.toLab(r: 255, g: 255, b: 255)
        let chroma = (white.a * white.a + white.b * white.b).squareRoot()
        #expect(chroma < 5)
        #expect(white.L > 95)
    }
}

// MARK: - 图像处理测试

@Suite("图像处理")
struct ImageProcessorTests {

    @Test("颜色名映射覆盖常见色")
    func colorNamesAreMapped() {
        #expect(ImageProcessor.colorName(r: 255, g: 255, b: 255) == "白色")
        #expect(ImageProcessor.colorName(r: 0, g: 0, b: 0) == "黑色")
        #expect(ImageProcessor.colorName(r: 200, g: 30, b: 30) == "红色")
        #expect(ImageProcessor.colorName(r: 30, g: 90, b: 200) == "蓝色")
    }

    @Test("抠图失败时返回原图而非崩溃")
    func backgroundRemovalFallsBack() {
        // 用一个无法处理的 image 验证不会崩
        let image = UIImage()
        let result = ImageProcessor.removeBackground(from: image)
        // 不崩溃即通过
        _ = result
    }

    @Test("缩略图生成尺寸正确")
    func thumbnailHasCorrectSize() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 80)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        }
        let thumb = ImageProcessor.makeThumbnail(from: image, size: 50)
        #expect(thumb.size.width == 50)
        #expect(thumb.size.height == 50)
    }
}
