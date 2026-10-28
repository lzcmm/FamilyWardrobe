import SwiftUI
import SwiftData

// MARK: - 统计总览
//
// 「记得清」最终要变成**看得见的数据**。这里是数据的出口。
//
// 三个核心问题：
//   1. 我有什么？（品类分布、颜色分布）
//   2. 我穿了多少？（总次数、频率）
//   3. 哪些该处理？（闲置、只穿过一次）

struct StatisticsView: View {
    @Query private var garments: [Garment]
    @Query private var logs: [WearLog]

    let profileID: UUID?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Metrics.groupSpacing) {
                overviewCard
                categoryCard
                topWornCard
                idleCard
                colorCard
            }
            .padding(Theme.Metrics.screenMargin)
        }
        .background(Theme.Palette.pageBackground)
        .navigationTitle("统计")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 总览

    private var overviewCard: some View {
        GroupCard(title: "总览", count: 4, unit: "项") {
            HStack(spacing: 0) {
                metric("衣服总数", "\(profileGarments.count)", "件")
                divider
                metric("穿着总次", "\(totalWears)", "次")
                divider
                metric("记录天数", "\(profileLogs.count)", "天")
                divider
                metric("日均穿着", dailyAverage, "件")
            }
        }
    }

    private func metric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(unit)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Text(label)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.Palette.separator).frame(width: 0.5, height: 30)
    }

    // MARK: 品类分布

    private var categoryCard: some View {
        GroupCard(title: "品类分布", count: categoryData.count, unit: "类") {
            VStack(spacing: 10) {
                ForEach(categoryData, id: \.layer) { item in
                    HStack(spacing: 10) {
                        Text(item.layer.displayName)
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .frame(width: 44, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.Palette.thumbnailFill)
                                Capsule()
                                    .fill(Theme.Palette.brand.opacity(0.75))
                                    .frame(width: geo.size.width * item.ratio)
                            }
                        }
                        .frame(height: 8)

                        Text("\(item.count)")
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }
        }
    }

    private struct CategoryItem {
        let layer: WearLayer
        let count: Int
        let ratio: Double
    }

    private var categoryData: [CategoryItem] {
        let counts = WearLayer.allCases.compactMap { layer -> CategoryItem? in
            let count = profileGarments.filter { $0.layer == layer }.count
            guard count > 0 else { return nil }
            return CategoryItem(layer: layer, count: count, ratio: 0)
        }
        let maxCount = counts.map(\.count).max() ?? 1
        return counts.map { item in
            CategoryItem(layer: item.layer, count: item.count, ratio: Double(item.count) / Double(maxCount))
        }
    }

    // MARK: 最常穿

    private var topWornCard: some View {
        let top = profileGarments
            .filter { $0.wearCount > 0 }
            .sorted { $0.wearCount > $1.wearCount }
            .prefix(5)

        return GroupCard(title: "最常穿", count: top.count, unit: "件") {
            if top.isEmpty {
                Text("还没有穿着记录")
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, garment in
                        if index > 0 {
                            Rectangle().fill(Theme.Palette.separator).frame(height: 0.5)
                        }
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.Palette.textTertiary)
                                .frame(width: 14)
                            ThumbnailTile(
                                image: AssetStore.shared.thumbnail(for: garment),
                                placeholderSymbol: garment.layer.placeholderSymbol
                            )
                            Text(garment.name)
                                .font(Theme.Typo.body)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Spacer()
                            Text("\(garment.wearCount) 次")
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    // MARK: 闲置提醒

    private var idleCard: some View {
        let idle = profileGarments
            .filter { garment in
                guard let last = garment.lastWornDate else { return garment.wearCount == 0 }
                return Date().timeIntervalSince(last) / 86_400 > 90
            }
            .sorted { $0.wearCount < $1.wearCount }

        return GroupCard(title: "超过 90 天没穿", count: idle.count, unit: "件") {
            if idle.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Theme.Palette.brand)
                    Text("衣橱轮换得很好，没有闲置")
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(idle.prefix(6).enumerated()), id: \.element.id) { index, garment in
                        if index > 0 {
                            Rectangle().fill(Theme.Palette.separator).frame(height: 0.5)
                        }
                        HStack(spacing: 10) {
                            ThumbnailTile(
                                image: AssetStore.shared.thumbnail(for: garment),
                                placeholderSymbol: garment.layer.placeholderSymbol
                            )
                            Text(garment.name)
                                .font(Theme.Typo.body)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Spacer()
                            Text(garment.wearCount == 0 ? "没穿过" : "\(garment.wearCount) 次")
                                .font(Theme.Typo.caption)
                                .foregroundStyle(
                                    garment.wearCount == 0 ? Theme.Palette.brand : Theme.Palette.textSecondary
                                )
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    // MARK: 颜色分布

    private var colorCard: some View {
        let colors = Dictionary(grouping: profileGarments, by: { $0.colorName.isEmpty ? "未分类" : $0.colorName })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(8)

        return GroupCard(title: "颜色分布", count: colors.count, unit: "种") {
            if colors.isEmpty {
                Text("还没有数据")
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(colors, id: \.name) { item in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(swatchColor(for: item.name))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(Theme.Palette.cardBorder, lineWidth: 0.5))
                            Text(item.name)
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Text("\(item.count)")
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Theme.Palette.thumbnailFill)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func swatchColor(for name: String) -> Color {
        switch name {
        case "白色": return Color(hex: 0xF5F5F0)
        case "米白": return Color(hex: 0xEDE7DA)
        case "浅灰": return Color(hex: 0xD3D1C7)
        case "灰色": return Color(hex: 0x9A9A94)
        case "黑色": return Color(hex: 0x2C2C2A)
        case "米色", "卡其": return Color(hex: 0xC9A87C)
        case "棕色": return Color(hex: 0x8B6A4E)
        case "红色": return Color(hex: 0xC0392B)
        case "酒红": return Color(hex: 0x7B2E3A)
        case "粉色": return Color(hex: 0xE8B4C0)
        case "橙色": return Color(hex: 0xE08A3C)
        case "黄色": return Color(hex: 0xE8C34A)
        case "芥末黄": return Color(hex: 0xB8963A)
        case "绿色": return Color(hex: 0x4A8C5A)
        case "墨绿": return Color(hex: 0x2F5A44)
        case "青色": return Color(hex: 0x4FA8A8)
        case "蓝色": return Color(hex: 0x3E6FA8)
        case "藏青": return Color(hex: 0x2A3A5C)
        case "紫色": return Color(hex: 0x7A5CA8)
        default: return Color(hex: 0xC7C7CC)
        }
    }

    // MARK: 数据

    private var profileGarments: [Garment] {
        guard let profileID else { return [] }
        return garments.filter { $0.profileID == profileID && !$0.archived }
    }

    private var profileLogs: [WearLog] {
        guard let profileID else { return [] }
        return logs.filter { $0.profileID == profileID }
    }

    private var totalWears: Int {
        profileLogs.reduce(0) { $0 + $1.garmentIDs.count }
    }

    private var dailyAverage: String {
        guard !profileLogs.isEmpty else { return "—" }
        let days = max(1, daysSinceFirstLog)
        return String(format: "%.1f", Double(totalWears) / Double(days))
    }

    private var daysSinceFirstLog: Int {
        guard let first = profileLogs.map(\.date).min() else { return 1 }
        let days = Int(Date().timeIntervalSince(first) / 86_400) + 1
        return max(1, days)
    }
}

// MARK: - 流式布局
//
// SwiftUI 没有内置的流式布局。用 Layout 协议实现（iOS 16+）。

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentRowWidth = 0
            }
            rows[rows.count - 1].append(size)
            currentRowWidth += size.width + spacing
        }

        let height = rows.reduce(CGFloat(0)) { total, row in
            total + (row.map(\.height).max() ?? 0) + (rows.count > 1 ? spacing : 0)
        }

        return CGSize(width: maxWidth == .infinity ? currentRowWidth : maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
