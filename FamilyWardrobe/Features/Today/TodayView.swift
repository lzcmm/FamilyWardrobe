import SwiftUI
import SwiftData

// MARK: - 今天
//
// 今日推荐 + 快速取件。四宫格位置已定稿（推荐卡在上、四宫格在下）。

struct TodayView: View {
    let profileID: UUID?

    @State private var occasion: Occasion = .commute

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Metrics.groupSpacing) {
                    occasionPicker

                    GroupCard(title: "今日推荐", count: 5, unit: "套") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("推荐引擎将在 M4 交付")
                                .font(Theme.Typo.body)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupCard(title: "快速取件", count: 4, unit: "件") {
                        HStack(spacing: Theme.Metrics.thumbnailSpacing) {
                            ForEach(0..<4, id: \.self) { _ in
                                ThumbnailTile(image: nil, placeholderSymbol: "tshirt.fill")
                            }
                        }
                    }
                }
                .padding(Theme.Metrics.screenMargin)
            }
            .background(Theme.Palette.pageBackground)
            .navigationTitle("今天")
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
}

// MARK: - 日历

struct CalendarView: View {
    let profileID: UUID?
    @Query private var logs: [WearLog]

    init(profileID: UUID?) {
        self.profileID = profileID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Metrics.groupSpacing) {
                    GroupCard(title: "本月记录", count: logs.count, unit: "天") {
                        Text("日历视图将在 M2 交付")
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Theme.Metrics.screenMargin)
            }
            .background(Theme.Palette.pageBackground)
            .navigationTitle("日历")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 灵感
//
// 随机搭配 + 试衣间入口。M5/M6 交付。

struct InspirationView: View {
    let profileID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Metrics.groupSpacing) {
                    GroupCard(title: "随机搭配", count: 3, unit: "套") {
                        Text("协调随机将在 M4 交付")
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupCard(title: "试衣间", count: 0, unit: "张") {
                        Text("写实换装将在 M6 交付")
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Theme.Metrics.screenMargin)
            }
            .background(Theme.Palette.pageBackground)
            .navigationTitle("灵感")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
