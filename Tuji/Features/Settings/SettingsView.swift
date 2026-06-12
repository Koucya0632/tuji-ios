// Settings (§III.N). Edits a draft copy of UserSettings — bottom save
// bar persists via POST /api/users/settings when dirty. v1 ships the
// 學習 / 顯示 / 帳號 sections; 提醒 / 字體大小 / 深色模式 / 語言
// come online when the matching backend or i18n infra is ready.

import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var showSignOutConfirm = false
    @State private var showDeleteFirst = false
    @State private var showDeleteSecond = false
    @State private var deleting = false
    @State private var deleteError: Error?
    @State private var showDiscardConfirm = false

    var body: some View {
        ZStack(alignment: .bottom) {
            self.list
            if self.store.dirty {
                self.saveBar
            }
        }
        .background(.tujiBg)
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .task { await self.store.loadIfNeeded() }
        .alert("登出？", isPresented: self.$showSignOutConfirm) {
            Button("取消", role: .cancel) {}
            Button("登出", role: .destructive) {
                Task { await self.auth.signOut() }
            }
        } message: {
            Text("收藏與設定會保留在伺服器")
        }
        .alert("確定要刪除帳號？", isPresented: self.$showDeleteFirst) {
            Button("取消", role: .cancel) {}
            Button("繼續", role: .destructive) {
                self.showDeleteSecond = true
            }
        } message: {
            Text("這個動作無法復原：收藏、學習紀錄、所有資料都會刪除")
        }
        .alert("最後一次確認", isPresented: self.$showDeleteSecond) {
            Button("取消", role: .cancel) {}
            Button("永久刪除", role: .destructive) {
                Task { await self.deleteAccount() }
            }
        } message: {
            Text("確定要永久刪除帳號嗎？")
        }
        .alert("刪除失敗", isPresented: Binding(
            get: { self.deleteError != nil },
            set: { if !$0 { self.deleteError = nil } }
        )) {
            Button("知道了", role: .cancel) { self.deleteError = nil }
        } message: {
            Text(self.deleteError?.localizedDescription ?? "")
        }
        .toolbar {
            if self.store.dirty {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        self.showDiscardConfirm = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.tujiInk2)
                    }
                }
            }
        }
        .alert("放棄未儲存的變更？", isPresented: self.$showDiscardConfirm) {
            Button("繼續編輯", role: .cancel) {}
            Button("放棄", role: .destructive) {
                self.store.revertDraft()
                self.dismiss()
            }
        }
    }

    // MARK: - List

    private var list: some View {
        @Bindable var store = store
        return List {
            Section("學習") {
                NavigationLink {
                    DailyGoalPickerView()
                } label: {
                    self.row(label: "每日目標題數", value: "\(self.store.draft.dailyGoal) 題")
                }
                Toggle("中文釋義", isOn: $store.draft.showZh)
                    .tint(.tujiTeal)
            }
            Section("顯示") {
                NavigationLink {
                    AccentPickerView()
                } label: {
                    self.row(label: "發音口音", value: self.accentLabel)
                }
            }
            Section("帳號") {
                NavigationLink {
                    EditProfileView()
                } label: {
                    self.row(label: "編輯個人資料", value: nil)
                }
                Button(role: .destructive) {
                    self.showSignOutConfirm = true
                } label: {
                    Text("登出")
                        .foregroundStyle(.tujiCoral)
                }
            }
            Section {
                Button(role: .destructive) {
                    self.showDeleteFirst = true
                } label: {
                    HStack {
                        if self.deleting {
                            ProgressView().tint(.tujiCoral)
                        }
                        Text(self.deleting ? "刪除中…" : "刪除帳號")
                            .foregroundStyle(.tujiCoral)
                    }
                }
                .disabled(self.deleting)
            }
            Section {
                Text("Tuji v1.0.0 · 圖記")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk4)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.tujiBg)
    }

    private func row(label: String, value: String?) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.tujiInk)
            Spacer()
            if let value {
                Text(value)
                    .foregroundStyle(.tujiInk3)
            }
        }
    }

    private var accentLabel: String {
        switch self.store.draft.accent {
        case "uk": "英式"
        case "us": "美式"
        default: self.store.draft.accent.uppercased()
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        BBtn(
            title: self.store.saving ? "儲存中…" : "儲存設定",
            bg: .tujiTeal,
            fg: .white,
            fullWidth: true,
            icon: "checkmark",
            action: { Task { await self.store.save() } }
        )
        .disabled(self.store.saving)
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s4)
        .background(.tujiBg.opacity(0.92))
    }

    // MARK: - Account actions

    private func deleteAccount() async {
        self.deleting = true
        self.deleteError = nil
        defer { self.deleting = false }
        struct EmptyBody: Encodable {}
        do {
            let _: SaveSettingsResponse = try await APIClient.shared.post(
                .usersDeleteAccount,
                body: EmptyBody()
            )
            await self.auth.signOut()
        } catch {
            self.deleteError = error
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(SettingsStore.shared)
            .environment(AuthService.shared)
    }
}
