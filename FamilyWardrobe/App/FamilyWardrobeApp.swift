import SwiftUI
import SwiftData

// MARK: - App 入口
//
// 启动流程：
//   ① 打开容器（内部完成：快照 → 迁移 → 校验 → 必要时回滚）
//   ② 成功 → 进档案选择
//   ③ 回滚 → 进档案选择，但顶部显示提示条告知用户
//   ④ 彻底失败 → 进恢复界面（不静默切内存库）

@main
struct FamilyWardrobeApp: App {
    @State private var startupState = StartupState.loading

    var body: some Scene {
        WindowGroup {
            switch startupState {
            case .loading:
                LaunchView()
                    .task { await bootstrap() }

            case .ready(let container, let notice):
                RootView(container: container, notice: notice)
                    .modelContainer(container)

            case .failed(let message):
                RecoveryView(message: message)
            }
        }
    }

    @MainActor
    private func bootstrap() async {
        switch WardrobeContainer.open() {
        case .success(let container):
            startupState = .ready(container: container, notice: nil)

        case .rolledBack(let container, let message):
            startupState = .ready(container: container, notice: message)

        case .failed(let error):
            startupState = .failed(message: error.localizedDescription)
        }
    }
}

// MARK: - 启动状态

enum StartupState {
    case loading
    case ready(container: ModelContainer, notice: String?)
    case failed(message: String)
}

// MARK: - 启动页

struct LaunchView: View {
    var body: some View {
        ZStack {
            Theme.Palette.pageBackground.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "tshirt.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.Palette.brand)
                Text("家庭衣橱")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
    }
}

// MARK: - 恢复界面
//
// 走到这里说明：数据库打不开，且没有可用快照自动恢复。
// 绝不能静默退化成内存库 —— 那等于告诉用户「一切正常」，
// 但他们的数据其实已经访问不到了。

struct RecoveryView: View {
    let message: String

    var body: some View {
        ZStack {
            Theme.Palette.pageBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color(hex: 0xBA7517))

                Text("数据暂时无法打开")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)

                Text(message)
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("你的数据仍在本机，没有被删除。请从「设置 → 备份」恢复，或联系技术支持。")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}
