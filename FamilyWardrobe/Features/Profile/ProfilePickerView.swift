import SwiftUI
import SwiftData

// MARK: - 档案选择
//
// 多档案是整个 App 的地基。数据全部挂 profileID，档案之间零串档。

struct ProfilePickerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]

    let onSelect: (UUID) -> Void

    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Metrics.groupSpacing) {
                    if profiles.isEmpty {
                        emptyState
                    } else {
                        ForEach(profiles) { profile in
                            ProfileRow(profile: profile) {
                                onSelect(profile.id)
                            }
                        }
                    }
                }
                .padding(Theme.Metrics.screenMargin)
            }
            .background(Theme.Palette.pageBackground)
            .navigationTitle("选择档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建档案")
                }
            }
            .sheet(isPresented: $showCreate) {
                ProfileCreateView { profile in
                    onSelect(profile.id)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("还没有档案")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("为每个家人建一个档案，衣服和记录分开存放，互不干扰。")
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - 档案行

struct ProfileRow: View {
    let profile: Profile
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(profile.avatarSeed.isEmpty ? "?" : profile.avatarSeed)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color(hexString: profile.accentHex, fallback: Theme.Palette.brand))
                    .clipShape(Circle())

                Text(profile.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(12)
            .background(Theme.Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Theme.Palette.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 新建档案

struct ProfileCreateView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let onCreate: (Profile) -> Void

    @State private var name = ""
    @State private var accentHex = "#4C63E6"

    private let accents = ["#4C63E6", "#D85A30", "#1D9E75", "#D4537E", "#BA7517", "#7F77DD"]

    var body: some View {
        NavigationStack {
            Form {
                Section("姓名") {
                    TextField("例如：我", text: $name)
                }

                Section("头像颜色") {
                    HStack(spacing: 12) {
                        ForEach(accents, id: \.self) { hex in
                            Button {
                                accentHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hexString: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if accentHex == hex {
                                            Circle()
                                                .strokeBorder(Theme.Palette.textPrimary, lineWidth: 2)
                                                .frame(width: 36, height: 36)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("新建档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("创建") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let profile = Profile(name: trimmed, accentHex: accentHex)
        context.insert(profile)
        try? context.save()
        onCreate(profile)
        dismiss()
    }
}
