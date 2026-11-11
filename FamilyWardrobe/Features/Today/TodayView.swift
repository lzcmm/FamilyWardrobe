import SwiftUI
import SwiftData

// MARK: - 今天首页
//
// 留存生死线：**从推荐到记录完成 = 1 次点击**。
// 任何需要重新选单品的步骤都是设计失败。
//
// 定稿决议 #1：快速取件四宫格位置不变（推荐卡在上、四宫格在下），
// 下方历史单品改横向滚动，不占首屏黄金位。

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var garments: [Garment]
    @Query private var logs: [WearLog]

    let profileID: UUID?

    @State private var occasion: Occasion = .commute
    @State private var recommendations: [RecommendationEngine.Recommendation] = []
    @State private var showReasonDetail = false
    @State private var recordedToday = false
    @State private var showEntry = false

    private var engine = RecommendationEngine()

    init(profileID: UUID?) {
        self.profileID = profileID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Metrics.groupSpacing) {
                    dateHeader
                    occasionPicker
                    recommendationCard
                    quickPickCard
                    recentStrip
                }
                .padding(Theme.Metrics.screenMargin)
            }
            .background(Theme.Palette.pageBackground)
            .navigationTitle("今天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加衣物")
                }
            }
            .sheet(isPresented: $showEntry) {
                if let profileID {
                    GarmentEntryView(profileID: profileID)
                }
            }
            .task(id: taskKey) { loadRecommendations() }
        }
    }

    private var taskKey: String {
        "\(profileID?.uuidString ?? "")-\(occasion.rawValue)-\(garments.count)"
    }

    // MARK: 日期与档案

    private var dateHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.month(.wide).day()))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("家庭衣橱")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            if recordedToday {
                Label("已记录", systemImage: "checkmark.circle.fill")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.brand)
            }
        }
    }

    // MARK: 场合切换

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

    // MARK: 今日推荐

    private var recommendationCard: some View {
        GroupCard(title: "今日推荐", count: recommendations.count, unit: "套") {
            VStack(alignment: .leading, spacing: 12) {
                if let best = recommendations.first {
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
                        ForEach(Array(best.reasons.enumerated()), id: \.offset) { _, reason in
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
                            recordToday(best)
                        } label: {
                            Text("记录今天")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(Theme.Palette.brand)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            showReasonDetail = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .frame(width: 42, height: 42)
                                .background(Theme.Palette.buttonFill)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看推荐理由")
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("衣橱还是空的")
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Button("添加第一件衣服") { showEntry = true }
                            .font(Theme.Typo.segment)
                            .foregroundStyle(Theme.Palette.brand)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .sheet(isPresented: $showReasonDetail) {
            if let best = recommendations.first {
                ReasonDetailView(recommendation: best)
            }
        }
    }

    // MARK: 快速取件四宫格

    private var quickPickCard: some View {
        GroupCard(title: "快速取件", count: 4, unit: "件") {
            HStack(spacing: Theme.Metrics.thumbnailSpacing) {
                ForEach(Array(quickPicks.prefix(4).enumerated()), id: \.element.id) { _, garment in
                    Button {
                        recordSingle(garment)
                    } label: {
                        ThumbnailTile(
                            image: AssetStore.shared.thumbnail(for: garment),
                            placeholderSymbol: garment.layer.placeholderSymbol
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("记录穿着 \(garment.name)")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var quickPicks: [Garment] {
        guard let profileID else { return [] }
        return garments
            .filter { $0.profileID == profileID && !$0.archived }
            .sorted { ($0.lastWornDate ?? .distantPast) > ($1.lastWornDate ?? .distantPast) }
    }

    // MARK: 最近记录（横向滚动）

    private var recentStrip: some View {
        GroupCard(title: "最近记录", count: recentLogs.count, unit: "天") {
            if recentLogs.isEmpty {
                Text("还没有穿着记录")
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Metrics.thumbnailSpacing) {
                        ForEach(recentLogs) { log in
                            VStack(spacing: 4) {
                                HStack(spacing: 3) {
                                    ForEach(log.garmentIDs.prefix(3), id: \.self) { id in
                                        miniThumb(for: id)
                                    }
                                }
                                Text(log.date.formatted(.dateTime.month(.defaultDigits).day()))
                                    .font(Theme.Typo.caption)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func miniThumb(for id: UUID) -> some View {
        Group {
            if let garment = garmentIndex[id] {
                ThumbnailTile(
                    image: AssetStore.shared.thumbnail(for: garment),
                    placeholderSymbol: garment.layer.placeholderSymbol
                )
                .frame(width: 34, height: 34)
            }
        }
    }

    /// 单品 ID → 单品 的索引
    private var garmentIndex: [UUID: Garment] {
        Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var recentLogs: [WearLog] {
        guard let profileID else { return [] }
        return logs
            .filter { $0.profileID == profileID }
            .sorted { $0.date > $1.date }
            .prefix(14)
            .map { $0 }
    }

    // MARK: 数据操作

    private func loadRecommendations() {
        guard let profileID else { return }
        recommendations = engine.recommend(
            from: garments,
            occasion: occasion,
            season: currentSeason(),
            profileID: profileID,
            recentIDs: recentGarmentIDs
        )
    }

    private var recentGarmentIDs: Set<UUID> {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return Set(logs.filter { $0.date >= cutoff }.flatMap(\.garmentIDs))
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

    /// **记录今天 —— 1 次点击完成，不重选任何单品**
    private func recordToday(_ recommendation: RecommendationEngine.Recommendation) {
        guard let profileID else { return }
        WearLogService.shared.recordToday(
            profileID: profileID,
            garmentIDs: recommendation.garments.map(\.id),
            occasion: occasion,
            fromRecommendation: true,
            context: context
        )
        recordedToday = true
        loadRecommendations()
    }

    private func recordSingle(_ garment: Garment) {
        guard let profileID else { return }
        WearLogService.shared.recordToday(
            profileID: profileID,
            garmentIDs: [garment.id],
            occasion: occasion,
            fromRecommendation: false,
            context: context
        )
        recordedToday = true
    }
}

// MARK: - 推荐理由详情

struct ReasonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let recommendation: RecommendationEngine.Recommendation

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Metrics.groupSpacing) {
                    GroupCard(title: "这套为什么好", count: recommendation.reasons.count, unit: "条") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(recommendation.reasons.enumerated()), id: \.offset) { _, reason in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: icon(for: reason.kind))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.Palette.brand)
                                        .frame(width: 18)
                                    Text(reason.text)
                                        .font(Theme.Typo.body)
                                        .foregroundStyle(Theme.Palette.textPrimary)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }

                    GroupCard(title: "包含单品", count: recommendation.garments.count, unit: "件") {
                        VStack(spacing: 0) {
                            ForEach(Array(recommendation.garments.enumerated()), id: \.element.id) { index, garment in
                                if index > 0 {
                                    Rectangle().fill(Theme.Palette.separator).frame(height: 0.5)
                                }
                                HStack(spacing: 10) {
                                    ThumbnailTile(
                                        image: AssetStore.shared.thumbnail(for: garment),
                                        placeholderSymbol: garment.layer.placeholderSymbol
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(garment.name)
                                            .font(Theme.Typo.body)
                                            .foregroundStyle(Theme.Palette.textPrimary)
                                        Text("\(garment.layer.displayName) · \(garment.colorName)")
                                            .font(Theme.Typo.caption)
                                            .foregroundStyle(Theme.Palette.textSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .padding(Theme.Metrics.screenMargin)
            }
            .background(Theme.Palette.pageBackground)
            .navigationTitle("推荐理由")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func icon(for kind: RecommendationEngine.Reason.Kind) -> String {
        switch kind {
        case .harmony: "paintpalette"
        case .proportion: "arrow.up.and.down"
        case .material: "square.stack.3d.up"
        case .completeness: "checkmark.seal"
        case .freshness: "sparkles"
        case .preference: "heart"
        }
    }
}
