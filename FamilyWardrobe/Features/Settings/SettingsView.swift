import SwiftUI
import SwiftData
import LocalAuthentication

// MARK: - 设置
//
// 三个板块：档案 / 数据与备份 / 隐私
//
// 「数据与备份」是这一页的重心 —— 它直接关系到「升级不丢数据」。
// 用户必须能：随时手动快照、查看历史快照、导出备份包、从备份恢复。

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]

    @Binding var profileID: UUID?

    @State private var snapshots: [(url: URL, date: Date)] = []
    @State private var exportURL: URL?
    @State private var showResetAlert = false
    @State private var requireFaceID = true

    var body: some View {
        NavigationStack {
            List {
                profileSection
                dataSection
                privacySection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { refreshSnapshots() }
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
            .confirmationDialog("清除所有数据？", isPresented: $showResetAlert, titleVisibility: .visible) {
                Button("清除", role: .destructive) { resetAll() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("所有档案、单品、记录都会被删除。此操作不可撤销，建议先导出备份。")
            }
        }
    }

    // MARK: 档案

    private var profileSection: some View {
        Section("档案") {
            if profiles.isEmpty {
                Text("尚未创建档案")
                    .foregroundStyle(Theme.Palette.textSecondary)
            } else {
                ForEach(profiles) { profile in
                    HStack {
                        Text(profile.avatarSeed.isEmpty ? "?" : profile.avatarSeed)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color(hexString: profile.accentHex, fallback: Theme.Palette.brand))
                            .clipShape(Circle())
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

            NavigationLink {
                StatisticsView(profileID: profileID)
            } label: {
                Label("统计", systemImage: "chart.bar")
            }
        }
    }

    // MARK: 数据与备份

    private var dataSection: some View {
        Section {
            LabeledContent("数据库版本", value: WardrobeContainer.currentSchemaVersion)
            LabeledContent("历史快照", value: "\(snapshots.count) 份")

            NavigationLink {
                SnapshotListView(snapshots: snapshots)
            } label: {
                Label("查看快照", systemImage: "clock.arrow.circlepath")
            }

            Button {
                StoreBackup.snapshot(reason: "manual")
                refreshSnapshots()
            } label: {
                Label("立即创建快照", systemImage: "camera")
            }

            Button {
                exportURL = BackupExporter.exportAll(profileID: profileID)
            } label: {
                Label("导出备份包", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                Label("清除所有数据", systemImage: "trash")
            }
        } header: {
            Text("数据与备份")
        } footer: {
            Text("备份包包含全家的全部照片与记录，请妥善保管。")
        }
    }

    // MARK: 隐私

    private var privacySection: some View {
        Section {
            Toggle("启动时需要 Face ID 验证", isOn: $requireFaceID)

            Label("照片仅保存在本机", systemImage: "lock")
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.Palette.textSecondary)

            Label("无网络请求", systemImage: "wifi.slash")
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        } header: {
            Text("隐私")
        } footer: {
            Text("本 App 不含任何网络请求代码。你的照片、记录、统计全部留在这台设备上。")
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: "1.0.0 (1)")
            LabeledContent("Schema", value: "V1")
            LabeledContent("最低系统", value: "iOS 17.0")
        }
    }

    // MARK: 操作

    private func refreshSnapshots() {
        snapshots = StoreBackup.listSnapshots()
    }

    private func resetAll() {
        for profile in profiles {
            context.delete(profile)
        }
        try? context.save()
    }
}

// MARK: - 备份导出
//
// 导出 zip = 数据库文件 + 全部照片。
// 存到「文件」App 后可以手动同步到 iCloud —— App 本身不联网，
// 但用户可以用系统能力自己同步。这保持了「离线」承诺的同时不丢灵活性。

enum BackupExporter {
    static func exportAll(profileID: UUID?) -> URL? {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let target = StoreBackup.exportDirectory.appending(path: "家庭衣橱备份-\(stamp).zip")

        var entries: [ZipWriter.Entry] = []

        // 数据库
        if fm.fileExists(atPath: StoreBackup.storeURL.path),
           let database = try? Data(contentsOf: StoreBackup.storeURL) {
            entries.append(ZipWriter.Entry(relativePath: "FamilyWardrobe.store", data: database))
        }

        // 照片：递归收集，保持相对目录结构
        let garmentsRoot = StoreBackup.assetsDirectory.appending(
            path: "garments", directoryHint: .isDirectory
        )
        if let enumerator = fm.enumerator(
            at: garmentsRoot, includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for case let fileURL as URL in enumerator {
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue,
                      let data = try? Data(contentsOf: fileURL) else { continue }
                let relative = "Assets/garments/" + fileURL.path
                    .replacingOccurrences(of: garmentsRoot.path + "/", with: "")
                entries.append(ZipWriter.Entry(relativePath: relative, data: data))
            }
        }

        let manifest = """
        家庭衣橱 备份包
        导出时间：\(Date().formatted(date: .abbreviated, time: .standard))
        数据库版本：\(WardrobeContainer.currentSchemaVersion)
        照片目录：Assets/garments/<单品ID>/
        恢复方式：解压后把 FamilyWardrobe.store 放回 App 沙盒对应位置，
                 Assets 目录内容合并到沙盒 Assets 目录。
        """
        if let readme = manifest.data(using: .utf8) {
            entries.append(ZipWriter.Entry(relativePath: "README.txt", data: readme))
        }

        do {
            try ZipWriter.create(at: target, entries: entries)
        } catch {
            return nil
        }
        return fm.fileExists(atPath: target.path) ? target : nil
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

// MARK: - 分享面板

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - URL 包装（用于 sheet(item:)

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
