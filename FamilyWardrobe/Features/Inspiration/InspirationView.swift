import SwiftUI
import SwiftData

// MARK: - 灵感
//
// 两个能力：
//   1. **随机搭配** —— 没想法时给灵感
//   2. **试衣间入口** —— 看穿在自己身上什么样
//
// 随机不是纯随机（纯随机九成不能穿出门，用户试两次就放弃）。
// 是在规则打分后的协调候选池内做**加权随机**，给的是
// 「没想过但穿得出门」的组合。

struct InspirationView: View {
    @Environment(\.modelContext) private var context
    @Query private var garments: [Garment]
    @Query private var logs: [WearLog]

    let profileID: UUID?

    @State private var occasion: Occasion = .casual
    @State private var current: [RecommendationEngine.Recommendation] = []
    @State private var showTryOn = false
    @State private var savedOutfitIDs: Set<UUID> = []

    private var engine = RecommendationEngine()

    // 有 private stored property 时，自动生成的 memberwise init 会变成 private，
    // 导致 RootView 跨文件构造失败。显式声明一个 internal init。
    init(profileID: UUID?) {
        self.profileID = profileID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Metrics.groupSpacing) {
                    occasionPicker
                    inspirationCard
                    tryOnCard
                    wardrobeSnapshot
                }
                .padding(Theme.Metrics.screenMargin)
            }
            .background(Theme.Palette.pageBackground)
            .navigationTitle("灵感")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var occasionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Occasion.allCases) { item in
                    CapsuleChip(title: item.displayName, isSelected: occasion == item) {
                        occasion = item
                    }
                }
            }
        }
    }

    // MARK: 随机搭配

    private var inspirationCard: some View {
        GroupCard(title: "随机搭配", count: current.count, unit: "套") {
            VStack(alignment: .leading, spacing: 12) {
                if let best = current.first {
                    HStack(spacing: Theme.Metrics.thumbnailSpacing) {
                        ForEach(best.garments) { garment in
                            ThumbnailTile(
                                image: AssetStore.shared.thumbnail(for: garment),
                                placeholderSymbol: garment.layer.placeholderSymbol
                            )
                        }
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(best.reasons.prefix(3).enumerated()), id: \.offset) { _, reason in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.Palette.brand)
                                Text(reason.text)
                                    .font(Theme.Typo.caption)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            inspire()
                        } label: {
                            Label("换一个", systemImage: "shuffle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(Theme.Palette.brand)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            saveAsOutfit(best)
                        } label: {
                            Image(systemName: savedOutfitIDs.contains(best.garments.first?.id ?? UUID()) ? "checkmark" : "bookmark")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .frame(width: 42, height: 42)
                                .background(Theme.Palette.buttonFill)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("存为搭配")
                    }
                } else {
                    Text("衣橱里还没有足够的衣服")
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task(id: taskKey) { inspire() }
    }

    private var taskKey: String {
        "\(profileID?.uuidString ?? "")-\(occasion.rawValue)-\(garments.count)"
    }

    // MARK: 试衣间入口

    private var tryOnCard: some View {
        GroupCard(title: "试衣间", count: 0, unit: "张") {
            VStack(alignment: .leading, spacing: 12) {
                Text("换一件看看效果")
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Text("每个品类都能单独切换，没想法时随机抽一件")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)

                Button {
                    showTryOn = true
                } label: {
                    Label("进入试衣间", systemImage: "person.crop.rectangle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Theme.Palette.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(profileID == nil)
            }
        }
        .fullScreenCover(isPresented: $showTryOn) {
            if let profileID {
                TryOnView(profileID: profileID)
            }
        }
    }

    // MARK: 衣橱快照

    private var wardrobeSnapshot: some View {
        GroupCard(title: "衣橱概况", count: profileGarments.count, unit: "件") {
            VStack(spacing: 8) {
                ForEach(WearLayer.allCases) { layer in
                    let count = profileGarments.filter { $0.layer == layer }.count
                    if count > 0 {
                        HStack {
                            Text(layer.displayName)
                                .font(Theme.Typo.body)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Spacer()
                            Text("\(count) 件")
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: 数据

    private var profileGarments: [Garment] {
        guard let profileID else { return [] }
        return garments.filter { $0.profileID == profileID && !$0.archived }
    }

    private func inspire() {
        guard let profileID else { return }
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        let recentIDs = Set(logs.filter { $0.date >= cutoff }.flatMap(\.garmentIDs))

        current = engine.inspire(
            from: garments,
            occasion: occasion,
            season: currentSeason(),
            profileID: profileID,
            recentIDs: recentIDs,
            count: 1
        )
    }

    private func currentSeason() -> Season {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    private func saveAsOutfit(_ recommendation: RecommendationEngine.Recommendation) {
        guard let profileID else { return }
        let outfit = Outfit(profileID: profileID, name: outfitName(recommendation), occasion: occasion)
        outfit.garmentIDs = recommendation.garments.map(\.id)
        context.insert(outfit)
        try? context.save()

        if let first = recommendation.garments.first {
            savedOutfitIDs.insert(first.id)
        }
    }

    private func outfitName(_ recommendation: RecommendationEngine.Recommendation) -> String {
        let names = recommendation.garments.map(\.name)
        if names.count >= 2 {
            return "\(names[0]) × \(names[1])"
        }
        return names.first ?? "新搭配"
    }
}
