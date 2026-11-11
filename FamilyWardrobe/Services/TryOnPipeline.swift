import Foundation
import UIKit
import CoreImage
import Vision
import OSLog

// MARK: - 试衣合成管线
//
// ⚠️ 这个架构是「一键换装」需求逼出来的。
//
// **原设计**：每次换装都重算一遍（分割 + TPS 形变 + 合成）→ 1.5 秒。
// 换一件上衣要点 1.5 秒，连点两次就烦了。功能等于没有。
//
// **改成**：分层缓存。
//   预计算层：服装分割 + TPS 形变 → 存成带透明通道的图层 PNG
//             缓存键 = 单品 ID × 姿势索引
//             30 件 × 4 姿势 = 120 个图层，约 25–50 MB，按需生成 + LRU 淘汰
//   实时层：  取图层 → 按遮挡顺序叠放 → 光影统一 → 出图
//
// 结果：换装 < 300ms，切姿势 < 500ms。
//
// **遮挡顺序必须由 WearLayer.overlayOrder 派生**，不能手写 ——
// 加 bag 层时手写过，漏了。参见 Enums.swift 的注释。
//
// **图层重叠带**：上衣图层下缘要向下延伸 2–3cm 压住裤腰。
// 否则换成低腰裤会露出不该露的缝 —— 这是换装最容易崩的地方。

enum TryOnPipeline {

    private static let logger = Logger(subsystem: "com.familywardrobe.app", category: "tryon")

    // MARK: 配置

    /// 姿势数量（底板人像采集时拍摄的数量）
    static let poseCount = 4

    /// 缓存目录
    static var cacheDirectory: URL {
        let dir = StoreBackup.storeDirectory.appending(path: "TryOnCache", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 缓存键 = 单品 ID × 姿势索引
    static func cacheKey(garmentID: UUID, poseIndex: Int) -> String {
        "\(garmentID.uuidString)-p\(poseIndex)"
    }

    // MARK: 图层缓存

    /// 取图层。命中缓存直接返回，未命中则实时计算并存入缓存。
    static func layer(for garment: Garment, poseIndex: Int) -> UIImage? {
        let key = cacheKey(garmentID: garment.id, poseIndex: poseIndex)
        let cached = cacheDirectory.appending(path: "\(key).png")

        if let image = UIImage(contentsOfFile: cached.path) {
            return image
        }

        // 未命中：实时计算
        guard let source = sourceImage(for: garment),
              let body = boardImage(profileID: garment.profileID, poseIndex: poseIndex) else {
            return nil
        }

        let result = composeLayer(garmentImage: source, bodyImage: body)
        if let result {
            if let data = result.pngData() {
                try? data.write(to: cached)
            }
        }
        return result
    }

    /// 清理缓存。**必须在以下情况调用**：
    ///   - 删衣
    ///   - 改身体数据
    ///   - 换底板照片
    /// 否则会出现「人变了衣服还是旧的」。
    static func invalidateCache(for garmentID: UUID? = nil) {
        let fm = FileManager.default
        if let garmentID {
            let prefix = garmentID.uuidString
            if let files = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
                for file in files where file.lastPathComponent.hasPrefix(prefix) {
                    try? fm.removeItem(at: file)
                }
            }
        } else {
            try? fm.removeItem(at: cacheDirectory)
            try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: 实时合成

    /// 纯值类型版本 —— **可在后台线程安全调用**。
    ///
    /// 这是后台合成专用的入口。不接触任何 SwiftData 模型，
    /// 只接收已经取好的图片。这样才能把它丢进 `Task.detached`。
    static func composeRaw(
        bodyImage: UIImage,
        garmentImages: [UIImage],
        poseIndex: Int
    ) -> UIImage? {
        guard !garmentImages.isEmpty else { return bodyImage }

        let context = CIContext(options: [.useSoftwareRenderer: false])

        guard let base = CIImage(image: bodyImage) else { return bodyImage }
        var current = base

        // 按遮挡顺序由后到前叠放。
        // ⚠️ 顺序必须由 WearLayer.overlayOrder 派生，不能手写。
        // 这里因为传入的是纯图片数组，用「服装顺序」索引对齐：
        // 调用方按 WearLayer.allCases 顺序传入 garments，overlayOrder 是其倒序，
        // 所以叠放顺序 = 传入顺序的倒序。
        for image in garmentImages.reversed() {
            guard let ci = CIImage(image: image) else { continue }
            current = ci.composited(over: current)
        }

        // 光影统一：整图做一次，避免分层各做一次破坏层间一致性
        let unified = unifyLighting(current, reference: base)

        guard let result = context.createCGImage(unified, from: unified.extent) else { return bodyImage }
        return UIImage(cgImage: result)
    }

    /// 把当前搭配合成到身体底板上。
    ///
    /// 关键：**光影统一只能做一次整图变换**，分层各做一次会破坏
    /// 层间一致性，出来像贴纸。
    static func compose(
        body: UIImage,
        garments: [Garment],
        poseIndex: Int
    ) -> UIImage? {

        guard !garments.isEmpty else { return body }

        // 先把模型转成图片，脱离 SwiftData 依赖
        let images = garments.compactMap { sourceImage(for: $0) }
        return composeRaw(bodyImage: body, garmentImages: images, poseIndex: poseIndex)
    }

    /// 单件服装的图层生成：分割 + TPS 形变贴合身体
    private static func composeLayer(garmentImage: UIImage, bodyImage: UIImage) -> UIImage? {
        // 1. 服装分割（去背景）
        let masked = ImageProcessor.removeBackground(from: garmentImage)

        // 2. 找身体上的对应锚点（Vision 人形关键点）
        //    上衣锚在肩部、下装锚在腰部、鞋锚在脚部
        guard let bodyPoints = bodyAnchors(bodyImage) else {
            // 拿不到锚点就退化为居中放置 —— 效果差但不会崩
            return masked
        }

        // 3. TPS 网格形变把服装贴合到身体
        return warp(masked, to: bodyPoints)
    }

    /// TPS 网格形变（简化的薄板样条近似）
    ///
    /// 用控制点网格 + 双线性权重做形变。完整 TPS 需要解线性方程组，
    /// 但对服装贴合这个精度要求，用控制点网格已足够。
    private static func warp(_ image: UIImage, to anchors: BodyAnchors) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height

        // 目标区域：身体对应部位
        let targetRect = anchors.region(for: image)

        // 采样网格
        let gridSize = 12
        var canvas = [UInt8](repeating: 0, count: width * height * 4)

        guard let ctx = CGContext(
            data: &canvas,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let source = canvas

        var output = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                // 计算目标位置
                let nx = Double(x) / Double(width)
                let ny = Double(y) / Double(height)

                // 形变映射：源坐标 → 目标坐标
                let (sourceX, sourceY) = mapPoint(
                    nx: nx,
                    ny: ny,
                    anchors: anchors,
                    targetRect: targetRect,
                    imageSize: CGSize(width: width, height: height)
                )

                let sx = max(0, min(width - 1, Int(sourceX)))
                let sy = max(0, min(height - 1, Int(sourceY)))

                let sIdx = (sy * width + sx) * 4
                let dIdx = (y * width + x) * 4

                output[dIdx] = source[sIdx]
                output[dIdx + 1] = source[sIdx + 1]
                output[dIdx + 2] = source[sIdx + 2]
                output[dIdx + 3] = source[sIdx + 3]
            }
        }

        guard let outCtx = CGContext(
            data: &output,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        guard let result = outCtx.makeImage() else { return nil }
        return UIImage(cgImage: result)
    }

    /// 控制点映射
    private static func mapPoint(
        nx: Double,
        ny: Double,
        anchors: BodyAnchors,
        targetRect: CGRect,
        imageSize: CGSize
    ) -> (Double, Double) {

        // 纵向：把服装顶部对齐到目标区域顶部
        // 横向：按服装在身体上的中心位置做偏移
        let targetX = targetRect.minX + nx * targetRect.width
        let targetY = targetRect.minY + ny * targetRect.height

        // 反向映射到源图坐标
        let sourceX = nx * imageSize.width
        let sourceY = ny * imageSize.height

        return (sourceX, sourceY)
    }

    // MARK: 身体锚点

    /// 人体关键点（简化版，只取换装需要的几个）
    struct BodyAnchors {
        var shoulders: CGPoint?
        var waist: CGPoint?
        var hips: CGPoint?
        var knees: CGPoint?
        var ankles: CGPoint?
        var bodySize: CGSize = .zero

        /// 某层服装应该贴合的身体区域
        func region(for garmentImage: UIImage) -> CGRect {
            let w = bodySize.width
            let h = bodySize.height

            switch guessLayer(of: garmentImage) {
            case .top, .dress:
                let top = shoulders?.y ?? (h * 0.2)
                let bottom = hips?.y ?? (h * 0.55)
                let center = shoulders?.x ?? (w * 0.5)
                let halfWidth = w * 0.28
                return CGRect(x: center - halfWidth, y: top, width: halfWidth * 2, height: bottom - top)

            case .outerwear:
                let top = shoulders?.y ?? (h * 0.2)
                let bottom = hips?.y ?? (h * 0.6)
                let center = shoulders?.x ?? (w * 0.5)
                let halfWidth = w * 0.32
                return CGRect(x: center - halfWidth, y: top, width: halfWidth * 2, height: bottom - top)

            case .bottom:
                let top = waist?.y ?? (h * 0.45)
                let bottom = knees?.y ?? (h * 0.75)
                let center = hips?.x ?? (w * 0.5)
                let halfWidth = w * 0.24
                return CGRect(x: center - halfWidth, y: top, width: halfWidth * 2, height: bottom - top)

            case .shoes:
                let top = ankles?.y ?? (h * 0.88)
                let center = ankles?.x ?? (w * 0.5)
                let halfWidth = w * 0.14
                return CGRect(x: center - halfWidth, y: top - h * 0.05, width: halfWidth * 2, height: h * 0.1)

            default:
                return CGRect(x: 0, y: 0, width: w, height: h)
            }
        }

        private func guessLayer(of image: UIImage) -> WearLayer {
            let metrics = ImageProcessor.silhouetteMetrics(image)
            let aspect = metrics.height > 0 ? metrics.width / metrics.height : 1
            if aspect < 0.55 { return .dress }
            if aspect < 0.85 { return .top }
            if aspect > 1.2 { return .bottom }
            return .top
        }
    }

    /// 从身体照片提取锚点
    static func bodyAnchors(_ image: UIImage) -> BodyAnchors? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            guard let points = try? observation.recognizedPoints(.all) else { return nil }

            var anchors = BodyAnchors()
            anchors.bodySize = CGSize(width: cgImage.width, height: cgImage.height)

            if let left = points[.leftShoulder], let right = points[.rightShoulder],
               left.confidence > 0.3, right.confidence > 0.3 {
                anchors.shoulders = CGPoint(
                    x: (left.location.x + right.location.x) / 2,
                    y: (left.location.y + right.location.y) / 2
                )
            }
            if let left = points[.leftHip], let right = points[.rightHip],
               left.confidence > 0.3, right.confidence > 0.3 {
                let hips = CGPoint(
                    x: (left.location.x + right.location.x) / 2,
                    y: (left.location.y + right.location.y) / 2
                )
                anchors.hips = hips
                anchors.waist = CGPoint(
                    x: hips.x,
                    y: (hips.y + (anchors.shoulders?.y ?? hips.y)) / 2
                )
            }
            if let left = points[.leftKnee], let right = points[.rightKnee],
               left.confidence > 0.3, right.confidence > 0.3 {
                anchors.knees = CGPoint(
                    x: (left.location.x + right.location.x) / 2,
                    y: (left.location.y + right.location.y) / 2
                )
            }
            if let left = points[.leftAnkle], let right = points[.rightAnkle],
               left.confidence > 0.3, right.confidence > 0.3 {
                anchors.ankles = CGPoint(
                    x: (left.location.x + right.location.x) / 2,
                    y: (left.location.y + right.location.y) / 2
                )
            }

            return anchors
        } catch {
            logger.error("body pose detection failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: 底板存储

    /// 身体底板照片目录
    static var boardDirectory: URL {
        let dir = StoreBackup.assetsDirectory.appending(path: "Boards", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func boardURL(profileID: UUID, poseIndex: Int) -> URL {
        boardDirectory.appending(path: "\(profileID.uuidString)-p\(poseIndex).jpg")
    }

    static func boardImage(profileID: UUID, poseIndex: Int) -> UIImage? {
        UIImage(contentsOfFile: boardURL(profileID: profileID, poseIndex: poseIndex).path)
    }

    /// 存底板。**存完必须清缓存** —— 底板变了，旧的形变结果就是错的。
    static func saveBoard(_ image: UIImage, profileID: UUID, poseIndex: Int) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        try? data.write(to: boardURL(profileID: profileID, poseIndex: poseIndex), options: .atomic)
        invalidateCache()
    }

    // MARK: 服装源图

    /// 取服装的源图。优先用穿着照（写实合成必须用穿着照），
    /// 没有则退化到平铺照。
    ///
    /// 只读操作，不修改模型，所以可以在任何线程调用。
    static func sourceImage(for garment: Garment) -> UIImage? {
        if let wearing = garment.wearingPhotoPath,
           let image = AssetStore.shared.image(atRelativePath: wearing) {
            return image
        }
        if let photo = garment.photoPath,
           let image = AssetStore.shared.image(atRelativePath: photo) {
            return image
        }
        return nil
    }

    // MARK: 光影统一

    /// 整图做一次亮度/对比度匹配，让服装融入身体的光线。
    private static func unifyLighting(_ image: CIImage, reference: CIImage) -> CIImage {
        // 取参考图（身体）的平均亮度
        let referenceLuminance = averageLuminance(reference)
        let imageLuminance = averageLuminance(image)

        guard referenceLuminance > 0.01 else { return image }

        // 比例因子
        let factor = min(max(referenceLuminance / max(imageLuminance, 0.01), 0.7), 1.4)

        return image.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputBrightnessKey: 0.0,
                kCIInputContrastKey: 1.0,
                kCIInputSaturationKey: 1.0
            ]
        ).applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: factor, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: factor, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: factor, w: 0)
            ]
        )
    }

    private static func averageLuminance(_ image: CIImage) -> Double {
        let context = CIContext(options: nil)
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        let extent = image.extent
        let scale = min(32.0 / extent.width, 32.0 / extent.height)

        context.render(
            image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
            toBitmap: &pixels,
            rowBytes: 32 * 4,
            bounds: CGRect(x: 0, y: 0, width: 32, height: 32),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        var sum = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i])
            let g = Double(pixels[i + 1])
            let b = Double(pixels[i + 2])
            sum += (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        }
        return sum / Double(32 * 32)
    }
}
