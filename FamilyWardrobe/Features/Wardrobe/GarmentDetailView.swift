import SwiftUI
import SwiftData

// MARK: - 单品详情
//
// **「记得清」这个核心价值的主要承载页面。**
// 定稿决议 #3：不折叠，11 行属性全量平铺。
//
// 为什么不能折叠：折叠 = 用户要多点一次 = 数据被藏起来。
// 这个页面存在的意义就是「一眼看完这件衣服的全部信息」。

struct GarmentDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var garment: Garment
    @Query private var logs: [WearLog]

    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showArchiveConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Metrics.groupSpacing) {
                headerCard
                statsCard
                attributesCard
                heatmapCard
                historyCard
                actionsCard
            }
            .padding(Theme.Metrics.screenMargin)
        }
        .background(Theme.Palette.pageBackground)
        .navigationTitle(garment.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑") { showEdit = true }
                    Button("收藏") { garment.favorite.toggle() }
                    Button("归档") { showArchiveConfirm = true }
                    Button("删除", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            GarmentEditView(garment: garment)
        }
        .confirmationDialog("确定删除这件衣服？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteGarment() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("记录会保留，但衣服本身会消失。")
        }
        .confirmationDialog("归档这件衣服？", isPresented: $showArchiveConfirm, titleVisibility: .visible) {
            Button("归档") {
                garment.archived = true
                try? context.save()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("归档后不再参与推荐，但历史记录和统计保留。")
        }
    }

    // MARK: 大图

    private var headerCard: some View {
        GroupCard(title: "", count: 0, unit: "") {
            VStack(spacing: 12) {
                if let image = AssetStore.shared.thumbnail(for: garment) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 260)
                } else {
                    Image(systemName: garment.layer.placeholderSymbol)
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(height: 180)
                }

                HStack(spacing: 8) {
                    CapsuleChip(title: garment.layer.displayName, isSelected: true) {}
                    if garment.favorite {
                        CapsuleChip(title: "收藏", isSelected: false) {}
                    }
                    if garment.archived {
                        CapsuleChip(title: "已归档", isSelected: false) {}
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: 核心指标

    private var statsCard: some View {
        GroupCard(title: "穿着统计", count: 3, unit: "项") {
            HStack(spacing: 0) {
                metricBlock("穿着次数", "\(garment.wearCount)")
                metricDivider
                metricBlock("单次成本", costPerWear)
                metricDivider
                metricBlock("最近穿", lastWornText)
            }
        }
    }

    private func metricBlock(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Theme.Palette.separator)
            .frame(width: 0.5, height: 28)
    }

    private var costPerWear: String {
        guard let price = garment.price, price > 0, garment.wearCount > 0 else { return "—" }
        return String(format: "¥%.1f", price / Double(garment.wearCount))
    }

    private var lastWornText: String {
        guard let last = garment.lastWornDate else { return "未穿" }
        let days = Int(Date().timeIntervalSince(last) / 86_400)
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days < 30 { return "\(days) 天前" }
        return "\(days / 30) 个月前"
    }

    // MARK: 11 行属性（全量平铺）

    private var attributesCard: some View {
        GroupCard(title: "属性", count: 11, unit: "项") {
            VStack(spacing: 0) {
                attributeRow("颜色", garment.colorName.isEmpty ? "未填" : garment.colorName)
                divider
                attributeRow("品类", garment.layer.displayName)
                divider
                attributeRow("图案", garment.pattern.displayName)
                divider
                attributeRow("材质", garment.material.displayName)
                divider
                attributeRow("厚薄", garment.thickness.displayName)
                divider
                attributeRow("版型", garment.fit.displayName)
                divider
                attributeRow("场合", garment.occasions.isEmpty ? "未填" : garment.occasions.map(\.displayName).joined(separator: "、"))
                divider
                attributeRow("季节", garment.seasons.isEmpty ? "未填" : garment.seasons.map(\.displayName).joined(separator: "、"))
                divider
                attributeRow("价格", garment.price.map { String(format: "¥%.0f", $0) } ?? "未填")
                divider
                attributeRow("品牌", garment.brand ?? "未填")
                divider
                attributeRow("购入日期", garment.purchaseDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "未填")
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.Palette.separator).frame(height: 0.5)
    }

    private func attributeRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
    }

    // MARK: 12 周穿着热力

    private var heatmapCard: some View {
        GroupCard(title: "近 12 周", count: 12, unit: "周") {
            let weeks = weeklyWearCounts()
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(weeks.reversed().indices, id: \.self) { index in
                        let count = weeks.reversed()[index]
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(heatColor(count: count))
                            .frame(height: 18)
                    }
                }
                HStack {
                    Text("84 天前")
                    Spacer()
                    Text("今天")
                }
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    /// 每周穿着次数
    private func weeklyWearCounts() -> [Int] {
        let garmentID = garment.id
        let logs = logs.filter { $0.garmentIDs.contains(garmentID) }
        let calendar = Calendar.current
        let now = Date()

        return (0..<12).map { weekOffset in
            let end = now.addingTimeInterval(-Double(weekOffset) * 7 * 86_400)
            let start = end.addingTimeInterval(-7 * 86_400)
            return logs.filter { log in
                log.date >= start && log.date < end
            }.count
        }
    }

    private func heatColor(count: Int) -> Color {
        switch count {
        case 0: return Theme.Palette.thumbnailFill
        case 1: return Color(hex: 0xB5D4F4)
        case 2: return Color(hex: 0x85B7EB)
        case 3: return Color(hex: 0x4C63E6)
        default: return Color(hex: 0x26215C)
        }
    }

    // MARK: 穿着历史

    private var historyCard: some View {
        let garmentID = garment.id
        let related = logs
            .filter { $0.garmentIDs.contains(garmentID) }
            .sorted { $0.date > $1.date }
            .prefix(10)

        return GroupCard(title: "穿着记录", count: related.count, unit: "条") {
            if related.isEmpty {
                Text("还没有穿过这件")
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(related.enumerated()), id: \.element.id) { index, log in
                        if index > 0 { divider }
                        HStack {
                            Text(log.date.formatted(date: .abbreviated, time: .omitted))
                                .font(Theme.Typo.body)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Spacer()
                            Text(log.occasion.displayName)
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    // MARK: 操作区

    private var actionsCard: some View {
        GroupCard(title: "操作", count: 2, unit: "项") {
            VStack(spacing: 8) {
                Button {
                    showEdit = true
                } label: {
                    Text("编辑属性")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.Palette.buttonFill)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    showArchiveConfirm = true
                } label: {
                    Text(garment.archived ? "取消归档" : "归档")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.Palette.buttonFill)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 删除

    private func deleteGarment() {
        // 软删除优先：归档即可保留历史。真正删除走这里。
        context.delete(garment)
        try? context.save()
        AssetStore.shared.deleteAll(for: garment.id)
        dismiss()
    }
}

// MARK: - 编辑单品

struct GarmentEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var garment: Garment

    @State private var name: String = ""
    @State private var layer: WearLayer = .top
    @State private var colorName: String = ""
    @State private var colorHex: String = "#CCCCCC"
    @State private var occasions: Set<Occasion> = []
    @State private var seasons: Set<Season> = []
    @State private var thickness: Thickness = .medium
    @State private var fit: Fit = .regular
    @State private var material: Material = .cotton
    @State private var pattern: Pattern = .solid
    @State private var price: String = ""
    @State private var brand: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
                    Picker("品类", selection: $layer) {
                        ForEach(WearLayer.allCases) { Text($0.displayName).tag($0) }
                    }
                    TextField("颜色名", text: $colorName)
                }

                Section("场合与季节") {
                    ForEach(Occasion.allCases) { item in
                        Toggle(item.displayName, isOn: Binding(
                            get: { occasions.contains(item) },
                            set: { on in
                                if on { occasions.insert(item) } else { occasions.remove(item) }
                            }
                        ))
                    }
                    ForEach(Season.allCases) { item in
                        Toggle(item.displayName, isOn: Binding(
                            get: { seasons.contains(item) },
                            set: { on in
                                if on { seasons.insert(item) } else { seasons.remove(item) }
                            }
                        ))
                    }
                }

                Section("属性") {
                    Picker("图案", selection: $pattern) {
                        ForEach(Pattern.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("材质", selection: $material) {
                        ForEach(Material.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("厚薄", selection: $thickness) {
                        ForEach(Thickness.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("版型", selection: $fit) {
                        ForEach(Fit.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                Section("购入信息") {
                    TextField("价格", text: $price)
                        .keyboardType(.decimalPad)
                    TextField("品牌", text: $brand)
                }
            }
            .navigationTitle("编辑单品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        name = garment.name
        layer = garment.layer
        colorName = garment.colorName
        colorHex = garment.colorHex
        occasions = Set(garment.occasions)
        seasons = Set(garment.seasons)
        thickness = garment.thickness
        fit = garment.fit
        material = garment.material
        pattern = garment.pattern
        price = garment.price.map { String(format: "%.0f", $0) } ?? ""
        brand = garment.brand ?? ""
    }

    private func save() {
        garment.name = name.trimmingCharacters(in: .whitespaces)
        garment.layer = layer
        garment.colorName = colorName
        garment.colorHex = colorHex
        garment.occasionRaws = occasions.map(\.rawValue)
        garment.seasonRaws = seasons.map(\.rawValue)
        garment.thicknessRaw = thickness.rawValue
        garment.fitRaw = fit.rawValue
        garment.materialRaw = material.rawValue
        garment.patternRaw = pattern.rawValue
        garment.price = Double(price)
        garment.brand = brand.isEmpty ? nil : brand
        garment.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}
