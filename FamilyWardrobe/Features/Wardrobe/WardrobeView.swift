import SwiftUI
import SwiftData

// MARK: - 衣橱页
//
// 参考样式实现：
//   - 导航栏右侧：搜索 / 网格 / 更多
//   - 分段控件：单品 / 组合
//   - 每层一张独立白卡，组头是「层级名 · N 件」+ 排序按钮
//   - 卡内横向滑动，缩略图不叠文字
//   - 右下角悬浮「+」
//
// 单品视图按穿戴层级正序（头→脚），组合视图按场合分组。
// 两者共用 GroupCard / ThumbnailRow / OutfitCard 组件。

struct WardrobeView: View {
    @Environment(\.modelContext) private var context
    @Query private var garments: [Garment]
    @Query private var outfits: [Outfit]

    @State private var segment = 0
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showGridMode = false
    @State private var selectedGarment: Garment?
    @State private var sortTarget: LayerSortTarget?

    private let profileID: UUID

    init(profileID: UUID) {
        self.profileID = profileID
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: Theme.Metrics.groupSpacing) {
                        SegmentedBar(options: ["单品", "组合"], selection: $segment)
                            .padding(.horizontal, Theme.Metrics.screenMargin)
                            .padding(.top, 4)

                        if segment == 0 {
                            singleItemSections
                        } else {
                            outfitSections
                        }
                    }
                    .padding(.vertical, Theme.Metrics.groupSpacing)
                }
                .background(Theme.Palette.pageBackground)

                FabButton {
                    // TODO: 接 P9 单件录入
                }
                .padding(.trailing, Theme.Metrics.screenMargin + 4)
                .padding(.bottom, 12)
            }
            .navigationTitle("我的衣橱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("切换档案") { }
                        Button("档案详情") { }
                    } label: {
                        HStack(spacing: 4) {
                            Text("我的衣橱")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(Theme.Typo.navTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation { showSearch.toggle() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("搜索")

                    Button {
                        showGridMode.toggle()
                    } label: {
                        Image(systemName: showGridMode ? "list.bullet" : "square.grid.2x2")
                    }
                    .accessibilityLabel("切换布局")

                    Menu {
                        Button("批量录入") { }
                        Button("筛选") { }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多")
                }
            }
            .sheet(item: $selectedGarment) { garment in
                GarmentDetailView(garment: garment)
            }
            .confirmationDialog(
                "排序方式",
                isPresented: Binding(
                    get: { sortTarget != nil },
                    set: { if !$0 { sortTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let target = sortTarget {
                    Button("穿着次数") { }
                    Button("最近穿") { }
                    Button("价格") { }
                    Button("名称") { }
                }
                Button("取消", role: .cancel) { sortTarget = nil }
            }
        }
    }

    // MARK: 单品视图

    @ViewBuilder
    private var singleItemSections: some View {
        let filtered = filteredGarments
        ForEach(WearLayer.allCases) { layer in
            let items = items(in: layer, from: filtered)
            if !items.isEmpty {
                GroupCard(
                    title: layer.displayName,
                    count: items.count,
                    onSort: { sortTarget = LayerSortTarget(layer: layer) }
                ) {
                    ThumbnailRow(items: items) { garment in
                        Button {
                            selectedGarment = garment
                        } label: {
                            ThumbnailTile(
                                image: AssetStore.shared.thumbnail(for: garment),
                                placeholderSymbol: layer.placeholderSymbol
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("查看详情") { selectedGarment = garment }
                            Button("删除", role: .destructive) { }
                        }
                    }
                }
            }
        }
    }

    // MARK: 组合视图

    @ViewBuilder
    private var outfitSections: some View {
        ForEach(Occasion.allCases) { occasion in
            let items = outfits.filter { $0.profileID == profileID && $0.occasion == occasion }
            if !items.isEmpty {
                GroupCard(
                    title: occasion.displayName,
                    count: items.count,
                    unit: "套"
                ) {
                    ThumbnailRow(items: items) { outfit in
                        OutfitCard(
                            name: outfit.name,
                            wearCount: outfit.wearCount,
                            memberImages: outfit.garmentIDs.compactMap { id in
                                garments.first { $0.id == id }.flatMap { AssetStore.shared.thumbnail(for: $0) }
                            },
                            memberSymbols: outfit.garmentIDs.map { id in
                                garments.first { $0.id == id }?.layer.placeholderSymbol ?? "tshirt.fill"
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: 数据

    private var filteredGarments: [Garment] {
        garments.filter { garment in
            guard garment.profileID == profileID, !garment.archived else { return false }
            if !searchText.isEmpty {
                return garment.name.localizedStandardContains(searchText)
                    || (garment.brand?.localizedStandardContains(searchText) ?? false)
                    || garment.colorName.localizedStandardContains(searchText)
            }
            return true
        }
    }

    private func items(in layer: WearLayer, from source: [Garment]) -> [Garment] {
        source
            .filter { $0.layer == layer }
            .sorted { lhs, rhs in
                // 默认：穿着次数降序。最常用的排最左边，日常最先拿的不用翻。
                if lhs.wearCount != rhs.wearCount { return lhs.wearCount > rhs.wearCount }
                return lhs.name < rhs.name
            }
    }
}

// MARK: - 排序目标

struct LayerSortTarget: Identifiable {
    let id = UUID()
    let layer: WearLayer
}

// MARK: - 单品详情占位

struct GarmentDetailView: View {
    let garment: Garment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ThumbnailTile(
                    image: AssetStore.shared.thumbnail(for: garment),
                    placeholderSymbol: garment.layer.placeholderSymbol
                )
                .frame(width: 160, height: 160)

                Text(garment.name)
                    .font(.system(size: 15, weight: .medium))

                Text("穿 \(garment.wearCount) 次")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.pageBackground)
            .navigationTitle("单品详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
