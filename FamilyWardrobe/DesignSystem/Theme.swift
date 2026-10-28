import SwiftUI

// MARK: - 设计系统
//
// 全 App 统一规范，见《页面清单与交互规格》第五章。
// 关键约束：
//   - 品牌蓝单页用色 ≤ 3 处
//   - 字阶只用 400 / 500 两级权重，禁用 600 / 700
//   - 缩略图不叠文字

enum Theme {

    // MARK: 色板

    enum Palette {
        /// 品牌蓝：选中态、悬浮按钮、Tab 激活
        static let brand = Color(hex: 0x4C63E6)
        /// 页面底
        static let pageBackground = Color(hex: 0xF6F6F8)
        /// 卡片白
        static let card = Color.white
        /// 正文
        static let textPrimary = Color(hex: 0x1C1C1E)
        /// 次要文字
        static let textSecondary = Color(hex: 0x9A9AA0)
        /// 三级文字 / 占位
        static let textTertiary = Color(hex: 0xC7C7CC)
        /// 按钮底
        static let buttonFill = Color(hex: 0xF2F2F5)
        /// 缩略图底
        static let thumbnailFill = Color(hex: 0xF3F3F5)
        /// 卡片描边
        static let cardBorder = Color(hex: 0xE8E8EC)
        /// 分隔线
        static let separator = Color(hex: 0xE8E8EC)
    }

    // MARK: 字阶

    enum Typo {
        /// 导航标题 14 / 500
        static let navTitle = Font.system(size: 14, weight: .medium)
        /// 组头标题 12 / 500
        static let groupTitle = Font.system(size: 12, weight: .medium)
        /// 分段、标签 12 / 500
        static let segment = Font.system(size: 12, weight: .medium)
        /// 计数、辅助 11 / 400
        static let caption = Font.system(size: 11, weight: .regular)
        /// 正文 13 / 400
        static let body = Font.system(size: 13, weight: .regular)
    }

    // MARK: 圆角与尺寸

    enum Metrics {
        /// 分组卡片圆角
        static let cardRadius: CGFloat = 12
        /// 缩略图圆角
        static let thumbnailRadius: CGFloat = 10
        /// 缩略图边长
        static let thumbnailSize: CGFloat = 52
        /// 组合卡圆角
        static let outfitRadius: CGFloat = 10
        /// 组合卡尺寸
        static let outfitSize = CGSize(width: 74, height: 76)
        /// 分段控件高度
        static let segmentHeight: CGFloat = 28
        /// 悬浮按钮直径
        static let fabDiameter: CGFloat = 42
        /// 屏幕左右边距
        static let screenMargin: CGFloat = 12
        /// 分组间距
        static let groupSpacing: CGFloat = 10
        /// 卡内缩略图间距
        static let thumbnailSpacing: CGFloat = 8
    }
}

// MARK: - Color hex 扩展

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    init(hexString: String, fallback: Color = .gray) {
        var cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard let value = UInt32(cleaned, radix: 16) else {
            self = fallback
            return
        }
        self.init(hex: value)
    }
}
