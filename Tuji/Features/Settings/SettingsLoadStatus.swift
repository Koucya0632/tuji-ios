// The line above 設定's controls, and in place of 學習主題's grid, while the
// account's settings have not arrived — why the controls do nothing, and the
// way out. See `SettingsWrite` for what a change made against the defaults did.

import SwiftUI

struct SettingsLoadStatus: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        if self.store.isEditable {
            EmptyView()
        } else if self.store.lastError != nil, !self.store.loading {
            // No save can have failed here — none is sent until the settings
            // arrive — so an error on this screen is the read's.
            HStack(spacing: Space.s3) {
                Text("無法載入你的設定，暫時不能修改")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiAlert)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("重試") {
                    Task { await self.store.load() }
                }
                .font(.tujiBodySm(.strong))
                .tint(.tujiBrandSecondary)
                .frame(minHeight: 44)
            }
            .padding(.vertical, Space.s1)
        } else {
            Text("載入設定中…")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Space.s3)
        }
    }
}
