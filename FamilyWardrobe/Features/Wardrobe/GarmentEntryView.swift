import SwiftUI
import SwiftData
import PhotosUI

// MARK: - 单件录入
//
// **字段全部预填是硬要求。**
//
// 空表单让人填 8 个字段，单件录入会从 5 秒变成 2 分钟，然后你就不录了 ——
// 这是弃用率第一杀手。所以流程是：
//
//   拍照/选图 → 自动抠图 → 自动识别品类 + 取色 → 展示预填结果 → 用户只做确认
//
// 目标：≤5 秒/件。

struct GarmentEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let profileID: UUID
    /// 预设层级（从「上衣行 +」进入时带过来）
    var presetLayer: WearLayer?

    @State private var step: Step = .pick
    @State private var originalImage: UIImage?
    @State private var maskedImage: UIImage?
    @State private var thumbImage: UIImage?
    @State private var detectedColor: ImageProcessor.ColorGuess?
    @State private var detectedLayer: WearLayer?

    // 预填字段
    @State private var name = ""
    @State private var layer: WearLayer = .top
    @State private var colorName = ""
    @State private var colorHex = "#CCCCCC"
    @State private var occasions: Set<Occasion> = []
    @State private var seasons: Set<Season> = []
    @State private var thickness: Thickness = .medium
    @State private var fit: Fit = .regular
    @State private var material: Material = .cotton
    @State private var pattern: Pattern = .solid
    @State private var price: String = ""
    @State private var brand: String = ""

    @State private var photosItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var showCamera = false

    enum Step {
        case pick
        case processing
        case confirm
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .pick: pickView
                case .processing: processingView
                case .confirm: confirmView
                }
            }
            .background(Theme.Palette.pageBackground)
            .navigationTitle("添加衣物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                if step == .confirm {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") { save() }
                            .font(Theme.Typo.segment)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    if let image { process(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photosItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        process(image)
                    }
                }
            }
        }
    }

    // MARK: 第一步 · 选图

    private var pickView: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text("拍一件，存一件")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("品类、颜色会自动识别，你只需确认")
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    showCamera = true
                } label: {
                    Label("拍照", systemImage: "camera.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.Palette.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $photosItem, matching: .images) {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.Palette.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.Palette.cardBorder, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Metrics.screenMargin)
            .padding(.bottom, 24)
        }
    }

    // MARK: 第二步 · 处理中

    private var processingView: some View {
        VStack(spacing: 16) {
            if let originalImage {
                Image(uiImage: originalImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
            }
            ProgressView()
                .controlSize(.regular)
            Text("正在识别品类与颜色…")
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(Theme.Metrics.screenMargin)
    }

    // MARK: 第三步 · 确认（预填）

    private var confirmView: some View {
        ScrollView {
            VStack(spacing: Theme.Metrics.groupSpacing) {
                // 预览
                GroupCard(title: "预览", count: 1, unit: "张") {
                    HStack(spacing: 12) {
                        if let thumbImage {
                            Image(uiImage: thumbImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("已自动填充")
                                .font(Theme.Typo.segment)
                                .foregroundStyle(Theme.Palette.brand)
                            Text("下面每一项都可以改")
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        Spacer()
                    }
                }

                // 7 行字段
                GroupCard(title: "属性", count: 7, unit: "项") {
                    VStack(spacing: 0) {
                        fieldRow("名称") {
                            TextField("例如：米色风衣", text: $name)
                                .multilineTextAlignment(.trailing)
                                .font(Theme.Typo.body)
                        }
                        divider
                        fieldRow("颜色") {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hexString: colorHex))
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().strokeBorder(Theme.Palette.cardBorder, lineWidth: 0.5))
                                TextField("颜色名", text: $colorName)
                                    .multilineTextAlignment(.trailing)
                                    .font(Theme.Typo.body)
                            }
                        }
                        divider
                        fieldRow("品类") {
                            Picker("品类", selection: $layer) {
                                ForEach(WearLayer.allCases) { item in
                                    Text(item.displayName).tag(item)
                                }
                            }
                            .labelsHidden()
                            .tint(Theme.Palette.brand)
                        }
                        divider
                        fieldRow("场合") {
                            Menu {
                                ForEach(Occasion.allCases) { item in
                                    Button {
                                        toggle(&occasions, item)
                                    } label: {
                                        Label(
                                            item.displayName,
                                            systemImage: occasions.contains(item) ? "checkmark" : ""
                                        )
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(occasions.isEmpty ? "未选择" : "\(occasions.count) 项")
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9))
                                }
                                .font(Theme.Typo.body)
                                .foregroundStyle(occasions.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textPrimary)
                            }
                        }
                        divider
                        fieldRow("季节") {
                            Menu {
                                ForEach(Season.allCases) { item in
                                    Button {
                                        toggle(&seasons, item)
                                    } label: {
                                        Label(
                                            item.displayName,
                                            systemImage: seasons.contains(item) ? "checkmark" : ""
                                        )
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(seasons.isEmpty ? "未选择" : "\(seasons.count) 项")
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9))
                                }
                                .font(Theme.Typo.body)
                                .foregroundStyle(seasons.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textPrimary)
                            }
                        }
                        divider
                        fieldRow("厚薄 / 版型") {
                            HStack(spacing: 8) {
                                Picker("", selection: $thickness) {
                                    ForEach(Thickness.allCases) { item in
                                        Text(item.displayName).tag(item)
                                    }
                                }
                                .labelsHidden()
                                .tint(Theme.Palette.brand)
                                Picker("", selection: $fit) {
                                    ForEach(Fit.allCases) { item in
                                        Text(item.displayName).tag(item)
                                    }
                                }
                                .labelsHidden()
                                .tint(Theme.Palette.brand)
                            }
                        }
                        divider
                        fieldRow("价格 / 品牌") {
                            HStack(spacing: 8) {
                                TextField("价格", text: $price)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(Theme.Typo.body)
                                    .frame(width: 60)
                                TextField("品牌", text: $brand)
                                    .multilineTextAlignment(.trailing)
                                    .font(Theme.Typo.body)
                            }
                        }
                    }
                }
            }
            .padding(Theme.Metrics.screenMargin)
        }
    }

    // MARK: 组件

    private var divider: some View {
        Rectangle()
            .fill(Theme.Palette.separator)
            .frame(height: 0.5)
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer(minLength: 12)
            content()
        }
        .padding(.vertical, 11)
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ item: T) {
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
    }

    // MARK: 处理流程

    private func process(_ image: UIImage) {
        step = .processing
        isProcessing = true
        originalImage = image

        Task {
            // 抠图
            let masked = ImageProcessor.removeBackground(from: image)
            maskedImage = masked

            // 品类识别
            let guess = ImageProcessor.guessCategory(from: masked)
            detectedLayer = guess.layer

            // 主色提取
            let color = ImageProcessor.extractDominantColor(from: masked)
            detectedColor = color

            // 缩略图
            let thumb = ImageProcessor.makeThumbnail(from: masked)

            await MainActor.run {
                maskedImage = masked
                thumbImage = thumb
                detectedLayer = guess.layer
                detectedColor = color

                // 预填
                layer = presetLayer ?? guess.layer
                colorName = color.name
                colorHex = color.hex
                name = defaultName(for: guess.layer, color: color)

                // 按季节预填当前季节
                let current = currentSeason()
                seasons = [current]

                step = .confirm
                isProcessing = false
            }
        }
    }

    /// 自动生成名称：「米色风衣」这种形式，比「未命名外套」有用得多
    private func defaultName(for layer: WearLayer, color: ImageProcessor.ColorGuess) -> String {
        let colorWord: String
        switch color.name {
        case "白色", "米白": colorWord = "白"
        case "浅灰", "灰色": colorWord = "灰"
        case "黑色": colorWord = "黑"
        case "卡其", "棕色", "芥末黄": colorWord = "卡其"
        default: colorWord = color.name
        }
        return "\(colorWord)\(layer.displayName)"
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

    // MARK: 保存

    private func save() {
        let garment = Garment(
            profileID: profileID,
            name: name.trimmingCharacters(in: .whitespaces),
            layer: layer,
            colorName: colorName,
            colorHex: colorHex
        )
        garment.patternRaw = pattern.rawValue
        garment.materialRaw = material.rawValue
        garment.thicknessRaw = thickness.rawValue
        garment.fitRaw = fit.rawValue
        garment.occasionRaws = occasions.map(\.rawValue)
        garment.seasonRaws = seasons.map(\.rawValue)
        garment.brand = brand.isEmpty ? nil : brand
        garment.price = Double(price)

        // 存照片
        if let originalImage {
            garment.photoPath = AssetStore.shared.save(image: originalImage, for: garment.id, kind: .original)
        }
        if let maskedImage {
            garment.maskPath = AssetStore.shared.save(image: maskedImage, for: garment.id, kind: .mask, compress: 0.9)
        }
        if let thumbImage {
            garment.thumbPath = AssetStore.shared.save(image: thumbImage, for: garment.id, kind: .thumb)
        }

        context.insert(garment)
        try? context.save()
        dismiss()
    }
}

// MARK: - 相机取景器

struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void

        init(onCapture: @escaping (UIImage?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
