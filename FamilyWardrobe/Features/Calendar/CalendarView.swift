import SwiftUI
import SwiftData

// MARK: - 日历
//
// 定稿决议 #4：**用当天主色深浅**表示记录状态，黑白二元作废。
//
// 衍生要求：
//   1. 图例常驻顶部（否则用户看不懂一片彩色格子）
//   2. 取色用 Lab 均值归一化（同一件衣服换个光线不能跳色）
//   3. 无记录 = 浅灰底无描边；有记录（哪怕素色）= 加极细描边
//      —— 否则「穿了但很素」和「没穿」分不开

struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Query private var garments: [Garment]
    @Query private var logs: [WearLog]

    let profileID: UUID?

    @State private var month = Date()
    @State private var selectedDate: Date?
    @State private var showEntry = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Metrics.groupSpacing) {
                    legendBar
                    calendarCard
                    if let selectedDate {
                        dayDetail(for: selectedDate)
                    }
                    statsCard
                }
                .padding(Theme.Metrics.screenMargin)
            }
            .background(Theme.Palette.pageBackground)
            .navigationTitle("日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("记录今天")
                }
            }
            .sheet(isPresented: $showEntry) {
                if let profileID {
                    GarmentEntryView(profileID: profileID)
                }
            }
        }
    }

    // MARK: 图例（常驻）

    private var legendBar: some View {
        HStack(spacing: 8) {
            Text("素色")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: 2) {
                ForEach(0..<DayColorScale.steps.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(DayColorScale.steps[index])
                        .frame(width: 16, height: 10)
                }
            }
            Text("多彩")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: 月视图

    private var calendarCard: some View {
        GroupCard(title: month.formatted(.dateTime.year().month(.wide)), count: monthLogs.count, unit: "天") {
            VStack(spacing: 8) {
                // 星期头
                HStack(spacing: 0) {
                    ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                        Text(day)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                // 日期格
                let days = monthDays()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(days, id: \.self) { date in
                        if let date {
                            dayCell(date)
                        } else {
                            Color.clear.frame(height: 40)
                        }
                    }
                }

                // 月份切换
                HStack {
                    Button {
                        month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .accessibilityLabel("上个月")
                    Spacer()
                    Button("本月") { month = Date() }
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Palette.brand)
                    Spacer()
                    Button {
                        month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .accessibilityLabel("下个月")
                }
                .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let dayLogs = logsFor(date)
        let dayGarments = garmentsFor(logs: dayLogs)
        let step = DayColorScale.step(for: dayGarments)
        let isSelected = selectedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
        let isToday = Calendar.current.isDateInToday(date)

        return Button {
            selectedDate = isSelected ? nil : date
        } label: {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 12, weight: isToday ? .medium : .regular))
                    .foregroundStyle(
                        dayLogs.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textPrimary
                    )
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(dayLogs.isEmpty ? DayColorScale.empty : DayColorScale.steps[step])
                    .frame(height: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(
                                dayLogs.isEmpty ? Color.clear : Theme.Palette.cardBorder,
                                lineWidth: 0.5
                            )
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.Palette.brand.opacity(0.12))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 月份的日期数组，前面补 nil 对齐星期
    private func monthDays() -> [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayRange = calendar.range(of: .day, in: .month, for: month) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leading)
        for day in dayRange {
            days.append(calendar.date(byAdding: .day, value: day - 1, to: interval.start))
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    // MARK: 单日详情

    @ViewBuilder
    private func dayDetail(for date: Date) -> some View {
        let dayLogs = logsFor(date)
        GroupCard(title: date.formatted(.dateTime.month().day()), count: dayLogs.count, unit: "条") {
            if dayLogs.isEmpty {
                Text("这天没有记录")
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dayLogs.enumerated()), id: \.element.id) { index, log in
                        if index > 0 {
                            Rectangle().fill(Theme.Palette.separator).frame(height: 0.5)
                        }
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.occasion.displayName)
                                    .font(Theme.Typo.body)
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                Text("\(log.garmentIDs.count) 件")
                                    .font(Theme.Typo.caption)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(log.garmentIDs.prefix(4), id: \.self) { id in
                                    if let garment = garmentIndex[id] {
                                        ThumbnailTile(
                                            image: AssetStore.shared.thumbnail(for: garment),
                                            placeholderSymbol: garment.layer.placeholderSymbol
                                        )
                                        .frame(width: 30, height: 30)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    // MARK: 月度统计

    private var statsCard: some View {
        GroupCard(title: "本月概览", count: 3, unit: "项") {
            HStack(spacing: 0) {
                metricBlock("记录天数", "\(monthLogs.count)")
                divider
                metricBlock("穿着件数", "\(monthGarmentIDs.count)")
                divider
                metricBlock("日均", dailyAverage)
            }
        }
    }

    private func metricBlock(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(label)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.Palette.separator).frame(width: 0.5, height: 28)
    }

    private var dailyAverage: String {
        guard !monthLogs.isEmpty else { return "—" }
        let days = Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 30
        return String(format: "%.1f", Double(monthLogs.count) / Double(days))
    }

    // MARK: 数据

    /// 单品 ID → 单品 的索引，避免逐个线性查找
    private var garmentIndex: [UUID: Garment] {
        Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var monthLogs: [WearLog] {
        guard let profileID else { return [] }
        return logs.filter { log in
            log.profileID == profileID
            && Calendar.current.isDate(log.date, equalTo: month, toGranularity: .month)
        }
    }

    private var monthGarmentIDs: Set<UUID> {
        Set(monthLogs.flatMap(\.garmentIDs))
    }

    private func logsFor(_ date: Date) -> [WearLog] {
        guard let profileID else { return [] }
        return logs.filter { log in
            log.profileID == profileID && Calendar.current.isDate(log.date, inSameDayAs: date)
        }
    }

    private func garmentsFor(logs: [WearLog]) -> [Garment] {
        let ids = Set(logs.flatMap(\.garmentIDs))
        return garments.filter { ids.contains($0.id) }
    }
}
