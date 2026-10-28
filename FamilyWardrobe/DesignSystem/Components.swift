import SwiftUI

// MARK: - 分组卡片
//
// 参考样式里的核心组件：白底分组卡 + 组头 + 卡内横滑。
// 单品视图与组合视图共用这套组件，只有分组维度不同。

struct GroupCard<Content: View>: View {
    let title: String
    let count: Int
    var unit: String = "件"
    var onSort: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Theme.Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Theme.Palette.cardBorder, lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Theme.Typo.groupTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("· \(count) \(unit)")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.textSecondary)

            Spacer(minLength: 8)

            if let onSort {
                Button(action: onSort) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 20, height: 20)
                        .background(Theme.Palette.buttonFill)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title)排序")
            }
        }
    }
}

// MARK: - 横滑缩略图行
//
// 三个硬要求：
//   1. 缩略图不叠任何文字
//   2. 行尾必须半露一张卡 + 渐隐遮罩（"还能滑"的唯一信号）
//   3. 水平滑动不影响垂直滚动

struct ThumbnailRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder var itemContent: (Item) -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Theme.Metrics.thumbnailSpacing) {
                ForEach(items) { item in
                    itemContent(item)
                }
            }
            .padding(.trailing, 4)
        }
        .scrollClipDisabled()
        .mask(alignment: .trailing) {
            // 右缘渐隐遮罩
            LinearGradient(
                colors: [.black, .black, .black.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing,
                stopPositions: [0, 0.94, 1]
            )
        }
    }
}

// MARK: - 缩略图

struct ThumbnailTile: View {
    var image: UIImage?
    var placeholderSymbol: String
    var tint: Color = Theme.Palette.textTertiary

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Metrics.thumbnailRadius, style: .continuous)
                .fill(Theme.Palette.thumbnailFill)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(tint.opacity(0.55))
            }
        }
        .frame(width: Theme.Metrics.thumbnailSize, height: Theme.Metrics.thumbnailSize)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.thumbnailRadius, style: .continuous))
    }
}

// MARK: - 分段控件

struct SegmentedBar: View {
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selection = index
                    }
                } label: {
                    Text(options[index])
                        .font(Theme.Typo.segment)
                        .foregroundStyle(
                            selection == index ? Theme.Palette.brand : Theme.Palette.textSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Metrics.segmentHeight - 4)
                        .background {
                            if selection == index {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.Palette.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Theme.Palette.cardBorder, lineWidth: 0.5)
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(hex: 0xECECEF))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.segmentHeight / 2, style: .continuous))
    }
}

// MARK: - 悬浮按钮

struct FabButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Theme.Metrics.fabDiameter, height: Theme.Metrics.fabDiameter)
                .background(Theme.Palette.brand)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加衣物")
    }
}

// MARK: - 胶囊标签

struct CapsuleChip: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typo.caption)
                .foregroundStyle(isSelected ? .white : Theme.Palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(isSelected ? Theme.Palette.brand : Theme.Palette.buttonFill)
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 组合卡片

struct OutfitCard: View {
    let name: String
    let wearCount: Int
    let memberImages: [UIImage?]
    let memberSymbols: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(Array(memberImages.enumerated()), id: \.offset) { _, image in
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Theme.Palette.thumbnailFill)
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(2)
                        }
                    }
                    .frame(width: 20, height: 20)
                }
            }

            Text(name)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)

            Text(wearCount > 0 ? "穿 \(wearCount) 次" : "未穿过")
                .font(Theme.Typo.caption)
                .foregroundStyle(
                    wearCount > 0 ? Theme.Palette.textSecondary : Theme.Palette.brand
                )
        }
        .padding(6)
        .frame(width: Theme.Metrics.outfitSize.width, height: Theme.Metrics.outfitSize.height, alignment: .topLeading)
        .background(Color(hex: 0xFAFAFB))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.outfitRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.outfitRadius, style: .continuous)
                .strokeBorder(Color(hex: 0xEDEDF0), lineWidth: 0.5)
        )
    }
}
