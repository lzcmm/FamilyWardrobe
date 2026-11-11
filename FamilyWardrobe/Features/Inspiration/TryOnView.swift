import SwiftUI
import SwiftData

// MARK: - 试衣间
//
// 「一键换装」需求把试衣间从「被动看结果」变成「主动玩搭配」。
//
// 两层切换入口：
//   1. **图上锚点**（主入口）—— 外套/上衣/下装/鞋各挂一个 ⇄ 按钮，
//      虚线引线指向身体部位。视线不用离开画面。
//   2. **底部槽位栏**（系统性入口）—— 固定 5 槽，每槽带 ⇄ 徽标。
//
// 空槽显示虚线边框 + 「+」号，**必须可点**。
// 否则用户看到「这搭配没外套」会以为不可编辑。
//
// 标题相应地是「加一件上衣」而不是「换上衣」。

struct TryOnView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var garments: [Garment]

    let profileID: UUID

    @State private var selected: [WearLayer: Garment] = [:]
    @State private var poseIndex = 0
    @State private var showPicker: PickerTarget?
    @State private var bodyImage: UIImage?
    @State private var composedImage: UIImage?
    @State private var isComposing = false
    @State private var showSaveSheet = false

    /// 槽位顺序 = 穿戴层级正序（头→脚）
    private let slots: [WearLayer] = [.top, .dress, .outerwear, .bottom, .shoes]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.Palette.pageBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    stage
                    slotBar
                }

                if isComposing {
                    ProgressView()
                        .controlSize(.regular)
                        .padding(20)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .navigationTitle("试衣间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("记录今天") { recordToday() }
                        Button("存为搭配") { showSaveSheet = true }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .sheet(item: $showPicker) { target in
                GarmentPickerView(
                    profileID: profileID,
                    layer: target.layer,
                    garments: garments.filter {
                        $0.profileID == profileID && $0.layer == target.layer && !$0.archived
                    },
                    onSelect: { garment in
                        select(garment, for: target.layer)
                    },
                    onRandom: {
                        randomPick(for: target.layer)
                    }
                )
            }
            .sheet(isPresented: $showSaveSheet) {
                OutfitSaveView(profileID: profileID, garments: selectedGarments)
            }
            .task { setup() }
            .onChange(of: selected) { _, _ in recompose() }
            .onChange(of: poseIndex) { _, _ in recompose() }
        }
    }

    // MARK: 舞台

    private var stage: some View {
        ZStack {
            if let composedImage {
                Image(uiImage: composedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 12)
            } else if let bodyImage {
                Image(uiImage: bodyImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 12)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Text("需要先采集底板人像")
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Text("去「设置 → 档案详情 → 体型底板」采集")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }

            // 图上锚点
            if composedImage != nil {
                anchorsOverlay
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// 图上锚点按钮 —— 主切换入口
    private var anchorsOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    ForEach([WearLayer.outerwear, .top, .bottom, .shoes], id: \.self) { layer in
                        anchorButton(for: layer)
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private func anchorButton(for layer: WearLayer) -> some View {
        Button {
            showPicker = PickerTarget(layer: layer)
        } label: {
            Image(systemName: selected[layer] == nil ? "plus" : "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected[layer] == nil ? Theme.Palette.textSecondary : Theme.Palette.brand)
                .frame(width: 30, height: 30)
                .background(.regularMaterial)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.cardBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected[layer] == nil ? "加一件\(layer.displayName)" : "换\(layer.displayName)")
    }

    // MARK: 槽位栏

    private var slotBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(slots, id: \.self) { layer in
                        slotView(layer)
                    }
                }
                .padding(.horizontal, Theme.Metrics.screenMargin)
            }

            // 姿势切换
            if bodyImage != nil {
                HStack(spacing: 6) {
                    ForEach(0..<TryOnPipeline.poseCount, id: \.self) { index in
                        Button {
                            poseIndex = index
                        } label: {
                            Text("姿势 \(index + 1)")
                                .font(Theme.Typo.caption)
                                .foregroundStyle(
                                    poseIndex == index ? .white : Theme.Palette.textSecondary
                                )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background {
                                    Capsule().fill(
                                        poseIndex == index ? Theme.Palette.brand : Theme.Palette.buttonFill
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.Metrics.screenMargin)
            }
        }
        .padding(.vertical, 12)
        .background(Theme.Palette.card)
    }

    private func slotView(_ layer: WearLayer) -> some View {
        let garment = selected[layer]
        let isCovered = isLayerCovered(layer)

        return Button {
            guard !isCovered else { return }
            showPicker = PickerTarget(layer: layer)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.Palette.thumbnailFill)

                    if let garment {
                        if let image = AssetStore.shared.thumbnail(for: garment) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(4)
                        } else {
                            Image(systemName: layer.placeholderSymbol)
                                .font(.system(size: 16, weight: .light))
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }

                        // ⇄ 徽标
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 15, height: 15)
                            .background(Theme.Palette.brand)
                            .clipShape(Circle())
                            .offset(x: 16, y: -12)
                    } else if isCovered {
                        Text("已覆盖")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    } else {
                        // 空槽：虚线边框 + 加号
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                .frame(width: 48, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            garment == nil && !isCovered ? Theme.Palette.textTertiary : Color.clear,
                            style: StrokeStyle(lineWidth: 0.5, dash: [3, 2])
                        )
                )

                Text(garment == nil && !isCovered ? "加一件\(layer.displayName)" : layer.displayName)
                    .font(.system(size: 9))
                    .foregroundStyle(
                        isCovered ? Theme.Palette.textTertiary : Theme.Palette.textSecondary
                    )
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isCovered)
    }

    /// 该层是否被连衣裙覆盖
    private func isLayerCovered(_ layer: WearLayer) -> Bool {
        guard let dress = selected[.dress] else { return false }
        return dress.coversLayers.contains(layer)
    }

    // MARK: 数据

    private var selectedGarments: [Garment] {
        WearLayer.allCases.compactMap { selected[$0] }
    }

    private func setup() {
        bodyImage = TryOnPipeline.boardImage(profileID: profileID, poseIndex: poseIndex)
        recompose()
    }

    private func select(_ garment: Garment, for layer: WearLayer) {
        selected[layer] = garment

        // 选了连衣裙 → 上衣和下装自动置为「已覆盖」
        if layer == .dress {
            selected.removeValue(forKey: .top)
            selected.removeValue(forKey: .bottom)
        }
        // 选了上衣或下装 → 取消连衣裙
        if layer == .top || layer == .bottom {
            selected.removeValue(forKey: .dress)
        }
    }

    /// 随机抽一件。**在协调池内随机**，纯随机的结果不可用率过高。
    private func randomPick(for layer: WearLayer) {
        let candidates = garments.filter {
            $0.profileID == profileID && $0.layer == layer && !$0.archived
        }
        guard !candidates.isEmpty else { return }

        // 加权：穿着次数少的新品优先（提供新鲜感），但不是完全随机
        let weights = candidates.map { garment -> Double in
            let base = 1.0
            let freshness = 1.0 + Double(min(garment.wearCount, 10)) * 0.3
            return base * freshness
        }

        let total = weights.reduce(0, +)
        var threshold = Double.random(in: 0..<total)

        for (index, garment) in candidates.enumerated() {
            threshold -= weights[index]
            if threshold <= 0 {
                select(garment, for: layer)
                return
            }
        }
        select(candidates.last!, for: layer)
    }

    private func recompose() {
        guard let bodyImage else { return }
        let garments = selectedGarments
        guard !garments.isEmpty else {
            composedImage = nil
            return
        }

        isComposing = true
        let pose = poseIndex

        // ⚠️ **绝不能用 Task.detached 传 SwiftData 模型**。
        //
        // @Model 类不是 Sendable，跨线程访问会崩溃（SwiftData 模型的
        // 存储上下文绑定在创建它的线程上）。所以先在主线程把模型
        // 转成纯值类型（图片 + ID），再交给后台线程。
        //
        // 另一个约束：UIImage 也不是 Sendable。所以这里用
        // @unchecked Sendable 包装，明确告诉编译器「我保证了线程安全」。
        let inputs = garments.compactMap { garment -> (id: UUID, image: UIImage)? in
            guard let image = TryOnPipeline.sourceImage(for: garment) else { return nil }
            return (garment.id, image)
        }

        Task {
            let body = UncheckedSendableBox(bodyImage)
            let items = inputs.map { UncheckedSendableBox($0) }

            // 后台线程只做像素运算，不碰任何 SwiftData 对象
            let result = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                TryOnPipeline.composeRaw(
                    bodyImage: body.value,
                    garmentImages: items.map { $0.value.image },
                    poseIndex: pose
                )
            }.value

            await MainActor.run {
                composedImage = result
                isComposing = false
            }
        }
    }

    /// 记录今天 —— **与今天页共用同一写入路径**
    private func recordToday() {
        let ids = selectedGarments.map(\.id)
        guard !ids.isEmpty else { return }

        WearLogService.shared.recordToday(
            profileID: profileID,
            garmentIDs: ids,
            occasion: .casual,
            fromRecommendation: false,
            context: context
        )
        dismiss()
    }
}

// MARK: - 候选面板

struct PickerTarget: Identifiable {
    let id = UUID()
    let layer: WearLayer
}

/// 品类切换候选面板（P23）
///
/// 服务三个入口：图上锚点、底部槽位、空槽 + 号。
/// 点候选即在后方预览换装效果，可以左右点着比。
/// 底部「随机换一件」在面板内直接抽，不关面板，可以连抽。
struct GarmentPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let profileID: UUID
    let layer: WearLayer
    let garments: [Garment]
    let onSelect: (Garment) -> Void
    let onRandom: () -> Void

    @State private var sortMode: RecommendationEngine.SortMode = .wearCount

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if garments.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 72), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(sortedGarments) { garment in
                                Button {
                                    onSelect(garment)
                                    dismiss()
                                } label: {
                                    VStack(spacing: 6) {
                                        ThumbnailTile(
                                            image: AssetStore.shared.thumbnail(for: garment),
                                            placeholderSymbol: layer.placeholderSymbol
                                        )
                                        .frame(width: 68, height: 68)
                                        Text(garment.name)
                                            .font(Theme.Typo.caption)
                                            .foregroundStyle(Theme.Palette.textPrimary)
                                            .lineLimit(1)
                                        Text("穿 \(garment.wearCount) 次")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Theme.Palette.textTertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Theme.Metrics.screenMargin)
                    }
                }
            }
            .background(Theme.Palette.pageBackground)
            .navigationTitle("选\(layer.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(RecommendationEngine.SortMode.allCases) { mode in
                            Button {
                                sortMode = mode
                            } label: {
                                Label(mode.rawValue, systemImage: sortMode == mode ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("排序")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        onRandom()
                    } label: {
                        Label("随机换一件\(layer.displayName)", systemImage: "shuffle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Theme.Palette.brand)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(Theme.Metrics.screenMargin)
                    .disabled(garments.isEmpty)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: layer.placeholderSymbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("没有\(layer.displayName)")
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text("先在衣橱里添加几件")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sortedGarments: [Garment] {
        switch sortMode {
        case .wearCount:
            garments.sorted { $0.wearCount > $1.wearCount }
        case .recent:
            garments.sorted { ($0.lastWornDate ?? .distantPast) > ($1.lastWornDate ?? .distantPast) }
        case .price:
            garments.sorted { ($0.price ?? .infinity) < ($1.price ?? .infinity) }
        case .name:
            garments.sorted { $0.name < $1.name }
        }
    }
}

// MARK: - 存为搭配

struct OutfitSaveView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let profileID: UUID
    let garments: [Garment]

    @State private var name = ""
    @State private var occasion: Occasion = .casual

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如：米色通勤", text: $name)
                }
                Section("场合") {
                    Picker("场合", selection: $occasion) {
                        ForEach(Occasion.allCases) { Text($0.displayName).tag($0) }
                    }
                }
                Section("包含") {
                    ForEach(garments) { garment in
                        HStack {
                            ThumbnailTile(
                                image: AssetStore.shared.thumbnail(for: garment),
                                placeholderSymbol: garment.layer.placeholderSymbol
                            )
                            .frame(width: 32, height: 32)
                            Text(garment.name)
                        }
                    }
                }
            }
            .navigationTitle("存为搭配")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadDefaultName)
        }
    }

    private func loadDefaultName() {
        guard name.isEmpty, garments.count >= 2 else { return }
        name = "\(garments[0].name) × \(garments[1].name)"
    }

    private func save() {
        let outfit = Outfit(
            profileID: profileID,
            name: name.trimmingCharacters(in: .whitespaces),
            occasion: occasion
        )
        outfit.garmentIDs = garments.map(\.id)
        context.insert(outfit)
        try? context.save()
        dismiss()
    }
}
