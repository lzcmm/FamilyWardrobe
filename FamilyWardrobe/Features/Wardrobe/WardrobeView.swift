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
    @Query private var profiles: [Profile]

    @State private var segment = 0
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showGridMode = false
    @State private var selectedGarment: Garment?
    @State private var sortTarget: LayerSortTarget?
    @State private var showEntry = false
    @State private var entryPresetLayer: WearLayer?
    @State private var showProfilePicker = false

    private let profileID: UUID
    /// 切换档案的回调（由 RootView 持有全局状态）
    var onSwitchProfile: (UUID) -> Void = { _ in }

    init(profileID: UUID, onSwitchProfile: @escaping (UUID) -> Void = { _ in }) {
        self.profileID = profileID
        self.onSwitchProfile = onSwitchProfile
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: Theme.Metrics.groupSpacing) {
                        SegmentedBar(options: ["单品", "组合"], selection: $segment)
                            .padding(.horizontal, Theme.Metrics.screenMargin)
                            .padding(.top, 4)

                        if showSearch {
                            searchBar
                                .padding(.horizontal, Theme.Metrics.screenMargin)
                        }

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
                    entryPresetLayer = nil
                    showEntry = true
                }
                .padding(.trailing, Theme.Metrics.screenMargin + 4)
                .padding(.bottom, 12)
            }
            .navigationTitle("我的衣橱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(availableProfiles) { profile in
                            Button {
                                onSwitchProfile(profile.id)
                            } label: {
                                Label(profile.name, systemImage: profile.id == profileID ? "checkmark" : "person")
                            }
                        }
                        Divider()
                        Button {
                            showProfilePicker = true
                        } label: {
                            Label("切换档案", systemImage: "person.2")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(currentProfileName)
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
                NavigationStack {
                    GarmentDetailView(garment: garment)
                }
            }
            .sheet(isPresented: $showEntry) {
                GarmentEntryView(profileID: profileID, presetLayer: entryPresetLayer)
            }
            .sheet(isPresented: $showProfilePicker) {
                ProfilePickerView { newProfileID in
                    onSwitchProfile(newProfileID)
                    showProfilePicker = false
                }
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

    // MARK: 搜索

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textSecondary)
            TextField("名称、品牌、颜色", text: $searchText)
                .font(Theme.Typo.body)
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Theme.Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: 0.5)
        )
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
                    if showGridMode {
                        gridLayout(items: items, layer: layer)
                    } else {
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
    }

    /// 网格布局 —— 快速扫描「我有多少件衣服、颜色分布」
    private func gridLayout(items: [Garment], layer: WearLayer) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: Theme.Metrics.thumbnailSpacing)], spacing: Theme.Metrics.thumbnailSpacing) {
            ForEach(items) { garment in
                Button {
                    selectedGarment = garment
                } label: {
                    ThumbnailTile(
                        image: AssetStore.shared.thumbnail(for: garment),
                        placeholderSymbol: layer.placeholderSymbol
                    )
                }
                .buttonStyle(.plain)
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
                                garmentIndex[id].flatMap { AssetStore.shared.thumbnail(for: $0) }
                            },
                            memberSymbols: outfit.garmentIDs.map { id in
                                garmentIndex[id]?.layer.placeholderSymbol ?? "tshirt.fill"
                            }
                        )
                    }
                }
            }
        }
    }

    /// 单品 ID → 单品 的索引。
    /// 组合卡片要按 ID 反查成员，如果每个成员都用 `garments.first { }` 线性扫，
    /// 一屏 9 张卡 × 3 成员 = 27 次全表扫描。预建字典后是 O(1)。
    private var garmentIndex: [UUID: Garment] {
        Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: 数据

    private var availableProfiles: [Profile] {
        profiles
    }

    private var currentProfileName: String {
        profiles.first { $0.id == profileID }?.name ?? "我的衣橱"
    }

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
