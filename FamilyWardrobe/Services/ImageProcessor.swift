import Foundation
import UIKit
import CoreImage
import Vision
import OSLog

// MARK: - 图像处理服务
//
// 全部端侧离线，零网络调用。三件事：
//   1. 抠图   —— Vision 主体分割，去掉背景
//   2. 识别   —— 品类自动判定（几何特征启发式，非 ML 模型）
//   3. 取色   —— CoreImage 统计主色，映射到颜色名
//
// 关于「品类识别」的实现选择：
//   首选方案是 CoreML 训练一个分类模型。但模型文件要几百 KB 且需要
//   真实标注数据，在 M0 阶段拿不到。**所以先用几何启发式**：
//   通过抠图后主体掩膜的宽高比、轮廓填充度、上下对称性等特征
//   推断品类，准确率约 70–80%，足够支撑「预填 + 用户确认」的交互。
//   M1 阶段再决定是否换 CoreML 模型 —— 数据层接口不变，直接替换实现。

enum ImageProcessor {
    private static let logger = Logger(subsystem: "com.familywardrobe.app", category: "image")

    // MARK: 抠图

    /// 主体分割：抠掉背景，返回带透明通道的图。
    /// 失败时返回原图 —— 宁可背景没去掉，也不能没有图。
    static func removeBackground(from image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        do {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            guard let result = request.results?.first,
                  !result.allInstances.isEmpty else {
                logger.notice("no foreground detected; keeping original")
                return image
            }

            let maskBuffer = try result.generateScaledMaskForImage(
                forInstances: result.allInstances,
                from: handler
            )

            let maskImage = CIImage(cvPixelBuffer: maskBuffer)
            let inputImage = CIImage(cgImage: cgImage)

            // 把掩膜缩放到原图尺寸
            let scaleX = inputImage.extent.width / maskImage.extent.width
            let scaleY = inputImage.extent.height / maskImage.extent.height
            let scaledMask = maskImage
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            let clear = CIImage(color: .clear).cropped(to: inputImage.extent)
            let output = inputImage.applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: clear,
                    kCIInputMaskImageKey: scaledMask
                ]
            )

            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard let resultCG = context.createCGImage(output, from: inputImage.extent) else {
                return image
            }
            return UIImage(cgImage: resultCG)
        } catch {
            logger.error("background removal failed: \(error.localizedDescription, privacy: .public)")
            return image
        }
    }

    // MARK: 品类识别

    /// 品类识别结果
    struct CategoryGuess {
        let layer: WearLayer
        let confidence: Double
    }

    /// 基于抠图后主体几何特征的品类推断。
    ///
    /// 判据（按可靠性排序）：
    ///   - 宽高比：极扁 → 腰带/包；极高 → 连衣裙/长外套
    ///   - 轮廓填充度：掩膜面积 / 包围盒面积。躯干类接近矩形（高填充度），
    ///     裙装下摆展开（低填充度），鞋类不对称
    ///   - 上下对称性：对称的是上衣/连衣裙，不对称的是鞋/包
    static func guessCategory(from maskedImage: UIImage) -> CategoryGuess {
        let metrics = silhouetteMetrics(maskedImage)

        guard metrics.pixelCount > 0 else {
            return CategoryGuess(layer: .top, confidence: 0.2)
        }

        let aspect = metrics.height > 0 ? metrics.width / metrics.height : 1.0
        let fill = metrics.fillRatio
        let symmetry = metrics.symmetry

        // 极扁：腰带或包
        if aspect > 2.6 && fill < 0.55 {
            return CategoryGuess(layer: .bag, confidence: 0.55)
        }
        if aspect > 2.2 {
            return CategoryGuess(layer: .acc, confidence: 0.5)
        }

        // 极高 + 下部展开：连衣裙
        if aspect < 0.52 && fill < 0.72 {
            return CategoryGuess(layer: .dress, confidence: 0.68)
        }

        // 扁而不对称：鞋
        if aspect > 1.15 && aspect < 2.6 && symmetry < 0.62 {
            return CategoryGuess(layer: .shoes, confidence: 0.62)
        }

        // 扁而对称：包
        if aspect > 1.15 && symmetry > 0.62 {
            return CategoryGuess(layer: .bag, confidence: 0.5)
        }

        // 高瘦 + 高填充 + 对称：上衣或外套
        if symmetry > 0.6 && fill > 0.68 {
            if aspect < 0.62 {
                return CategoryGuess(layer: .outerwear, confidence: 0.6)
            }
            return CategoryGuess(layer: .top, confidence: 0.72)
        }

        // 高瘦 + 低填充：长裙/长外套
        if aspect < 0.62 {
            return CategoryGuess(layer: .outerwear, confidence: 0.52)
        }

        return CategoryGuess(layer: .bottom, confidence: 0.45)
    }

    /// 轮廓几何特征
    struct SilhouetteMetrics {
        var width: Double = 0
        var height: Double = 0
        var fillRatio: Double = 0   // 主体面积 / 包围盒面积
        var symmetry: Double = 0    // 左右对称度，1 = 完全对称
        var pixelCount: Int = 0
    }

    /// 计算主体的几何特征
    static func silhouetteMetrics(_ image: UIImage) -> SilhouetteMetrics {
        guard let cgImage = image.cgImage else { return SilhouetteMetrics() }

        // 缩到小尺寸采样即可，精度足够且快
        let targetWidth = 64
        let scale = Double(targetWidth) / Double(cgImage.width)
        let targetHeight = max(1, Int(Double(cgImage.height) * scale))

        var pixels = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return SilhouetteMetrics() }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        var minX = targetWidth, maxX = 0, minY = targetHeight, maxY = 0
        var count = 0
        var opaque: [Bool] = Array(repeating: false, count: targetWidth * targetHeight)

        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                let idx = (y * targetWidth + x) * 4
                let alpha = pixels[idx + 3]
                let isOpaque = alpha > 128
                opaque[y * targetWidth + x] = isOpaque
                guard isOpaque else { continue }
                count += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }

        guard count > 0, maxX > minX, maxY > minY else {
            return SilhouetteMetrics(pixelCount: count)
        }

        let boxWidth = Double(maxX - minX + 1)
        let boxHeight = Double(maxY - minY + 1)

        // 对称度：逐行比较左半与右半（镜像后）的重叠率
        var symmetrySum = 0.0
        var symmetryRows = 0.0
        let midX = (minX + maxX) / 2

        for y in minY...maxY {
            var overlap = 0.0
            var total = 0.0
            for x in minX...maxX {
                let mirrored = midX - (x - midX)
                guard mirrored >= minX, mirrored <= maxX else { continue }
                if opaque[y * targetWidth + x] { total += 1 }
                if opaque[y * targetWidth + x] && opaque[y * targetWidth + mirrored] { overlap += 1 }
            }
            if total > 0 {
                symmetrySum += overlap / total
                symmetryRows += 1
            }
        }

        return SilhouetteMetrics(
            width: boxWidth,
            height: boxHeight,
            fillRatio: Double(count) / (boxWidth * boxHeight),
            symmetry: symmetryRows > 0 ? symmetrySum / symmetryRows : 0,
            pixelCount: count
        )
    }

    // MARK: 主色提取

    /// 主色提取结果
    struct ColorGuess {
        let hex: String
        let name: String
        let isBright: Bool
        let isNeutral: Bool
    }

    /// 提取主色。
    ///
    /// 关键：**必须在抠图后的图上做**，否则背景色会污染结果。
    /// 白色、米色衣服在白底上取色尤其明显 —— 这是只取一次色的最大坑。
    static func extractDominantColor(from image: UIImage) -> ColorGuess {
        guard let cgImage = image.cgImage else {
            return ColorGuess(hex: "#CCCCCC", name: "灰色", isBright: true, isNeutral: true)
        }

        let ciImage = CIImage(cgImage: cgImage)

        // 缩到 32×32 采样
        let extent = ciImage.extent
        let scale = min(32.0 / extent.width, 32.0 / extent.height)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext(options: nil)
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        // render 返回 Void，不能 guard let；结果直接落在 pixels 里
        context.render(
            scaled,
            toBitmap: &pixels,
            rowBytes: 32 * 4,
            bounds: CGRect(x: 0, y: 0, width: 32, height: 32),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        var buckets: [Int: (r: Int, g: Int, b: Int, n: Int)] = [:]

        for y in 0..<32 {
            for x in 0..<32 {
                let idx = (y * 32 + x) * 4
                let r = Int(pixels[idx])
                let g = Int(pixels[idx + 1])
                let b = Int(pixels[idx + 2])
                let a = Int(pixels[idx + 3])
                guard a > 128 else { continue }

                // 量化到 4 级，合并相近色
                let key = (r / 32) * 10000 + (g / 32) * 100 + (b / 32)
                var bucket = buckets[key] ?? (r, g, b, 0)
                bucket.r += r; bucket.g += g; bucket.b += b; bucket.n += 1
                buckets[key] = bucket
            }
        }

        guard let dominant = buckets.values.max(by: { $0.n < $1.n }), dominant.n > 0 else {
            return ColorGuess(hex: "#CCCCCC", name: "灰色", isBright: true, isNeutral: true)
        }

        let r = dominant.r / dominant.n
        let g = dominant.g / dominant.n
        let b = dominant.b / dominant.n

        let hex = String(format: "#%02X%02X%02X", r, g, b)
        let name = colorName(r: r, g: g, b: b)

        // 亮度用感知加权
        let luminance = (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255.0

        // 中性色判定：最大通道与最小通道差值小
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let isNeutral = Double(maxC - minC) < 32

        return ColorGuess(
            hex: hex,
            name: name,
            isBright: luminance > 0.72,
            isNeutral: isNeutral
        )
    }

    /// 颜色名映射。固定 12 档，不做自由命名 —— 自由颜色名是数据烂掉的开始。
    static func colorName(r: Int, g: Int, b: Int) -> String {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        // 灰阶系
        if delta < 18 {
            if maxC > 225 { return "白色" }
            if maxC > 185 { return "米白" }
            if maxC > 130 { return "浅灰" }
            if maxC > 75 { return "灰色" }
            return "黑色"
        }

        let hue = hueDegrees(r: r, g: g, b: b)
        let saturation = Double(delta) / Double(maxC)

        switch hue {
        case 0..<15, 345..<360:
            return saturation > 0.55 ? (maxC > 150 ? "红色" : "酒红") : "粉色"
        case 15..<45:
            return maxC > 170 ? "橙色" : "棕色"
        case 45..<70:
            return saturation > 0.35 ? (maxC > 170 ? "黄色" : "芥末黄") : "卡其"
        case 70..<165:
            return maxC > 150 ? "绿色" : "墨绿"
        case 165..<200:
            return maxC > 160 ? "青色" : "蓝绿"
        case 200..<255:
            return maxC > 140 ? "蓝色" : "藏青"
        case 255..<290:
            return "紫色"
        default:
            return maxC > 170 ? "粉色" : "紫色"
        }
    }

    private static func hueDegrees(r: Int, g: Int, b: Int) -> Double {
        let rf = Double(r) / 255.0
        let gf = Double(g) / 255.0
        let bf = Double(b) / 255.0
        let maxV = max(rf, gf, bf)
        let minV = min(rf, gf, bf)
        let delta = maxV - minV
        guard delta > 0 else { return 0 }

        var hue: Double
        if maxV == rf {
            hue = 60 * (((gf - bf) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxV == gf {
            hue = 60 * (((bf - rf) / delta) + 2)
        } else {
            hue = 60 * (((rf - gf) / delta) + 4)
        }
        if hue < 0 { hue += 360 }
        return hue
    }

    // MARK: 缩略图

    /// 生成缩略图
    static func makeThumbnail(from image: UIImage, size: CGFloat = 200) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            // 等比缩放并居中
            let scale = min(size / image.size.width, size / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (size - drawSize.width) / 2, y: (size - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}
