import SwiftUI
import SwiftData

// MARK: - 设置
//
// 数据备份与隐私是这一页的重点 —— 它们直接关系到「升级不丢数据」。

struct SettingsView: View {
    @Binding var profileID: UUID?
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]

    @State private var snapshots: [(url: URL, date: Date)] = []

    var body: some View {
        NavigationStack {
            List {
                Section("档案") {
                    if profiles.isEmpty {
                        Text("尚未创建档案")
                            .foregroundStyle(Theme.Palette.textSecondary)
                    } else {
                        ForEach(profiles) { profile in
                            HStack {
                                Text(profile.name)
                                Spacer()
                                if profile.id == profileID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.Palette.brand)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { profileID = profile.id }
                        }
                    }
                }

                Section("数据与备份") {
                    LabeledContent("数据库版本", value: WardrobeContainer.currentSchemaVersion)

                    LabeledContent("历史快照", value: "\(snapshots.count) 份")

                    NavigationLink {
                        SnapshotListView(snapshots: snapshots)
                    } label: {
                        Text("查看快照")
                    }

                    Button {
                        StoreBackup.snapshot(reason: "manual")
                        refreshSnapshots()
                    } label: {
                        Label("立即创建快照", systemImage: "camera")
                    }

                    Button {
                        // TODO: 导出 zip 到「文件」
                    } label: {
                        Label("导出备份包", systemImage: "square.and.arrow.up")
                    }
                }

                Section("隐私") {
                    Label("照片仅保存在本机", systemImage: "lock")
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.Palette.textSecondary)

                    Toggle("启动时需要 Face ID 验证", isOn: .constant(true))

                    Text("本 App 不含任何网络请求代码。你的照片、记录、统计全部留在这台设备上。")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.0.0 (1)")
                    LabeledContent("Schema", value: "V1")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { refreshSnapshots() }
        }
    }

    private func refreshSnapshots() {
        snapshots = StoreBackup.listSnapshots()
    }
}

// MARK: - 快照列表

struct SnapshotListView: View {
    let snapshots: [(url: URL, date: Date)]

    var body: some View {
        List {
            if snapshots.isEmpty {
                Text("暂无快照")
                    .foregroundStyle(Theme.Palette.textSecondary)
            } else {
                ForEach(snapshots, id: \.url) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.date.formatted(date: .abbreviated, time: .standard))
                            .font(.system(size: 14, weight: .medium))
                        Text(item.url.lastPathComponent)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("历史快照")
        .navigationBarTitleDisplayMode(.inline)
    }
}
