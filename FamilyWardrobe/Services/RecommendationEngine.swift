import Foundation
import SwiftData

// MARK: - 推荐引擎
//
// 为什么用规则打分而不用大模型：
//   1. 一百多件衣服的组合空间不大，穷举 + 打分足够
//   2. 用户的偏好高度个性化且稳定，规则可以持续积累
//   3. 离线、无延迟、不耗电、不发热
//   4. **每条推荐都能给出可验证的理由** —— 这是规则引擎的天然优势
//
// 核心设计：**理由必须是可验证的一句话**。
//   ✅「全身仅 2 个主色」「针织 + 光泽皮面，材质有对比」
//   ❌「很适合你」「很有气质」
//   不可验证的形容词会让推荐变成玄学，用户就不信了。

struct RecommendationEngine {

    // MARK: 结果类型

    /// 一套推荐
    struct Recommendation {
        let garments: [Garment]
        let score: Double
        let reasons: [Reason]
        let occasion: Occasion
    }

    /// 一条理由（必须可验证）
    struct Reason {
        enum Kind {
            case harmony       // 色彩和谐
            case proportion    // 比例
            case material      // 材质对比
            case completeness  // 完整度
            case freshness     // 唤醒闲置
            case preference    // 偏好匹配
        }

        let kind: Kind
        let text: String
    }

    // MARK: 参数

    /// 层内排序方式
    enum SortMode: String, CaseIterable, Identifiable {
        case wearCount = "穿着次数"
        case recent = "最近穿"
        case price = "价格"
        case name = "名称"

        var id: String { rawValue }
    }

    /// 评分权重。调这些就能改变推荐风格。
    struct Weights {
        var colorHarmony: Double = 30
        var proportion: Double = 20
        var materialContrast: Double = 15
        var completeness: Double = 20
        var freshness: Double = 10
        var preference: Double = 15
    }

    var weights = Weights()

    // MARK: 主入口

    /// 生成推荐。
    ///
    /// 流程：按场合过滤 → 按层级分桶 → 组合候选 → 打分 → 取最优。
    /// 候选上限 `maxCandidates` 控制计算量：一百多件衣服的全组合
    /// 是百万级，逐个打分会卡。所以先按层各取前 N 个候选，
    /// 再从这些候选里组合 —— 组合数降到 (N^层数) 量级。
    func recommend(
        from garments: [Garment],
        occasion: Occasion,
        season: Season,
        profileID: UUID,
        recentIDs: Set<UUID>,
        maxCandidates: Int = 12,
        limit: Int = 5
    ) -> [Recommendation] {

        // 过滤候选池。
        //
        // ⚠️ 每一项都单独判断，不要用 `&&`/`||` 混写 ——
        // `&&` 优先级高于 `||`，混写会导致「非当前档案的单品」混入池子。
        // 这是数据隔离漏洞，家人共用时会把别人的衣服推荐出来。
        let pool = garments.filter { garment in
            // 档案隔离
            guard garment.profileID == profileID else { return false }
            // 已归档的不参与
            guard !garment.archived else { return false }
            // 季节：没标季节视为四季通用
            guard garment.seasons.isEmpty || garment.seasons.contains(season.rawValue) else {
                return false
            }
            // 场合：没标场合视为通用
            guard garment.occasions.isEmpty || garment.occasions.contains(occasion.rawValue) else {
                return false
            }
            return true
        }

        guard pool.count >= 3 else { return [] }

        // 按层分桶，每桶按穿着次数降序取前 N
        var buckets: [WearLayer: [Garment]] = [:]
        for layer in WearLayer.allCases {
            let items = pool
                .filter { $0.layer == layer }
                .sorted { $0.wearCount > $1.wearCount }
            if !items.isEmpty {
                buckets[layer] = Array(items.prefix(maxCandidates))
            }
        }

        // 生成候选组合
        let tops = buckets[.top] ?? []
        let bottoms = buckets[.bottom] ?? []
        let dresses = buckets[.dress] ?? []
        let outers = buckets[.outerwear] ?? []
        let shoes = buckets[.shoes] ?? []

        var candidates: [[Garment]] = []

        // 路径一：上衣 + 下装（可搭外套）
        for top in tops {
            for bottom in bottoms {
                candidates.append([top, bottom])
                for outer in outers.prefix(4) {
                    candidates.append([top, outer, bottom])
                }
            }
        }

        // 路径二：连衣裙（可搭外套）
        for dress in dresses {
            candidates.append([dress])
            for outer in outers.prefix(4) {
                candidates.append([dress, outer])
            }
        }

        guard !candidates.isEmpty else { return [] }

        // 逐个打分
        var scored = candidates.map { combination -> Recommendation in
            evaluate(combination: combination, pool: pool, occasion: occasion, recentIDs: recentIDs)
        }

        scored.sort { $0.score > $1.score }

        // 去重：同一套里不要出现两件同层的单品
        var deduped: [Recommendation] = []
        for candidate in scored {
            let layerSet = Set(candidate.garments.map(\.layer))
            let isDuplicate = deduped.contains { existing in
                let existingIDs = Set(existing.garments.map(\.id))
                let candidateIDs = Set(candidate.garments.map(\.id))
                let overlap = existingIDs.intersection(candidateIDs)
                return !overlap.isEmpty && layerSet == Set(existing.garments.map(\.layer))
            }
            if !isDuplicate {
                deduped.append(candidate)
            }
            if deduped.count >= limit { break }
        }

        return deduped
    }

    // MARK: 随机灵感

    /// 协调随机 —— 在可行解空间内做加权随机。
    ///
    /// **纯随机是错的**：一百多件衣服里抽 5 件，九成不能穿出门。
    /// 用户试两次就会放弃这个功能。
    ///
    /// 正确做法：先按规则打分，再在高分候选里加权抽取。
    /// 权重 = f(分数, 新鲜度, 闲置天数)
    /// 结果是「没想过但穿得出门」的组合 —— 这才是灵感。
    func inspire(
        from garments: [Garment],
        occasion: Occasion,
        season: Season,
        profileID: UUID,
        recentIDs: Set<UUID>,
        count: Int = 1
    ) -> [Recommendation] {

        let scored = recommend(
            from: garments,
            occasion: occasion,
            season: season,
            profileID: profileID,
            recentIDs: recentIDs,
            limit: 30
        )

        guard !scored.isEmpty else { return [] }

        // 权重：分数越高权重越大，但闲置久的单品额外加权（唤醒闲置）
        var results: [Recommendation] = []
        var usedIDs = Set<UUID>()

        for _ in 0..<count {
            let weights = scored.map { recommendation -> Double in
                let base = max(0.01, recommendation.score / 100.0)
                let idleBonus = recommendation.garments.reduce(0.0) { sum, garment in
                    guard let last = garment.lastWornDate else { return sum + 0.5 }
                    let days = Date().timeIntervalSince(last) / 86_400
                    return sum + min(days / 30.0, 2.0) * 0.15
                }
                return base * (1 + idleBonus)
            }

            let picked = weightedPick(scored, weights: weights)
            guard let chosen = picked else { break }

            // 避免连续抽到同一套
            let signature = Set(chosen.garments.map(\.id))
            if usedIDs.contains(signature) { continue }
            usedIDs.insert(signature)

            results.append(chosen)
        }

        return results
    }

    private func weightedPick(_ items: [Recommendation], weights: [Double]) -> Recommendation? {
        let total = weights.reduce(0, +)
        guard total > 0 else { return items.first }

        var threshold = Double.random(in: 0..<total)
        for (index, item) in items.enumerated() {
            threshold -= weights[index]
            if threshold <= 0 { return item }
        }
        return items.last
    }

    // MARK: 评分

    /// 给一套组合打分，同时产出理由清单
    private func evaluate(
        combination: [Garment],
        pool: [Garment],
        occasion: Occasion,
        recentIDs: Set<UUID>
    ) -> Recommendation {

        var score = 0.0
        var reasons: [Reason] = []

        // ① 色彩和谐
        let colorResult = evaluateColor(combination)
        score += colorResult.score
        if let text = colorResult.text {
            reasons.append(Reason(kind: .harmony, text: text))
        }

        // ② 比例
        let proportionResult = evaluateProportion(combination)
        score += proportionResult.score
        if let text = proportionResult.text {
            reasons.append(Reason(kind: .proportion, text: text))
        }

        // ③ 材质对比
        let materialResult = evaluateMaterial(combination)
        score += materialResult.score
        if let text = materialResult.text {
            reasons.append(Reason(kind: .material, text: text))
        }

        // ④ 完整度
        let completenessResult = evaluateCompleteness(combination)
        score += completenessResult.score
        if let text = completenessResult.text {
            reasons.append(Reason(kind: .completeness, text: text))
        }

        // ⑤ 新鲜度 / 闲置唤醒
        let freshnessResult = evaluateFreshness(combination, recentIDs: recentIDs)
        score += freshnessResult.score
        if let text = freshnessResult.text {
            reasons.append(Reason(kind: .freshness, text: text))
        }

        // ⑥ 偏好匹配
        let preferenceResult = evaluatePreference(combination, occasion: occasion)
        score += preferenceResult.score
        if let text = preferenceResult.text {
            reasons.append(Reason(kind: .preference, text: text))
        }

        return Recommendation(
            garments: combination,
            score: min(score, 100),
            reasons: reasons,
            occasion: occasion
        )
    }

    // MARK: 各维度评估

    private struct Evaluation {
        var score: Double = 0
        var text: String?
    }

    /// ① 色彩和谐：全身主色 ≤ 3，亮色只允许一处
    private func evaluateColor(_ garments: [Garment]) -> Evaluation {
        let colors = garments.compactMap { guessColor(for: $0) }
        guard !colors.isEmpty else { return Evaluation() }

        let distinct = Set(colors.map(\.name))
        var score = weights.colorHarmony
        var text: String?

        if distinct.count <= 3 {
            text = "全身仅 \(distinct.count) 个主色"
        } else {
            let excess = Double(distinct.count - 3)
            score -= excess * 8
            text = "有 \(distinct.count) 个主色，偏多"
        }

        // 亮色只允许一处
        let brightCount = colors.filter(\.isBright).count
        if brightCount > 1 {
            score -= Double(brightCount - 1) * 6
        }

        // 中性色是万能胶，加分
        let neutralCount = colors.filter(\.isNeutral).count
        if neutralCount > 0 {
            score += 3
        }

        return Evaluation(score: max(0, score), text: text)
    }

    /// ② 比例：上短下长 / 宽窄对比
    private func evaluateProportion(_ garments: [Garment]) -> Evaluation {
        let layers = Set(garments.map(\.layer))
        var score = weights.proportion
        var text: String?

        let hasTop = layers.contains(.top) || layers.contains(.dress)
        let hasBottom = layers.contains(.bottom)
        let hasOuter = layers.contains(.outerwear)

        // 上短下长：短上衣 + 高腰下装
        if hasTop && hasBottom {
            let top = garments.first { $0.layer == .top || $0.layer == .dress }
            let bottom = garments.first { $0.layer == .bottom }
            if let top, let bottom {
                if top.fit == .slim && bottom.fit == .loose {
                    score += 6
                    text = "上窄下宽，比例拉长"
                } else if top.fit == .oversized && bottom.fit == .slim {
                    score += 4
                    text = "上宽下窄，有廓形对比"
                } else {
                    text = "上下装型接近"
                }
            }
        }

        // 外套长度与下装：短外套配长下装更协调
        if hasOuter && hasBottom {
            score += 2
        }

        return Evaluation(score: max(0, score), text: text)
    }

    /// ③ 材质对比：粗针织配光泽面料
    private func evaluateMaterial(_ garments: [Garment]) -> Evaluation {
        let materials = garments.map(\.material)
        var score = weights.materialContrast
        var text: String?

        let hasTextured = materials.contains { $0.isTextured }
        let hasGlossy = materials.contains { $0.isGlossy }

        if hasTextured && hasGlossy {
            score += 6
            text = "粗糙料配光泽面，材质有对比"
        } else if !hasTextured && !hasGlossy {
            text = "全身质地统一"
        } else {
            text = "材质偏单一"
        }

        // 全身都是针织会显臃肿
        if materials.filter({ $0 == .knit }).count >= 2 {
            score -= 5
        }

        return Evaluation(score: max(0, score), text: text)
    }

    /// ④ 完整度：通勤必须「上装 + 下装 + 正装鞋」
    private func evaluateCompleteness(_ garments: [Garment]) -> Evaluation {
        let layers = Set(garments.map(\.layer))
        var score = weights.completeness
        var text: String?

        let hasTop = layers.contains(.top) || layers.contains(.dress)
        let hasBottom = layers.contains(.bottom) || layers.contains(.dress)
        let hasShoes = layers.contains(.shoes)

        if hasTop && hasBottom && hasShoes {
            score += 8
            text = "上装 + 下装 + 鞋，配齐了"
        } else {
            let missing: [String] = []
            if !hasTop { missing.append("上衣") }
            if !hasBottom { missing.append("下装") }
            if !hasShoes { missing.append("鞋") }
            score -= Double(missing.count) * 6
            text = "还缺 \(missing.joined(separator: "、"))"
        }

        return Evaluation(score: max(0, score), text: text)
    }

    /// ⑤ 新鲜度：7 天内不重复；闲置 90 天以上额外加分
    private func evaluateFreshness(_ garments: [Garment], recentIDs: Set<UUID>) -> Evaluation {
        var score = weights.freshness
        var text: String?

        let recentHits = garments.filter { recentIDs.contains($0.id) }.count
        if recentHits > 0 {
            score -= Double(recentHits) * 15
            text = "有 \(recentHits) 件最近穿过"
        }

        // 闲置唤醒
        let idleGarments = garments.filter { garment in
            guard let last = garment.lastWornDate else { return true }
            return Date().timeIntervalSince(last) / 86_400 > 90
        }

        if !idleGarments.isEmpty {
            score += Double(idleGarments.count) * 4
            if text == nil {
                let names = idleGarments.map(\.name).joined(separator: "、")
                text = "\(names) 90 天未穿，一并唤醒"
            }
        }

        return Evaluation(score: max(0, score), text: text)
    }

    /// ⑥ 偏好匹配：场合一致 + 颜色偏好
    private func evaluatePreference(_ garments: [Garment], occasion: Occasion) -> Evaluation {
        var score = weights.preference
        var text: String?

        let matched = garments.filter { $0.occasions.contains(occasion.rawValue) }.count
        if matched == garments.count && !garments.isEmpty {
            score += 8
            text = "全部单品都适合\(occasion.displayName)"
        } else if matched > 0 {
            score += Double(matched) * 2
        }

        return Evaluation(score: max(0, score), text: text)
    }

    // MARK: 辅助

    /// 从 hex 判断颜色属性
    private func guessColor(for garment: Garment) -> (name: String, isBright: Bool, isNeutral: Bool)? {
        let hex = garment.colorHex
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard let value = UInt32(cleaned, radix: 16) else { return nil }

        let r = Int((value >> 16) & 0xFF)
        let g = Int((value >> 8) & 0xFF)
        let b = Int(value & 0xFF)

        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let luminance = (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255.0

        return (
            name: garment.colorName.isEmpty ? ImageProcessor.colorName(r: r, g: g, b: b) : garment.colorName,
            isBright: luminance > 0.72,
            isNeutral: Double(maxC - minC) < 32
        )
    }
}
