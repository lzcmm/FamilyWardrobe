import Foundation
import UIKit

// MARK: - Sendable 包装
//
// Swift 6 严格并发下，`UIImage` 不是 Sendable。但像素运算本身是线程安全的
// （只要不再修改同一份位图）。用 `@unchecked Sendable` 明确承担这个责任，
// 比在各处加锁或强制 `MainActor` 更高效 —— 合成是重 CPU 操作，压到主线程
// 会让界面卡顿。

struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

// MARK: - 线程安全约定
//
// ⚠️ 约定：**UIImage 实例一旦交给后台线程，就不能在主线程再修改它**。
// UIImage 本身是不可变值类型（位图数据不可变），只要不调用
// `UIGraphicsImageRenderer` 之类会改动它的 API，就是安全的。
//
// `TryOnPipeline.composeRaw` 会创建新的 CIContext 与新的位图缓冲区，
// 不修改传入的 image，因此可以安全地在后台线程执行。

extension UIImage {
    /// 深拷贝为独立位图。跨线程传递前调用，确保没有共享的绘制上下文。
    func makeThreadSafeCopy() -> UIImage {
        guard let cgImage = cgImage else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
