// UI language picker. Writes the chosen code into SettingsStore via
// update(_:), applying it immediately and auto-persisting via
// POST /api/users/settings. RootView reads SettingsStore.current.uiLang at
// render time to apply the matching locale to the whole app.

import SwiftUI

struct LangPickerView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private struct Option: Hashable {
        let code: String
        let label: String
        let native: String
    }

    private static let options: [Option] = [
        Option(code: "zh-Hant", label: "繁體中文", native: "繁體中文"),
        Option(code: "zh-Hans", label: "简体中文", native: "简体中文"),
        Option(code: "ja", label: "日本語", native: "日本語")
    ]

    var body: some View {
        List {
            Section {
                ForEach(Self.options, id: \.code) { opt in
                    Button {
                        self.store.update { $0.uiLang = opt.code }
                        self.dismiss()
                    } label: {
                        HStack(spacing: Space.s3) {
                            Text(opt.native)
                                .foregroundStyle(.tujiInk)
                            Spacer()
                            if self.store.current.uiLang == opt.code {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tujiTeal)
                            }
                        }
                    }
                }
            } header: {
                Text("App 介面與後端內容會用這個語言")
            } footer: {
                Text("儲存後立即生效。Word definition / examples 也會用這個語言請求。")
                    .foregroundStyle(.tujiInk3)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.tujiBg)
        .navigationTitle("語言")
        .navigationBarTitleDisplayMode(.inline)
    }
}
