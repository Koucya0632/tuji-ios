// UI language picker over UILanguage.allCases. Writes the choice into
// SettingsStore via update(_:), applying it immediately and auto-persisting
// via POST /api/users/settings. TujiApp reads SettingsStore.current.uiLanguage
// at render time to apply the matching locale to the whole app.

import SwiftUI

struct LangPickerView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(UILanguage.allCases, id: \.self) { lang in
                    Button {
                        self.store.update { $0.uiLanguage = lang }
                        self.dismiss()
                    } label: {
                        HStack(spacing: Space.s3) {
                            Text(verbatim: lang.nativeName)
                                .foregroundStyle(.tujiInk)
                            Spacer()
                            if self.store.current.uiLanguage == lang {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tujiTeal)
                            }
                        }
                    }
                }
            } header: {
                Text("App 介面會使用這個語言")
            } footer: {
                Text("變更立即生效。單字與例句維持中文內容，繁簡會跟隨此設定。")
                    .foregroundStyle(.tujiInk3)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.tujiBg)
        .navigationTitle("語言")
        .navigationBarTitleDisplayMode(.inline)
    }
}
