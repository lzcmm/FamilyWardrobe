import SwiftUI
import SwiftData

// MARK: - 根视图
//
// 5 Tab：衣橱 / 今天 / 日历 / 灵感 / 设置
// 衣橱排第一 —— 它是数据底座，打开先看库。
// 档案切换是全局的：换档案后衣橱、记录、统计全部跟着换。

struct RootView: View {
    let container: ModelContainer
    let notice: String?

    @State private var selectedTab = 0
    @State private var selectedProfileID: UUID?
    @State private var showNotice = false

    var body: some View {
        TabView(selection: $selectedTab) {
            if let profileID = selectedProfileID {
                WardrobeView(profileID: profileID)
                    .tabItem { Label("衣橱", systemImage: "square.grid.2x2") }
                    .tag(0)
            } else {
                ProfilePickerView { profileID in
                    selectedProfileID = profileID
                }
                .tabItem { Label("衣橱", systemImage: "square.grid.2x2") }
                .tag(0)
            }

            TodayView(profileID: selectedProfileID)
                .tabItem { Label("今天", systemImage: "clock") }
                .tag(1)

            CalendarView(profileID: selectedProfileID)
                .tabItem { Label("日历", systemImage: "calendar") }
                .tag(2)

            InspirationView(profileID: selectedProfileID)
                .tabItem { Label("灵感", systemImage: "sparkle") }
                .tag(3)

            SettingsView(profileID: $selectedProfileID)
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
                .tag(4)
        }
        .tint(Theme.Palette.brand)
        .overlay(alignment: .top) {
            if let notice {
                NoticeBar(message: notice) {
                    withAnimation { showNotice = false }
                }
                .padding(.horizontal, Theme.Metrics.screenMargin)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear { showNotice = true }
            }
        }
    }
}

// MARK: - 提示条

struct NoticeBar: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color(hex: 0xBA7517))
            Text(message)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(hex: 0xFAC775), lineWidth: 0.5)
        )
    }
}
